/// Handing a cloud object to *another* app.
///
/// Other apps cannot read our objects directly: the engine serves them from a
/// loopback URL behind Basic auth, which no external player/viewer can present.
/// So the bytes are STAGED — streamed into the app's own cache dir — and the
/// resulting real file is what the OS receives:
///
///  * Android — a `content://` URI from our `FileProvider` (authority
///    `<applicationId>.fileprovider`) attached to an ACTION_VIEW / ACTION_SEND
///    chooser with a one-shot read grant. See MainActivity.kt.
///  * Desktop — a `file:` URL through `url_launcher`, i.e. the shell's default
///    handler.
///
/// A LOCAL remote needs none of this; callers pass its real OS path straight to
/// [handOffToOs] and skip staging entirely.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../rclone/rclone_client.dart';

/// Whether the staged file is opened for viewing or offered to a share target.
/// Desktop has no share concept and always opens.
enum ExternalOpenMode { view, share }

/// Whether this platform can hand a file to another app at all. iOS has no
/// implementation yet (it also has no engine — see the dual-engine plan), so
/// callers hide the action there rather than failing at the tap.
bool get canOpenExternally =>
    Platform.isAndroid ||
    Platform.isWindows ||
    Platform.isMacOS ||
    Platform.isLinux;

/// Cancellation handle for one [stageForExternalOpen] run.
///
/// Cancelling does two things: it sets the flag the stream loop checks, AND it
/// aborts the in-flight HTTP request. The flag alone isn't enough — a cloud read
/// that has stalled delivers no further chunks, so the loop would never notice
/// and Cancel would appear to do nothing.
class ExternalOpenTask {
  bool _cancelled = false;
  void Function()? _abort;

  bool get cancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    final abort = _abort;
    _abort = null;
    abort?.call();
  }
}

/// Staged files live here, under the app cache so the OS can reclaim them.
const String _stageDirName = 'airclone_open';

/// How long a staged file survives. The receiving app has usually finished with
/// it long before this; the TTL just stops the directory growing forever.
const Duration _stageTtl = Duration(hours: 12);

/// Streams [object] into the staging dir under [name] and returns the staged
/// path, or null if [task] was cancelled first.
///
/// [onProgress] reports `(received, total)`; `total` is null when the server
/// sends no Content-Length. Throws on transport/HTTP failure — the caller
/// surfaces the message.
Future<String?> stageForExternalOpen({
  required ObjectRef object,
  required String name,
  required ExternalOpenTask task,
  void Function(int received, int? total)? onProgress,
}) async {
  final dir = await _stageDir();
  final leaf = _safeLeaf(name);
  await _pruneStage(dir, keep: leaf);

  final target = File('${dir.path}/$leaf');
  // Write to `.part` first so a cancelled or failed run can never hand a
  // truncated file to another app.
  final partial = File('${target.path}.part');

  final client = http.Client();
  // Closing the client mid-stream is what makes Cancel instant on a stalled
  // read; the resulting stream error is recognised as cancellation below.
  task._abort = client.close;
  IOSink? sink;
  try {
    final request = http.Request('GET', Uri.parse(object.url))
      ..headers.addAll(object.headers);
    final response = await client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final total = response.contentLength;
    var received = 0;
    sink = partial.openWrite();
    await for (final chunk in response.stream) {
      if (task.cancelled) break;
      sink.add(chunk);
      received += chunk.length;
      onProgress?.call(received, total);
    }
    await sink.flush();
    await sink.close();
    sink = null;

    if (task.cancelled) {
      await _quietDelete(partial);
      return null;
    }
    // Replace any previous staging of the same name (Windows rename won't
    // clobber, and a stale same-name file would otherwise be re-opened).
    await _quietDelete(target);
    await partial.rename(target.path);
    return target.path;
  } catch (_) {
    await _quietDelete(partial);
    // An abort raised by cancel() lands here — that's a cancellation, not a
    // failure the user should see an error about.
    if (task.cancelled) return null;
    rethrow;
  } finally {
    task._abort = null;
    try {
      await sink?.close();
    } catch (_) {
      // Already closed, or the write failed — nothing left to do.
    }
    client.close();
  }
}

