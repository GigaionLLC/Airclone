package app.airclone.airclone

import android.app.Activity
import android.app.Application
import android.os.Bundle

/// The process-wide root. Two jobs, both because a WorkManager worker runs
/// with no Activity in sight:
///
///  1. It is the [android.content.Context] the Application-scoped
///     `airclone/native` channel is built on (see NativeChannel.kt) — every
///     engine, foreground or background, registers against the same facts.
///  2. It knows whether the app is on screen. The in-app scheduler ticks every
///     30 s while it is, and runs due tasks itself; a background worker that
///     fired at the same moment would spawn a second rclone engine and race the
///     first over the same SharedPreferences. So the worker asks here and yields
///     when a visible Activity already owns the job (DueTasksWorker.kt).
class AircloneApplication : Application() {

    companion object {
        /// Number of our Activities between onStart and onStop. Read from the
        /// worker's thread; written on the main thread only.
        @Volatile
        private var startedActivities = 0

        /// True while any Activity of ours is on screen (started, not merely
        /// alive in the back stack).
        val activityVisible: Boolean
            get() = startedActivities > 0
    }

    override fun onCreate() {
        super.onCreate()
        registerActivityLifecycleCallbacks(object : ActivityLifecycleCallbacks {
            override fun onActivityStarted(activity: Activity) {
                startedActivities++
            }

            override fun onActivityStopped(activity: Activity) {
                startedActivities = maxOf(0, startedActivities - 1)
            }

            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
            override fun onActivityResumed(activity: Activity) {}
            override fun onActivityPaused(activity: Activity) {}
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
            override fun onActivityDestroyed(activity: Activity) {}
        })
    }
}
