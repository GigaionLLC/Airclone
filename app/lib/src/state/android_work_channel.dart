import 'dart:io';
import 'dart:ui' show PluginUtilities;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Dart's handle on Android WorkManager (see WorkChannel.kt).
///
/// One periodic request under one fixed name is the whole design — the
/// Android half of the "shared poller" in registration_policy.dart. Every call
/// here is a safe no-op off Android and never throws: background scheduling
/// failing must never take the settings screen down with it.
const String kAndroidWorkChannel = 'airclone/work';

/// What WorkManager currently holds for the periodic request, plus the stamp
/// the worker leaves behind after each run. Everything optional: absent means
/// "never", not "broken".
@immutable
class AndroidWorkStatus {
  const AndroidWorkStatus({
    required this.enqueued,
    this.state,
    this.nextRunAt,
    this.lastRunAt,
    this.lastExitCode,
    this.lastDetail,
    this.error,
  });

  /// Whether a live (not finished/cancelled) periodic request exists.
  final bool enqueued;

  /// WorkManager's own state name (`ENQUEUED`, `RUNNING`, …), for diagnostics.
  final String? state;

  /// When WorkManager expects to run it next, if it has decided.
  final DateTime? nextRunAt;

  /// When the worker last ran to completion (any exit code).
  final DateTime? lastRunAt;

  /// The headless exit code of that run: 0 ok, 1 a task failed, 2 could not
  /// start (see headless_runner.dart).
  final int? lastExitCode;

  /// The run's summary lines, joined — or the reason it could not start.
  final String? lastDetail;

  /// A platform-side failure reading the status, if any.
  final String? error;

  static const none = AndroidWorkStatus(enqueued: false);

  factory AndroidWorkStatus.fromMap(Map<Object?, Object?> m) {
    DateTime? at(Object? v) =>
        v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;
    return AndroidWorkStatus(
      enqueued: m['enqueued'] == true,
      state: m['state'] as String?,
      nextRunAt: at(m['nextRunAt']),
      lastRunAt: at(m['lastRunAt']),
      lastExitCode: (m['lastExitCode'] as num?)?.toInt(),
      lastDetail: m['lastDetail'] as String?,
      error: m['error'] as String?,
    );
  }
}

/// The channel wrapper. Injectable so a test can hand it a fake channel; the
/// default talks to WorkChannel.kt.
class AndroidWork {
  const AndroidWork({this.channel = const MethodChannel(kAndroidWorkChannel)});

  final MethodChannel channel;
  MethodChannel get _channel => channel;

  /// Stores the raw callback handle of [entrypoint] natively, so a worker
  /// starting a fresh engine knows which Dart function to run. Must be a
  /// top-level or static function annotated `@pragma('vm:entry-point')`.
  /// Returns false when the handle could not be resolved or stored.
  Future<bool> registerCallback(Function entrypoint) async {
    if (!Platform.isAndroid) return false;
    final handle = PluginUtilities.getCallbackHandle(entrypoint);
    if (handle == null) return false;
    try {
      await _channel.invokeMethod<void>('registerCallback', {
        'handle': handle.toRawHandle(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Creates or updates the periodic request. Returns the interval actually in
  /// force (WorkManager's floor is 15 minutes), or null on failure.
  Future<int?> enqueuePeriodic({
    required int intervalMinutes,
    required bool unmetered,
    required bool charging,
  }) async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<int>('enqueuePeriodic', {
        'intervalMinutes': intervalMinutes,
        'unmetered': unmetered,
        'charging': charging,
      });
    } catch (_) {
      return null;
    }
  }

  /// Removes the periodic request. Returns whether the platform accepted it.
  Future<bool> cancelPeriodic() async {
    if (!Platform.isAndroid) return false;
    try {
      await _channel.invokeMethod<void>('cancelPeriodic');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Queues one unconstrained run of the due tasks in the background — the
  /// user asked for it now, on whatever network they are on.
  Future<bool> runOnce() async {
    if (!Platform.isAndroid) return false;
    try {
      await _channel.invokeMethod<void>('runOnce');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<AndroidWorkStatus> status() async {
    if (!Platform.isAndroid) return AndroidWorkStatus.none;
    try {
      final m = await _channel.invokeMethod<Map<Object?, Object?>>('status');
      return m == null ? AndroidWorkStatus.none : AndroidWorkStatus.fromMap(m);
    } catch (e) {
      return AndroidWorkStatus(enqueued: false, error: '$e');
    }
  }
}

final androidWorkProvider = Provider<AndroidWork>((_) => const AndroidWork());

/// A fresh read of the WorkManager status each time something watches it.
/// autoDispose so the settings section re-asks on every open rather than
/// showing the answer from the last time it was on screen.
final androidWorkStatusProvider = FutureProvider.autoDispose<AndroidWorkStatus>(
  (ref) => ref.read(androidWorkProvider).status(),
);
