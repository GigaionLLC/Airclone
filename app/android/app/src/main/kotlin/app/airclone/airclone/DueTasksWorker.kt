package app.airclone.airclone

import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.FlutterCallbackInformation
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume

/// The WorkManager worker behind `airclone.run-due`: boots a headless Flutter
/// engine with no Activity, runs the Dart entrypoint registered through
/// WorkChannel (android_work_entrypoint.dart → `--run-due`), and finishes when
/// Dart reports its exit code.
///
/// Three things decide whether this can work at all, and each is here rather
/// than somewhere more obvious for a reason:
///
///  * **The `airclone/native` channel is registered on this engine too.** The
///    rclone engine cannot come up without `nativeLibraryDir`, and that used to
///    be an Activity's to answer. NativeChannel.kt is Application-scoped now
///    precisely so this line can exist.
///  * **`setForeground`, not `startForegroundService`.** Android 12+ forbids
///    starting a foreground service from the background, and a worker IS the
///    background. WorkManager's own foreground promotion is one of the
///    sanctioned routes, and it is what keeps the process — and the rclone
///    child it spawns — alive for the length of a real backup rather than the
///    ten minutes a plain worker gets. The notification reuses
///    TransferService's channel so the user sees one kind of "Airclone is
///    working" notification, not two.
///  * **It yields to a visible app.** The in-app scheduler ticks every 30 s
///    while the app is on screen and runs due tasks itself; running here as
///    well would spawn a second rclone engine and race it over the same
///    SharedPreferences (last-writer-wins). AircloneApplication knows whether an
///    Activity is started, and this worker simply returns when one is.
///
/// Android 15 caps a `dataSync` foreground service at roughly six hours a day,
/// after which the promotion is withdrawn; the Dart side is told to cap its own
/// run below that. A run cut short is not lost — rclone `copy` skips what is
/// already at the destination, so the next period picks up where this one
/// stopped.
class DueTasksWorker(appContext: Context, params: WorkerParameters) :
    CoroutineWorker(appContext, params) {

    companion object {
        const val TAG = "AircloneWork"

        /// Distinct from TransferService.NOTIFICATION_ID so a background poll
        /// cannot replace (or be replaced by) a live transfer's notification.
        const val NOTIFICATION_ID = 1002

        /// The channel the Dart entrypoint talks back over: `start` to fetch
        /// its argv, `log` for a line into logcat, `done` with the exit code.
        const val BG_CHANNEL = "airclone/work_bg"

        /// The wall-clock cap handed to Dart as `--timeout-minutes` when the
        /// worker holds the foreground. Five hours keeps a first full
        /// camera-roll backup under Android 15's ~6h/day dataSync budget with
        /// room for the poll that follows it.
        const val DART_TIMEOUT_MINUTES = 300L

        /// The cap when the promotion was refused: a plain worker is stopped
        /// after ~10 minutes, and the Dart run must finish — rclone quit,
        /// outcome recorded — before that, not be killed by it.
        const val UNPROMOTED_TIMEOUT_MINUTES = 8L

        /// Exit codes mirror headless_runner.dart — 0 ok, 1 a task failed,
        /// 2 could not start.
        const val EXIT_CANNOT_START = 2
    }

    override suspend fun doWork(): Result {
        // The periodic wake yields to a visible app; a one-off the user asked
        // for from inside the app ("Run due tasks in background now") does
        // not — that button exists to show the background path working.
        val userRequested = tags.contains(WorkChannel.UNIQUE_ONCE)
        if (!userRequested && AircloneApplication.activityVisible) {
            Log.i(TAG, "skipped: the app is on screen, the in-app scheduler owns due tasks")
            return Result.success()
        }
        val prefs = applicationContext.getSharedPreferences(WorkChannel.PREFS, Context.MODE_PRIVATE)
        val handle = prefs.getLong(WorkChannel.KEY_CALLBACK, 0L)
        if (handle == 0L) {
            // Dart never registered its entrypoint — the app has not been
            // launched since this build was installed. Nothing to run.
            stamp(prefs, EXIT_CANNOT_START, "no Dart entrypoint registered; open Airclone once")
            return Result.failure()
        }

        // MEASURED, not assumed (Android 15 emulator, 2026-09-09): a periodic
        // job started by JobScheduler with the app in the background is
        // refused the promotion — "startForegroundService() not allowed due to
        // mAllowStartForeground false". WorkManager's setForeground() is NOT
        // one of the Android 12+ background-start exemptions for periodic
        // work; only expedited work and a visible app are. So the promotion
        // is attempted (it succeeds on Android 8–11, and on 12+ when the user
        // launched the one-off from inside the app), and when it is refused
        // the run is capped INSIDE the plain worker's ~10-minute budget so it
        // ends cleanly — rclone quit, outcome recorded — rather than being
        // torn down mid-copy by WorkManager. A big first backup then proceeds
        // in slices, one per wake, resuming where it stopped: rclone copy
        // skips what the destination already has.
        val promoted = try {
            setForeground(foregroundInfo())
            true
        } catch (e: Exception) {
            Log.w(TAG, "foreground promotion refused: ${e.message}")
            false
        }
        val dartTimeoutMinutes = if (promoted) DART_TIMEOUT_MINUTES else UNPROMOTED_TIMEOUT_MINUTES

        val outcome = withTimeoutOrNull(TimeUnit.MINUTES.toMillis(dartTimeoutMinutes + 2)) {
            withContext(Dispatchers.Main) { runDart(handle, dartTimeoutMinutes) }
        } ?: (EXIT_CANNOT_START to "the Dart entrypoint did not report back within the cap")

        val detail = if (promoted) outcome.second
        else "${outcome.second}\n(ran without foreground promotion — Android 12+ refuses it to a background wake — so this run was capped at $UNPROMOTED_TIMEOUT_MINUTES min; a longer backup continues at the next wake)"
        stamp(prefs, outcome.first, detail)
        Log.i(TAG, "run-due finished with exit ${outcome.first} (promoted=$promoted): ${outcome.second}")
        // A failed task is recorded in that task's own history (TaskRunRecord);
        // there is nothing WorkManager could usefully retry. Success keeps the
        // period ticking; failure is visible in dumpsys and to the status call.
        return if (outcome.first == 0) Result.success() else Result.failure()
    }

    /// Requested by WorkManager for expedited work on older APIs; also the
    /// notification [setForeground] posts.
    override suspend fun getForegroundInfo(): ForegroundInfo = foregroundInfo()

    private fun foregroundInfo(): ForegroundInfo {
        TransferService.ensureChannel(applicationContext)
        val notification = TransferService.buildNotification(
            applicationContext,
            "Running scheduled tasks",
            "Checking what is due",
        )
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ForegroundInfo(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            ForegroundInfo(NOTIFICATION_ID, notification)
        }
    }

    /// Boots a headless engine on the main thread, runs the registered Dart
    /// callback, and resumes with (exit code, detail) when Dart calls `done`.
    /// Must be called on the main thread: FlutterEngine is main-thread-only.
    private suspend fun runDart(handle: Long, timeoutMinutes: Long): Pair<Int, String> =
        suspendCancellableCoroutine { cont ->
            val main = Handler(Looper.getMainLooper())
            var engine: FlutterEngine? = null
            var native: NativeChannel? = null
            var finished = false

            fun finish(code: Int, detail: String) {
                if (finished) return
                finished = true
                // Destroy on the next loop, never from inside the channel
                // callback that is still executing on this engine.
                main.post {
                    native?.dispose()
                    try {
                        engine?.destroy()
                    } catch (e: Exception) {
                        Log.w(TAG, "engine destroy: ${e.message}")
                    }
                }
                if (cont.isActive) cont.resume(code to detail)
            }

            cont.invokeOnCancellation { main.post { finish(EXIT_CANNOT_START, "cancelled") } }

            try {
                val loader = FlutterInjector.instance().flutterLoader()
                loader.startInitialization(applicationContext)
                loader.ensureInitializationComplete(applicationContext, null)
                val info = FlutterCallbackInformation.lookupCallbackInformation(handle)
                if (info == null) {
                    finish(EXIT_CANNOT_START, "callback handle $handle did not resolve (stale build?)")
                    return@suspendCancellableCoroutine
                }
                // FlutterEngine(Context) auto-registers every plugin in
                // GeneratedPluginRegistrant (path_provider, shared_preferences,
                // …) — the same set the Activity's engine gets.
                val e = FlutterEngine(applicationContext)
                engine = e
                val messenger = e.dartExecutor.binaryMessenger
                // The Application-scoped channel — no Activity, and none needed.
                native = NativeChannel.register(messenger, applicationContext)
                MethodChannel(messenger, BG_CHANNEL).setMethodCallHandler { call, result ->
                    when (call.method) {
                        "start" -> result.success(
                            mapOf(
                                "args" to listOf(
                                    "--run-due",
                                    "--timeout-minutes",
                                    timeoutMinutes.toString(),
                                ),
                            ),
                        )
                        "log" -> {
                            Log.i(TAG, call.argument<String>("line") ?: "")
                            result.success(null)
                        }
                        "done" -> {
                            val code = call.argument<Int>("code") ?: EXIT_CANNOT_START
                            val lines = call.argument<List<String>>("summary") ?: emptyList()
                            result.success(null)
                            finish(code, lines.joinToString("\n").ifEmpty { "(no summary)" })
                        }
                        else -> result.notImplemented()
                    }
                }
                e.dartExecutor.executeDartCallback(
                    DartExecutor.DartCallback(
                        applicationContext.assets,
                        loader.findAppBundlePath(),
                        info,
                    ),
                )
            } catch (t: Throwable) {
                Log.e(TAG, "could not start the headless engine", t)
                finish(EXIT_CANNOT_START, "headless engine failed to start: ${t.message}")
            }
        }

    /// What the last run did, for Settings and for `adb shell` verification.
    private fun stamp(prefs: android.content.SharedPreferences, code: Int, detail: String) {
        prefs.edit()
            .putLong(WorkChannel.KEY_LAST_RUN_AT, System.currentTimeMillis())
            .putInt(WorkChannel.KEY_LAST_EXIT, code)
            .putString(WorkChannel.KEY_LAST_DETAIL, detail.take(2000))
            .apply()
    }
}
