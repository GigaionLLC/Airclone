import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/rclone_file.dart';
import '../rclone/models/remote.dart';

/// A snapshot of what the user has copied or cut, ready to be pasted into a
/// destination folder. The [remote] + [parentPath] locate the source so the
/// integrator can build each file's full path (`'$parentPath/${file.name}'`).
@immutable
class ClipboardItems {
  const ClipboardItems({
    required this.remote,
    required this.parentPath,
    required this.files,
    required this.isCut,
  });

  /// The source remote the [files] were taken from, or `null` when empty.
  final Remote? remote;

  /// The folder (relative to [remote]'s fs) the [files] live in.
  final String parentPath;

  /// The entries staged on the clipboard.
  final List<RcloneFile> files;

  /// `true` for a cut (move-on-paste), `false` for a copy.
  final bool isCut;

  /// Whether the clipboard holds nothing to paste.
  bool get isEmpty => files.isEmpty;

  /// Convenience: the opposite of [isEmpty].
  bool get isNotEmpty => files.isNotEmpty;
}

/// Holds the copy/cut staging area shared across both browser panes.
///
/// Pure state only: it records what was copied or cut and from where. The
/// integrator performs the actual transfer (e.g. `operations/copyfile` /
/// `operations/movefile`) on paste and then calls [clear] for a cut.
class ClipboardController extends Notifier<ClipboardItems> {
  @override
  ClipboardItems build() => const ClipboardItems(
    remote: null,
    parentPath: '',
    files: [],
    isCut: false,
  );

  /// Stage [files] from [r]/[parentPath] for a copy-on-paste.
  void copy(Remote r, String parentPath, List<RcloneFile> files) {
    state = ClipboardItems(
      remote: r,
      parentPath: parentPath,
      files: List.unmodifiable(files),
      isCut: false,
    );
  }

  /// Stage [files] from [r]/[parentPath] for a move-on-paste.
  void cut(Remote r, String parentPath, List<RcloneFile> files) {
    state = ClipboardItems(
      remote: r,
      parentPath: parentPath,
      files: List.unmodifiable(files),
      isCut: true,
    );
  }

  /// Empty the clipboard (call after a successful cut+paste).
  void clear() => state = const ClipboardItems(
    remote: null,
    parentPath: '',
    files: [],
    isCut: false,
  );
}

/// Shared clipboard for the dual-pane browser.
final clipboardControllerProvider =
    NotifierProvider<ClipboardController, ClipboardItems>(
      ClipboardController.new,
    );