/// Hands the real file at [path] to the OS. [mime] steers Android's chooser;
/// desktop ignores it and lets the shell decide from the extension.
Future<void> handOffToOs(
  String path, {
  required String mime,
  ExternalOpenMode mode = ExternalOpenMode.view,
}) async {
  if (Platform.isAndroid) {
    await const MethodChannel('airclone/native').invokeMethod<bool>(
      'openExternal',
      {'path': path, 'mime': mime, 'share': mode == ExternalOpenMode.share},
    );
    return;
  }
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    if (!await launchUrl(Uri.file(path))) {
      throw Exception('No app is registered to open this kind of file.');
    }
    return;
  }
  throw Exception('Opening in another app is not supported on this platform.');
}

/// Best-effort MIME type for [name], preferring rclone's own [fallback]
/// (`RcloneFile.mimeType`) when it is meaningful.
///
/// Android's chooser is only as good as the type we give it: `*/*` offers every
/// app on the device, so an extension we recognise always wins over a generic
/// `application/octet-stream` from the backend.
String mimeForName(String name, {String fallback = ''}) {
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 || dot == name.length - 1
      ? ''
      : name.substring(dot + 1).toLowerCase();
  final known = _mimeByExt[ext];
  if (known != null) return known;
  final trimmed = fallback.trim();
  if (trimmed.isNotEmpty && trimmed != 'application/octet-stream') {
    return trimmed;
  }
  return 'application/octet-stream';
}

/// Extensions the app itself previews (see preview_dialog.dart) plus the common
/// document/archive types a phone is likely to have a handler for.
const Map<String, String> _mimeByExt = {
  // images
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'bmp': 'image/bmp',
  'heic': 'image/heic',
  'heif': 'image/heif',
  'svg': 'image/svg+xml',
  // video
  'mp4': 'video/mp4',
  'm4v': 'video/x-m4v',
  'mkv': 'video/x-matroska',
  'webm': 'video/webm',
  'mov': 'video/quicktime',
  'avi': 'video/x-msvideo',
  'mpg': 'video/mpeg',
  'mpeg': 'video/mpeg',
  'wmv': 'video/x-ms-wmv',
  '3gp': 'video/3gpp',
  // audio
  'mp3': 'audio/mpeg',
  'flac': 'audio/flac',
  'wav': 'audio/wav',
  'ogg': 'audio/ogg',
  'opus': 'audio/opus',
  'm4a': 'audio/mp4',
  'aac': 'audio/aac',
  'wma': 'audio/x-ms-wma',
  // documents / text
  'pdf': 'application/pdf',
  'txt': 'text/plain',
  'log': 'text/plain',
  'md': 'text/markdown',
  'csv': 'text/csv',
  'json': 'application/json',
  'xml': 'application/xml',
  'yaml': 'application/x-yaml',
  'yml': 'application/x-yaml',
  'html': 'text/html',
  'htm': 'text/html',
  'doc': 'application/msword',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx':
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  // archives
  'zip': 'application/zip',
  'gz': 'application/gzip',
  '7z': 'application/x-7z-compressed',
  'rar': 'application/vnd.rar',
  'tar': 'application/x-tar',
};

Future<Directory> _stageDir() async {
  Directory base;
  try {
    base = await getApplicationCacheDirectory();
  } catch (_) {
    base = await getTemporaryDirectory();
  }
  final dir = Directory('${base.path}/$_stageDirName');
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

/// Deletes staged files older than [_stageTtl], never touching [keep] (the leaf
/// we are about to write). Best-effort: a file the receiving app still holds
/// open simply stays and is retried on the next hand-off.
Future<void> _pruneStage(Directory dir, {String? keep}) async {
  try {
    final cutoff = DateTime.now().subtract(_stageTtl);
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final leaf = entity.uri.pathSegments.last;
      if (leaf == keep || leaf == '$keep.part') continue;
      try {
        if ((await entity.stat()).modified.isBefore(cutoff)) {
          await entity.delete();
        }
      } catch (_) {
        // Locked or already gone — skip it.
      }
    }
  } catch (_) {
    // Pruning is housekeeping; never let it block an open.
  }
}

Future<void> _quietDelete(File file) async {
  try {
    if (await file.exists()) await file.delete();
  } catch (_) {
    // Locked by a receiving app, or already gone.
  }
}

/// Strips path separators and characters Windows rejects, so a remote name can
/// never escape the staging dir or produce an unopenable file.
String _safeLeaf(String name) {
  final cleaned = name
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
      .replaceAll(RegExp(r'^\.+'), '')
      .trim();
  return cleaned.isEmpty ? 'file' : cleaned;
}
