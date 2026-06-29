import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The remembered default download folder (or null until one is chosen).
class DownloadDir extends Notifier<String?> {
  static const _key = 'download_dir';

  @override
  String? build() {
    _load();
    return null;
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      state = p.getString(_key);
    } catch (_) {
      // keep null
    }
  }

  Future<void> set(String? v) async {
    state = (v == null || v.isEmpty) ? null : v;
    try {
      final p = await SharedPreferences.getInstance();
      if (state == null) {
        await p.remove(_key);
      } else {
        await p.setString(_key, state!);
      }
    } catch (_) {
      // best-effort
    }
  }
}

final downloadDirProvider = NotifierProvider<DownloadDir, String?>(
  DownloadDir.new,
);

/// When true, every download asks where to save (instead of using the default).
class DownloadAlwaysPrompt extends Notifier<bool> {
  static const _key = 'download_always_prompt';

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

final downloadAlwaysPromptProvider =
    NotifierProvider<DownloadAlwaysPrompt, bool>(DownloadAlwaysPrompt.new);

/// Resolves the folder a download should go to. Uses the remembered default
/// unless "always ask" is on (or there is no default yet), in which case it
/// opens a native folder picker and remembers the choice. Returns a
/// forward-slashed path with NO trailing slash, or null if the user cancelled.
Future<String?> resolveDownloadDir(WidgetRef ref) async {
  final always = ref.read(downloadAlwaysPromptProvider);
  final saved = ref.read(downloadDirProvider);
  if (!always && saved != null && saved.isNotEmpty) return saved;
  final picked = await getDirectoryPath(
    initialDirectory: (saved != null && saved.isNotEmpty) ? saved : null,
  );
  if (picked == null) return null;
  final norm = picked.replaceAll('\\', '/');
  await ref.read(downloadDirProvider.notifier).set(norm);
  return norm;
}
