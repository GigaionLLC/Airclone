import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/cache_crypto.dart';
import '../state/config_io.dart';
import '../state/config_transfer_controller.dart';
import 'dialog_body.dart';
import 'theme/tokens.dart';

/// Opens the config Export wizard (plan §4): scope (all/checklist, with the
/// dependency closure auto-included), then an envelope choice — Airclone
/// encrypted (default), plaintext INI (destructive-confirm), or an exact copy of
/// an already-rclone-encrypted config.
Future<void> showConfigExportDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const _ConfigExportDialog(),
);

/// The three export envelopes (plan §4).
enum _Envelope { airclone, plaintext, exactCopy }

enum _ExportStep { loading, form, confirmPlaintext, saving, done, error }

class _ConfigExportDialog extends ConsumerStatefulWidget {
  const _ConfigExportDialog();

  @override
  ConsumerState<_ConfigExportDialog> createState() =>
      _ConfigExportDialogState();
}

class _ConfigExportDialogState extends ConsumerState<_ConfigExportDialog> {
  _ExportStep _step = _ExportStep.loading;

  // All remotes from the live config/dump — the source of truth for the picker
  // (works even for an already-unlocked encrypted config).
  ConfigModel? _full;

  bool _allScope = true;
  final _selected = <String>{};
  _Envelope _envelope = _Envelope.airclone;

  // Secrets live only in these controllers (disposed on close).
  final _pass = TextEditingController();
  final _confirm = TextEditingController();

  String? _formError;
  String? _errorMessage;
  String? _savedPath;

