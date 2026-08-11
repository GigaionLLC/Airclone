import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/cache_crypto.dart';
import '../state/config_io.dart';
import '../state/config_transfer_controller.dart';
import '../state/diagnostics.dart';
import '../state/remote_summary.dart';
import 'dialog_body.dart';
import 'theme/tokens.dart';

/// Opens the config Import wizard (plan §3): pick a file → (decrypt if needed) →
/// preview the incoming remotes with collision renames → merge, or replace. This
/// is "Import File Config" — opening a file. QR import is a separate, phone-camera
/// flow (see scan_from_desktop_sheet.dart), never a file pick.
Future<void> showConfigImportDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const _ConfigImportDialog(),
);

/// Wizard steps. [pick] chooses a file; [passphrase]/[rclonePassword] unlock the
/// two encrypted source kinds; [preview] is the heart (remote list + collision
/// renames + merge/replace); [confirmReplace] is the destructive guard;
/// [applying] runs it; [report] shows the per-remote outcome; [error] is a dead
/// end with a Close/Back.
enum _ImportStep {
  pick,
  passphrase,
  rclonePassword,
  preview,
  confirmReplace,
  applying,
  report,
  error,
}

class _ConfigImportDialog extends ConsumerStatefulWidget {
  const _ConfigImportDialog();

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

  DiagnosticsLog get _log => ref.read(diagnosticsProvider.notifier);

  @override
  void dispose() {
    _passphrase.dispose();
    _rclonePw.dispose();
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
    final List<int> bytes;
    final String name;
    // The pick and the read are the two steps that can fail for reasons OUTSIDE
    // the config format — a cancelled/denied picker, or a URI the platform hands
    // back that we can't read (Android returns a `content://` document, not a
    // path). Without this guard those threw out of the button callback: the
    // dialog kept its spinner forever and told the user nothing.
    try {
      final file = await openFile(confirmButtonText: 'Import');
      if (file == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      bytes = await file.readAsBytes();
      name = file.name;
    } catch (e) {
      _log.error('config-import', 'Could not read the picked file', detail: e);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = _ImportStep.error;
        _errorMessage =
            "Couldn't read that file ($e). If you picked it from a cloud or "
            'download provider, copy it to this device first and try again.';
      });
      return;
    }
    if (!mounted) return;
    final format = detectConfigFormat(bytes);
    setState(() {
      _bytes = bytes;
      _sourceName = name;
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
      _log.error('config-import', 'Could not decode the config', detail: e);
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
      for (final f in report.failed) {
        _log.error(
          'config-import',
          'Remote "${f.name}" did not import',
          detail: f.error,
        );
      }
      if (!mounted) return;
      setState(() {
        _report = report;
        _busy = false;
        _step = _ImportStep.report;
      });
    } catch (e) {
      _log.error('config-import', 'Merge failed', detail: e);
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
      _log.error('config-import', 'Replace failed', detail: e);
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
      child: DialogBody(
        width: 540,
        child: Padding(
          padding: const EdgeInsets.all(Space.x5),
          child: SingleChildScrollView(
            child: switch (_step) {
              _ImportStep.pick => _pickView(c),
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
      _title(c, Icons.file_download_outlined, 'Import File Config'),
      const SizedBox(height: Space.x2),
      Text(
        'Bring in remotes from a file: an rclone.conf, an rclone config-dump, or '
        'an Airclone encrypted export. Encrypted sources prompt for their '
        'password, and you preview everything before anything is written.',
        style: TextStyle(color: c.textFaint, fontSize: 12),
      ),
      const SizedBox(height: Space.x4),
      Row(
        children: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text('Cancel', style: TextStyle(color: c.textMuted)),
          ),
          const Spacer(),
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
        // A Wrap, not a Row: Cancel + "Replace instead…" + Merge are together
        // wider than a phone-sized dialog, so a Row clipped **Merge** off the
        // right edge — the flow completed fine, but on a phone there was no
        // button to press. Wrapping puts Merge on its own line instead; on a
        // desktop-width dialog all three still sit on one.
        Wrap(
          alignment: WrapAlignment.end,
          spacing: Space.x2,
          runSpacing: Space.x2,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel', style: TextStyle(color: c.textMuted)),
            ),
            if (plan.isNotEmpty)
              TextButton(
                onPressed: () =>
                    setState(() => _step = _ImportStep.confirmReplace),
                child: Text(
                  'Replace instead…',
                  style: TextStyle(color: c.error),
                ),
              ),
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
        // Wrap for the same reason as the preview step's actions: this is the
        // destructive confirm, so its button must never be off-screen.
        Wrap(
          alignment: WrapAlignment.end,
          spacing: Space.x2,
          runSpacing: Space.x2,
          children: [
            TextButton(
              onPressed: () => setState(() => _step = _ImportStep.preview),
              child: Text('Back', style: TextStyle(color: c.textMuted)),
            ),
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
      SelectableText(
        _errorMessage ?? 'Unknown error',
        style: TextStyle(color: c.textMuted, fontSize: 12),
      ),
      const SizedBox(height: Space.x2),
      Text(
        'This was recorded in Settings → Diagnostics, where you can copy a '
        'redacted report to attach to a bug report.',
        style: TextStyle(color: c.textFaint, fontSize: 11),
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
