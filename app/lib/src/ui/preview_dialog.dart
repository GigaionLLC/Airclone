import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:pdfrx/pdfrx.dart';

import '../rclone/models/rclone_file.dart';
import '../rclone/models/remote.dart';
import '../rclone/rclone_client.dart';
import '../state/engine_controller.dart';
import 'format.dart';
import 'media_preview.dart';
import 'theme/tokens.dart';

/// Largest text/markdown payload we fetch + render inline. Anything beyond this
/// is truncated (with a note) so a stray multi-megabyte log never freezes the UI.
const int _maxTextBytes = 512 * 1024;

/// The kind of preview to render, chosen from extension first, then mimeType.
enum _PreviewKind { image, text, markdown, pdf, video, audio, unsupported }

/// Opens a large, themed [Dialog] previewing [file] (which lives at
/// [parentPath] within [remote]). The content is fetched lazily through the
/// running engine's authenticated object URL.
///
/// Safe to call for any file: unsupported types fall back to a friendly
/// "No preview available" card, and every render branch is guarded so a fetch
/// or decode failure surfaces as an inline message rather than throwing.
Future<void> showPreviewDialog(
  BuildContext context,
  WidgetRef ref,
  Remote remote,
  String parentPath,
  RcloneFile file,
) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) =>
        _PreviewDialog(remote: remote, parentPath: parentPath, file: file),
  );
}

/// Joins a parent path with a leaf name into an rclone `remote` path
/// (e.g. `'a/b'` + `'file.png'` -> `'a/b/file.png'`).
String _joinPath(String parentPath, String name) {
  final trimmed = parentPath.trim();
  if (trimmed.isEmpty) return name;
  return trimmed.endsWith('/') ? '$trimmed$name' : '$trimmed/$name';
}

/// Lower-cased file extension without the dot, or `''` when there is none.
String _extOf(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1).toLowerCase();
}

const Set<String> _imageExts = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};

const Set<String> _markdownExts = {'md', 'markdown'};

const Set<String> _textExts = {
  'txt',
  'log',
  'json',
  'yaml',
  'yml',
  'dart',
  'js',
  'ts',
  'py',
  'sh',
  'c',
  'cpp',
  'h',
  'xml',
  'csv',
  'ini',
  'conf',
  'toml',
};

const Set<String> _videoExts = {
  'mp4',
  'mkv',
  'webm',
  'mov',
  'avi',
  'm4v',
  'mpg',
  'mpeg',
  'wmv',
};

const Set<String> _audioExts = {
  'mp3',
  'flac',
  'wav',
  'ogg',
  'm4a',
  'aac',
  'opus',
  'wma',
};

_PreviewKind _kindFor(RcloneFile file) {
  final ext = _extOf(file.name);
  if (_imageExts.contains(ext)) return _PreviewKind.image;
  if (_markdownExts.contains(ext)) return _PreviewKind.markdown;
  if (ext == 'pdf') return _PreviewKind.pdf;
  if (_videoExts.contains(ext)) return _PreviewKind.video;
  if (_audioExts.contains(ext)) return _PreviewKind.audio;
  if (_textExts.contains(ext)) return _PreviewKind.text;

  // Fall back to mimeType for extension-less files.
  final mime = file.mimeType.toLowerCase();
  if (mime.startsWith('image/')) return _PreviewKind.image;
  if (mime.startsWith('video/')) return _PreviewKind.video;
  if (mime.startsWith('audio/')) return _PreviewKind.audio;
  if (mime == 'application/pdf') return _PreviewKind.pdf;
  if (mime == 'text/markdown') return _PreviewKind.markdown;
  if (mime.startsWith('text/') ||
      mime == 'application/json' ||
      mime == 'application/xml' ||
      mime == 'application/x-yaml') {
    // Treat small unknown text as previewable; large unknowns still cap below.
    return _PreviewKind.text;
  }
  return _PreviewKind.unsupported;
}

IconData _iconFor(_PreviewKind kind) {
  switch (kind) {
    case _PreviewKind.image:
      return Icons.image_outlined;
    case _PreviewKind.text:
      return Icons.description_outlined;
    case _PreviewKind.markdown:
      return Icons.article_outlined;
    case _PreviewKind.pdf:
      return Icons.picture_as_pdf_outlined;
    case _PreviewKind.video:
      return Icons.movie_outlined;
    case _PreviewKind.audio:
      return Icons.audiotrack_outlined;
    case _PreviewKind.unsupported:
      return Icons.insert_drive_file_outlined;
  }
}

