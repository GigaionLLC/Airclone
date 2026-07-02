import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/job.dart';
import 'jobs_controller.dart';
import 'stats_controller.dart';

/// Android: holds a dataSync foreground service (with a progress notification)
/// while transfers are queued/running, so the OS doesn't freeze the app — and
/// the rclone engine child process with it — when the user switches away.
///
/// Armed once from the shell's initState (same pattern as the scheduler);
/// no-op off Android. The jobs poller ticks every second, so this listener is
/// also the notification's update pulse (posts only when the text changes).
final transferForegroundServiceProvider = Provider<void>((ref) {
  if (!Platform.isAndroid) return;
  const channel = MethodChannel('airclone/native');
  var running = false;
  var askedForPermission = false;
  var lastText = '';

  ref.listen<List<Job>>(jobsControllerProvider, (_, jobs) async {
    final active = jobs
        .where(
          (j) => j.status == JobStatus.running || j.status == JobStatus.queued,
        )
        .length;
    try {
      if (active == 0) {
        if (running) {
          // Stop first; only clear the latch on success so a failed stop is
          // retried on the next (1s) poll tick instead of leaking a service
          // that outlives its transfers.
          await channel.invokeMethod<void>('stopTransferService');
          running = false;
          lastText = '';
        }
        return;
      }
      final speed = ref.read(statsProvider).speed;
      final text =
          '$active transfer${active == 1 ? '' : 's'}'
          '${speed > 0 ? ' · ${_humanSpeed(speed)}' : ''}';
      if (!running && !askedForPermission) {
        // Android 13+ shows the progress notification only after this grant;
        // the service itself runs either way.
        askedForPermission = true;
        await channel.invokeMethod<void>('requestNotificationPermission');
      }
      if (!running || text != lastText) {
        running = true;
        lastText = text;
        await channel.invokeMethod<void>('startTransferService', {
          'title': 'Transferring files',
          'text': text,
        });
      }
    } catch (_) {
      // Notification plumbing must never break transfers themselves.
    }
  });

  // If the provider graph is torn down mid-transfer, don't leak the service.
  ref.onDispose(() {
    if (running) {
      channel.invokeMethod<void>('stopTransferService').catchError((_) {});
    }
  });
});

String _humanSpeed(double bytesPerSec) {
  const units = ['B/s', 'KB/s', 'MB/s', 'GB/s'];
  var v = bytesPerSec;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 10 ? 0 : 1)} ${units[i]}';
}