  ConfigTransferController get _ctrl =>
      ref.read(configTransferControllerProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final full = await _ctrl.activeConfigModel();
      if (!mounted) return;
      setState(() {
        _full = full;
        _step = _ExportStep.form;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _ExportStep.error;
        _errorMessage = e is ConfigTransferError ? e.message : '$e';
      });
    }
  }

  // --- Scope helpers --------------------------------------------------------

  Set<String> get _scope =>
      _allScope ? (_full?.keys.toSet() ?? <String>{}) : _selected;

  /// The bases the current selection pulls in transitively, as
  /// (dependent → base) pairs for the "X needs Y — included" preview lines.
  List<({String dependent, String base})> _autoIncluded() {
    final full = _full ?? const {};
    final closure = dependencyClosure(full, _selected);
    final auto = closure.difference(_selected);
    if (auto.isEmpty) return const [];
    final pairs = <({String dependent, String base})>[];
    final seen = <String>{};
    for (final name in closure) {
      final cfg = full[name];
      if (cfg == null) continue;
      for (final dep in remoteDependencies(cfg)) {
        if (!auto.contains(dep) || !full.containsKey(dep)) continue;
        if (seen.add('$name->$dep')) {
          pairs.add((dependent: name, base: dep));
        }
      }
    }
    return pairs;
  }

  // --- Export ---------------------------------------------------------------

  Future<void> _export() async {
    final full = _full ?? const {};
    final scope = _scope;
    if (!_allScope && scope.isEmpty) {
      setState(() => _formError = 'Pick at least one remote.');
      return;
    }
    switch (_envelope) {
      case _Envelope.airclone:
        if (_pass.text.isEmpty) {
          setState(() => _formError = 'Enter a passphrase.');
          return;
        }
        // Minimum-strength gate: this envelope is an offline-brute-forceable
        // artifact, so refuse a trivially short passphrase even though the KDF
        // is Argon2id (a 1-char passphrase is the case a weak KDF was dangerous
        // for). Encourage a real passphrase, not just non-empty.
        if (_pass.text.length < 8) {
          setState(
            () => _formError = 'Use a passphrase of at least 8 characters.',
          );
          return;
        }
        if (_pass.text != _confirm.text) {
          setState(() => _formError = "Passphrases don't match.");
          return;
        }
        final loc = await getSaveLocation(
          suggestedName: 'airclone-remotes.airclone-config',
          confirmButtonText: 'Export',
        );
        if (loc == null || !mounted) return;
        setState(() {
          _formError = null;
          _step = _ExportStep.saving;
        });
        try {
          final bytes = await _ctrl.sealExport(
            _ctrl.scopedModel(full, scope),
            _pass.text,
          );
          await File(loc.path).writeAsBytes(bytes, flush: true);
          _done(loc.path);
        } catch (e) {
          _fail(e);
        }
      case _Envelope.plaintext:
        // Destructive: gate behind an explicit confirm before touching disk.
        setState(() {
          _formError = null;
          _step = _ExportStep.confirmPlaintext;
        });
      case _Envelope.exactCopy:
        final loc = await getSaveLocation(
          suggestedName: 'rclone.conf',
          confirmButtonText: 'Export',
        );
        if (loc == null || !mounted) return;
        setState(() {
          _formError = null;
          _step = _ExportStep.saving;
        });
        try {
          await _ctrl.exportExactCopy(loc.path);
          _done(loc.path);
        } catch (e) {
          _fail(e);
        }
    }
  }

  Future<void> _exportPlaintext() async {
    final full = _full ?? const {};
    final scope = _scope;
    final loc = await getSaveLocation(
      suggestedName: 'rclone.conf',
      confirmButtonText: 'Export',
    );
    if (loc == null) {
      if (mounted) setState(() => _step = _ExportStep.form);
      return;
    }
    if (!mounted) return;
    setState(() => _step = _ExportStep.saving);
    try {
      final ini = serializeIni(_ctrl.scopedModel(full, scope));
      await File(loc.path).writeAsString(ini, flush: true);
      _done(loc.path);
    } catch (e) {
      _fail(e);
    }
  }

  void _done(String path) {
    if (!mounted) return;
    setState(() {
      _savedPath = path;
      _step = _ExportStep.done;
    });
  }

  void _fail(Object e) {
    if (!mounted) return;
    setState(() {
      _step = _ExportStep.error;
      _errorMessage = e is ConfigTransferError ? e.message : '$e';
    });
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
              _ExportStep.loading => _busyView(c, 'Reading remotes…'),
              _ExportStep.form => _formView(c),
              _ExportStep.confirmPlaintext => _confirmPlaintextView(c),
              _ExportStep.saving => _busyView(c, 'Exporting…'),
              _ExportStep.done => _doneView(c),
              _ExportStep.error => _errorView(c),
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

  Widget _formView(AircloneColors c) {
    final full = _full ?? const {};
    final names = full.keys.toList();
    // "Exact copy" only makes sense for the WHOLE config, and only when it's
    // already rclone-natively encrypted (the copy stays encrypted). The held
    // config password is the live "encrypted?" signal (as in the Config section).
    final encrypted = ref.watch(cachePassphraseProvider) != null;
    final exactCopyAvailable = _allScope && encrypted;
    final auto = _allScope
        ? const <({String dependent, String base})>[]
        : _autoIncluded();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(c, Icons.file_upload_outlined, 'Export config'),
        const SizedBox(height: Space.x2),
        Text(
          'Save your remotes to a file — encrypted by default. Import it on '
          'another device from Settings → Config → Import.',
          style: TextStyle(color: c.textFaint, fontSize: 12),
        ),
        const SizedBox(height: Space.x4),

        // Scope --------------------------------------------------------------
        _sectionLabel(c, 'What to export'),
        _radioTile<bool>(
          c,
          value: true,
          group: _allScope,
          onChanged: (_) => setState(() => _allScope = true),
          title: 'All remotes',
          subtitle: '${names.length} remote${names.length == 1 ? '' : 's'}',
        ),
        _radioTile<bool>(
          c,
          value: false,
          group: _allScope,
          onChanged: (_) => setState(() {
            _allScope = false;
            // Exact copy is whole-config only — fall back to the safe default.
            if (_envelope == _Envelope.exactCopy) {
              _envelope = _Envelope.airclone;
            }
          }),
          title: 'Choose remotes',
          subtitle: 'Bases that a crypt/alias/union needs are added for you',
        ),
        if (!_allScope) ...[
          const SizedBox(height: Space.x1),
          if (names.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: Space.x4, bottom: Space.x2),
              child: Text(
                'No remotes configured.',
                style: TextStyle(color: c.textFaint, fontSize: 12),
              ),
            ),
          for (final name in names)
            _remoteCheck(c, name, full[name]?['type'] ?? ''),
          if (auto.isNotEmpty) ...[
            const SizedBox(height: Space.x1),
            Container(
              padding: const EdgeInsets.all(Space.x3),
              decoration: BoxDecoration(
                color: c.surfaceSunken,
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final p in auto)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: Text(
                        '${p.dependent} needs ${p.base} — included',
                        style: TextStyle(color: c.textMuted, fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
        const SizedBox(height: Space.x4),

        // Envelope -----------------------------------------------------------
        _sectionLabel(c, 'Format'),
        _radioTile<_Envelope>(
          c,
          value: _Envelope.airclone,
          group: _envelope,
          onChanged: (v) => setState(() => _envelope = v!),
          title: 'Airclone encrypted (recommended)',
          subtitle: 'AES-256-GCM under a passphrase you choose',
        ),
        _radioTile<_Envelope>(
          c,
          value: _Envelope.plaintext,
          group: _envelope,
          onChanged: (v) => setState(() => _envelope = v!),
          title: 'Plaintext rclone.conf',
          subtitle: 'Readable secrets — for the rclone CLI. Asks to confirm.',
        ),
        if (exactCopyAvailable)
          _radioTile<_Envelope>(
            c,
            value: _Envelope.exactCopy,
            group: _envelope,
            onChanged: (v) => setState(() => _envelope = v!),
            title: 'Exact copy (stays rclone-encrypted)',
            subtitle: 'Byte-for-byte copy — opens with rclone + its password',
          ),
        // TODO(plan §4, optional): a SCOPED rclone-native re-encryption via
        // `rclone config encryption set` on the temp file (for the rclone CLI
        // rather than another Airclone). Deferred — the plan marks it optional
        // and the Airclone envelope already covers scoped encrypted export.
        if (_envelope == _Envelope.airclone) ...[
          const SizedBox(height: Space.x3),
          _passwordField(c, _pass, 'Passphrase'),
          const SizedBox(height: Space.x2),
          _passwordField(c, _confirm, 'Confirm passphrase'),
          const SizedBox(height: Space.x2),
          Text(
            "There's no recovery — if you lose this passphrase the export can't "
            'be opened. Store it in a password manager.',
            style: TextStyle(color: c.textFaint, fontSize: 11),
          ),
        ],
        if (_formError != null) ...[
          const SizedBox(height: Space.x2),
          Text(_formError!, style: TextStyle(color: c.error, fontSize: 12)),
        ],
        const SizedBox(height: Space.x4),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel', style: TextStyle(color: c.textMuted)),
            ),
            const SizedBox(width: Space.x2),
            FilledButton.icon(
              onPressed: _export,
              icon: const Icon(Icons.file_upload_outlined, size: 16),
              label: const Text('Export…'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _confirmPlaintextView(AircloneColors c) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title(c, Icons.warning_amber_rounded, 'Export readable secrets?'),
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
                'This file contains the keys to your cloud accounts (OAuth '
                'tokens, secrets) in recoverable form. Anyone who gets the file '
                'gets your remotes. Store it somewhere safe and delete it when '
                "you're done.",
                style: TextStyle(color: c.textMuted, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: Space.x4),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => setState(() => _step = _ExportStep.form),
            child: Text('Back', style: TextStyle(color: c.textMuted)),
          ),
          const SizedBox(width: Space.x2),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: c.error,
              foregroundColor: c.onPrimary,
            ),
            onPressed: _exportPlaintext,
            child: const Text('Export plaintext'),
          ),
        ],
      ),
    ],
  );

  Widget _doneView(AircloneColors c) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title(c, Icons.check_circle_outline, 'Exported'),
      const SizedBox(height: Space.x3),
      Text('Saved to', style: TextStyle(color: c.textFaint, fontSize: 11)),
      const SizedBox(height: 2),
      Text(
        _savedPath ?? '',
        style: TextStyle(color: c.textMuted, fontSize: 12),
      ),
      const SizedBox(height: Space.x4),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ),
    ],
  );

  Widget _errorView(AircloneColors c) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title(c, Icons.error_outline, "Couldn't export"),
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
              _step = _ExportStep.form;
              _errorMessage = null;
            }),
            child: const Text('Back'),
          ),
        ],
      ),
    ],
  );

  // --- Small building blocks ------------------------------------------------

  Widget _sectionLabel(AircloneColors c, String text) => Padding(
    padding: const EdgeInsets.only(bottom: Space.x1),
    child: Text(
      text,
      style: TextStyle(
        color: c.textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _radioTile<T>(
    AircloneColors c, {
    required T value,
    required T group,
    required ValueChanged<T?> onChanged,
    required String title,
    required String subtitle,
  }) => InkWell(
    onTap: () => onChanged(value),
    borderRadius: BorderRadius.circular(Radii.sm),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Radio<T>(
            value: value,
            // ignore: deprecated_member_use
            groupValue: group,
            // ignore: deprecated_member_use
            onChanged: onChanged,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          const SizedBox(width: Space.x1),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    title,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(color: c.textFaint, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _remoteCheck(AircloneColors c, String name, String type) {
    final checked = _selected.contains(name);
    return InkWell(
      onTap: () => setState(() {
        if (checked) {
          _selected.remove(name);
        } else {
          _selected.add(name);
        }
      }),
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Padding(
        padding: const EdgeInsets.only(left: Space.x3),
        child: Row(
          children: [
            Checkbox(
              value: checked,
              onChanged: (v) => setState(() {
                if (v == true) {
                  _selected.add(name);
                } else {
                  _selected.remove(name);
                }
              }),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: Space.x2),
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.text, fontSize: 13),
              ),
            ),
            const SizedBox(width: Space.x2),
            Text(
              type.isEmpty ? 'unknown' : type,
              style: TextStyle(color: c.textFaint, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _passwordField(
    AircloneColors c,
    TextEditingController controller,
    String hint,
  ) => TextField(
    controller: controller,
    obscureText: true,
    decoration: InputDecoration(
      isDense: true,
      hintText: hint,
      hintStyle: TextStyle(color: c.textFaint, fontSize: 13),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.md)),
    ),
    style: TextStyle(color: c.text, fontSize: 13),
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
