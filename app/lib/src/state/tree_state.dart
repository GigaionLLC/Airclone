/// The tree view's forest (tree-view plan §4.A).
///
/// The flat browser holds ONE folder: `BrowserState.path` + `entries`. The
/// tree holds many at once — a listing per expanded folder, keyed by that
/// folder's full path — and, unlike the flat listing, it is not cleared on
/// navigate. That is exactly the condition the v0.5.0 stale-listing race was
/// written against, which is why every row here carries its OWN parent path
/// ([TreeRow.parentPath]) and why nothing in this file reads `state.path`.
///
/// Everything here is pure data + pure functions so it can be tested without
/// an engine or a widget tree.
library;

import 'package:flutter/foundation.dart';

import '../rclone/models/rclone_file.dart';
import '../ui/pane_drag.dart' show joinPath;

/// Per-tab tree state, kept beside the flat listing in `BrowserState`.
///
/// Every key and every member of every set is a **full path relative to the
/// remote root** (the same shape as `RcloneFile.path`), never a bare name.
@immutable
class TreeState {
  const TreeState({
    this.children = const {},
    this.expanded = const {},
    this.loading = const {},
    this.errors = const {},
    this.selected = const {},
    this.cursor,
  });

  /// Cached listings by folder path. Filled lazily — one `operations/list` on
  /// a folder's FIRST expand — and kept across collapse so re-expanding costs
  /// nothing. The root's listing is NOT here; it is `BrowserState.entries`.
  final Map<String, List<RcloneFile>> children;

  /// Folders currently open. Session-only on purpose: a tree that reopened
  /// forty folders at launch would issue forty listings (plan §5).
  final Set<String> expanded;

  /// Folders whose listing is in flight (the disclosure shows a spinner).
  final Set<String> loading;

  /// Folders whose last listing failed, with the error text.
  final Map<String, String> errors;

  /// The tree's multi-selection: full paths, which may span several folders.
  /// Deliberately separate from `BrowserState.selected` (names within ONE
  /// folder) — see `BrowserState.selectedEntries`.
  final Set<String> selected;

  /// The keyboard cursor row (full path), or null.
  final String? cursor;

  TreeState copyWith({
    Map<String, List<RcloneFile>>? children,
    Set<String>? expanded,
    Set<String>? loading,
    Map<String, String>? errors,
    Set<String>? selected,
    String? cursor,
    bool clearCursor = false,
  }) => TreeState(
    children: children ?? this.children,
    expanded: expanded ?? this.expanded,
    loading: loading ?? this.loading,
    errors: errors ?? this.errors,
    selected: selected ?? this.selected,
    cursor: clearCursor ? null : (cursor ?? this.cursor),
  );

  /// The tree with everything forgotten — used when the remote changes, since
  /// path keys from one remote mean nothing on another.
  static const empty = TreeState();
}

/// What a flattened row is: a real entry, or one of the two placeholder rows
/// an expanded folder shows beneath itself when it has nothing to show.
enum TreeRowKind { entry, empty, error }

/// One row of the flattened tree.
///
/// [parentPath] is the folder this row lives in and is the ONLY thing an
/// operation may build the row's path from. It is captured when the row is
/// flattened from `children[parentPath]`, so it cannot drift from the listing
/// the row came out of.
@immutable
class TreeRow {
  const TreeRow.entry({
    required RcloneFile this.entry,
    required this.parentPath,
    required this.depth,
  }) : kind = TreeRowKind.entry,
       message = '';

  /// The "Empty" placeholder under an expanded folder with no children.
  /// [parentPath] is that folder.
  const TreeRow.empty({required this.parentPath, required this.depth})
    : entry = null,
      kind = TreeRowKind.empty,
      message = '';

  /// The "could not list" placeholder under an expanded folder whose listing
  /// failed. [parentPath] is that folder.
  const TreeRow.error({
    required this.parentPath,
    required this.depth,
    required this.message,
  }) : entry = null,
       kind = TreeRowKind.error;

  /// The listed entry — null for the two placeholder kinds.
  final RcloneFile? entry;
  final String parentPath;
  final int depth;
  final TreeRowKind kind;
  final String message;

  bool get isEntry => kind == TreeRowKind.entry;

  /// The entry. Only meaningful for [TreeRowKind.entry] rows.
  RcloneFile get file => entry!;

  bool get isDir => entry?.isDir ?? false;

  /// The row's full path — parent + name for an entry; for a placeholder, the
  /// folder it describes (so the two kinds never share a key with an entry).
  String get path => isEntry ? joinPath(parentPath, file.name) : parentPath;