/// The dialog shell: a fixed-size, themed surface with a header row and the
/// kind-specific body.
class _PreviewDialog extends ConsumerWidget {
  const _PreviewDialog({
    required this.remote,
    required this.parentPath,
    required this.file,
  });

  final Remote remote;
  final String parentPath;
  final RcloneFile file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final kind = _kindFor(file);

    return Dialog(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: BorderSide(color: c.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
        child: SizedBox(
          width: 720,
          height: 640,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(file: file, kind: kind),
              Divider(height: 1, thickness: 1, color: c.border),
              Expanded(
                child: PreviewContent(
                  remote: remote,
                  parentPath: parentPath,
                  file: file,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The kind-specific preview body for [file] (at [parentPath] within [remote]),
/// fetched lazily through the engine's authenticated object URL. Reused by the
/// preview [Dialog] and by Quick Look. Never throws — engine/fetch/decode
/// failures render as an inline [_Message] instead.
class PreviewContent extends ConsumerWidget {
  const PreviewContent({
    super.key,
    required this.remote,
    required this.parentPath,
    required this.file,
  });

  final Remote remote;
  final String parentPath;
  final RcloneFile file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.read(engineControllerProvider).client;
    if (client == null) {
      return const _Message(
        icon: Icons.cloud_off_outlined,
        title: 'Engine not ready',
        detail:
            'The rclone engine is not running, so this file '
            'cannot be previewed right now.',
      );
    }

    final fullPath = _joinPath(parentPath, file.name);
    final ObjectRef ref0;
    try {
      ref0 = client.objectRef(remote.fs, fullPath);
    } catch (e) {
      return _Message(
        icon: Icons.error_outline,
        title: 'Could not locate file',
        detail: '$e',
      );
    }

    switch (_kindFor(file)) {
      case _PreviewKind.image:
        return _ImageBody(ref0: ref0);
      case _PreviewKind.text:
        return _TextBody(ref0: ref0, asMarkdown: false);
      case _PreviewKind.markdown:
        return _TextBody(ref0: ref0, asMarkdown: true);
      case _PreviewKind.pdf:
        return _PdfBody(ref0: ref0);
      case _PreviewKind.video:
        return MediaPreviewBody(url: ref0.url, headers: ref0.headers);
      case _PreviewKind.audio:
        return MediaPreviewBody(
          url: ref0.url,
          headers: ref0.headers,
          audioOnly: true,
        );
      case _PreviewKind.unsupported:
        return _UnsupportedBody(file: file);
    }
  }
}

/// Header: type icon, file name, human size, close button.
class _Header extends StatelessWidget {
  const _Header({required this.file, required this.kind});

  final RcloneFile file;
  final _PreviewKind kind;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.x4,
        Space.x3,
        Space.x2,
        Space.x3,
      ),
      child: Row(
        children: [
          Icon(_iconFor(kind), size: 20, color: c.textMuted),
          const SizedBox(width: Space.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (file.size >= 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      humanSize(file.size),
                      style: TextStyle(color: c.textFaint, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: Space.x2),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            color: c.textMuted,
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// Image preview: pannable/zoomable, with loading + error states.
class _ImageBody extends StatelessWidget {
  const _ImageBody({required this.ref0});

  final ObjectRef ref0;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return Container(
      color: c.surfaceSunken,
      width: double.infinity,
      child: InteractiveViewer(
        maxScale: 8,
        child: Center(
          child: Image.network(
            ref0.url,
            headers: ref0.headers,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return const Center(child: CircularProgressIndicator());
            },
            errorBuilder: (context, error, stack) => _Message(
              icon: Icons.broken_image_outlined,
              title: 'Could not load image',
              detail: '$error',
            ),
          ),
        ),
      ),
    );
  }
}

/// Text / code / markdown preview: fetches the body once via http, then renders
/// either monospace [SelectableText] or a [Markdown] view.
class _TextBody extends StatefulWidget {
  const _TextBody({required this.ref0, required this.asMarkdown});

  final ObjectRef ref0;
  final bool asMarkdown;

  @override
  State<_TextBody> createState() => _TextBodyState();
}

class _TextBodyState extends State<_TextBody> {
  late final Future<_TextResult> _future = _fetch();

  Future<_TextResult> _fetch() async {
    final resp = await http.get(
      Uri.parse(widget.ref0.url),
      headers: widget.ref0.headers,
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    var bytes = resp.bodyBytes;
    var truncated = false;
    if (bytes.length > _maxTextBytes) {
      bytes = bytes.sublist(0, _maxTextBytes);
      truncated = true;
    }
    // Lenient decode so a stray non-UTF8 byte never throws.
    final text = const Utf8Decoder(allowMalformed: true).convert(bytes);
    return _TextResult(text, truncated);
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return FutureBuilder<_TextResult>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError || !snap.hasData) {
          return _Message(
            icon: Icons.error_outline,
            title: 'Could not load file',
            detail: '${snap.error ?? 'Unknown error'}',
          );
        }
        final result = snap.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (result.truncated)
              Container(
                width: double.infinity,
                color: c.warningBg,
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.x4,
                  vertical: Space.x2,
                ),
                child: Text(
                  'Preview truncated to the first '
                  '${humanSize(_maxTextBytes)}.',
                  style: TextStyle(color: c.warning, fontSize: 12),
                ),
              ),
            Expanded(
              child: widget.asMarkdown
                  ? _markdownView(result.text)
                  : _codeView(c, result.text),
            ),
          ],
        );
      },
    );
  }

  Widget _markdownView(String text) {
    try {
      return Markdown(
        data: text,
        padding: const EdgeInsets.all(Space.x4),
        selectable: true,
      );
    } catch (e) {
      return _Message(
        icon: Icons.error_outline,
        title: 'Could not render markdown',
        detail: '$e',
      );
    }
  }

  Widget _codeView(AircloneColors c, String text) {
    return Container(
      color: c.surfaceSunken,
      child: Scrollbar(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Space.x4),
          child: SelectableText(
            text,
            style: TextStyle(
              fontFamily: 'JetBrains Mono',
              fontFamilyFallback: const ['monospace'],
              fontSize: 12.5,
              height: 1.45,
              color: c.text,
            ),
          ),
        ),
      ),
    );
  }
}

