import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/theme/tokens.dart' show Skin;

export '../ui/theme/tokens.dart' show Skin;

/// The active visual skin, persisted. Defaults to the host OS's skin
/// ([Skin.forHost] — Explorer on Windows, Finder on macOS, GNOME on Linux) so
/// a fresh install reads like the file manager the user came from; a persisted
/// choice (including Airclone, the brand look) always wins.
class SkinController extends Notifier<Skin> {
  static const _key = 'skin';

  @override
  Skin build() {
    _load();
    return Skin.forHost();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final name = p.getString(_key);
      if (name != null) {
        state = Skin.values.firstWhere(
          (s) => s.name == name,
          orElse: () => Skin.forHost(),
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
