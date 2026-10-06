import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:media_kit/media_kit.dart';

import '../native/mpv_access.dart';
import '../state/diagnostics.dart';
import '../state/host_platform.dart';
import '../state/media_capabilities.dart';
import '../state/media_formats.dart';
import 'dialog_body.dart';
import 'theme/tokens.dart';
import 'tv_player_keys.dart' show tvPlayerEnabled;

/// Settings → Diagnostics → *Media capabilities*: asks this build's libmpv what
/// it can open and shows the answer as copyable text.
///
/// The output is the raw material for `dev/media-support-matrix.md` (player
/// format plan, spike A0.1). It is behind Advanced mode because it is a
/// maintainer's tool: a user who is asked for it in an issue can switch that on,
/// and nobody else needs a wall of codec names in Settings.
///
/// Never shown on the web build — the browser's `<video>` element is the
/// decoder there and has no libmpv to ask.
Future<void> showMediaCapabilitiesDialog(BuildContext context) =>
    showDialog<void>(
      context: context,
      builder: (_) => const _MediaCapabilitiesDialog(),
    );

/// Creates a throwaway player, reads the capability properties, disposes it.
///
/// No media is opened, so `hwdec-current` reads empty; the report says so
/// rather than pretending. The protocol whitelist is the preview one, for the
/// same reason every other player in the app sets it explicitly (see
/// [kPreviewProtocols]) — even a player that never opens anything should not be
/// the one place the unsafe default survives.
Future<MediaCapabilityDump> dumpMediaCapabilities() async {
  final player = Player(
    configuration: const PlayerConfiguration(
      protocolWhitelist: kPreviewProtocols,
    ),
  );
  try {
    if (!hasMpv(player)) {
      throw UnsupportedError('This build has no libmpv to ask.');
    }
    Future<String> read(String property) async {
      try {
        return await mpvGetProperty(player, property) ?? '';
      } catch (_) {
        return '';
      }
    }

    return MediaCapabilityDump(
      platform:
          '${HostPlatform.operatingSystem}${tvPlayerEnabled ? ' (television)' : ''}',
      mpvVersion: await read('mpv-version'),
      ffmpegVersion: await read('ffmpeg-version'),
      hwdec: await read('hwdec'),
      hwdecCurrent: await read('hwdec-current'),
      demuxers: await read('demuxer-lavf-list'),
      decoders: await read('decoder-list'),
      protocols: await read('protocol-list'),
    );
  } finally {
    try {
      await player.dispose();
    } catch (_) {
      // Never fully constructed.
    }
  }
}

class _MediaCapabilitiesDialog extends StatefulWidget {
  const _MediaCapabilitiesDialog();

  @override
  State<_MediaCapabilitiesDialog> createState() =>
      _MediaCapabilitiesDialogState();
}

class _MediaCapabilitiesDialogState extends State<_MediaCapabilitiesDialog> {
  String? _report;
  String? _error;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final dump = await dumpMediaCapabilities();
      logDiagnostic(
        DiagLevel.info,
        'media-capabilities',
        mediaCapabilitySummary(dump),
      );
      if (mounted) setState(() => _report = buildMediaCapabilityReport(dump));
    } catch (e) {
      if (mounted) setState(() => _error = redactSensitive('$e'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final report = _report;
    return AlertDialog(
      backgroundColor: c.surface,
      title: const Text('Media capabilities'),
      content: DialogBody(
        width: 560,
        height: 420,
        child: report != null
            ? SingleChildScrollView(
                child: SelectableText(
                  report,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 12,
                    fontFamily: 'monospace',
                    height: 1.4,
                  ),
                ),
              )
            : Center(
                child: _error != null
                    ? Text(
                        "Couldn't read the player's capabilities: $_error",
                        style: TextStyle(color: c.error, fontSize: 13),
                      )
                    : const CircularProgressIndicator(),
              ),
      ),
      actions: [
        if (report != null)
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: report));
              if (mounted) setState(() => _copied = true);
            },
            icon: Icon(_copied ? Icons.check : Icons.copy_all_outlined),
            label: Text(_copied ? 'Copied' : 'Copy'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
      contentPadding: const EdgeInsets.fromLTRB(
        Space.x6,
        Space.x4,
        Space.x6,
        Space.x2,
      ),
    );
  }
}
