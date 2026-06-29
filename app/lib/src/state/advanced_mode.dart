import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Easy mode (default) keeps the UI simple; advanced mode reveals power-user
/// features — the advanced Copy/Move/Sync dialog and saved transfer tasks.
class AdvancedMode extends Notifier<bool> {
  static const _key = 'advanced_mode';

  @override
  bool build() {
    _load();
    return false;
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      state = p.getBool(_key) ?? false;
    } catch (_) {
      // keep default
    }
  }

  Future<void> set(bool v) async {
    state = v;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_key, v);
    } catch (_) {
      // best-effort
    }
  }
}

final advancedModeProvider = NotifierProvider<AdvancedMode, bool>(
  AdvancedMode.new,
);
