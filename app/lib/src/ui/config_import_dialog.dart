import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/cache_crypto.dart';
import '../state/config_io.dart';
import '../state/config_transfer_controller.dart';
import '../state/offline_qr.dart';
import '../state/qr_image_decode.dart';
import '../state/remote_summary.dart';
import 'theme/tokens.dart';

/// Opens the config Import wizard (plan §3): pick a file → (decrypt if needed) →
/// preview the incoming remotes with collision renames → merge, or replace.
Future<void> showConfigImportDialog(
  BuildContext context, {
  bool startOnQr = false,
}) => showDialog<void>(
  context: context,
  builder: (_) => _ConfigImportDialog(startOnQr: startOnQr),
);

/// Wizard steps. [pick] chooses a file; [passphrase]/[rclonePassword] unlock the
/// two encrypted source kinds; [preview] is the heart (remote list + collision
/// renames + merge/replace); [confirmReplace] is the destructive guard;
/// [applying] runs it; [report] shows the per-remote outcome; [error] is a dead
/// end with a Close/Back.
enum _ImportStep {
  pick,
  qrCode,
  passphrase,
  rclonePassword,
  preview,
  confirmReplace,
  applying,
  report,
  error,
}

class _ConfigImportDialog extends ConsumerStatefulWidget {
  const _ConfigImportDialog({this.startOnQr = false});

  /// Open straight into the "From QR image" pick — the desktop "Import QR
  /// Config" entry (vs "Import File Config", which starts on the file pick).
  final bool startOnQr;

  @override
  ConsumerState<_ConfigImportDialog> createState() =>
      _ConfigImportDialogState();
}

class _ConfigImportDialogState extends ConsumerState<_ConfigImportDialog> {
  /// rclone's remote-name charset: letters, digits, `_`, `-`, `.`. Used to
  /// validate a collision rename before apply (config/create would reject the
  /// rest, e.g. `:` `/` `\`).
  static final RegExp _validRemoteName = RegExp(r'^[A-Za-z0-9_.-]+$');

  _ImportStep _step = _ImportStep.pick;

  ConfigFormat? _format;
  // The picked bytes live ONLY here (RAM), never in provider state, and are
  // dropped when the dialog closes — they may contain recoverable secrets.
  List<int>? _bytes;
  String _sourceName = '';

  // --- Offline-QR import (desktop: decode the QR out of a picked image) -------
  // A computer has no camera, so importing an Offline QR here means picking its
  // image (a screenshot or photo). [_qrPayload] is the assembled self-contained
  // payload once a single QR is decoded or every chunk of a multi-QR export is in
  // hand; chunks accumulate across picks so images can be added a few at a time.
  // The unlock code lives ONLY in [_qrCode] (disposed on close) — never in
  // provider state, never logged.
  String? _qrPayload;
  final Map<int, String> _qrChunks = {};
  String? _qrChunkId;
  int _qrChunkTotal = 0;
  final _qrCode = TextEditingController();
  String? _qrError; // inline retry on the code step
  String? _qrHint; // progress / "not an Offline QR" note on the pick step

  ConfigModel? _incoming;
  ConfigModel? _existing;
  List<ImportDecision>? _plan;

  // Editable rename fields, one per COLLIDING incoming remote (keyed by its
  // original name), pre-seeded from planImport's `-imported` suffix.
  final _renames = <String, TextEditingController>{};

  // Secrets live only in these controllers (disposed on close).
  final _passphrase = TextEditingController();
  final _rclonePw = TextEditingController();

  String? _secretError; // inline retry error on the two unlock steps
  String? _previewError; // rename validation error on the preview step
  String? _errorMessage; // terminal error text
  MergeReport? _report; // merge outcome
  int? _replacedCount; // replace outcome
  bool _busy = false;

  ConfigTransferController get _ctrl =>
      ref.read(configTransferControllerProvider);

