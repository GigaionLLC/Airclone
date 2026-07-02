package app.airclone.airclone

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

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
}
