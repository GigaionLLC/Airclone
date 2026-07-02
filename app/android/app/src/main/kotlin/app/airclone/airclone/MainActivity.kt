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
