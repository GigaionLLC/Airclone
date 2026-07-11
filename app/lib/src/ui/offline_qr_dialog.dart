import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../state/config_io.dart';
import '../state/config_transfer_controller.dart';
import '../state/offline_qr.dart';
import '../state/pairing_protocol.dart' show newPairingCode;
import 'theme/tokens.dart';

/// Desktop "Offline QR" export (config-portability plan §5, user-requested): seal
/// the (scoped) config into a self-contained QR that carries the WHOLE encrypted
/// config — no Wi-Fi, no server. You choose an unlock CODE (never shown in the QR);
/// the phone scans the QR and enters the same code to decrypt. A thief needs BOTH
/// the QR photo AND the code. Distinct from "Send to phone…", which streams the
/// config over the local network. Desktop-only (mounted behind a desktop gate).
Future<void> showOfflineQrDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const _OfflineQrDialog(),
);

enum _Step { loading, compose, qr, error }

class _OfflineQrDialog extends ConsumerStatefulWidget {
  const _OfflineQrDialog();

  @override
  ConsumerState<_OfflineQrDialog> createState() => _OfflineQrDialogState();
}

class _OfflineQrDialogState extends ConsumerState<_OfflineQrDialog> {
  _Step _step = _Step.loading;
  ConfigModel? _full;

  bool _allScope = true;
  final _selected = <String>{};

  // The code lives ONLY in these controllers (disposed on close) — never in
  // provider state, never logged, never in the QR.
  final _code = TextEditingController();
  final _confirm = TextEditingController();
  bool _reveal = false;
  bool _busy = false;
  String? _formError;
  String? _errorMessage;

