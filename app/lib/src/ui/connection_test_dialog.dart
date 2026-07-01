import 'package:flutter/material.dart';

import '../rclone/models/remote.dart';
import '../rclone/rclone_client.dart';
import 'format.dart';
import 'theme/tokens.dart';

/// Outcome of a reachability check: [ok] plus a human message.
class ConnectionResult {
  const ConnectionResult(this.ok, this.message);
  final bool ok;
  final String message;
}

/// Actively verifies [r] is reachable: tries `operations/about` (reporting free/
/// total when the backend supplies them), falling back to a root `operations/
/// list` for backends without About. Read-only; surfaces the real error string
/// on failure instead of silently succeeding.
Future<ConnectionResult> testRemoteConnection(
  RcloneClient client,
  Remote r,
) async {
  try {
    final res = await client.rpc('operations/about', {'fs': r.fs});
    final free = res['free'];
    final total = res['total'];
    if (free is num && total is num) {
      return ConnectionResult(
        true,
        'Reachable — ${humanSize(free.toInt())} free of '
        '${humanSize(total.toInt())}.',
      );
    }
    return const ConnectionResult(true, 'Reachable.');
  } on RcloneException {
    // About is unsupported on some backends → prove reachability by listing.
    try {
      await client.rpc('operations/list', r.listParams(''));
      return const ConnectionResult(
        true,
        'Reachable (this backend reports no usage info).',
      );
    } on RcloneException catch (e) {
      return ConnectionResult(false, e.message);
    } catch (e) {
      return ConnectionResult(false, '$e');
    }
  } catch (e) {
    return ConnectionResult(false, '$e');
  }
}

/// Runs [testRemoteConnection] for [remote] in a small dialog: a spinner while
/// it runs, then a success or the error reason.
Future<void> showConnectionTest(
  BuildContext context,
  RcloneClient client,
  Remote remote,
) => showDialog<void>(
  context: context,
  builder: (_) => _ConnectionTestDialog(client: client, remote: remote),
);

class _ConnectionTestDialog extends StatefulWidget {
  const _ConnectionTestDialog({required this.client, required this.remote});
  final RcloneClient client;
  final Remote remote;

  @override
  State<_ConnectionTestDialog> createState() => _ConnectionTestDialogState();
}

class _ConnectionTestDialogState extends State<_ConnectionTestDialog> {
  ConnectionResult? _result;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => _result = null);
    final r = await testRemoteConnection(widget.client, widget.remote);
    if (!mounted) return;
    setState(() => _result = r);
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final result = _result;
    return AlertDialog(
      backgroundColor: c.surfaceRaised,
      title: Text('Test connection · ${widget.remote.name}'),
      content: SizedBox(
        width: 380,
        child: Row(
          children: [
            if (result == null)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                result.ok ? Icons.check_circle : Icons.error_outline,
                color: result.ok ? c.success : c.error,
                size: 22,
              ),
            const SizedBox(width: Space.x3),
            Expanded(
              child: Text(
                result == null ? 'Checking…' : result.message,
                style: TextStyle(
                  color: result != null && !result.ok ? c.error : c.text,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (result != null && !result.ok)
          TextButton(
            onPressed: _run,
            child: Text('Retry', style: TextStyle(color: c.textMuted)),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
