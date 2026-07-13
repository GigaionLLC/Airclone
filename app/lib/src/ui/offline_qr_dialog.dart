import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../state/config_io.dart';
import '../state/config_transfer_controller.dart';
import '../state/offline_qr.dart';
import 'theme/tokens.dart';

/// Desktop/mobile "Export QR Config" (config-portability plan §5, reworked
/// 2026-07): seal the (scoped) config into a self-contained QR that carries the
/// WHOLE encrypted config — no Wi-Fi, no server.
///
/// The unlock CODE is NOT generated or shown here. Instead the OTHER device (the
/// one that will scan) opens "Import QR Config" first, which shows a one-time
/// code; you TYPE that code here — obscured, so a shoulder-surfer or a screen
/// recording of this window captures only the QR, never the code. The scanning
/// device already knows the code, so it opens automatically. A thief needs BOTH
/// the QR photo AND the code, and the code never appears on this screen at all.
Future<void> showOfflineQrDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const _OfflineQrDialog(),
);

enum _Step { loading, compose, qr, error }

/// Auto-uppercases typed input. The scanning device's code is uppercase Crockford
/// (see [newPairingCode]); the seal/open is case-sensitive, so uppercasing what
/// the user types removes the #1 "wrong code" cause — retyping `k7wx` for `K7WX`.
class _UpperCaseFormatter extends TextInputFormatter {
  const _UpperCaseFormatter();
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue _,
    TextEditingValue next,
  ) => next.copyWith(text: next.text.toUpperCase());
}

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

  // The code lives ONLY in this controller (disposed on close) — never in
  // provider state, never logged, never in the QR. Obscured by default; the eye
  // toggle lets the user verify it matches the phone before sealing.
  final _code = TextEditingController();
  bool _reveal = false;
  bool _busy = false;
  String? _formError;
  String? _errorMessage;

  // The generated QR payload(s), once composed — one for a config that fits a
  // single QR, several for a large config split across QRs. [_qrIndex] pages them.
  List<String>? _payloads;
  int _qrIndex = 0;

  // For a multi-QR export, auto-CYCLE the codes on one screen (~5.5 fps) so the
  // phone just points once and the accumulating scanner collects each frame as
  // it flashes by — far less clunky than paging + holding each still. Looping
  // means a missed frame comes back around. [_playing] toggles it; manual
  // prev/next pause it.
  Timer? _cycle;
  bool _playing = true;

  ConfigTransferController get _ctrl =>
      ref.read(configTransferControllerProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cycle?.cancel();
    _code.dispose();
    super.dispose();
  }

  /// Start/stop the auto-cycle timer to match the current state: it runs only on
  /// the QR step, with more than one code, while [_playing]. Idempotent — call it
  /// after any state change that could affect those conditions.
  void _syncCycle() {
    _cycle?.cancel();
    _cycle = null;
    final n = _payloads?.length ?? 0;
    if (_step == _Step.qr && n > 1 && _playing) {
      _cycle = Timer.periodic(const Duration(milliseconds: 180), (_) {
        if (!mounted) return;
        setState(() => _qrIndex = (_qrIndex + 1) % n);
      });
    }
  }

  /// Manually jump to code [i] — this pauses the auto-cycle so the user can hold
  /// a specific one steady.
  void _stepTo(int i) {
    setState(() {
      _playing = false;
      _qrIndex = i;
    });
    _syncCycle();
  }

  Future<void> _load() async {
    try {
      final full = await _ctrl.activeConfigModel();
      if (!mounted) return;
      setState(() {
        _full = full;
        _step = _Step.compose;
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
    // Validate against the canonical form (dashes/spaces stripped) — the phone
    // shows a dashed code like K7WX-4PMB, so 6+ real symbols is the real floor.
    final code = _code.text;
    if (canonicalOfflineCode(code).length < 6) {
      setState(
        () => _formError =
            "Enter the code from the phone's Import QR Config screen.",
      );
      return;
    }
    setState(() {
      _busy = true;
      _formError = null;
    });
    try {
      final model = _ctrl.scopedModel(full, scope);
      final text = serializeIni(model);
      final payloads = await buildOfflineQrPayloads(text, code);
      if (!mounted) return;
      setState(() {
        _payloads = payloads;
        _qrIndex = 0;
        _playing = true;
        _busy = false;
        _step = _Step.qr;
      });
      _syncCycle(); // auto-cycle if this produced multiple codes
    } on OfflineQrTooLarge {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _formError =
            'This config is too large even for a batch of offline QR codes. '
            'Choose fewer remotes and try again.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _formError = e is ConfigTransferError ? e.message : '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    // Shown on desktop AND mobile now: cap at a comfortable width, but shrink to
    // fit a narrow phone (with tighter inset margins) so nothing overflows.
    final screenW = MediaQuery.of(context).size.width;
    final narrow = screenW < 560;
    final dialogW = narrow ? screenW - Space.x3 * 2 : 520.0;
    return Dialog(
      backgroundColor: c.surfaceRaised,
      insetPadding: EdgeInsets.symmetric(
        horizontal: narrow ? Space.x3 : Space.x5,
        vertical: Space.x5,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: SizedBox(
        width: dialogW,
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
        _title(c, Icons.qr_code_2, 'Export QR Config'),
        const SizedBox(height: Space.x2),
        Text(
          'Send your remotes to a phone in a single QR — no Wi-Fi, no account. '
          'On the phone, open "Import QR Config" first: it shows a one-time code. '
          'Enter that code below, make the QR, then scan it with the phone.',
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
        _sectionLabel(c, 'Code from the phone'),
        _codeField(c, autofocus: true),
        const SizedBox(height: Space.x1),
        Text(
          "Type the code shown on the phone's Import QR Config screen (the dash is "
          "optional). It's case-sensitive, so we uppercase it for you. The code "
          'is never stored in the QR — a photo of the QR alone cannot open your '
          'remotes.',
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

  Widget _qrView(AircloneColors c) {
    final payloads = _payloads ?? const [];
    final multi = payloads.length > 1;
    final idx = _qrIndex.clamp(0, payloads.length - 1);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(
          c,
          Icons.qr_code_2,
          multi ? 'Scan all ${payloads.length} codes' : 'Scan with your phone',
        ),
        if (multi) ...[
          const SizedBox(height: Space.x2),
          Text(
            "This config is too big for one QR, so it's split across "
            '${payloads.length} codes. On the phone → Import QR Config → Scan, '
            "point at each in turn — it counts them down and reassembles them. "
            "Order doesn't matter; scan every one.",
            style: TextStyle(color: c.textFaint, fontSize: 12),
          ),
        ],
        const SizedBox(height: Space.x3),
        Center(
          child: Container(
            padding: const EdgeInsets.all(Space.x3),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: LayoutBuilder(
              builder: (context, cns) {
                // Render as large as the (possibly narrow, mobile) dialog allows,
                // capped at 380: a phone scanning off a lit screen needs enough
                // pixels-per-module, and the smaller payload/chunk sizing in
                // offline_qr.dart keeps the module count comfortably scannable.
                final qrSize = (cns.maxWidth.isFinite ? cns.maxWidth : 380.0)
                    .clamp(160.0, 380.0);
                return QrImageView(
                  data: payloads[idx],
                  version: QrVersions.auto,
                  size: qrSize,
                  backgroundColor: Colors.white,
                  // Medium error correction — robust to a screen-photo scan
                  // without over-spending capacity.
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFF000000),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF000000),
                  ),
                );
              },
            ),
          ),
        ),
        if (multi) ...[
          const SizedBox(height: Space.x2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () =>
                    _stepTo((idx - 1 + payloads.length) % payloads.length),
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Previous',
              ),
              IconButton(
                onPressed: () {
                  setState(() => _playing = !_playing);
                  _syncCycle();
                },
                icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                color: c.primary,
                tooltip: _playing ? 'Pause cycling' : 'Resume cycling',
              ),
              Text(
                'QR ${idx + 1} of ${payloads.length}',
                style: TextStyle(
                  color: c.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              IconButton(
                onPressed: () => _stepTo((idx + 1) % payloads.length),
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Next',
              ),
            ],
          ),
        ],
        const SizedBox(height: Space.x2),
        Text(
          multi
              ? 'These codes cycle on their own — on the phone → Import QR Config → '
                    'Scan, just hold the camera on this square and it collects them '
                    'all, then opens automatically. Everything transfers offline.'
              : "Point the phone's camera (Import QR Config → Scan) at this code. "
                    'The phone already has the unlock code, so it opens '
                    'automatically. Everything transfers offline — nothing leaves '
                    'this screen except the picture.',
          style: TextStyle(color: c.textFaint, fontSize: 12),
        ),
        const SizedBox(height: Space.x4),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () {
                setState(() => _step = _Step.compose);
                _syncCycle(); // leaving the QR step stops the cycle
              },
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
  }

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

  Widget _codeField(AircloneColors c, {bool autofocus = false}) => TextField(
    controller: _code,
    obscureText: !_reveal,
    autofocus: autofocus,
    autocorrect: false,
    enableSuggestions: false,
    inputFormatters: const [_UpperCaseFormatter()],
    textCapitalization: TextCapitalization.characters,
    onSubmitted: (_) => _busy ? null : _generate(),
    style: TextStyle(color: c.text, letterSpacing: 1.2),
    decoration: InputDecoration(
      isDense: true,
      labelText: 'Code',
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.md)),
      suffixIcon: IconButton(
        tooltip: _reveal ? 'Hide code' : 'Show code',
        onPressed: () => setState(() => _reveal = !_reveal),
        icon: Icon(
          _reveal ? Icons.visibility_off : Icons.visibility,
          size: 16,
          color: c.textMuted,
        ),
      ),
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
