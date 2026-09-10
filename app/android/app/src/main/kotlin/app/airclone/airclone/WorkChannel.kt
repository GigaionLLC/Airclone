package app.airclone.airclone

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/// The `airclone/work` MethodChannel: Dart's handle on WorkManager (see
/// android_work_channel.dart). Registered on the foreground engine only —
/// enqueueing is something the app does, never something a worker does to
/// itself.
///
/// One periodic request under one fixed unique name is the whole design. It
/// is the Android half of the "shared poller" in registration_policy.dart:
/// WorkManager wakes us on a cadence and the Dart entrypoint runs whatever
/// `dueTasks` says is due, exactly as `--run-due` does on Windows. There are no
/// exact-time triggers here — WorkManager has none — so daily and weekly
/// schedules are served by the same poll and can start up to one period late.
///
/// **No BOOT_COMPLETED receiver, on purpose.** WorkManager persists its
/// requests in its own database and re-arms them after a reboot through the
/// receiver it declares itself; a second one of ours would be a second wakeup
/// source with nothing to add.
class WorkChannel private constructor(private val context: Context) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val NAME = "airclone/work"

        /// The one periodic request. A fixed name so it can be updated in place,
        /// cancelled by name, and recognised in `dumpsys jobscheduler` output.
        const val UNIQUE_PERIODIC = "airclone.run-due"

        /// A user-triggered "run the due tasks now, in the background".
        const val UNIQUE_ONCE = "airclone.run-due.once"

        /// Android's floor for periodic work. Anything smaller is silently
        /// raised by WorkManager; we clamp here so the value Dart reads back is
        /// the one that is really in force.
        const val MIN_INTERVAL_MINUTES = 15L

        const val PREFS = "airclone_work"
        const val KEY_CALLBACK = "callback_handle"
        const val KEY_LAST_RUN_AT = "last_run_at"
        const val KEY_LAST_EXIT = "last_exit_code"
        const val KEY_LAST_DETAIL = "last_detail"

        fun register(messenger: BinaryMessenger, context: Context): WorkChannel {
            val handler = WorkChannel(context.applicationContext)
            MethodChannel(messenger, NAME).setMethodCallHandler(handler)
            return handler
        }
    }

    /// `WorkManager.getWorkInfos…().get()` blocks on the WorkManager database,
    /// which must not happen on the platform thread.
    private val io = Executors.newSingleThreadExecutor()
    private val mainThread = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // The Dart entrypoint the worker will run, as a raw callback handle
            // (PluginUtilities.getCallbackHandle). Persisted natively because
            // the worker starts a fresh engine with nothing but this to go on.
            "registerCallback" -> {
                val handle = call.argument<Number>("handle")?.toLong()
                if (handle == null || handle == 0L) {
                    result.error("bad_args", "handle is required", null)
                } else {
                    prefs().edit().putLong(KEY_CALLBACK, handle).apply()
                    result.success(null)
                }
            }
            "enqueuePeriodic" -> {
                val minutes = maxOf(
                    MIN_INTERVAL_MINUTES,
                    (call.argument<Number>("intervalMinutes") ?: MIN_INTERVAL_MINUTES).toLong(),
                )
                val unmetered = call.argument<Boolean>("unmetered") ?: true
                val charging = call.argument<Boolean>("charging") ?: false
                val request = PeriodicWorkRequestBuilder<DueTasksWorker>(minutes, TimeUnit.MINUTES)
                    .setConstraints(constraints(unmetered = unmetered, charging = charging))
                    .addTag(UNIQUE_PERIODIC)
                    .build()
                try {
                    // UPDATE rather than REPLACE: a changed constraint or cadence
                    // is applied to the existing request without resetting its
                    // next-run time, so re-saving a task does not push the next
                    // poll out by a whole period.
                    WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                        UNIQUE_PERIODIC,
                        ExistingPeriodicWorkPolicy.UPDATE,
                        request,
                    )
                    result.success(minutes.toInt())
                } catch (e: Exception) {
                    result.error("enqueue_failed", e.message, null)
                }
            }
            "cancelPeriodic" -> {
                try {
                    WorkManager.getInstance(context).cancelUniqueWork(UNIQUE_PERIODIC)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("cancel_failed", e.message, null)
                }
            }
            // No constraints: the user asked for it now, on whatever network
            // they are on. KEEP so a double-tap does not queue two.
            "runOnce" -> {
                val request = OneTimeWorkRequestBuilder<DueTasksWorker>()
                    .addTag(UNIQUE_ONCE)
                    .build()
                try {
                    WorkManager.getInstance(context).enqueueUniqueWork(
                        UNIQUE_ONCE,
                        ExistingWorkPolicy.KEEP,
                        request,
                    )
                    result.success(null)
                } catch (e: Exception) {
                    result.error("enqueue_failed", e.message, null)
                }
            }
            "status" -> status(result)
            else -> result.notImplemented()
        }
    }

    private fun prefs() = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun constraints(unmetered: Boolean, charging: Boolean): Constraints =
        Constraints.Builder()
            // Wi-Fi-only is the default because a 40 GB camera roll on cellular
            // is a bill. CONNECTED (any network) only when the user turned the
            // Wi-Fi-only setting off.
            .setRequiredNetworkType(if (unmetered) NetworkType.UNMETERED else NetworkType.CONNECTED)
            .setRequiresCharging(charging)
            .build()

    /// What WorkManager currently holds for the periodic request, plus the
    /// stamp the worker leaves behind after each run. All optional: an absent
    /// key means "never", not an error.
    private fun status(result: MethodChannel.Result) {
        io.execute {
            val out = HashMap<String, Any?>()
            try {
                val infos = WorkManager.getInstance(context)
                    .getWorkInfosForUniqueWork(UNIQUE_PERIODIC)
                    .get(5, TimeUnit.SECONDS)
                val live = infos.firstOrNull { !it.state.isFinished }
                out["enqueued"] = live != null
                out["state"] = live?.state?.name
                if (live != null) {
                    val next = live.nextScheduleTimeMillis
                    // Long.MAX_VALUE is WorkManager's "not scheduled yet".
                    if (next in 1 until Long.MAX_VALUE) out["nextRunAt"] = next
                }
            } catch (e: Exception) {
                out["enqueued"] = false
                out["error"] = e.message
            }
            val p = prefs()
            if (p.contains(KEY_LAST_RUN_AT)) out["lastRunAt"] = p.getLong(KEY_LAST_RUN_AT, 0L)
            if (p.contains(KEY_LAST_EXIT)) out["lastExitCode"] = p.getInt(KEY_LAST_EXIT, -1)
            out["lastDetail"] = p.getString(KEY_LAST_DETAIL, null)
            out["sdk"] = Build.VERSION.SDK_INT
            mainThread.post { result.success(out) }
        }
    }
}
