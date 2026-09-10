package app.airclone.airclone

import android.app.Activity
import android.app.UiModeManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/// The `airclone/native` MethodChannel: native facts and actions Dart cannot
/// reach on its own (see android_native.dart, rclone_engine.dart,
/// open_external.dart, thumbnail_service.dart, photo_backup.dart).
///
/// **Application-scoped, deliberately.** This used to be registered inside
/// `MainActivity.configureFlutterEngine`, which meant it existed only on the
/// engine an Activity had created. A WorkManager worker runs a SECOND Flutter
/// engine with no Activity at all, and everything the rclone engine needs to
/// come up — above all `nativeLibraryDir`, the one place Android permits
/// exec() of the bundled `librclone.so` — was unreachable from it. Every
/// answer here is therefore computed from the application [context]; the
/// [activity] provider is consulted only by the handful of methods that
/// genuinely need one (permission prompts, launching a chooser), and those
/// degrade rather than crash when it returns null.
///
/// One instance per engine, because the video frame-grabber executor belongs to
/// the engine that asked; call [dispose] when that engine goes away.
class NativeChannel private constructor(
    private val context: Context,
    private val activity: () -> Activity?,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val NAME = "airclone/native"

        /// How much the sampled luma may vary before a frame counts as a real
        /// picture. Kept in step with the same check in thumbnail_service.dart.
        private const val BLANK_LUMA_RANGE = 12

        /// Attach the handler to [messenger]. [activity] returns the hosting
        /// Activity while one exists; a background engine passes nothing and
        /// gets the Activity-free behaviour described on each method.
        fun register(
            messenger: BinaryMessenger,
            context: Context,
            activity: () -> Activity? = { null },
        ): NativeChannel {
            val handler = NativeChannel(context.applicationContext, activity)
            MethodChannel(messenger, NAME).setMethodCallHandler(handler)
            return handler
        }
    }

    /// Decoding a video frame blocks for as long as the bytes take to arrive,
    /// so it must never run on the platform thread (that is an ANR). One
    /// thread, because Dart already serialises video thumbnails.
    private val frameGrabber: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainThread = Handler(Looper.getMainLooper())

    fun dispose() {
        frameGrabber.shutdownNow()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // The rclone engine ships as an executable named librclone.so inside
            // jniLibs, which the installer extracts to nativeLibraryDir — the one
            // location Android still permits exec() from under W^X (targetSdk 29+).
            "nativeLibraryDir" -> result.success(context.applicationInfo.nativeLibraryDir)
            "externalStorageDir" ->
                result.success(Environment.getExternalStorageDirectory().absolutePath)
            "hasAllFilesAccess" ->
                result.success(
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
                        Environment.isExternalStorageManager()
                    else
                        // Pre-R: legacy READ permission is what gates
                        // shared-storage paths.
                        context.checkSelfPermission(
                            android.Manifest.permission.READ_EXTERNAL_STORAGE
                        ) == PackageManager.PERMISSION_GRANTED
                )
            // Running on a television? Decides which shell the UI builds (see
            // android_native.dart). Asked natively because no Dart-visible
            // signal distinguishes a TV from a tablet: both are large,
            // landscape and Android.
            "isTelevision" -> result.success(isTelevision())
            // Which app installed us — Play Store, Amazon, F-Droid, or null/the
            // package installer for a sideloaded APK. Dart maps this to an
            // update channel so a store install is never shown an out-of-store
            // download link (see install_source.dart).
            "installerPackage" -> result.success(installerPackageName())
            // The user-facing device name, for the per-device backup folder
            // (task_kind.dart `deviceFolderName`). Settings.Global.DEVICE_NAME
            // is what the phone calls itself in Bluetooth/Wi-Fi Direct; it is
            // null on some builds, so fall back to make+model.
            "deviceName" -> result.success(deviceName())
            "openExternal" -> openExternal(call, result)
            "videoThumbnail" -> videoThumbnail(call, result)
            // ── Transfer foreground service (see TransferService.kt) ──
            "startTransferService" -> {
                val intent = Intent(context, TransferService::class.java)
                    .putExtra(TransferService.EXTRA_TITLE, call.argument<String>("title"))
                    .putExtra(TransferService.EXTRA_TEXT, call.argument<String>("text"))
                // Same call both starts and updates: onStartCommand re-posts
                // the notification with the new text.
                try {
                    context.startForegroundService(intent)
                } catch (e: Exception) {
                    // Android 12+ forbids starting a foreground service from
                    // the background (ForegroundServiceStartNotAllowed-
                    // Exception, an IllegalStateException). A transfer kicked
                    // off while the app is already backgrounded then simply
                    // runs without the keep-alive rather than crashing the app.
                }
                result.success(null)
            }
            "stopTransferService" -> {
                context.stopService(Intent(context, TransferService::class.java))
                result.success(null)
            }
            "requestNotificationPermission" -> {
                // Needs an Activity to host the system prompt. Without one
                // (background engine) there is nobody to ask, and the service
                // runs either way — only the notification is affected.
                val host = activity()
                if (host != null &&
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                    host.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) !=
                        PackageManager.PERMISSION_GRANTED
                ) {
                    host.requestPermissions(
                        arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                        9002,
                    )
                }
                result.success(null)
            }
            "requestAllFilesAccess" -> {
                requestAllFilesAccess()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // ── Hand a staged file to another app (see open_external.dart) ──
    // Dart has already streamed the object into our cache dir; all that's
    // left is a content:// URI another app may read. A raw file:// Uri would
    // throw FileUriExposedException, so this MUST go through FileProvider.
    private fun openExternal(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        val mime = call.argument<String>("mime") ?: "application/octet-stream"
        val share = call.argument<Boolean>("share") ?: false
        if (path.isNullOrEmpty()) {
            result.error("bad_args", "path is required", null)
            return
        }
        try {
            val uri = try {
                FileProvider.getUriForFile(
                    context,
                    "${context.packageName}.fileprovider",
                    File(path),
                )
            } catch (e: IllegalArgumentException) {
                // The file is outside every root in file_paths.xml — an SD
                // card or USB volume, whose mount point is neither the cache
                // dir nor primary shared storage. Report it as its own code so
                // Dart can stage a copy into the cache dir and retry, instead
                // of showing the user a raw "Failed to find configured root".
                result.error("not_shareable", e.message, null)
                return
            }
            val intent = if (share) {
                Intent(Intent.ACTION_SEND)
                    .setType(mime)
                    .putExtra(Intent.EXTRA_STREAM, uri)
            } else {
                Intent(Intent.ACTION_VIEW).setDataAndType(uri, mime)
            }
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            // The chooser needs the grant too, so the app the user picks
            // inherits read access to the URI.
            val chooser = Intent.createChooser(
                intent,
                if (share) "Share with" else "Open with",
            ).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            startFromHost(chooser)
            result.success(true)
        } catch (e: ActivityNotFoundException) {
            // Dart maps this code to a "no app can open this" message rather
            // than blaming the download.
            result.error("no_handler", e.message, null)
        } catch (e: Exception) {
            result.error("open_failed", e.message, null)
        }
    }

    // ── Video thumbnails (see thumbnail_service.dart) ──
    // libmpv is the app's video engine everywhere else, but on Android it
    // decodes into a Surface, so its `screenshot` command has no CPU-readable
    // frame to hand back and every video tile stayed empty.
    // MediaMetadataRetriever is Android's own frame grabber: it decodes
    // straight to a Bitmap, applies the track's rotation, and reads http with
    // the engine's auth headers.
    private fun videoThumbnail(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url")
        val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
        val size = call.argument<Int>("size") ?: 256
        if (url.isNullOrEmpty()) {
            result.error("bad_args", "url is required", null)
            return
        }
        frameGrabber.execute {
            val bytes = try {
                grabVideoFrame(url, headers, size)
            } catch (e: Throwable) {
                // OutOfMemory on a huge frame included: a missing thumbnail is
                // never worth a crash.
                null
            }
            mainThread.post {
                try {
                    result.success(bytes)
                } catch (e: Exception) {
                    // The engine went away mid-decode (activity destroyed) —
                    // nothing to reply to.
                }
            }
        }
    }

    private fun requestAllFilesAccess() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Per-app screen first; some OEM builds only ship the list screen
            // — and some ship neither, so both launches are guarded.
            try {
                startFromHost(
                    Intent(
                        Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                        Uri.parse("package:${context.packageName}")
                    )
                )
            } catch (e: Exception) {
                try {
                    startFromHost(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
                } catch (e2: Exception) {
                    // No settings screen available; nothing to do.
                }
            }
        } else {
            // A runtime-permission prompt can only be hosted by an Activity.
            activity()?.requestPermissions(
                arrayOf(
                    android.Manifest.permission.READ_EXTERNAL_STORAGE,
                    android.Manifest.permission.WRITE_EXTERNAL_STORAGE,
                ),
                9001,
            )
        }
    }

    /// Launches [intent] from the Activity when there is one, else from the
    /// application context — which requires NEW_TASK, because there is no task
    /// of ours for the new Activity to join.
    private fun startFromHost(intent: Intent) {
        val host = activity()
        if (host != null) {
            host.startActivity(intent)
        } else {
            context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }

    /// PNG bytes of a representative frame from the video at [url], or null
    /// when Android can't decode one. Runs on [frameGrabber], never the
    /// platform thread.
    private fun grabVideoFrame(
        url: String,
        headers: Map<String, String>,
        size: Int,
    ): ByteArray? {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(url, headers)
            val duration = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 0L
            val width = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                ?.toIntOrNull() ?: 0
            val height = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                ?.toIntOrNull() ?: 0
            // Videos routinely open on black (fade-in, slate, camera warm-up),
            // so try a frame a little way in first and fall back towards the
            // start. LinkedHashSet keeps the order and drops duplicates on a
            // very short clip.
            val times = LinkedHashSet<Long>()
            if (duration > 0) {
                times.add(duration / 10)
                times.add(minOf(1000L, duration / 2))
            } else {
                times.add(1000L)
            }
            times.add(0L)

            var fallback: Bitmap? = null
            for (ms in times) {
                val frame = frameAt(retriever, ms * 1000, size, width, height)
                    ?: continue
                if (!looksBlank(frame)) {
                    fallback?.recycle()
                    return encodePng(frame)
                }
                // Keep the first blank frame: Dart makes the final call on
                // whether a flat frame is worth showing, in one place for
                // every platform.
                if (fallback == null) fallback = frame else frame.recycle()
            }
            return fallback?.let { encodePng(it) }
        } finally {
            try {
                retriever.release()
            } catch (e: Exception) {
                // best-effort
            }
        }
    }

    /// One decoded frame at [timeUs], scaled into a [size]-px box when the
    /// track's dimensions are known (decoding a 4K frame to throw 99% of it
    /// away is the slow way to build a 256px tile).
    private fun frameAt(
        retriever: MediaMetadataRetriever,
        timeUs: Long,
        size: Int,
        srcWidth: Int,
        srcHeight: Int,
    ): Bitmap? = try {
        val option = MediaMetadataRetriever.OPTION_CLOSEST_SYNC
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1 &&
            srcWidth > 0 && srcHeight > 0
        ) {
            val scale = minOf(
                size.toFloat() / srcWidth,
                size.toFloat() / srcHeight,
                1f,
            )
            retriever.getScaledFrameAtTime(
                timeUs,
                option,
                maxOf(1, (srcWidth * scale).toInt()),
                maxOf(1, (srcHeight * scale).toInt()),
            )
        } else {
            retriever.getFrameAtTime(timeUs, option)
        }
    } catch (e: Exception) {
        null
    }

    /// True when a frame carries no picture — every sampled pixel the same
    /// shade, i.e. the black leader or a frame that never decoded. Sampled on
    /// a coarse grid; reading every pixel of a large frame would cost more
    /// than the decode did.
    private fun looksBlank(frame: Bitmap): Boolean {
        val w = frame.width
        val h = frame.height
        if (w <= 0 || h <= 0) return true
        // A hardware-backed bitmap has no readable pixels; treat it as real
        // rather than throwing away a frame we simply can't inspect.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            frame.config == Bitmap.Config.HARDWARE
        ) {
            return false
        }
        var min = 255
        var max = 0
        val stepX = maxOf(1, w / 16)
        val stepY = maxOf(1, h / 16)
        var y = 0
        while (y < h) {
            var x = 0
            while (x < w) {
                val p = frame.getPixel(x, y)
                val luma = ((p shr 16 and 0xFF) * 77 +
                    (p shr 8 and 0xFF) * 150 +
                    (p and 0xFF) * 29) shr 8
                if (luma < min) min = luma
                if (luma > max) max = luma
                if (max - min > BLANK_LUMA_RANGE) return false
                x += stepX
            }
            y += stepY
        }
        return true
    }

    private fun encodePng(frame: Bitmap): ByteArray {
        val out = ByteArrayOutputStream()
        frame.compress(Bitmap.CompressFormat.PNG, 100, out)
        frame.recycle()
        return out.toByteArray()
    }

    /// Whether this is a TV. Two independent signals because neither is
    /// reliable alone: UI_MODE_TYPE_TELEVISION is what the platform reports at
    /// runtime and is what emulators set, while FEATURE_LEANBACK is what Play
    /// filters on and what some manufacturer boxes report instead. Either one
    /// is enough to mean "no touchscreen, D-pad only".
    private fun isTelevision(): Boolean {
        val uiMode = context.getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
        if (uiMode?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION) {
            return true
        }
        return context.packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
    }

    /// The package that installed this app, or null when nothing claims it (an
    /// `adb install`, or a build sideloaded by a file manager that doesn't set
    /// itself as the installer). `getInstallerPackageName` was deprecated in
    /// API 30 in favour of `getInstallSourceInfo`, so both are used by level.
    private fun installerPackageName(): String? = try {
        val pm = context.packageManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            pm.getInstallSourceInfo(context.packageName).installingPackageName
        } else {
            @Suppress("DEPRECATION")
            pm.getInstallerPackageName(context.packageName)
        }
    } catch (e: Exception) {
        // NameNotFoundException can't happen for our own package, but a
        // defensive null keeps the update UI on the conservative (non-store)
        // path.
        null
    }

    private fun deviceName(): String {
        val named = try {
            Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME)
        } catch (e: Exception) {
            null
        }
        if (!named.isNullOrBlank()) return named
        val make = Build.MANUFACTURER?.trim().orEmpty()
        val model = Build.MODEL?.trim().orEmpty()
        return when {
            model.isEmpty() -> "Android"
            make.isEmpty() || model.startsWith(make, ignoreCase = true) -> model
            else -> "$make $model"
        }
    }
}
