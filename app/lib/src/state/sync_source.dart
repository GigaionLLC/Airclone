import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/remote.dart';

/// The folder a later "Sync to here" will sync FROM.
///
/// Deliberately separate from the copy/cut clipboard rather than a third state
/// on it. The clipboard is a list of NAMES inside a folder; this is the folder
/// itself. `ClipboardItems.isNotEmpty` also drives whether Paste appears in five
/// places, so a sync mark living there would either surface Paste for something
/// that cannot be pasted or force every one of those call sites to learn about
/// sync. And the two gestures are orthogonal — marking a sync source should not
/// throw away what you copied a minute ago.
///
/// Session-only, like the clipboard. A mark that survived a restart would be a
/// pointer at a folder the user has long forgotten aiming, attached to an
/// operation that deletes.
@immutable
class SyncSource {
  const SyncSource({this.remote, this.path = ''});

  /// The marked remote, or null when nothing is marked.
  final Remote? remote;

  /// The folder within [remote], relative to its fs. Empty means its root.
  final String path;

  bool get isSet => remote != null;

  /// `name:path` — for menu rows and dialog headers.
  String get label => remote == null ? '' : '${remote!.name}:$path';

  /// The rclone fs string this syncs from, assembled the way
  /// `TransferService.transferAdvanced` assembles its own.
  String get fs => remote == null ? '' : '${remote!.fs}$path';
}

class SyncSourceController extends Notifier<SyncSource> {
  @override
  SyncSource build() => const SyncSource();

  /// Mark [path] within [remote] as the source of the next sync.
  void mark(Remote remote, String path) =>
      state = SyncSource(remote: remote, path: path);

  void clear() => state = const SyncSource();
}

final syncSourceProvider = NotifierProvider<SyncSourceController, SyncSource>(
  SyncSourceController.new,
);

/// Why syncing [srcFs] into [dstFs] must be refused, or null when it is sane.
///
/// A one-way sync makes the destination match the source and DELETES whatever
/// else is there, so an overlapping pair is not a mistake to warn about — it is
/// one to refuse. The marked-source flow makes these reachable in a way the
/// two-pane flow never did: the endpoints are now chosen minutes apart, so
/// "sync this remote's root into a folder inside it" is two clicks with nothing
/// on screen to make the overlap obvious.
///
/// Compared case-INSENSITIVELY. Two remotes' paths differing only in case is
/// vanishingly rare; a Windows local path reaching the same folder through a
/// different case is not. A false refusal costs a rename; a missed overlap costs
/// the data.
String? syncTargetRefusal({required String srcFs, required String dstFs}) {
  final src = _normalize(srcFs);
  final dst = _normalize(dstFs);
  if (src.isEmpty || dst.isEmpty) return 'That location is not a folder.';
  if (src == dst) {
    return 'The source and the destination are the same folder.';
  }
  if (_contains(src, dst)) {
    return 'The destination is inside the source. Syncing a folder into itself '
        'would copy it into a copy of itself.';
  }
  if (_contains(dst, src)) {
    return 'The source is inside the destination. A sync would delete '
        'everything else in the destination — including the folders around the '
        'source.';
  }
  return null;
}

String _normalize(String fs) {
  var s = fs.trim().toLowerCase().replaceAll('\\', '/');
  // One trailing slash carries no meaning here, but `remote:`'s colon does.
  while (s.length > 1 && s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

/// Whether [child] lies inside [parent], both already normalized.
///
/// A remote's root ends in `:` and a local root in `/` or `:`, and neither takes
/// a separator before its first segment — so `remote:` contains `remote:photos`
/// with no slash between them.
bool _contains(String parent, String child) {
  if (parent.endsWith(':') || parent.endsWith('/')) {
    return child.startsWith(parent);
  }
  return child.startsWith('$parent/');
}