/// PDF preview via pdfrx, with a fallback message on failure.
class _PdfBody extends StatelessWidget {
  const _PdfBody({required this.ref0});

  final ObjectRef ref0;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    try {
      return Container(
        color: c.surfaceSunken,
        child: PdfViewer.uri(
          Uri.parse(ref0.url),
          headers: ref0.headers,
          params: PdfViewerParams(
            loadingBannerBuilder: (context, bytesDownloaded, totalBytes) =>
                const Center(child: CircularProgressIndicator()),
            errorBannerBuilder: (context, error, stack, documentRef) =>
                _Message(
                  icon: Icons.picture_as_pdf_outlined,
                  title: 'Could not open PDF',
                  detail: '$error',
                ),
          ),
        ),
      );
    } catch (e) {
      return _Message(
        icon: Icons.picture_as_pdf_outlined,
        title: 'Could not open PDF',
        detail: '$e',
      );
    }
  }
}

/// Fallback card for file types we cannot render inline.
class _UnsupportedBody extends StatelessWidget {
  const _UnsupportedBody({required this.file});

  final RcloneFile file;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final mime = file.mimeType.isEmpty ? 'unknown type' : file.mimeType;
    return _Message(
      icon: Icons.visibility_off_outlined,
      title: 'No preview available',
      detail:
          '${file.name}\n'
          '${humanSize(file.size)} · $mime',
      color: c.textMuted,
    );
  }
}

/// A centered icon + title + detail block used for empty/error/fallback states.
class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    this.detail,
    this.color,
  });

  final IconData icon;
  final String title;
  final String? detail;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final accent = color ?? c.textMuted;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: accent),
            const SizedBox(height: Space.x3),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.text,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (detail != null && detail!.isNotEmpty) ...[
              const SizedBox(height: Space.x2),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textFaint, fontSize: 12, height: 1.4),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Result of fetching a text/markdown body: the (possibly truncated) text and
/// whether truncation occurred.
class _TextResult {
  const _TextResult(this.text, this.truncated);
  final String text;
  final bool truncated;
}
