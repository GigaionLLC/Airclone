package app.airclone.airclone

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var native: NativeChannel? = null

    override fun onDestroy() {
        native?.dispose()
        native = null
        super.onDestroy()
    }

    // The `airclone/native` handler lives in NativeChannel.kt and is built on
    // the APPLICATION context, not this Activity: a WorkManager worker registers
    // the same handler on its own headless engine (DueTasksWorker.kt), where
    // there is no Activity at all. This Activity only lends itself for the few
    // calls that genuinely need one (permission prompts, choosers), and adds the
    // WorkManager channel, which only a foreground engine should ever hold.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        native = NativeChannel.register(messenger, applicationContext) { this }
        WorkChannel.register(messenger, applicationContext)
    }
}
