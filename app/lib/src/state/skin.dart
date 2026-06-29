import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/theme/tokens.dart' show Skin;

export '../ui/theme/tokens.dart' show Skin;

/// The active visual skin, persisted. Defaults to [Skin.airclone] (the brand
/// look); the OS skins (Windows/macOS/GNOME) are optional opt-ins.
class SkinController extends Notifier<Skin> {
  static const _key = 'skin';

  @override
  Skin build() {
    _load();
    return Skin.airclone;
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final name = p.getString(_key);
      if (name != null) {
        state = Skin.values.firstWhere(
          (s) => s.name == name,
          orElse: () => Skin.airclone,
        );
      }
    } catch (_) {
      // keep default
    }
  }

  Future<void> set(Skin value) async {
    state = value;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, value.name);
    } catch (_) {
      // best-effort
    }
  }
}

final skinProvider = NotifierProvider<SkinController, Skin>(SkinController.new);
