import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../state/config_io.dart';
import '../state/config_transfer_controller.dart';
import '../state/offline_qr.dart';
import '../state/remote_summary.dart';
import 'dialog_body.dart';
import 'theme/tokens.dart';

/// Opens the phone-side "Import QR Config" flow (reworked 2026-07):
///  1. This phone GENERATES a one-time unlock code and shows it.
///  2. You enter that code on the computer's "Export QR Config" screen and make
///     the QR (the code is typed there privately — it never appears on the
///     computer's screen, so a screen-grab of the QR alone can't open it).
///  3. You scan the QR here. Because this phone already knows the code, it
///     decrypts AUTOMATICALLY — no code to retype on the phone.
///
/// The whole config travels inside the QR; there is NO network. The import lands
/// in the MANDATORY preview/merge review before anything is written.
Future<void> showScanFromDesktopSheet(BuildContext context) => Navigator.of(
  context,
).push<void>(MaterialPageRoute(builder: (_) => const _ScanFromDesktopScreen()));

/// A computer can't scan a QR (no camera / no camera plugin on desktop), so its
/// "Import QR Config" explains that and points at the file-based flows instead.
/// QR transfer is phone-camera only, by design.
Future<void> showQrCameraUnavailableDialog(BuildContext context) {
  final c = AircloneTheme.of(context);
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: c.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      title: Row(
        children: [
          Icon(Icons.no_photography_outlined, size: 20, color: c.primary),
          const SizedBox(width: Space.x2),
          Text(
            'QR import needs a camera',
            style: TextStyle(
              color: c.text,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      content: DialogBody(
        width: 420,
        child: Text(
          'Scanning a QR uses a camera, which this computer can\'t do. To move a '
          'config here, use "Import File Config". To send THIS computer\'s config '
          'to a phone, use "Export QR Config" and scan it with the phone\'s '
          'camera (its "Import QR Config").',
          style: TextStyle(color: c.textMuted, fontSize: 13, height: 1.4),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        Space.x4,
        0,
        Space.x4,
        Space.x4,
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}

/// The flow's steps. [showCode] displays this phone's generated unlock code;
/// [scanning] is the live camera; [unlocking] decrypts the scanned QR with that
/// code; [preview] is the MANDATORY review (type + endpoint per remote, collision
/// renames); [applying]/[report] run and summarise the merge; [error] is a
/// terminal dead-end with a retry.
enum _Step { showCode, scanning, unlocking, preview, applying, report, error }

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

  /// Only-scan-QRs, and ignore repeated reads of the same code. autoStart:false —
  /// we drive start()/stop() ourselves so the camera is off on the code screen
  /// and the permission prompt only appears when the user taps "Scan the QR".
  final MobileScannerController _scanner = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
    autoStart: false,
  );

  _Step _step = _Step.showCode;
  bool _handledScan = false; // guard: process the first valid QR exactly once

  /// This phone's one-time unlock code, generated once for the session and shown
  /// on the code screen. The user enters it on the computer's Export QR Config;
  /// we decrypt the scanned QR with it automatically. Lives only here — never in
  /// provider state, never logged, never in the QR.
  final String _code = newPairingCode();
  String?
  _codeError; // "that didn't match" note carried back to the code screen

  // Multi-QR accumulation: a big config split across several chunk-QRs. We keep
  // scanning until all `_chunkTotal` (identified by `_chunkId`) are collected,
  // then reassemble into a single offline payload.
  final Map<int, String> _chunks = {};
  String? _chunkId;
  int _chunkTotal = 0;

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

  /// Arm and open the camera: clear any partial chunk collection, re-arm the
  /// one-shot guard, and start the scanner. The permission prompt (Android
  /// CAMERA / iOS NSCameraUsageDescription) surfaces here, in-flow, not at launch.
  void _beginScan() {
    _handledScan = false;
    setState(() {
      _codeError = null;
      _chunks.clear();
      _chunkId = null;
      _chunkTotal = 0;
      _step = _Step.scanning;
    });
    unawaited(_scanner.start());
  }

  /// Handles a camera detection: take the first non-empty raw QR value and route
  /// it. A self-contained Offline QR decrypts immediately; a multi-QR chunk is
  /// accumulated (camera stays live) until every chunk is in; anything else is a
  /// clear terminal error — NEVER a network fetch.
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
    // A MULTI-QR chunk (a config too big for one QR): accumulate and KEEP the
    // camera running until every chunk is in — only then handle it.
    if (isOfflineQrChunk(raw)) {
      _collectChunk(raw);
      return;
    }
    _handledScan = true;
    unawaited(_scanner.stop());
    // A self-contained OFFLINE QR carries the whole encrypted config — decrypt it
    // with the code this phone generated. Anything else isn't an Airclone config QR.
    if (isOfflineQrPayload(raw)) {
      _decrypt(raw);
      return;
    }
    _toError(
      "That QR isn't an Airclone config QR. On your computer, open Airclone → "
      'Settings → "Export QR Config", enter the code shown on this phone, then '
      'scan the QR it makes.',
    );
  }

  /// Collects one multi-QR chunk. A chunk whose [OfflineQrChunk.id] differs from
  /// the current batch starts a fresh collection (you scanned a different export).
  /// Once every chunk is present, reassemble and decrypt.
  void _collectChunk(String raw) {
    final chunk = parseOfflineQrChunk(raw);
    if (chunk == null) return; // malformed frame — ignore, keep scanning
    setState(() {
      if (_chunkId != chunk.id) {
        _chunkId = chunk.id;
        _chunkTotal = chunk.total;
        _chunks.clear();
      }
      _chunks[chunk.index] = chunk.body;
    });
    if (_chunks.length < _chunkTotal) return;
    _handledScan = true;
    unawaited(_scanner.stop());
    final assembled = assembleOfflineQrPayload(_chunks, _chunkTotal);
    if (assembled == null) {
      _toError('Some codes were missed. Scan again and capture every QR.');
      return;
    }
    _decrypt(assembled);
  }

  // --- Decrypt (with this phone's own code) + preview -----------------------

  /// Decrypts the scanned payload with the code this phone generated, parses the
  /// config, and lands in the MANDATORY preview. A wrong code (the computer typed
  /// it differently) returns to the code screen so the user can re-check + re-make
  /// the QR; a malformed or foreign QR is a terminal error.
  Future<void> _decrypt(String payload) async {
    setState(() => _step = _Step.unlocking);
    try {
      final text = await openOfflineQrPayload(payload, _code);
      if (_disposed) return;
      _incoming = parseIni(text);
      await _enterPreview();
    } on WrongPassphrase {
      if (_disposed) return;
      setState(() {
        _codeError =
            "That QR was made with a different code. On your computer, enter the "
            'code below EXACTLY, make the QR again, then scan it.';
        _step = _Step.showCode;
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
      _toError("Couldn't open that QR. Try again.");
    }
  }

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

  /// Full reset back to the code screen (fresh scan session, same code so the
  /// computer's already-typed code still matches).
  void _restart() {
    _disposeRenames();
    setState(() {
      _handledScan = false;
      _codeError = null;
      _chunks.clear();
      _chunkId = null;
      _chunkTotal = 0;
      _incoming = null;
      _existing = null;
      _plan = null;
      _report = null;
      _errorMessage = null;
      _previewError = null;
      _step = _Step.showCode;
    });
  }

  // --- Views ----------------------------------------------------------------

  Widget _showCodeView(AircloneColors c) => SingleChildScrollView(
    padding: const EdgeInsets.all(Space.x5),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Space.x3),
        Icon(Icons.key_outlined, size: 40, color: c.primary),
        const SizedBox(height: Space.x3),
        Text(
          'Your one-time code',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: c.text,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: Space.x2),
        Text(
          'On your computer, open Airclone → Settings → "Export QR Config", '
          'enter this code, and make the QR. Then scan it below.',
          textAlign: TextAlign.center,
          style: TextStyle(color: c.textMuted, fontSize: 13),
        ),
        const SizedBox(height: Space.x5),
        // The code itself — big, monospaced, with a copy affordance.
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.x4,
            vertical: Space.x4,
          ),
          decoration: BoxDecoration(
            color: c.surfaceSunken,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: c.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  _code,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: Space.x2),
              IconButton(
                tooltip: 'Copy code',
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _code));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Code copied'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                icon: Icon(Icons.copy_outlined, size: 18, color: c.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.x3),
        Text(
          "The code is case-insensitive to type — your computer uppercases it. "
          "It never travels in the QR, so a photo of the QR alone can't open "
          'your remotes.',
          textAlign: TextAlign.center,
          style: TextStyle(color: c.textFaint, fontSize: 11),
        ),
        if (_codeError != null) ...[
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
                    _codeError!,
                    style: TextStyle(color: c.error, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: Space.x5),
        FilledButton.icon(
          onPressed: _beginScan,
          icon: const Icon(Icons.qr_code_scanner, size: 18),
          label: const Text('Scan the QR'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return Scaffold(
      backgroundColor: c.surface,
      appBar: AppBar(
        backgroundColor: c.surface,
        title: const Text('Import QR Config'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: switch (_step) {
          _Step.showCode => _showCodeView(c),
          _Step.scanning => _scanView(c),
          _Step.unlocking => _busyView(c, 'Unlocking…'),
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
          errorBuilder: (context, error) => _cameraError(c, error),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(Space.x4),
        child: _chunkTotal > 0
            // Multi-QR in progress: show how many chunks are still to scan.
            ? Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.sm),
                    child: LinearProgressIndicator(
                      value: _chunks.length / _chunkTotal,
                      minHeight: 4,
                      backgroundColor: c.surfaceSunken,
                    ),
                  ),
                  const SizedBox(height: Space.x2),
                  Text(
                    'Scanned ${_chunks.length} of $_chunkTotal codes — keep '
                    'pointing at the rest (any order).',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.text, fontSize: 13),
                  ),
                ],
              )
            : Column(
                children: [
                  Icon(Icons.qr_code_scanner, size: 24, color: c.primary),
                  const SizedBox(height: Space.x2),
                  Text(
                    'Point the camera at the QR your computer is showing '
                    '(Export QR Config). It opens automatically.',
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
                        'then come back — or use "Import File Config" instead.'
                  : "This device can't scan a QR. Use \"Import File Config\" / "
                        '"Export File Config" to move your config instead.',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textMuted, fontSize: 13),
            ),
          ],
        ),
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
    final endpoint = remoteEndpointSummary(section);
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
            FilledButton(onPressed: _restart, child: const Text('Start over')),
          ],
        ),
      ],
    ),
  );
}