  // The generated payload string, once composed.
  String? _payload;

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
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final full = await _ctrl.activeConfigModel();
      if (!mounted) return;
      // Default to a strong GENERATED code (the secure path). A weak self-chosen
      // code is the offline QR's main risk — an attacker with the QR photo can
      // brute-force it offline — so make the strong code the default, revealed so
      // the user can read + type it on the phone.
      final code = newPairingCode();
      setState(() {
        _full = full;
        _step = _Step.compose;
        _code.text = code;
        _confirm.text = code;
        _reveal = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _Step.error;
        _errorMessage = e is ConfigTransferError ? e.message : '$e';
      });
    }
  }

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
        if (seen.add('$name->$dep')) pairs.add((dependent: name, base: dep));
      }
    }
    return pairs;
  }

  Future<void> _generate() async {
    final full = _full ?? const {};
    final scope = _scope;
    if (scope.isEmpty) {
      setState(
        () => _formError = _allScope
            ? 'You have no remotes to put in a QR.'
            : 'Pick at least one remote.',
      );
      return;
    }
    final code = _code.text;
    if (code.length < 8) {
      setState(
        () =>
            _formError = 'Use a longer code — or tap "Suggest a strong code".',
      );
      return;
    }
    // A word-like (all-lowercase) code is easy to brute-force from the QR photo
    // unless it's very long. Steer to the strong generated code instead.
    if (RegExp(r'^[a-z]+$').hasMatch(code) && code.length < 14) {
      setState(
        () => _formError =
            'That code is too guessable. Use the suggested code, add capitals/'
            'digits, or make it much longer.',
      );
      return;
    }
    if (code != _confirm.text) {
      setState(() => _formError = "The codes don't match.");
      return;
    }
    setState(() {
      _busy = true;
      _formError = null;
    });
    try {
      final model = _ctrl.scopedModel(full, scope);
      final text = serializeIni(model);
      final payload = await buildOfflineQrPayload(text, code);
      if (!mounted) return;
      setState(() {
        _payload = payload;
        _busy = false;
        _step = _Step.qr;
      });
    } on OfflineQrTooLarge {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _formError =
            'This config is too large for a single offline QR. Choose fewer '
            'remotes, or use "Send to phone" over Wi-Fi instead.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _formError = e is ConfigTransferError ? e.message : '$e';
      });
    }
  }

  void _suggest() {
    final code = newPairingCode(); // e.g. K7WX-4PMB — easy to read + type
    setState(() {
      _code.text = code;
      _confirm.text = code;
      _reveal = true; // reveal so the user can note the generated code
      _formError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return Dialog(
      backgroundColor: c.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: SizedBox(
        width: 520,
        child: Padding(
          padding: const EdgeInsets.all(Space.x5),
          child: SingleChildScrollView(
            child: switch (_step) {
              _Step.loading => _busyView(c, 'Reading remotes…'),
              _Step.compose => _composeView(c),
              _Step.qr => _qrView(c),
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

  Widget _composeView(AircloneColors c) {
    final full = _full ?? const {};
    final names = full.keys.toList();
    final auto = _allScope ? const [] : _autoIncluded();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(c, Icons.qr_code_2, 'Offline QR'),
        const SizedBox(height: Space.x2),
        Text(
          'Put your remotes in a single QR — no Wi-Fi, no account. Choose a code; '
          'the QR holds the encrypted config, and your phone needs that same code '
          'to open it. The code is never in the QR.',
          style: TextStyle(color: c.textFaint, fontSize: 12),
        ),
        const SizedBox(height: Space.x4),
        _sectionLabel(c, 'What to include'),
        _radioTile(
          c,
          value: true,
          group: _allScope,
          onChanged: () => setState(() => _allScope = true),
          title: 'All remotes',
          subtitle: '${names.length} remote${names.length == 1 ? '' : 's'}',
        ),
        _radioTile(
          c,
          value: false,
          group: _allScope,
          onChanged: () => setState(() => _allScope = false),
          title: 'Choose remotes',
          subtitle: 'Bases a crypt/alias/union needs are added for you',
        ),
        if (!_allScope) ...[
          for (final name in names)
            _remoteCheck(c, name, full[name]?['type'] ?? ''),
          if (auto.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Space.x1, left: Space.x3),
              child: Text(
                auto.map((p) => '${p.dependent} needs ${p.base}').join(' · '),
                style: TextStyle(color: c.textMuted, fontSize: 11),
              ),
            ),
        ],
        const SizedBox(height: Space.x4),
        _sectionLabel(c, 'Unlock code'),
        _codeField(c, _code, 'Code', autofocus: true),
        const SizedBox(height: Space.x2),
        _codeField(c, _confirm, 'Confirm code'),
        const SizedBox(height: Space.x1),
        Row(
          children: [
            TextButton.icon(
              onPressed: _suggest,
              icon: const Icon(Icons.casino_outlined, size: 15),
              label: const Text('Suggest a strong code'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
            const Spacer(),
            IconButton(
              tooltip: _reveal ? 'Hide code' : 'Show code',
              onPressed: () => setState(() => _reveal = !_reveal),
              icon: Icon(
                _reveal ? Icons.visibility_off : Icons.visibility,
                size: 16,
                color: c.textMuted,
              ),
            ),
          ],
        ),
        Text(
          "Anyone with both the QR and this code can read your remotes' secrets. "
          'The QR is easy to photograph, so the code is your only protection — '
          'use the suggested one (or a long random code), not a word you know.',
          style: TextStyle(color: c.textFaint, fontSize: 11),
        ),
        if (_formError != null) ...[
          const SizedBox(height: Space.x2),
          Text(_formError!, style: TextStyle(color: c.error, fontSize: 12)),
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
              onPressed: _busy ? null : _generate,
              icon: _busy
                  ? const SizedBox(
                      height: 14,
                      width: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.qr_code_2, size: 16),
              label: Text(_busy ? 'Sealing…' : 'Make QR'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _qrView(AircloneColors c) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title(c, Icons.qr_code_2, 'Scan with your phone'),
      const SizedBox(height: Space.x3),
      Center(
        child: Container(
          padding: const EdgeInsets.all(Space.x3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: QrImageView(
            data: _payload!,
            version: QrVersions.auto,
            size: 300,
            backgroundColor: Colors.white,
            // Medium error correction — robust to a screen-photo scan without
            // over-spending capacity.
            errorCorrectionLevel: QrErrorCorrectLevel.M,
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
        'On your phone: open Airclone → Scan, point it at this QR, then enter '
        'the code you chose. Everything transfers offline — nothing leaves this '
        'screen except the picture.',
        style: TextStyle(color: c.textFaint, fontSize: 12),
      ),
      const SizedBox(height: Space.x4),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => setState(() => _step = _Step.compose),
            child: Text('Back', style: TextStyle(color: c.textMuted)),
          ),
          const SizedBox(width: Space.x2),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    ],
  );

  Widget _errorView(AircloneColors c) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title(c, Icons.error_outline, "Couldn't read the config"),
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

  // --- building blocks ------------------------------------------------------

  Widget _codeField(
    AircloneColors c,
    TextEditingController ctrl,
    String label, {
    bool autofocus = false,
  }) => TextField(
    controller: ctrl,
    obscureText: !_reveal,
    autofocus: autofocus,
    style: TextStyle(color: c.text, letterSpacing: 1.2),
    decoration: InputDecoration(
      isDense: true,
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.md)),
    ),
  );

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

  Widget _radioTile(
    AircloneColors c, {
    required bool value,
    required bool group,
    required VoidCallback onChanged,
    required String title,
    required String subtitle,
  }) => InkWell(
    onTap: onChanged,
    borderRadius: BorderRadius.circular(Radii.sm),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            value == group
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            size: 18,
            color: value == group ? c.primary : c.textFaint,
          ),
          const SizedBox(width: Space.x2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
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
        checked ? _selected.remove(name) : _selected.add(name);
      }),
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Padding(
        padding: const EdgeInsets.only(left: Space.x3),
        child: Row(
          children: [
            Checkbox(
              value: checked,
              onChanged: (v) => setState(() {
                v == true ? _selected.add(name) : _selected.remove(name);
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
