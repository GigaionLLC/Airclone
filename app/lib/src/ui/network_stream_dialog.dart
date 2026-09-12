import 'package:flutter/material.dart';

import 'dialog_body.dart';
import 'media_preview.dart';
import 'theme/tokens.dart';

/// Schemes the player is allowed to be pointed at.
///
/// libmpv understands a great many more, but most of them are not things a user
/// types into a box: `file://` would make this a local-file reader, and the
/// oddities (`avdevice://`, `cdda://`, `bd://`) address hardware on the host.
/// An allowlist keeps the surface to "a stream somewhere on the network", which
/// is what was asked for.
const Set<String> kStreamSchemes = {
  'http',
  'https',
  'rtsp',
  'rtsps',
  'rtmp',
  'rtmps',
  'srt',
  'rtp',
  'udp',
  'mms',
  'mmsh',
};

/// Validates a user-typed stream URL. Returns null when it is acceptable, or a
/// sentence to show under the field.
///
/// Pure, so the rules are testable without a widget: what a user may point the
/// player at is a security decision, not a cosmetic one.
String? validateStreamUrl(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return 'Enter a stream address.';
  final uri = Uri.tryParse(text);
  if (uri == null) return "That doesn't look like a URL.";
  if (!uri.hasScheme) {
    return 'Include the protocol, for example https://example.com/live.m3u8';
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'file') {
    return 'Local files open from the file list, not here.';
  }
  if (!kStreamSchemes.contains(scheme)) {
    return '$scheme:// streams are not supported.';
  }
  if (uri.host.isEmpty) return 'That URL has no server in it.';
  return null;
}

/// Asks for a stream address and plays it.
///
/// **Why the player is reached this way at all.** Every other route to it starts
/// from a `Remote` and an `RcloneFile` — the preview dialog cannot be built
/// without them — so there was no way to play something that is not a listed
/// object on a remote. A live broadcast is exactly that, so it needs its own
/// door.
///
/// The stream is opened with [ObjectRef.network] semantics: no headers at all.
/// The engine's credentials protect a loopback port on this machine and have no
/// business travelling to a host the user named.
Future<void> showNetworkStreamDialog(BuildContext context) async {
  final controller = TextEditingController();
  final url = await showDialog<String>(
    context: context,
    builder: (ctx) => _NetworkStreamPrompt(controller: controller),
  );
  controller.dispose();
  if (url == null || !context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => _StreamPlayerDialog(url: url),
  );
}

class _NetworkStreamPrompt extends StatefulWidget {
  const _NetworkStreamPrompt({required this.controller});
  final TextEditingController controller;

  @override
  State<_NetworkStreamPrompt> createState() => _NetworkStreamPromptState();
}

class _NetworkStreamPromptState extends State<_NetworkStreamPrompt> {
  String? _error;

  void _submit() {
    final text = widget.controller.text.trim();
    final problem = validateStreamUrl(text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Open network stream'),
      content: DialogBody(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: widget.controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Stream address',
                hintText: 'https://example.com/live.m3u8',
                errorText: _error,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: Space.x3),
            const Text(
              'HLS (.m3u8), MPEG-DASH (.mpd) and RTSP streams play here. '
              'Airclone sends no account details to the address you enter.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      // Wrap, not Row: two buttons fit a phone today, but this is the shape that
      // clipped the Run button off five other dialogs.
      actions: [
        Wrap(
          alignment: WrapAlignment.end,
          spacing: Space.x2,
          runSpacing: Space.x2,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(onPressed: _submit, child: const Text('Play')),
          ],
        ),
      ],
    );
  }
}

class _StreamPlayerDialog extends StatelessWidget {
  const _StreamPlayerDialog({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: DialogBody(
        width: 900,
        height: 560,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.x4,
                Space.x3,
                Space.x2,
                0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              // No headers: see showNetworkStreamDialog. isNetworkStream buys
              // the longer start deadline a stream needs to resolve a manifest
              // and fetch its first segments.
              child: MediaPreviewBody(url: url, isNetworkStream: true),
            ),
          ],
        ),
      ),
    );
  }
}
