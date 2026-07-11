import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../state/config_io.dart';
import '../state/config_transfer_controller.dart';
import '../state/offline_qr.dart';
import '../state/pairing_protocol.dart';
import '../state/pairing_receiver.dart';
import 'theme/tokens.dart';

/// Opens the phone-side "Import from a computer (QR)" flow (config-portability
/// plan §5, v3 QR-pinned-TLS): scan the desktop's QR → show a pairing code to type
/// on the computer → run the pinned-TLS authenticate-before-serve handshake → land
/// in the MANDATORY preview/merge review before anything is written.
///
/// Pushed as a full-screen route (the camera + multi-step flow needs the height);
/// the crypto/networking all lives in [PairingReceiver] and the import apply reuses
/// [ConfigTransferController] — this widget is only the phone-first choreography.
Future<void> showScanFromDesktopSheet(BuildContext context) => Navigator.of(
  context,
).push<void>(MaterialPageRoute(builder: (_) => const _ScanFromDesktopScreen()));

/// The flow's steps. [scanning] is the live camera; [pairing] shows the code and
/// polls the desktop (LAN QR); [offlineCode] prompts for the unlock code of a
/// self-contained OFFLINE QR; [preview] is the MANDATORY review (type + endpoint
/// per remote, collision renames); [applying]/[report] run and summarise the
/// merge; [error] is a terminal dead-end with a retry.
enum _Step { scanning, pairing, offlineCode, preview, applying, report, error }

class _ScanFromDesktopScreen extends ConsumerStatefulWidget {
  const _ScanFromDesktopScreen();

  @override
  ConsumerState<_ScanFromDesktopScreen> createState() =>
      _ScanFromDesktopScreenState();
}

