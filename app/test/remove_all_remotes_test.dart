import 'package:airclone/src/rclone/rclone_client.dart';
import 'package:airclone/src/state/config_transfer_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Starting over used to mean confirming a delete once per remote, in a sidebar
/// where several names differ only in their last two characters. This is the
/// bulk form, and it is the most destructive thing the app can do to a config —
/// so the backup is not a nicety, it is the precondition that makes offering it
/// defensible at all.
class _Client implements RcloneClient {
  _Client({this.failOn = const {}});

  /// Names whose `config/delete` should throw, to prove one failure does not
  /// abort the rest.
  final Set<String> failOn;
  final calls = <String>[];

  @override
  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    final name = (params?['name'] ?? '').toString();
    calls.add('$method:$name');
    if (method == 'config/delete' && failOn.contains(name)) {
      throw RcloneException(method, 'in use');
    }
    return <String, dynamic>{};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('deletes every named remote and reports them', () async {
    final client = _Client();
    final result = await deleteAllRemotes(
      client: client,
      names: const ['gdrive', 'vault', 's3'],
      backup: () async {},
    );
    expect(client.calls, [
      'config/delete:gdrive',
      'config/delete:vault',
      'config/delete:s3',
    ]);
    expect(result.deleted, ['gdrive', 'vault', 's3']);
    expect(result.failed, isEmpty);
  });

  test('backs up BEFORE the first delete', () async {
    final client = _Client();
    var backedUp = false;
    await deleteAllRemotes(
      client: client,
      names: const ['gdrive'],
      backup: () async {
        expect(client.calls, isEmpty);
        backedUp = true;
      },
    );
    expect(backedUp, isTrue);
  });

  test('one failure does not abort the rest, and is reported', () async {
    // Half-deleted with no report is the outcome to avoid: the user cannot see
    // what survived, and the sidebar would look arbitrary.
    final client = _Client(failOn: {'vault'});
    final result = await deleteAllRemotes(
      client: client,
      names: const ['gdrive', 'vault', 's3'],
      backup: () async {},
    );
    expect(result.deleted, ['gdrive', 's3']);
    expect(result.failed.single.name, 'vault');
    expect(result.failed.single.error, contains('in use'));
  });

  test('an empty config is a no-op, not an error', () async {
    final client = _Client();
    final result = await deleteAllRemotes(
      client: client,
      names: const [],
      backup: () async {},
    );
    expect(client.calls, isEmpty);
    expect(result.deleted, isEmpty);
    expect(result.failed, isEmpty);
  });
}
