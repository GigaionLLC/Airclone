import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../rclone/rclone_client.dart';
import 'theme/tokens.dart';

/// Hash types requested for LOCAL files. Cloud backends store hashes as
/// metadata (free to read, and often exotic types like QuickXor that are the
/// only ones they have — so those get no restriction), but the local backend
/// COMPUTES each requested type by reading the whole file; unrestricted it
/// hashes ~13 types and a large file blows the 30s RPC timeout.
const localHashTypes = ['md5', 'sha1', 'sha256'];

/// Fetches the hashes the backend exposes for one file, via
/// `operations/stat {opt:{showHash:true}}` (lsjson item shape → `Hashes` map).
/// [hashTypes] restricts which types are computed (pass [localHashTypes] for
/// local files). Returns null when the file no longer exists (stat's
/// documented not-found response is `item: null`), an empty map when the
/// backend exposes no hashes; rethrows RC errors.
Future<Map<String, String>?> fetchChecksums(
  RcloneClient client, {
  required String fs,
  required String remote,
  List<String>? hashTypes,
}) async {
  final res = await client.rpc('operations/stat', {
    'fs': fs,
    'remote': remote,
    'opt': {'showHash': true, 'hashTypes': ?hashTypes},
  });
  final item = res['item'];
  if (item is! Map) return null; // not found (deleted/renamed since listing)
  final hashes = item['Hashes'];
  if (hashes is! Map) return const {};
  final out = <String, String>{};
  for (final e in hashes.entries) {
    final v = e.value;
    if (v is String && v.isNotEmpty) out['${e.key}'] = v;
  }
  // Stable, alphabetical order (MD5 before SHA-1 …).
  final sorted = out.keys.toList()..sort();
  return {for (final k in sorted) k: out[k]!};
}

/// Shows [name]'s checksums (every hash type the backend reports) with a
/// per-row copy button — for verifying a download against a published hash.
Future<void> showChecksumDialog(
  BuildContext context,
  RcloneClient client, {
  required String fs,
  required String remote,
  required String name,
  List<String>? hashTypes,
}) => showDialog<void>(
  context: context,
  builder: (_) => _ChecksumDialog(
    client: client,
    fs: fs,
    remote: remote,
    name: name,
    hashTypes: hashTypes,
  ),
);

class _ChecksumDialog extends StatefulWidget {
  const _ChecksumDialog({
    required this.client,
    required this.fs,
    required this.remote,
    required this.name,
    this.hashTypes,
  });
  final RcloneClient client;
  final String fs;
  final String remote;
  final String name;
  final List<String>? hashTypes;

  @override
  State<_ChecksumDialog> createState() => _ChecksumDialogState();
}

class _ChecksumDialogState extends State<_ChecksumDialog> {
  Map<String, String>? _hashes;
  bool _notFound = false;
  String? _error;
  String? _copied;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final h = await fetchChecksums(
        widget.client,
        fs: widget.fs,
        remote: widget.remote,
        hashTypes: widget.hashTypes,
      );
      if (!mounted) return;
      setState(() {
        _hashes = h ?? const {};
        _notFound = h == null;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e is RcloneException ? e.message : '$e';
      setState(
        () => _error = msg.contains('TimeoutException')
            // Hashing a local file means reading all of it; huge files exceed
            // the RPC deadline even with the reduced hash set.
            ? 'Hashing timed out — this file is too large to hash quickly.'
            : msg,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return AlertDialog(
      backgroundColor: c.surfaceRaised,
      title: Text('Checksums · ${widget.name}'),
      content: SizedBox(width: 520, child: _body(c)),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _body(AircloneColors c) {
    if (_error != null) {
      return Text(_error!, style: TextStyle(color: c.error, fontSize: 12));
    }
    final hashes = _hashes;
    if (hashes == null) {
      return const SizedBox(
        height: 48,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_notFound) {
      return Text(
        'File not found — it may have been moved or deleted.',
        style: TextStyle(color: c.textMuted, fontSize: 13),
      );
    }
    if (hashes.isEmpty) {
      return Text(
        'This backend reports no hashes for this file.',
        style: TextStyle(color: c.textMuted, fontSize: 13),
      );
    }
    // Height-capped + scrollable: the local backend can report a dozen types.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 360),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final e in hashes.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.x1),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 90,
                      child: Text(
                        e.key,
                        style: TextStyle(
                          color: c.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: SelectableText(
                        e.value,
                        style: TextStyle(
                          color: c.text,
                          fontSize: 12,
                          fontFamily: 'monospace',
                          fontFamilyFallback: const ['Consolas', 'Menlo'],
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: e.value));
                        setState(() => _copied = e.key);
                      },
                      icon: Icon(
                        _copied == e.key ? Icons.check : Icons.copy,
                        size: 15,
                      ),
                      color: _copied == e.key ? c.success : c.textMuted,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
