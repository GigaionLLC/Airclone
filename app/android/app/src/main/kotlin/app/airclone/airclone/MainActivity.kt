package app.airclone.airclone

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    // Native facts Dart can't reach on its own. The rclone engine ships as an
    // executable named librclone.so inside jniLibs, which the installer extracts
    // to nativeLibraryDir — the one location Android still permits exec() from
    // under W^X (targetSdk 29+).
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "airclone/native")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "nativeLibraryDir" -> result.success(applicationInfo.nativeLibraryDir)
                    "externalStorageDir" ->
                        result.success(Environment.getExternalStorageDirectory().absolutePath)
                    "hasAllFilesAccess" ->
                        result.success(
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
                                Environment.isExternalStorageManager()
                            else
                                // Pre-R: legacy READ permission is what gates
                                // shared-storage paths.
                                checkSelfPermission(
                                    android.Manifest.permission.READ_EXTERNAL_STORAGE
                                ) == PackageManager.PERMISSION_GRANTED
                        )
                    // Which app installed us — Play Store, Amazon, F-Droid, or
                    // null/the package installer for a sideloaded APK. Dart maps
                    // this to an update channel so a store install is never shown
                    // an out-of-store download link (see install_source.dart).
                    "installerPackage" -> result.success(installerPackageName())
                    // ── Hand a staged file to another app (see open_external.dart) ──
                    // Dart has already streamed the object into our cache dir;
                    // all that's left is a content:// URI another app may read.
                    // A raw file:// Uri would throw FileUriExposedException, so
                    // this MUST go through FileProvider.
                    "openExternal" -> {
                        val path = call.argument<String>("path")
                        val mime = call.argument<String>("mime") ?: "application/octet-stream"
                        val share = call.argument<Boolean>("share") ?: false
                        if (path.isNullOrEmpty()) {
                            result.error("bad_args", "path is required", null)
                        } else {
                            try {
                                val uri = try {
                                    FileProvider.getUriForFile(
                                        this,
                                        "$packageName.fileprovider",
                                        File(path),
                                    )
                                } catch (e: IllegalArgumentException) {
                                    // The file is outside every root in
                                    // file_paths.xml — an SD card or USB volume,
                                    // whose mount point is neither the cache dir
                                    // nor primary shared storage. Report it as its
                                    // own code so Dart can stage a copy into the
                                    // cache dir and retry, instead of showing the
                                    // user a raw "Failed to find configured root".
                                    result.error("not_shareable", e.message, null)
                                    return@setMethodCallHandler
                                }
                                val intent = if (share) {
                                    Intent(Intent.ACTION_SEND)
                                        .setType(mime)
                                        .putExtra(Intent.EXTRA_STREAM, uri)
                                } else {
                                    Intent(Intent.ACTION_VIEW).setDataAndType(uri, mime)
                                }
                                intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                // The chooser needs the grant too, so the app the
                                // user picks inherits read access to the URI.
                                val chooser = Intent.createChooser(
                                    intent,
                                    if (share) "Share with" else "Open with",
                                ).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                startActivity(chooser)
                                result.success(true)
                            } catch (e: ActivityNotFoundException) {
                                // Dart maps this code to a "no app can open this"
                                // message rather than blaming the download.
                                result.error("no_handler", e.message, null)
                            } catch (e: Exception) {
                                result.error("open_failed", e.message, null)
                            }
                        }
                    }
                    // ── Transfer foreground service (see TransferService.kt) ──
                    "startTransferService" -> {
                        val intent = Intent(this, TransferService::class.java)
                            .putExtra(TransferService.EXTRA_TITLE, call.argument<String>("title"))
                            .putExtra(TransferService.EXTRA_TEXT, call.argument<String>("text"))
                        // Same call both starts and updates: onStartCommand
                        // re-posts the notification with the new text.
                        try {
                            startForegroundService(intent)
                        } catch (e: Exception) {
                            // Android 12+ forbids starting a foreground service
                            // from the background (ForegroundServiceStartNotAllowed-
                            // Exception, an IllegalStateException). A transfer
                            // kicked off while the app is already backgrounded
                            // (e.g. the in-app scheduler) then simply runs without
                            // the keep-alive rather than crashing the app.
                        }
                        result.success(null)
                    }
                    "stopTransferService" -> {
                        stopService(Intent(this, TransferService::class.java))
                        result.success(null)
                    }
                    "requestNotificationPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) !=
                                PackageManager.PERMISSION_GRANTED
                        ) {
                            requestPermissions(
                                arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                                9002,
                            )
                        }
                        result.success(null)
                    }
                    "requestAllFilesAccess" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            // Per-app screen first; some OEM builds only ship the
                            // list screen — and some ship neither, so both
                            // launches are guarded.
                            try {
                                startActivity(
                                    Intent(
                                        Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                                        Uri.parse("package:$packageName")
                                    )
                                )
                            } catch (e: Exception) {
                                try {
                                    startActivity(
                                        Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                                    )
                                } catch (e2: Exception) {
                                    // No settings screen available; nothing to do.
                                }
                            }
                        } else {
                            requestPermissions(
                                arrayOf(
                                    android.Manifest.permission.READ_EXTERNAL_STORAGE,
                                    android.Manifest.permission.WRITE_EXTERNAL_STORAGE,
                                ),
                                9001,
                            )
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// The package that installed this app, or null when nothing claims it (an
    /// `adb install`, or a build sideloaded by a file manager that doesn't set
    /// itself as the installer). `getInstallerPackageName` was deprecated in
    /// API 30 in favour of `getInstallSourceInfo`, so both are used by level.
    private fun installerPackageName(): String? = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            packageManager.getInstallSourceInfo(packageName).installingPackageName
        } else {
            @Suppress("DEPRECATION")
            packageManager.getInstallerPackageName(packageName)
        }
    } catch (e: Exception) {
        // NameNotFoundException can't happen for our own package, but a defensive
        // null keeps the update UI on the conservative (non-store) path.
        null
    }
}
