import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../rclone/models/remote.dart';

/// A pinned folder: enough to rebuild its [Remote] and navigate back into it.
@immutable
class Bookmark {
  const Bookmark({
    required this.name,
    required this.type,
    required this.fs,
    required this.path,
    this.isLocal = false,
  });

  /// Remote/location name (no trailing colon).
  final String name;
  final String type;
  final String fs;

  /// Folder path within the remote (`''` = its root).
  final String path;
  final bool isLocal;

  /// Stable identity — a remote+path is pinned at most once.
  String get key => '$fs|$path';

  /// Human label, e.g. `gdrive/Work/Q1` (or just `gdrive` at the root).
  String get label => path.isEmpty ? name : '$name/$path';

  /// Rebuilds the [Remote] this bookmark points into.
  Remote get remote => Remote(name: name, type: type, fs: fs, isLocal: isLocal);

  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type,
    'fs': fs,
    'path': path,
    'isLocal': isLocal,
  };

  factory Bookmark.fromJson(Map<String, dynamic> j) => Bookmark(
    name: (j['name'] ?? '') as String,
    type: (j['type'] ?? '') as String,
    fs: (j['fs'] ?? '') as String,
    path: (j['path'] ?? '') as String,
    isLocal: (j['isLocal'] ?? false) as bool,
  );
}

/// The user's pinned folders ("Favorites"), persisted across launches. Order is
/// most-recently-pinned first.
class BookmarksController extends Notifier<List<Bookmark>> {
  static const _key = 'bookmarks';

  @override
  List<Bookmark> build() {
    _load();
    return const [];
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null) return;
      final list = (jsonDecode(raw) as List)
          .cast<Map<String, dynamic>>()
          .map(Bookmark.fromJson)
          .toList();
      state = list;
    } catch (_) {
      /* keep default */
    }
  }

  Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _key,
        jsonEncode(state.map((b) => b.toJson()).toList()),
      );
    } catch (_) {
      /* best-effort */
    }
  }

  static String _keyFor(String fs, String path) => '$fs|$path';

  bool isPinned(String fs, String path) {
    final k = _keyFor(fs, path);
    return state.any((b) => b.key == k);
  }

  /// Pin a folder (no-op if already pinned). Newest first.
  void add(Bookmark b) {
    if (isPinned(b.fs, b.path)) return;
    state = [b, ...state];
    _persist();
  }

  /// Unpin whatever folder matches [fs]+[path].
  void remove(String fs, String path) {
    final k = _keyFor(fs, path);
    state = state.where((b) => b.key != k).toList();
    _persist();
  }
}

final bookmarksProvider = NotifierProvider<BookmarksController, List<Bookmark>>(
  BookmarksController.new,
);
