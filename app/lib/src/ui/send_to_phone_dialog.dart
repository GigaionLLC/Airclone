import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../state/config_io.dart';
import '../state/config_transfer_controller.dart';
import '../state/pairing_sender.dart';
import 'theme/tokens.dart';

/// Opens the desktop "Send to phone" wizard (plan §5, v3 QR-pinned TLS): pick a
/// scope (all/checklist, with the dependency closure auto-included, exactly like
/// Export), then show a QR the phone scans and a field for the pairing code the
/// phone displays. The config never leaves this machine until a phone proves it
/// knows that code over the pinned-TLS channel. Desktop-only — mounted behind a
/// desktop gate in Settings → Config.
Future<void> showSendToPhoneDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const _SendToPhoneDialog(),
);

enum _Step { loading, scope, pairing, error }

class _SendToPhoneDialog extends ConsumerStatefulWidget {
  const _SendToPhoneDialog();

  @override
  ConsumerState<_SendToPhoneDialog> createState() => _SendToPhoneDialogState();
}

class _SendToPhoneDialogState extends ConsumerState<_SendToPhoneDialog> {
  _Step _step = _Step.loading;

  // All remotes from the live config/dump — the picker's source of truth.
  ConfigModel? _full;

  bool _allScope = true;
  final _selected = <String>{};

  // The pairing code the user reads off the phone lives ONLY in this controller
  // (disposed on close) — never in provider state, never logged.
  final _code = TextEditingController();

  PairingSender? _sender;
  bool _starting = false;
  bool _finishing = false; // guards the one-shot auto-close on delivery
  String? _scopeError;
  String? _codeError;
  String? _errorMessage;

