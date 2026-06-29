import '../rclone/models/rclone_file.dart';
import '../rclone/models/remote.dart';

/// Joins a parent path and a leaf name with a single forward slash.
/// Empty parent yields the bare name (remote root).
String joinPath(String parent, String name) =>
    parent.isEmpty ? name : '$parent/$name';

/// Payload dragged from a file row/tile — one file, or the whole selection.
/// Shared by the list ([BrowserPane]) and grid ([FileGrid]) views and the
/// sidebar drop targets, so it lives here rather than in any one view.
class PaneDragData {
  const PaneDragData(this.remote, this.parentPath, this.files);
  final Remote remote;
  final String parentPath;
  final List<RcloneFile> files;
}
