package app.airclone.airclone

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/// Foreground service held while transfers run. Android freezes (or kills)
/// cached background apps — and the bundled rclone engine is a child process
/// of this app — so without this, backgrounding the app stalls every
/// transfer. Type dataSync, with a live progress notification; started,
/// updated, and stopped from Dart over the airclone/native channel.
class TransferService : Service() {
    companion object {
        const val CHANNEL_ID = "transfers"
        const val NOTIFICATION_ID = 1001
        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Transfers",
                // Low importance: silent, no heads-up — it's a progress ticker.
                NotificationManager.IMPORTANCE_LOW
            )
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "Transferring files"
        val text = intent?.getStringExtra(EXTRA_TEXT) ?: ""
        val notification = build(title, text)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            // If the platform refuses the foreground promotion (e.g. the API 31+
            // background-start restriction races us here), bail out cleanly
            // instead of leaving a "started but never went foreground" service
            // that the system would ANR/kill a few seconds later.
            stopSelf()
        }
        return START_NOT_STICKY
    }

    // Android 15+ caps a dataSync foreground service at ~6 cumulative hours per
    // day; when the cap is hit the system calls onTimeout and requires us to
    // stop within seconds. Comply (the transfer's rclone child keeps running,
    // just without the keep-alive) rather than eating an ANR / forced removal.
    // Both overloads exist as of the compile SDK; only the matching one fires
    // per device API level.
    override fun onTimeout(startId: Int) {
        stopSelf()
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        stopSelf()
    }

    private fun build(title: String, text: String): Notification {
        val tap = PendingIntent.getActivity(
            this,
            0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        return Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(tap)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }
}
