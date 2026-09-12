import '../state/cloud_placeholder.dart';
import '../state/host_platform.dart';
import '../state/media_formats.dart';
import 'dialog_body.dart';
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
import '../state/open_external.dart';
import 'format.dart';
import 'media_preview.dart';
import 'open_external_action.dart';
import 'theme/tokens.dart';
import 'zoomable_network_image.dart';

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

_PreviewKind _kindFor(RcloneFile file) {
  final ext = _extOf(file.name);
  if (_imageExts.contains(ext)) return _PreviewKind.image;
  if (_markdownExts.contains(ext)) return _PreviewKind.markdown;
  if (ext == 'pdf') return _PreviewKind.pdf;
  if (isVideoLikeExt(ext)) return _PreviewKind.video;
  if (isAudioExt(ext)) return _PreviewKind.audio;
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

/// Whether [file] renders as an image — gates the desktop "Pop out" action
/// (only images pop out) using the SAME kind detection as the inline preview,
/// so the button and the actual preview never disagree.
bool isImagePreview(RcloneFile file) => _kindFor(file) == _PreviewKind.image;

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
        // Clamped against the live screen — see DialogBody. The ConstrainedBox
        // above caps the desktop size; this keeps it on a phone or a fold.
        child: DialogBody(
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
    this.imageBackground,
    this.onPrevious,
    this.onNext,
  });

  final Remote remote;
  final String parentPath;
  final RcloneFile file;

  /// Overrides the matte behind an image. Quick Look's fullscreen phone shape
  /// passes black so a photo doesn't sit in a light themed band; the dialog
  /// leaves it null and keeps the sunken surface.
  final Color? imageBackground;

  /// Move to the sibling before / after this file, when the host has a list.
  /// Only the media bodies use them today — a swipe or an arrow key covers the
  /// others, but an audio player has neither on a television remote.
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

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

    // The escape hatch offered when we can't render a file ourselves: libmpv
    // may not decode it, but the OS very likely has an app that can.
    final VoidCallback? openExternally = canOpenExternally
        ? () {
            openFileInAnotherApp(context, ref, remote, parentPath, file);
          }
        : null;

    final kind = _kindFor(file);
    // A preview READS CONTENT, which is what hydrates a Files On-Demand
    // placeholder. Listing this folder was free; opening this file is not.
    if (wouldHydrateOnRead(remote, fullPath)) {
      return _OnlineOnlyGate(
        file: file,
        proceed: () => _body(context, ref, kind, ref0, openExternally),
      );
    }
    return _body(context, ref, kind, ref0, openExternally);
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    _PreviewKind kind,
    ObjectRef ref0,
    VoidCallback? openExternally,
  ) {
    switch (kind) {
      case _PreviewKind.image:
        return _ImageBody(ref0: ref0, background: imageBackground);
      case _PreviewKind.text:
        return _TextBody(ref0: ref0, asMarkdown: false);
      case _PreviewKind.markdown:
        return _TextBody(ref0: ref0, asMarkdown: true);
      case _PreviewKind.pdf:
        return _PdfBody(ref0: ref0);
      case _PreviewKind.video:
      case _PreviewKind.audio:
        // In a browser, playback is the browser's own decoder - media_kit's web
        // backend is an HTMLVideoElement - so an .avi or .mkv cannot play here
        // however well the app behaves. Say that, instead of handing the user
        // the browser's "no supported source was found" beside a Try again
        // button that can never succeed.
        if (HostPlatform.isWeb && isUnplayableInBrowser(_extOf(file.name))) {
          return _BrowserCannotPlayBody(file: file);
        }
        return MediaPreviewBody(
          url: ref0.url,
          headers: ref0.headers,
          audioOnly: kind == _PreviewKind.audio,
          onOpenExternally: openExternally,
          onPrevious: onPrevious,
          onNext: onNext,
        );
      case _PreviewKind.unsupported:
        return _UnsupportedBody(file: file, onOpenExternally: openExternally);
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

/// Image preview: pannable/zoomable via the shared [ZoomableNetworkImage] (the
/// SAME widget the desktop pop-out window uses, so zoom is identical in both),
/// keeping the sunken surface fill and the dialog's themed error card.
class _ImageBody extends StatelessWidget {
  const _ImageBody({required this.ref0, this.background});

  final ObjectRef ref0;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return ZoomableNetworkImage(
      url: ref0.url,
      headers: ref0.headers,
      backgroundColor: background ?? c.surfaceSunken,
      errorBuilder: (context, error, stack) => _Message(
        icon: Icons.broken_image_outlined,
        title: 'Could not load image',
        detail: '$error',
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

  /// Shared by the code view's Scrollbar and its scroll view. A Scrollbar with
  /// no controller cannot find the scrollable to drive, so its thumb renders
  /// and then ignores the mouse — visible, and inert.
  final _codeScroll = ScrollController();

  @override
  void dispose() {
    _codeScroll.dispose();
    super.dispose();
  }

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
        controller: _codeScroll,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _codeScroll,
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

/// Fallback card for file types we cannot render inline. Offers the hand-off to
/// another app, which for these files is the only way to actually see them.
class _UnsupportedBody extends StatelessWidget {
  const _UnsupportedBody({required this.file, this.onOpenExternally});

  final RcloneFile file;
  final VoidCallback? onOpenExternally;

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
      action: onOpenExternally == null
          ? null
          : FilledButton.icon(
              onPressed: onOpenExternally,
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Open in another app'),
            ),
    );
  }
}

/// Shown in the Web UI for media a browser has no decoder for.
///
/// Not an error state, because nothing went wrong: media_kit's web backend is
/// an `HTMLVideoElement`, so an `.avi` or `.mkv` was never going to play in a
/// browser however well the server behaves. The desktop app plays it through
/// libmpv, which is why the same file opens fine there and the difference needs
/// explaining rather than reporting as a failure.
///
/// Deliberately offers no retry. The previous behaviour handed the user the
/// browser's own "Failed to load because no supported source was found" beside
/// a Try again button that could never succeed — which teaches a user that the
/// app is unreliable, rather than that their browser has limits.
class _BrowserCannotPlayBody extends StatelessWidget {
  const _BrowserCannotPlayBody({required this.file});

  final RcloneFile file;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final ext = _extOf(file.name);
    return _Message(
      icon: Icons.download_for_offline_outlined,
      title: 'Your browser can’t play .$ext files',
      detail:
          '${file.name}\n'
          '${humanSize(file.size)}\n\n'
          'Browsers only play a few formats — MP4, WebM and Ogg. Download '
          'this file and open it in a media player, or open it in the Airclone '
          'app on this machine, which plays it directly.',
      color: c.textMuted,
    );
  }
}

/// Asks before hydrating an online-only cloud placeholder for a preview.
///
/// **Why a preview needs this and a listing does not.** Listing and stat are
/// free on a Files On-Demand placeholder — that is the whole point of one. It is
/// reading the CONTENT that makes the OS fetch the entire file, and a preview
/// reads content. So a user browsing a synced OneDrive/iCloud/Proton folder can
/// look around freely, and only an explicit "yes" starts a download.
///
/// This used to fetch on open, which meant one click on a 4GB video began
/// downloading 4GB on whatever connection the machine happened to be on. The
/// same consent shape already guarded the checksum dialog; the preview simply
/// never got it.
///
/// Deliberately NOT applied to copy, sync or download. There the hydration IS
/// the operation the user asked for, and asking again would be nagging.
class _OnlineOnlyGate extends StatefulWidget {
  const _OnlineOnlyGate({required this.file, required this.proceed});

  final RcloneFile file;

  /// Builds the real preview, once the user has said yes.
  final Widget Function() proceed;

  @override
  State<_OnlineOnlyGate> createState() => _OnlineOnlyGateState();
}

class _OnlineOnlyGateState extends State<_OnlineOnlyGate> {
  bool _consented = false;

  @override
  Widget build(BuildContext context) {
    if (_consented) return widget.proceed();
    final c = AircloneTheme.of(context);
    return _Message(
      icon: Icons.cloud_download_outlined,
      title: 'This file is stored online only',
      detail:
          '${widget.file.name}\n'
          '${humanSize(widget.file.size)}\n\n'
          'Only a placeholder is on this device. Previewing it downloads the '
          'whole file first — which takes time on a slow connection and counts '
          'against a metered one. Browsing and renaming need no download.',
      color: c.textMuted,
      action: FilledButton.icon(
        onPressed: () => setState(() => _consented = true),
        icon: const Icon(Icons.download, size: 18),
        label: Text('Download ${humanSize(widget.file.size)} & preview'),
      ),
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
    this.action,
  });

  final IconData icon;
  final String title;
  final String? detail;
  final Color? color;

  /// Optional button rendered under the detail text (e.g. the hand-off).
  final Widget? action;

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
            if (action != null) ...[const SizedBox(height: Space.x4), action!],
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