class _ScanFromDesktopScreenState
    extends ConsumerState<_ScanFromDesktopScreen> {
  /// rclone's remote-name charset (letters/digits/`_`/`-`/`.`) — validate a
  /// collision rename before apply, exactly as the file-import wizard does.
  static final RegExp _validRemoteName = RegExp(r'^[A-Za-z0-9_.-]+$');

  /// Only-scan-QRs, and ignore repeated reads of the same code — we act on the
  /// first frame that carries a valid payload and then stop the camera.
  final MobileScannerController _scanner = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  _Step _step = _Step.scanning;
  bool _handledScan = false; // guard: process the first valid QR exactly once

  ParsedQrPayload? _qr;
  // The pairing code is minted once per session on THIS phone and shown for the
  // user to type on the desktop. A short-lived String (immutable — can't be
  // wiped); it lives only for the pairing step and is dropped when we leave.
  String? _code;
  String _status = '';

  // Offline-QR path: the scanned self-contained payload + the code the user
  // enters here to decrypt it (lives only in the controller, never logged).
  String? _offlinePayload;
  final _offlineCode = TextEditingController();
  bool _offlineBusy = false;
  String? _offlineError;

  // Import review state (mirrors the file-import wizard's preview).
  ConfigModel? _incoming;
  ConfigModel? _existing;
  List<ImportDecision>? _plan;
  final _renames = <String, TextEditingController>{};
  String? _previewError;

  MergeReport? _report;
  String? _errorMessage;

  bool _disposed = false;

  ConfigTransferController get _ctrl =>
      ref.read(configTransferControllerProvider);

  @override
  void dispose() {
    _disposed = true;
    _scanner.dispose();
    _offlineCode.dispose();
    _disposeRenames();
    super.dispose();
  }

  void _disposeRenames() {
    for (final c in _renames.values) {
      c.dispose();
    }
    _renames.clear();
  }

  // --- Scan -----------------------------------------------------------------

  /// Handles a camera detection: take the first non-empty raw QR value, stop the
  /// camera, and strictly parse it. A parse rejection (wrong scheme, non-private
  /// host, bad lengths) is a clear terminal error — NEVER a fetch — matching the
  /// two-channel security model.
  void _onDetect(BarcodeCapture capture) {
    if (_handledScan) return;
    String? raw;
    for (final b in capture.barcodes) {
      if (b.rawValue != null && b.rawValue!.isNotEmpty) {
        raw = b.rawValue;
        break;
      }
    }
    if (raw == null) return;
    _handledScan = true;
    unawaited(_scanner.stop());
    // A self-contained OFFLINE QR carries the whole encrypted config — no network
    // handshake. Route to the code prompt instead of the LAN pairing flow.
    if (isOfflineQrPayload(raw)) {
      setState(() {
        _offlinePayload = raw;
        _offlineError = null;
        _step = _Step.offlineCode;
      });
      return;
    }
    try {
      final qr = parseQrPayload(raw);
      setState(() {
        _qr = qr;
        _code = newPairingCode();
        _status = 'Waiting for the computer…';
        _step = _Step.pairing;
      });
      unawaited(_runPairing());
    } on QrPayloadError catch (e) {
      _toError(
        "That QR code isn't a valid Airclone transfer (${e.message}). Make sure "
        "you're scanning the code from the Airclone \"Send to phone\" window.",
      );
    } catch (_) {
      _toError("That QR code couldn't be read. Try generating a fresh one.");
    }
  }

  // --- Offline QR (decrypt-in-place, no network) ----------------------------

  /// Decrypts the scanned offline QR with the entered code, parses the config,
  /// and lands in the MANDATORY preview — reusing the same merge review as every
  /// other import. A wrong code stays on this step (recoverable); a malformed or
  /// foreign QR is a terminal error.
  Future<void> _openOffline() async {
    final payload = _offlinePayload;
    if (payload == null) return;
    final code = _offlineCode.text;
    if (code.isEmpty) {
      setState(() => _offlineError = 'Enter the code from your computer.');
      return;
    }
    setState(() {
      _offlineBusy = true;
      _offlineError = null;
    });
    try {
      final text = await openOfflineQrPayload(payload, code);
      if (_disposed) return;
      _incoming = parseIni(text);
      _offlineBusy = false;
      await _enterPreview();
    } on WrongPassphrase {
      if (_disposed) return;
      setState(() {
        _offlineBusy = false;
        _offlineError =
            "That code didn't work — check your computer and re-enter it.";
      });
    } on NotAnOfflineQr {
      _toError("That QR isn't an Airclone offline transfer.");
    } on CorruptEnvelope catch (e) {
      _toError(
        "That offline QR couldn't be read (${e.message}). Generate a fresh one.",
      );
    } on FormatException {
      _toError('That offline QR is malformed. Generate a fresh one.');
    } catch (_) {
      if (_disposed) return;
      setState(() {
        _offlineBusy = false;
        _offlineError = "Couldn't open that QR. Try again.";
      });
    }
  }

  // --- Pairing (handshake + retry-until-code-typed) -------------------------

  /// Runs the authenticated fetch, retrying on [PairingFailureKind.notReady] (the
  /// desktop is still waiting for the code) on a fresh connection each time until a
  /// short deadline. Every other outcome is terminal with an honest message.
  Future<void> _runPairing() async {
    final receiver = ref.read(pairingReceiverProvider);
    final qr = _qr!;
    final code = _code!;
    final deadline = DateTime.now().add(const Duration(seconds: 90));

    while (!_disposed && _step == _Step.pairing) {
      try {
        await receiver.receive(
          qr: qr,
          code: code,
          onConfig: (model) => _incoming = model,
        );
        // Success: onConfig stashed the config. Build the mandatory preview.
        if (_disposed) return;
        await _enterPreview();
        return;
      } on PairingReceiverError catch (e) {
        if (_disposed) return;
        if (e.kind == PairingFailureKind.notReady) {
          if (DateTime.now().isAfter(deadline)) {
            _toError(
              'The computer never picked up. Type the code before it times out, '
              'and check both devices are on the same Wi-Fi.',
            );
            return;
          }
          setState(() => _status = 'Waiting for you to type the code…');
          // A plain delay; the loop re-checks `_disposed`/`_step` after it fires,
          // so leaving the screen mid-wait just ends the poll cleanly.
          await Future<void>.delayed(const Duration(milliseconds: 1200));
          continue; // fresh connection + challenge
        }
        _toError(e.message);
        return;
      } catch (_) {
        if (_disposed) return;
        _toError('Something went wrong during the transfer.');
        return;
      }
    }
  }

  // --- Preview / merge (MANDATORY review; reuses the transfer controller) ----

  /// Reads the live config, plans the merge, seeds collision-rename fields, and
  /// shows the review. Nothing is written until the user confirms the merge.
  Future<void> _enterPreview() async {
    try {
      final existing = await _ctrl.activeConfigModel();
      if (_disposed) return;
      final plan = planImport(existing, _incoming!);
      _disposeRenames();
      for (final d in plan) {
        if (d.collision) {
          _renames[d.name] = TextEditingController(
            text: d.renamedTo ?? '${d.name}-imported',
          );
        }
      }
      setState(() {
        _existing = existing;
        _plan = plan;
        _step = _Step.preview;
      });
    } catch (_) {
      _toError(
        "Received the config, but couldn't read your current remotes to "
        'preview the merge. Is the engine running?',
      );
    }
  }

  /// Builds and validates the final decision list from the rename fields — the
  /// same rules as the file-import wizard (non-empty, valid charset, no two
  /// remotes on one name, no silent overwrite of an existing remote).
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
      _step = _Step.applying;
    });
    try {
      // applyMerge backs up, config/creates each remote through the RC seam, and
      // invalidates remotesProvider itself — so the list refreshes without us
      // touching ref after the await.
      final report = await _ctrl.applyMerge(_incoming!, edited);
      if (_disposed) return;
      setState(() {
        _report = report;
        _step = _Step.report;
      });
    } catch (e) {
      if (_disposed) return;
      _toError(e is ConfigTransferError ? e.message : 'Import failed.');
    }
  }

  void _toError(String message) {
    if (_disposed) return;
    setState(() {
      _errorMessage = message;
      _step = _Step.error;
    });
  }

  /// Rewind to a fresh scan (re-arm the guard, restart the camera, drop session
  /// material). Used by the error step's "Scan again".
  void _restartScan() {
    _disposeRenames();
    _offlineCode.clear();
    setState(() {
      _handledScan = false;
      _qr = null;
      _code = null;
      _offlinePayload = null;
      _offlineError = null;
      _offlineBusy = false;
      _incoming = null;
      _existing = null;
      _plan = null;
      _report = null;
      _errorMessage = null;
      _previewError = null;
      _status = '';
      _step = _Step.scanning;
    });
    unawaited(_scanner.start());
  }

  // --- Views ----------------------------------------------------------------

  Widget _offlineCodeView(AircloneColors c) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: Space.x6),
      Icon(Icons.lock_outline, size: 40, color: c.primary),
      const SizedBox(height: Space.x3),
      Text(
        'Enter the code',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: c.text,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: Space.x2),
      Text(
        'Type the code you set on the computer to unlock this transfer. It is '
        "not in the QR — that's what keeps it safe.",
        textAlign: TextAlign.center,
        style: TextStyle(color: c.textMuted, fontSize: 13),
      ),
      const SizedBox(height: Space.x5),
      TextField(
        controller: _offlineCode,
        autofocus: true,
        obscureText: true,
        enabled: !_offlineBusy,
        onSubmitted: (_) => _offlineBusy ? null : _openOffline(),
        style: TextStyle(color: c.text, fontSize: 16, letterSpacing: 1.5),
        decoration: InputDecoration(
          hintText: 'Unlock code',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Radii.md),
          ),
        ),
      ),
      if (_offlineError != null) ...[
        const SizedBox(height: Space.x2),
        Text(_offlineError!, style: TextStyle(color: c.error, fontSize: 12)),
      ],
      const SizedBox(height: Space.x4),
      FilledButton.icon(
        onPressed: _offlineBusy ? null : _openOffline,
        icon: _offlineBusy
            ? const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.lock_open, size: 18),
        label: Text(_offlineBusy ? 'Unlocking…' : 'Unlock'),
      ),
      const SizedBox(height: Space.x2),
      TextButton(
        onPressed: _offlineBusy ? null : _restartScan,
        child: Text(
          'Scan a different QR',
          style: TextStyle(color: c.textMuted),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return Scaffold(
      backgroundColor: c.surface,
      appBar: AppBar(
        backgroundColor: c.surface,
        title: const Text('Import from a computer'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: switch (_step) {
          _Step.scanning => _scanView(c),
          _Step.pairing => _pairingView(c),
          _Step.offlineCode => _offlineCodeView(c),
          _Step.preview => _previewView(c),
          _Step.applying => _busyView(c, 'Importing…'),
          _Step.report => _reportView(c),
          _Step.error => _errorView(c),
        },
      ),
    );
  }

  Widget _scanView(AircloneColors c) => Column(
    children: [
      Expanded(
        child: MobileScanner(
          controller: _scanner,
          onDetect: _onDetect,
          // Camera unavailable / permission denied: a clear message, never a
          // crash. The permission is requested in-flow by mobile_scanner the
          // first time the camera starts (never at launch).
          // NOTE: this is the mobile_scanner 7.x errorBuilder arity
          // `(context, error)`. If pub resolves a build whose signature still
          // carries the trailing `Widget? child`, add it here — the body ignores
          // it either way.
          errorBuilder: (context, error) => _cameraError(c, error),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(Space.x4),
        child: Column(
          children: [
            Icon(Icons.qr_code_scanner, size: 24, color: c.primary),
            const SizedBox(height: Space.x2),
            Text(
              'On your computer, open Airclone → Settings → "Send to phone", '
              'then point this camera at the QR code it shows.',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textMuted, fontSize: 13),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _cameraError(AircloneColors c, MobileScannerException error) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.x5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.no_photography_outlined, size: 40, color: c.error),
            const SizedBox(height: Space.x3),
            Text(
              denied ? 'Camera access is off' : "Couldn't start the camera",
              style: TextStyle(
                color: c.text,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: Space.x2),
            Text(
              denied
                  ? 'Airclone needs the camera to scan the QR code. Turn it on '
                        'in your phone Settings → Apps → Airclone → Permissions, '
                        'then come back.'
                  : 'Close other apps using the camera and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textMuted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pairingView(AircloneColors c) {
    final code = _code ?? '';
    return Padding(
      padding: const EdgeInsets.all(Space.x5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.laptop_mac, size: 32, color: c.primary),
          const SizedBox(height: Space.x4),
          Text(
            'Type this code on your computer',
            style: TextStyle(
              color: c.text,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: Space.x4),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.x5,
              vertical: Space.x4,
            ),
            decoration: BoxDecoration(
              color: c.surfaceRaised,
              borderRadius: BorderRadius.circular(Radii.lg),
              border: Border.all(color: c.border),
            ),
            child: Text(
              code,
              style: TextStyle(
                color: c.text,
                fontSize: 34,
                fontWeight: FontWeight.w700,
                letterSpacing: 4,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: Space.x5),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 14,
                width: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: c.textMuted,
                ),
              ),
              const SizedBox(width: Space.x2),
              Flexible(
                child: Text(
                  _status,
                  style: TextStyle(color: c.textMuted, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.x3),
          Text(
            'Keep both devices on the same Wi-Fi. The code never leaves this '
            'screen — nobody else can see it.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.textFaint, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _previewView(AircloneColors c) {
    final plan = _plan ?? const [];
    final collisions = plan.where((d) => d.collision).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x4, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.fact_check_outlined, size: 20, color: c.primary),
                  const SizedBox(width: Space.x2),
                  Text(
                    'Review before importing',
                    style: TextStyle(
                      color: c.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.x2),
              Text(
                plan.isEmpty
                    ? 'The computer sent no remotes to import.'
                    : '${plan.length} remote${plan.length == 1 ? '' : 's'} from '
                          'your computer'
                          '${collisions > 0 ? '  ·  $collisions name${collisions == 1 ? '' : 's'} already in use' : ''}. '
                          'Check each one below before merging.',
                style: TextStyle(color: c.textFaint, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.x3),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: Space.x4),
            children: [for (final d in plan) _decisionRow(c, d)],
          ),
        ),
        if (_previewError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x4),
            child: Text(
              _previewError!,
              style: TextStyle(color: c.error, fontSize: 12),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(Space.x4),
          child: Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: Text('Cancel', style: TextStyle(color: c.textMuted)),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: plan.isEmpty ? null : _applyMerge,
                icon: const Icon(Icons.merge_type, size: 16),
                label: const Text('Merge'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// One incoming remote: name, TYPE, and its ENDPOINT (host/url/base) — showing
  /// the endpoint is a plan §5 requirement so a swapped/overlay QR can't silently
  /// re-point a remote at an attacker's target without the user seeing it.
  Widget _decisionRow(AircloneColors c, ImportDecision d) {
    final section = _incoming?[d.name] ?? const <String, String>{};
    final endpoint = _endpointOf(section);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.x3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            d.collision ? Icons.sync_problem_outlined : Icons.cloud_outlined,
            size: 18,
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
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: Space.x2),
                    Text(
                      d.type.isEmpty ? 'unknown type' : d.type,
                      style: TextStyle(color: c.textFaint, fontSize: 11),
                    ),
                  ],
                ),
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
                  const SizedBox(height: Space.x2),
                  Row(
                    children: [
                      Text(
                        'Import as',
                        style: TextStyle(color: c.textFaint, fontSize: 11),
                      ),
                      const SizedBox(width: Space.x2),
                      Expanded(
                        child: SizedBox(
                          height: 34,
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

  /// A best-effort human "endpoint" for the review: the first meaningful
  /// location-ish key present. Never shows secrets (tokens/passwords/keys).
  String _endpointOf(Map<String, String> section) {
    for (final k in const [
      'host',
      'url',
      'endpoint',
      'remote',
      'account',
      'region',
      'provider',
    ]) {
      final v = section[k];
      if (v != null && v.isNotEmpty) return '$k: $v';
    }
    return '';
  }

  Widget _busyView(AircloneColors c, String label) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(strokeWidth: 2),
        const SizedBox(height: Space.x3),
        Text(label, style: TextStyle(color: c.textMuted, fontSize: 13)),
      ],
    ),
  );

  Widget _reportView(AircloneColors c) {
    final report = _report;
    final ok = report?.allOk ?? true;
    return Padding(
      padding: const EdgeInsets.all(Space.x5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ok ? Icons.check_circle_outline : Icons.report_problem_outlined,
                size: 22,
                color: ok ? c.success : c.warning,
              ),
              const SizedBox(width: Space.x2),
              Expanded(
                child: Text(
                  ok
                      ? 'Imported ${report?.created.length ?? 0} remote(s)'
                      : 'Imported with problems',
                  style: TextStyle(
                    color: c.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.x3),
          if ((report?.created ?? const []).isNotEmpty) ...[
            Text(
              'Merged',
              style: TextStyle(
                color: c.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: Space.x1),
            for (final name in report!.created)
              _outcomeRow(c, Icons.check, c.success, name, null),
          ],
          if ((report?.failed ?? const []).isNotEmpty) ...[
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
            for (final f in report!.failed)
              _outcomeRow(c, Icons.close, c.error, f.name, f.error),
          ],
          const SizedBox(height: Space.x5),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Done'),
            ),
          ),
        ],
      ),
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

  Widget _errorView(AircloneColors c) => Padding(
    padding: const EdgeInsets.all(Space.x5),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.error_outline, size: 40, color: c.error),
        const SizedBox(height: Space.x3),
        Text(
          "Couldn't import",
          style: TextStyle(
            color: c.text,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: Space.x2),
        Text(
          _errorMessage ?? 'Unknown error',
          textAlign: TextAlign.center,
          style: TextStyle(color: c.textMuted, fontSize: 13),
        ),
        const SizedBox(height: Space.x4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: Text('Close', style: TextStyle(color: c.textMuted)),
            ),
            const SizedBox(width: Space.x2),
            FilledButton(
              onPressed: _restartScan,
              child: const Text('Scan again'),
            ),
          ],
        ),
      ],
    ),
  );
}