  /// A key that is unique per row: two placeholder kinds can share a folder,
  /// and an entry can share its path with neither.
  String get key => '${kind.name}:$path';
}

/// The folder part of a full path (`''` for a top-level name).
String parentOf(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? '' : path.substring(0, i);
}

/// The leaf name of a full path.
String leafOf(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? path : path.substring(i + 1);
}

/// True when [path] is strictly inside [folder] (`''` is the root and holds
/// everything except itself).
bool isUnder(String path, String folder) =>
    folder.isEmpty ? path.isNotEmpty : path.startsWith('$folder/');

/// Flattens the forest into the rows a single `ListView` shows, top to bottom,
/// depth-first, in listing order. No nested scrollables (plan §4.B).
///
/// [rootPath] is the folder the tree is rooted at and [rootEntries] its
/// (already sorted) listing — `BrowserState.path` / `.entries`. Deeper levels
/// come from [tree.children]. Each row's [TreeRow.parentPath] is the folder
/// whose listing it was read from.
///
/// [filter] is the pane's Ctrl+F text and is a filter over what is LOADED,
/// not a search: a row stays when its name matches, and an expanded folder
/// stays when any loaded descendant matches (so the match remains reachable).
/// A collapsed folder is not opened to look inside it — that would be a
/// recursive walk (plan §4.f).
List<TreeRow> flattenTree({
  required String rootPath,
  required List<RcloneFile> rootEntries,
  required TreeState tree,
  String filter = '',
}) {
  final out = <TreeRow>[];
  final q = filter.toLowerCase();

  // Returns whether anything under [entries] was emitted (drives the
  // keep-the-ancestor rule when filtering).
  bool visit(String parentPath, List<RcloneFile> entries, int depth) {
    var emitted = false;
    for (final f in entries) {
      final path = joinPath(parentPath, f.name);
      final matches = q.isEmpty || f.name.toLowerCase().contains(q);
      if (f.isDir && tree.expanded.contains(path)) {
        final mark = out.length;
        out.add(TreeRow.entry(entry: f, parentPath: parentPath, depth: depth));
        var any = false;
        final kids = tree.children[path];
        if (kids != null) {
          any = visit(path, kids, depth + 1);
          if (kids.isEmpty && q.isEmpty) {
            out.add(TreeRow.empty(parentPath: path, depth: depth + 1));
          }
        } else {
          final err = tree.errors[path];
          if (err != null && q.isEmpty) {
            out.add(
              TreeRow.error(parentPath: path, depth: depth + 1, message: err),
            );
          }
          // Still loading: the disclosure shows the spinner; no row.
        }
        if (matches || any) {
          emitted = true;
        } else {
          out.removeRange(mark, out.length);
        }
      } else if (matches) {
        out.add(TreeRow.entry(entry: f, parentPath: parentPath, depth: depth));
        emitted = true;
      }
    }
    return emitted;
  }

  visit(rootPath, rootEntries, 0);
  return out;
}

/// The expanded folders that are actually on screen under [rootPath] — every
/// ancestor between the root and the folder is itself expanded — shallowest
/// first. This is the bounded set a refresh re-lists: what the user opened and
/// can see, never the whole forest.
List<String> visibleExpandedFolders(String rootPath, TreeState tree) {
  bool visible(String p) {
    if (!isUnder(p, rootPath)) return false;
    var parent = parentOf(p);
    while (parent != rootPath) {
      if (!tree.expanded.contains(parent)) return false;
      // A parent above the root can only happen for a path that is not under
      // the root, which isUnder already excluded — but never loop forever.
      if (parent.isEmpty) return false;
      parent = parentOf(parent);
    }
    return true;
  }

  final out = tree.expanded.where(visible).toList()
    ..sort((a, b) {
      final d = a.split('/').length.compareTo(b.split('/').length);
      return d != 0 ? d : a.compareTo(b);
    });
  return out;
}

/// Groups entry rows by the folder they live in, keeping first-seen order for
/// both the folders and the files within each. This is the shape every
/// multi-item operation needs: `transferNamesIntoFolder` takes ONE source
/// folder + names, so a selection spanning folders becomes one call per group
/// (plan §4.D) — the same shape an OS drop from several folders already uses.
Map<String, List<RcloneFile>> groupByParent(Iterable<TreeRow> rows) {
  final groups = <String, List<RcloneFile>>{};
  for (final r in rows) {
    if (!r.isEntry) continue;
    (groups[r.parentPath] ??= <RcloneFile>[]).add(r.file);
  }
  return groups;
}