  @override
  void initState() {
    super.initState();
    // Desktop "Import QR Config" opens directly into the QR-image pick.
    if (widget.startOnQr) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pickQrImages();
      });
    }
  }

  @override
  void dispose() {
    _passphrase.dispose();
    _rclonePw.dispose();
    _qrCode.dispose();
    _disposeRenames();
    super.dispose();
  }

  void _disposeRenames() {
    for (final c in _renames.values) {
      c.dispose();
    }
    _renames.clear();
  }

  // --- Flow -----------------------------------------------------------------

  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    final file = await openFile(confirmButtonText: 'Import');
    if (file == null) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    final format = detectConfigFormat(bytes);
    setState(() {
      _bytes = bytes;
      _sourceName = file.name;
      _format = format;
      _busy = false;
    });
    switch (format) {
      case ConfigFormat.rcloneIni:
      case ConfigFormat.dumpJson:
        await _decodeAndPreview();
      case ConfigFormat.aircloneEnvelope:
        setState(() => _step = _ImportStep.passphrase);
      case ConfigFormat.rcloneEncrypted:
        setState(() => _step = _ImportStep.rclonePassword);
      case ConfigFormat.unknown:
        setState(() {
          _step = _ImportStep.error;
          _errorMessage =
              "That file isn't a recognised rclone or Airclone config.";
        });
    }
  }

  /// Parses the picked bytes (with the entered secret, if any), reads the live
  /// config, plans the merge, and moves to the preview. A wrong secret stays on
  /// the unlock step with an inline retry; a corrupt/unknown file is terminal.
  Future<void> _decodeAndPreview({
    String? passphrase,
    String? rclonePassword,
  }) async {
    final bytes = _bytes;
    final format = _format;
    if (bytes == null || format == null) return;
    setState(() {
      _busy = true;
      _secretError = null;
    });
    try {
      final incoming = await _ctrl.parseImport(
        bytes: bytes,
        format: format,
        passphrase: passphrase,
        rclonePassword: rclonePassword,
      );
      await _enterPreviewWith(incoming);
    } on WrongPassphrase {
      setState(() {
        _busy = false;
        _secretError = 'Wrong passphrase — try again.';
      });
    } on WrongRcloneConfigPassword {
      setState(() {
        _busy = false;
        _secretError = 'Wrong password — try again.';
      });
    } on CorruptEnvelope catch (e) {
      setState(() {
        _busy = false;
        _step = _ImportStep.error;
        _errorMessage = "This isn't a valid Airclone export (${e.message}).";
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _step = _ImportStep.error;
        _errorMessage = e is ConfigTransferError ? e.message : '$e';
      });
    }
  }

  /// Given a decoded incoming config (from a file OR an Offline QR), read the
  /// live config, plan the merge, seed the collision-rename fields, and show the
  /// MANDATORY preview. Shared by the file path and the QR path so both land in
  /// the exact same review before anything is written. Caller wraps this in the
  /// try that owns error/retry handling; it only throws through.
  Future<void> _enterPreviewWith(ConfigModel incoming) async {
    final existing = await _ctrl.activeConfigModel();
    if (!mounted) return;
    final plan = planImport(existing, incoming);
    _disposeRenames();
    for (final d in plan) {
      if (d.collision) {
        _renames[d.name] = TextEditingController(
          text: d.renamedTo ?? '${d.name}-imported',
        );
      }
    }
    setState(() {
      _incoming = incoming;
      _existing = existing;
      _plan = plan;
      _busy = false;
      _step = _ImportStep.preview;
    });
  }

  /// DESKTOP Offline-QR import: pick the QR image(s) — a screenshot or a photo of
  /// the code(s) shown on the other computer — decode each in a background
  /// isolate, and route by kind. A single self-contained QR moves straight to the
  /// code prompt; multi-QR chunks accumulate (across picks, any order) until every
  /// one is in hand, then reassemble. A non-Airclone (or non-Offline-QR) image is
  /// refused with a clear note rather than fed forward. Nothing is decrypted here
  /// — that waits for the code.
  Future<void> _pickQrImages() async {
    setState(() {
      _busy = true;
      _errorMessage = null;
      _qrError = null;
      _qrHint = null;
    });
    final files = await openFiles(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'QR image',
          extensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif'],
        ),
      ],
    );
    if (files.isEmpty) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    var unreadable = 0;
    var foreign = 0;
    String? single;
    for (final f in files) {
      final bytes = await f.readAsBytes();
      String? raw;
      try {
        raw = await decodeQrFromImage(bytes);
      } catch (_) {
        raw =
            null; // a decode failure (e.g. an oversized image) is "unreadable"
      }
      if (raw == null) {
        unreadable++;
        continue;
      }
      if (isOfflineQrChunk(raw)) {
        final chunk = parseOfflineQrChunk(raw);
        if (chunk == null) {
          unreadable++;
          continue;
        }
        // A chunk from a different export starts a fresh collection.
        if (_qrChunkId != chunk.id) {
          _qrChunkId = chunk.id;
          _qrChunkTotal = chunk.total;
          _qrChunks.clear();
        }
        _qrChunks[chunk.index] = chunk.body;
        continue;
      }
      if (isOfflineQrPayload(raw)) {
        single = raw;
        continue;
      }
      foreign++; // not an Airclone Offline QR (or not an Airclone QR at all)
    }
    if (!mounted) return;
    // A single self-contained QR wins outright; otherwise assemble the chunks if
    // they're all present now.
    final assembled =
        single ??
        (_qrChunkTotal > 0 && _qrChunks.length >= _qrChunkTotal
            ? assembleOfflineQrPayload(_qrChunks, _qrChunkTotal)
            : null);
    if (assembled != null) {
      final label = single != null
          ? (files.length == 1 ? files.first.name : 'Offline QR')
          : 'Offline QR ($_qrChunkTotal images)';
      setState(() {
        _qrPayload = assembled;
        _sourceName = label;
        _qrError = null;
        _qrHint = null;
        _busy = false;
        _step = _ImportStep.qrCode;
        // The collection is complete and captured in _qrPayload — drop it so a
        // later foreign pick can't re-fire the assembly guard and resurrect this
        // export instead of reporting the newly picked image.
        _qrChunks.clear();
        _qrChunkId = null;
        _qrChunkTotal = 0;
      });
      return;
    }
    // Nothing complete yet — explain precisely and stay on the pick step so more
    // images can be added.
    setState(() {
      _busy = false;
      final have = _qrChunks.length;
      if (_qrChunkTotal > 0 && have < _qrChunkTotal) {
        _qrHint =
            'Collected $have of $_qrChunkTotal QR images — add the other '
            '${_qrChunkTotal - have}.';
      } else if (foreign > 0 && unreadable == 0) {
        _qrHint =
            "That image isn't an Airclone Offline QR. On the other computer, use "
            'Settings → "Export QR Config" to make one.';
      } else {
        _qrHint =
            "Couldn't find an Airclone Offline QR in "
            '${files.length == 1 ? 'that image' : 'those images'}. Pick the '
            'screenshot or photo of the Offline QR.';
      }
    });
  }

  /// Decrypts the assembled Offline-QR payload with the entered code, parses the
  /// config, and lands in the shared preview. A wrong code stays put (recoverable
  /// inline retry); a foreign/corrupt/malformed QR is a terminal error.
  Future<void> _openQr() async {
    final payload = _qrPayload;
    if (payload == null) return;
    final code = _qrCode.text;
    if (code.isEmpty) {
      setState(
        () => _qrError = 'Enter the code that was set when the QR was made.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _qrError = null;
    });
    try {
      final text = await openOfflineQrPayload(payload, code);
      if (!mounted) return;
      await _enterPreviewWith(parseIni(text));
    } on WrongPassphrase {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _qrError = "That code didn't work — check it and try again.";
      });
    } on NotAnOfflineQr {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = _ImportStep.error;
        _errorMessage = "That QR isn't an Airclone offline config.";
      });
    } on CorruptEnvelope catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = _ImportStep.error;
        _errorMessage = "That offline QR couldn't be read (${e.message}).";
      });
    } on FormatException {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = _ImportStep.error;
        _errorMessage = 'That offline QR is malformed.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = _ImportStep.error;
        _errorMessage = e is ConfigTransferError ? e.message : '$e';
      });
    }
  }

  /// Builds the final, user-edited decision list from the rename fields and
  /// validates it before applying: every collision needs a non-empty name, no
  /// two remotes may land on the same final name, and a rename must not silently
  /// overwrite an existing remote. Returns null (and sets [_previewError]) on a
  /// validation failure.
  List<ImportDecision>? _editedPlan() {
    final plan = _plan!;
    final existing = _existing ?? const {};
    final edited = <ImportDecision>[];
    final finals = <String>[];
    for (final d in plan) {
      var renamedTo = d.renamedTo;
      if (d.collision) {
        final v = _renames[d.name]!.text.trim();
        if (v.isEmpty) {
          setState(() => _previewError = 'Give "${d.name}" a new name.');
          return null;
        }
        // Validate against rclone's remote-name charset up front, so an invalid
        // rename (e.g. containing ':' '/' '\') is caught inline rather than
        // surfacing later as a per-remote "didn't import" from config/create.
        if (!_validRemoteName.hasMatch(v)) {
          setState(
            () => _previewError =
                '"$v" isn\'t a valid remote name — use letters, numbers, '
                '"_", "-" or ".".',
          );
          return null;
        }
        renamedTo = v;
      }
      final finalName = renamedTo ?? d.name;
      finals.add(finalName);
      edited.add(
        ImportDecision(
          name: d.name,
          type: d.type,
          collision: d.collision,
          renamedTo: renamedTo,
        ),
      );
    }
    if (finals.toSet().length != finals.length) {
      setState(
        () => _previewError = 'Two remotes would land on the same name.',
      );
      return null;
    }
    for (final d in edited) {
      if (d.collision && existing.containsKey(d.renamedTo)) {
        setState(
          () => _previewError =
              '"${d.renamedTo}" already exists — pick another name.',
        );
        return null;
      }
    }
    return edited;
  }

  Future<void> _applyMerge() async {
    final edited = _editedPlan();
    if (edited == null) return;
    setState(() {
      _previewError = null;
      _busy = true;
      _step = _ImportStep.applying;
    });
    try {
      final report = await _ctrl.applyMerge(_incoming!, edited);
      if (!mounted) return;
      setState(() {
        _report = report;
        _busy = false;
        _step = _ImportStep.report;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = _ImportStep.error;
        _errorMessage = e is ConfigTransferError ? e.message : '$e';
      });
    }
  }

  Future<void> _applyReplace() async {
    setState(() {
      _busy = true;
      _step = _ImportStep.applying;
    });
    try {
      final incoming = _incoming!;
      await _ctrl.applyReplace(incoming);
      if (!mounted) return;
      setState(() {
        _replacedCount = incoming.length;
        _busy = false;
        _step = _ImportStep.report;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = _ImportStep.error;
        _errorMessage = e is ConfigTransferError ? e.message : '$e';
      });
    }
  }

  // --- Views ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return Dialog(
      backgroundColor: c.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: SizedBox(
        width: 540,
        child: Padding(
          padding: const EdgeInsets.all(Space.x5),
          child: SingleChildScrollView(
            child: switch (_step) {
              _ImportStep.pick => _pickView(c),
              _ImportStep.qrCode => _qrCodeView(c),
              _ImportStep.passphrase => _secretView(c, envelope: true),
              _ImportStep.rclonePassword => _secretView(c, envelope: false),
              _ImportStep.preview => _previewView(c),
              _ImportStep.confirmReplace => _confirmReplaceView(c),
              _ImportStep.applying => _busyView(c, 'Applying…'),
              _ImportStep.report => _reportView(c),
              _ImportStep.error => _errorView(c),
            },
          ),
        ),
      ),
    );
  }

  Widget _busyView(AircloneColors c, String label) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const SizedBox(height: Space.x4),
      const CircularProgressIndicator(strokeWidth: 2),
      const SizedBox(height: Space.x3),
      Text(label, style: TextStyle(color: c.textMuted, fontSize: 13)),
      const SizedBox(height: Space.x4),
    ],
  );

  Widget _pickView(AircloneColors c) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title(c, Icons.file_download_outlined, 'Import a config'),
      const SizedBox(height: Space.x2),
      Text(
        'Bring in remotes from an rclone.conf, an rclone config-dump, an Airclone '
        'encrypted export, or an Offline QR image (a screenshot or photo of the '
        'code). Encrypted sources prompt for their password, and you preview '
        'everything before anything is written.',
        style: TextStyle(color: c.textFaint, fontSize: 12),
      ),
      if (_qrHint != null) ...[
        const SizedBox(height: Space.x3),
        Container(
          padding: const EdgeInsets.all(Space.x3),
          decoration: BoxDecoration(
            color: c.surfaceSunken,
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.qr_code_2, size: 16, color: c.textMuted),
              const SizedBox(width: Space.x2),
              Expanded(
                child: Text(
                  _qrHint!,
                  style: TextStyle(color: c.textMuted, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: Space.x4),
      Row(
        children: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text('Cancel', style: TextStyle(color: c.textMuted)),
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickQrImages,
            icon: const Icon(Icons.qr_code_2, size: 16),
            label: const Text('From QR image…'),
          ),
          const SizedBox(width: Space.x2),
          FilledButton.icon(
            onPressed: _busy ? null : _pick,
            icon: _busy
                ? const SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.folder_open_outlined, size: 16),
            label: const Text('Choose a file…'),
          ),
        ],
      ),
    ],
  );

  Widget _qrCodeView(AircloneColors c) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title(c, Icons.lock_outline, 'Enter the QR code'),
      const SizedBox(height: Space.x2),
      Text(
        'Type the unlock code that was set when this Offline QR was made. The '
        "code was never in the QR — that's what keeps it safe.",
        style: TextStyle(color: c.textFaint, fontSize: 12),
      ),
      const SizedBox(height: Space.x2),
      Text(
        _sourceName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: c.textMuted, fontSize: 11),
      ),
      const SizedBox(height: Space.x3),
      TextField(
        controller: _qrCode,
        obscureText: true,
        autofocus: true,
        enabled: !_busy,
        onSubmitted: (_) => _busy ? null : _openQr(),
        style: TextStyle(color: c.text, fontSize: 13, letterSpacing: 1.2),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Unlock code',
          hintStyle: TextStyle(color: c.textFaint, fontSize: 13),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Radii.md),
          ),
        ),
      ),
      if (_qrError != null) ...[
        const SizedBox(height: Space.x2),
        Text(_qrError!, style: TextStyle(color: c.error, fontSize: 12)),
      ],
      const SizedBox(height: Space.x4),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                    _qrError = null;
                    _step = _ImportStep.pick;
                  }),
            child: Text('Back', style: TextStyle(color: c.textMuted)),
          ),
          const SizedBox(width: Space.x2),
          FilledButton.icon(
            onPressed: _busy ? null : _openQr,
            icon: _busy
                ? const SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.lock_open, size: 16),
            label: const Text('Unlock'),
          ),
        ],
      ),
    ],
  );

  Widget _secretView(AircloneColors c, {required bool envelope}) {
    final controller = envelope ? _passphrase : _rclonePw;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(
          c,
          Icons.lock_outline,
          envelope ? 'Encrypted export' : 'Encrypted config',
        ),
        const SizedBox(height: Space.x2),
        Text(
          envelope
              ? 'This Airclone export is encrypted. Enter its passphrase to '
                    'decrypt and preview it.'
              : 'This rclone config is encrypted. Enter its config password to '
                    'decrypt and preview it.',
          style: TextStyle(color: c.textFaint, fontSize: 12),
        ),
        const SizedBox(height: Space.x2),
        Text(
          _sourceName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: c.textMuted, fontSize: 11),
        ),
        const SizedBox(height: Space.x3),
        TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          onSubmitted: (_) => _submitSecret(envelope),
          decoration: InputDecoration(
            isDense: true,
            hintText: envelope ? 'Passphrase' : 'Config password',
            hintStyle: TextStyle(color: c.textFaint, fontSize: 13),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.md),
            ),
          ),
          style: TextStyle(color: c.text, fontSize: 13),
        ),
        if (_secretError != null) ...[
          const SizedBox(height: Space.x2),
          Text(_secretError!, style: TextStyle(color: c.error, fontSize: 12)),
        ],
        const SizedBox(height: Space.x4),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: Text('Cancel', style: TextStyle(color: c.textMuted)),
            ),
            const SizedBox(width: Space.x2),
            FilledButton.icon(
              onPressed: _busy ? null : () => _submitSecret(envelope),
              icon: _busy
                  ? const SizedBox(
                      height: 14,
                      width: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.lock_open, size: 16),
              label: const Text('Unlock'),
            ),
          ],
        ),
      ],
    );
  }

  void _submitSecret(bool envelope) {
    if (envelope) {
      _decodeAndPreview(passphrase: _passphrase.text);
    } else {
      _decodeAndPreview(rclonePassword: _rclonePw.text);
    }
  }

  Widget _previewView(AircloneColors c) {
    final plan = _plan ?? const [];
    final collisions = plan.where((d) => d.collision).length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(c, Icons.fact_check_outlined, 'Review import'),
        const SizedBox(height: Space.x2),
        Text(
          plan.isEmpty
              ? 'This file has no remotes to import.'
              : '${plan.length} remote${plan.length == 1 ? '' : 's'} from '
                    '$_sourceName'
                    '${collisions > 0 ? '  ·  $collisions name${collisions == 1 ? '' : 's'} already in use' : ''}',
          style: TextStyle(color: c.textFaint, fontSize: 12),
        ),
        const SizedBox(height: Space.x3),
        for (final d in plan) _decisionRow(c, d),
        if (_previewError != null) ...[
          const SizedBox(height: Space.x2),
          Text(_previewError!, style: TextStyle(color: c.error, fontSize: 12)),
        ],
        const SizedBox(height: Space.x4),
        Row(
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel', style: TextStyle(color: c.textMuted)),
            ),
            const Spacer(),
            if (plan.isNotEmpty)
              TextButton(
                onPressed: () =>
                    setState(() => _step = _ImportStep.confirmReplace),
                child: Text(
                  'Replace instead…',
                  style: TextStyle(color: c.error),
                ),
              ),
            const SizedBox(width: Space.x2),
            FilledButton.icon(
              onPressed: plan.isEmpty ? null : _applyMerge,
              icon: const Icon(Icons.merge_type, size: 16),
              label: const Text('Merge'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _decisionRow(AircloneColors c, ImportDecision d) {
    final typeLabel = d.type.isEmpty ? 'unknown type' : d.type;
    final endpoint = remoteEndpointSummary(_incoming?[d.name] ?? const {});
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.x2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            d.collision ? Icons.sync_problem_outlined : Icons.cloud_outlined,
            size: 16,
            color: d.collision ? c.warning : c.textMuted,
          ),
          const SizedBox(width: Space.x2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        d.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: Space.x2),
                    Text(
                      typeLabel,
                      style: TextStyle(color: c.textFaint, fontSize: 11),
                    ),
                  ],
                ),
                // The remote's endpoint (host/url/…) — surfaced so a swapped or
                // poisoned import (a picked QR image is untrusted) can't silently
                // re-point a remote at an attacker's target unseen (plan §5).
                if (endpoint.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      endpoint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.textMuted, fontSize: 11),
                    ),
                  ),
                if (d.collision) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        'Import as',
                        style: TextStyle(color: c.textFaint, fontSize: 11),
                      ),
                      const SizedBox(width: Space.x2),
                      Expanded(
                        child: SizedBox(
                          height: 32,
                          child: TextField(
                            controller: _renames[d.name],
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: Space.x2,
                                vertical: Space.x2,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(Radii.sm),
                              ),
                            ),
                            style: TextStyle(color: c.text, fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _confirmReplaceView(AircloneColors c) {
    // The held config password is the live "encrypted?" signal (as in Settings →
    // Config). When set, the replacement is re-encrypted so encryption-at-rest is
    // never silently dropped — say so explicitly so consent is informed.
    final encrypted = ref.watch(cachePassphraseProvider) != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(c, Icons.warning_amber_rounded, 'Replace your whole config?'),
        const SizedBox(height: Space.x3),
        Container(
          padding: const EdgeInsets.all(Space.x3),
          decoration: BoxDecoration(
            color: c.errorBg,
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, size: 16, color: c.error),
              const SizedBox(width: Space.x2),
              Expanded(
                child: Text(
                  'This overwrites your ENTIRE active rclone config with the '
                  '${_incoming?.length ?? 0} imported remote(s) and restarts the '
                  'engine. Your current remotes are backed up first (Settings → '
                  'Config → Restore a backup), but every remote not in this file '
                  'will disappear until you restore.',
                  style: TextStyle(color: c.textMuted, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        if (encrypted) ...[
          const SizedBox(height: Space.x2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline, size: 16, color: c.textMuted),
              const SizedBox(width: Space.x2),
              Expanded(
                child: Text(
                  'Your config is encrypted — the replacement will be '
                  're-encrypted with your current config password so your '
                  'secrets stay encrypted at rest.',
                  style: TextStyle(color: c.textMuted, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: Space.x4),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => setState(() => _step = _ImportStep.preview),
              child: Text('Back', style: TextStyle(color: c.textMuted)),
            ),
            const SizedBox(width: Space.x2),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: c.error,
                foregroundColor: c.onPrimary,
              ),
              onPressed: _applyReplace,
              child: const Text('Replace config'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _reportView(AircloneColors c) {
    final report = _report;
    // Replace outcome (no per-remote report).
    if (report == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(c, Icons.check_circle_outline, 'Config replaced'),
          const SizedBox(height: Space.x3),
          Text(
            'Replaced your config with ${_replacedCount ?? 0} remote(s) and '
            'restarted the engine.',
            style: TextStyle(color: c.textMuted, fontSize: 13),
          ),
          const SizedBox(height: Space.x4),
          _doneButton(c),
        ],
      );
    }
    final ok = report.allOk;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(
          c,
          ok ? Icons.check_circle_outline : Icons.report_problem_outlined,
          ok
              ? 'Imported ${report.created.length} remote(s)'
              : 'Imported with problems',
        ),
        const SizedBox(height: Space.x3),
        if (report.created.isNotEmpty) ...[
          Text(
            'Merged',
            style: TextStyle(
              color: c.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: Space.x1),
          for (final name in report.created)
            _outcomeRow(c, Icons.check, c.success, name, null),
        ],
        if (report.failed.isNotEmpty) ...[
          const SizedBox(height: Space.x3),
          Text(
            "Didn't import",
            style: TextStyle(
              color: c.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: Space.x1),
          for (final f in report.failed)
            _outcomeRow(c, Icons.close, c.error, f.name, f.error),
        ],
        const SizedBox(height: Space.x4),
        _doneButton(c),
      ],
    );
  }

  Widget _outcomeRow(
    AircloneColors c,
    IconData icon,
    Color tint,
    String name,
    String? detail,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: tint),
        const SizedBox(width: Space.x2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: TextStyle(color: c.text, fontSize: 12)),
              if (detail != null)
                Text(
                  detail,
                  style: TextStyle(color: c.textFaint, fontSize: 11),
                ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _errorView(AircloneColors c) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title(c, Icons.error_outline, "Couldn't import"),
      const SizedBox(height: Space.x3),
      Text(
        _errorMessage ?? 'Unknown error',
        style: TextStyle(color: c.textMuted, fontSize: 12),
      ),
      const SizedBox(height: Space.x4),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Close', style: TextStyle(color: c.textMuted)),
          ),
          const SizedBox(width: Space.x2),
          FilledButton(
            onPressed: () => setState(() {
              _step = _ImportStep.pick;
              _errorMessage = null;
            }),
            child: const Text('Start over'),
          ),
        ],
      ),
    ],
  );

  Widget _doneButton(AircloneColors c) => Align(
    alignment: Alignment.centerRight,
    child: FilledButton(
      onPressed: () => Navigator.of(context).pop(),
      child: const Text('Done'),
    ),
  );

  Widget _title(AircloneColors c, IconData icon, String text) => Row(
    children: [
      Icon(icon, size: 20, color: c.primary),
      const SizedBox(width: Space.x2),
      Expanded(
        child: Text(
          text,
          style: TextStyle(
            color: c.text,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}
