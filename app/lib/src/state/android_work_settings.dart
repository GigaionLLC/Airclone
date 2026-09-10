import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The conditions Android must meet before it wakes Airclone to run due tasks
/// (WorkManager constraints; see WorkChannel.kt).
///
/// [unmetered] defaults to ON because the headline background task on a phone
/// is a camera-roll backup, and a 40 GB roll on cellular is a bill. It is a
/// per-device setting rather than per-task because WorkManager applies it to
/// the single shared wake, not to what runs inside it.
@immutable
class AndroidWorkConstraints {
  const AndroidWorkConstraints({this.unmetered = true, this.charging = false});

  /// Wi-Fi (or another unmetered network) only.
  final bool unmetered;

  /// Only while plugged in.
  final bool charging;

  AndroidWorkConstraints copyWith({bool? unmetered, bool? charging}) =>
      AndroidWorkConstraints(
        unmetered: unmetered ?? this.unmetered,
        charging: charging ?? this.charging,
      );

  @override
  bool operator ==(Object other) =>
      other is AndroidWorkConstraints &&
      other.unmetered == unmetered &&
      other.charging == charging;

  @override
  int get hashCode => Object.hash(unmetered, charging);
}

class AndroidWorkSettings extends Notifier<AndroidWorkConstraints> {
  static const _unmeteredKey = 'android_work_unmetered';
  static const _chargingKey = 'android_work_charging';

  @override
  AndroidWorkConstraints build() {
    _load();
    return const AndroidWorkConstraints();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      state = AndroidWorkConstraints(
        unmetered: p.getBool(_unmeteredKey) ?? true,
        charging: p.getBool(_chargingKey) ?? false,
      );
    } catch (_) {
      // keep the defaults
    }
  }

  Future<void> setUnmetered(bool v) => _set(state.copyWith(unmetered: v));

  Future<void> setCharging(bool v) => _set(state.copyWith(charging: v));

  Future<void> _set(AndroidWorkConstraints next) async {
    if (next == state) return;
    state = next;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_unmeteredKey, next.unmetered);
      await p.setBool(_chargingKey, next.charging);
    } catch (_) {
      // best-effort; the in-memory value still drives this session
    }
  }
}

final androidWorkSettingsProvider =
    NotifierProvider<AndroidWorkSettings, AndroidWorkConstraints>(
      AndroidWorkSettings.new,
    );