  ConfigTransferController get _ctrl =>
      ref.read(configTransferControllerProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    // Zeroizes salt/key/blob and tears down the socket — nothing survives close.
    _sender?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final full = await _ctrl.activeConfigModel();
      if (!mounted) return;
      setState(() {
        _full = full;
        _step = _Step.scope;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _Step.error;
        _errorMessage = e is ConfigTransferError ? e.message : '$e';
      });
    }
  }

  // --- Scope helpers (mirrors the Export wizard) ----------------------------

  Set<String> get _scope =>
      _allScope ? (_full?.keys.toSet() ?? <String>{}) : _selected;

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

  // --- Flow -----------------------------------------------------------------

  Future<void> _start() async {
    final full = _full ?? const {};
    final scope = _scope;
    if (!_allScope && scope.isEmpty) {
      setState(() => _scopeError = 'Pick at least one remote.');
      return;
    }
    setState(() {
      _starting = true;
      _scopeError = null;
    });
    try {
      // The blob is the scoped config as plaintext INI — the pairing seal IS the
      // transport encryption, so we hand the sender the plaintext bytes and it
      // never touches disk. Reuses the controller's dependency-closure scoping.
      final model = _ctrl.scopedModel(full, scope);
      final blob = utf8.encode(serializeIni(model));
      final sender = await ref
          .read(pairingSenderProvider)
          .start(configBlob: blob);
      if (!mounted) {
        await sender.dispose();
        return;
      }
      setState(() {
        _sender = sender;
        _starting = false;
        _step = _Step.pairing;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _step = _Step.error;
        _errorMessage = switch (e) {
          PairingSenderError(:final message) => message,
          ConfigTransferError(:final message) => message,
          _ => '$e',
        };
      });
    }
  }

  Future<void> _armCode() async {
    final sender = _sender;
    if (sender == null) return;
    setState(() => _codeError = null);
    try {
      await sender.armCode(_code.text);
    } on FormatException {
      if (!mounted) return;
      setState(
        () => _codeError =
            "That code doesn't look right — check your phone and re-type it.",
      );
    }
  }

  void _onStatus(PairingStatus status) {
    // Auto-close a moment after a successful delivery so the user sees the
    // confirmation. Guarded so it fires exactly once.
    if (status.phase == PairingPhase.delivered && !_finishing) {
      _finishing = true;
      Future<void>.delayed(const Duration(milliseconds: 1100), () {
        if (mounted) Navigator.of(context).pop();
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
              _Step.loading => _busyView(c, 'Reading remotes…'),
              _Step.scope => _scopeView(c),
              _Step.pairing => _pairingView(c),
              _Step.error => _errorView(c),
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

  Widget _scopeView(AircloneColors c) {
    final full = _full ?? const {};
    final names = full.keys.toList();
    final auto = _allScope
        ? const <({String dependent, String base})>[]
        : _autoIncluded();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(c, Icons.qr_code_2, 'Send to phone'),
        const SizedBox(height: Space.x2),
        Text(
          'Move remotes to your phone over your local network — no cloud, no '
          'account. Pick what to send, then scan the QR on your phone and type '
          'the code it shows.',
          style: TextStyle(color: c.textFaint, fontSize: 12),
        ),
        const SizedBox(height: Space.x4),
        _sectionLabel(c, 'What to send'),
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
          onChanged: (_) => setState(() => _allScope = false),
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
        if (_scopeError != null) ...[
          const SizedBox(height: Space.x2),
          Text(_scopeError!, style: TextStyle(color: c.error, fontSize: 12)),
        ],
        const SizedBox(height: Space.x4),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _starting ? null : () => Navigator.of(context).pop(),
              child: Text('Cancel', style: TextStyle(color: c.textMuted)),
            ),
            const SizedBox(width: Space.x2),
            FilledButton.icon(
              onPressed: _starting ? null : _start,
              icon: _starting
                  ? const SizedBox(
                      height: 14,
                      width: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.qr_code_2, size: 16),
              label: Text(_starting ? 'Starting…' : 'Show QR'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _pairingView(AircloneColors c) {
    final sender = _sender!;
    return ValueListenableBuilder<PairingStatus>(
      valueListenable: sender.status,
      builder: (context, status, _) {
        _onStatus(status);
        final done =
            status.phase == PairingPhase.delivered ||
            status.phase == PairingPhase.lockedOut ||
            status.phase == PairingPhase.expired;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title(c, Icons.qr_code_2, 'Scan with your phone'),
            const SizedBox(height: Space.x3),
            // The QR needs a light quiet-zone to scan reliably, so it always
            // renders black-on-white regardless of the app theme.
            Center(
              child: Container(
                padding: const EdgeInsets.all(Space.x3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: QrImageView(
                  data: sender.qrPayload,
                  version: QrVersions.auto,
                  size: 216,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFF000000),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF000000),
                  ),
                ),
              ),
            ),
            const SizedBox(height: Space.x3),
            Text(
              'On your phone: open Airclone → Scan, point it at this code, then '
              "type the code it shows back here. (The code never appears on this "
              'screen — reading it off the phone is what keeps the transfer safe.)',
              style: TextStyle(color: c.textFaint, fontSize: 12),
            ),
            const SizedBox(height: Space.x3),
            _codeField(c, enabled: !done),
            if (_codeError != null) ...[
              const SizedBox(height: Space.x2),
              Text(_codeError!, style: TextStyle(color: c.error, fontSize: 12)),
            ],
            const SizedBox(height: Space.x3),
            _statusRow(c, status),
            const SizedBox(height: Space.x2),
            _hostHint(c, sender),
            const SizedBox(height: Space.x4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    done ? 'Close' : 'Cancel',
                    style: TextStyle(color: c.textMuted),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _codeField(AircloneColors c, {required bool enabled}) => Row(
    children: [
      Expanded(
        child: TextField(
          controller: _code,
          enabled: enabled,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          onSubmitted: (_) => _armCode(),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Code from your phone (e.g. K7WX-4PMB)',
            hintStyle: TextStyle(color: c.textFaint, fontSize: 13),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.md),
            ),
          ),
          style: TextStyle(color: c.text, fontSize: 14, letterSpacing: 1.5),
        ),
      ),
      const SizedBox(width: Space.x2),
      FilledButton(
        onPressed: enabled ? _armCode : null,
        child: const Text('Enter'),
      ),
    ],
  );

  Widget _statusRow(AircloneColors c, PairingStatus status) {
    final (icon, tint, text) = switch (status.phase) {
      PairingPhase.waiting => (
        Icons.wifi_tethering,
        c.textMuted,
        'Waiting for your phone to scan…',
      ),
      PairingPhase.phoneConnected =>
        status.codeArmed
            ? (Icons.sync, c.info, 'Phone connected — verifying the code…')
            : (
                Icons.smartphone,
                c.info,
                "Phone connected. Type the code it's showing above.",
              ),
      PairingPhase.delivered => (
        Icons.check_circle_outline,
        c.success,
        'Sent to your phone.',
      ),
      PairingPhase.lockedOut => (
        Icons.gpp_maybe_outlined,
        c.error,
        'Stopped after 3 wrong codes — someone may be interfering on your '
            'network. Close and start again.',
      ),
      PairingPhase.expired => (
        Icons.timer_off_outlined,
        c.warning,
        'This transfer timed out (5 minutes). Close and start again.',
      ),
      PairingPhase.error => (
        Icons.error_outline,
        c.error,
        'The transfer was stopped by an unexpected error.',
      ),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: tint),
        const SizedBox(width: Space.x2),
        Expanded(
          child: Text(text, style: TextStyle(color: tint, fontSize: 12)),
        ),
      ],
    );
  }

  /// Honest failure hints: which address this computer is on, and — if it has
  /// several — that the phone must be on the SAME network to connect.
  Widget _hostHint(AircloneColors c, PairingSender sender) {
    final others = sender.candidateHosts
        .where((h) => h.address != sender.host.address)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'This computer: ${sender.host.address}',
          style: TextStyle(color: c.textFaint, fontSize: 11),
        ),
        if (others.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              "Can't connect? Your phone must be on the same Wi-Fi. Other "
              'addresses on this computer: ${others.map((h) => h.address).join(', ')}.',
              style: TextStyle(color: c.textFaint, fontSize: 11),
            ),
          ),
      ],
    );
  }

  Widget _errorView(AircloneColors c) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title(c, Icons.error_outline, "Couldn't start"),
      const SizedBox(height: Space.x3),
      Text(
        _errorMessage ?? 'Unknown error',
        style: TextStyle(color: c.textMuted, fontSize: 12),
      ),
      const SizedBox(height: Space.x4),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ),
    ],
  );

  // --- Small building blocks (mirrors config_export_dialog) -----------------

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
