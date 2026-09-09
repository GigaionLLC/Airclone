import 'package:airclone/src/rclone/rclone_client.dart';
import 'package:airclone/src/state/config_io.dart';
import 'package:airclone/src/state/config_transfer_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Merge's only answer to a name clash was a rename, so re-importing a corrected
/// config left `foo` and `foo-imported` side by side with the app still using the
/// stale `foo`. Replace is the other reasonable intent — and the destructive one,
/// so it is opt-in per import and reported separately afterwards.
class _CapturingClient implements RcloneClient {
  final calls = <({String method, Map<String, dynamic>? params})>[];

  @override
  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    calls.add((method: method, params: params));
    return <String, dynamic>{};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The names `config/create` was actually called with, in order.
List<String> _createdNames(_CapturingClient c) => [
  for (final call in c.calls)
    if (call.method == 'config/create') call.params!['name'] as String,
];

void main() {
  const incoming = <String, Map<String, String>>{
    'gdrive': {'type': 'drive', 'token': 'abc'},
    'vault': {'type': 'crypt', 'remote': 'gdrive:enc'},
    'fresh': {'type': 's3'},
  };

  test('a replace decision writes to the ORIGINAL name', () async {
    final client = _CapturingClient();
    final report = await mergeRemotes(
      client: client,
      incoming: incoming,
      plan: const [
        ImportDecision(
          name: 'gdrive',
          type: 'drive',
          collision: true,
          replaceExisting: true,
        ),
      ],
      backup: () async {},
    );
    expect(_createdNames(client), ['gdrive']);
    expect(report.replaced, ['gdrive']);
    // Not double-counted: an overwrite is not a creation.
    expect(report.created, isEmpty);
    expect(report.allOk, isTrue);
  });

  test('a rename decision still lands beside the existing remote', () async {
    final client = _CapturingClient();
    final report = await mergeRemotes(
      client: client,
      incoming: incoming,
      plan: const [
        ImportDecision(
          name: 'gdrive',
          type: 'drive',
          collision: true,
          renamedTo: 'gdrive-imported',
        ),
      ],
      backup: () async {},
    );
    expect(_createdNames(client), ['gdrive-imported']);
    expect(report.created, ['gdrive-imported']);
    expect(report.replaced, isEmpty);
  });

  test('the two modes coexist in one plan', () async {
    final client = _CapturingClient();
    final report = await mergeRemotes(
      client: client,
      incoming: incoming,
      plan: const [
        ImportDecision(
          name: 'gdrive',
          type: 'drive',
          collision: true,
          replaceExisting: true,
        ),
        ImportDecision(
          name: 'vault',
          type: 'crypt',
          collision: true,
          renamedTo: 'vault-imported',
        ),
        ImportDecision(name: 'fresh', type: 's3', collision: false),
      ],
      backup: () async {},
    );
    expect(_createdNames(client), ['gdrive', 'vault-imported', 'fresh']);
    expect(report.replaced, ['gdrive']);
    expect(report.created, ['vault-imported', 'fresh']);
  });

  test('the backup still runs before anything is written', () async {
    // A replace is exactly when the backup matters most: the remote it lands on
    // may hold the only copy of those settings.
    final client = _CapturingClient();
    var backedUp = false;
    await mergeRemotes(
      client: client,
      incoming: incoming,
      plan: const [
        ImportDecision(
          name: 'gdrive',
          type: 'drive',
          collision: true,
          replaceExisting: true,
        ),
      ],
      backup: () async {
        expect(client.calls, isEmpty, reason: 'backup precedes every write');
        backedUp = true;
      },
    );
    expect(backedUp, isTrue);
  });

  test('a replaced remote carries the incoming settings verbatim', () async {
    // noObscure is load-bearing: imported passwords are already in rclone's
    // obscured storage form, and re-obscuring them would corrupt them.
    final client = _CapturingClient();
    await mergeRemotes(
      client: client,
      incoming: incoming,
      plan: const [
        ImportDecision(
          name: 'gdrive',
          type: 'drive',
          collision: true,
          replaceExisting: true,
        ),
      ],
      backup: () async {},
    );
    final params = client.calls.single.params!;
    expect(params['type'], 'drive');
    expect((params['parameters'] as Map)['token'], 'abc');
    expect((params['opt'] as Map)['noObscure'], true);
  });

  group('ImportDecision', () {
    test('replaceExisting participates in equality', () {
      const rename = ImportDecision(
        name: 'a',
        type: 's3',
        collision: true,
        renamedTo: 'a-imported',
      );
      const replace = ImportDecision(
        name: 'a',
        type: 's3',
        collision: true,
        replaceExisting: true,
      );
      expect(rename == replace, isFalse);
      expect(replace.hashCode == rename.hashCode, isFalse);
    });

    test('defaults to the non-destructive mode', () {
      const d = ImportDecision(name: 'a', type: 's3', collision: true);
      expect(d.replaceExisting, isFalse);
    });
  });

  test('planImport still suggests a rename, never a replace', () {
    // The plan proposes the safe resolution; only the user's checkbox turns a
    // decision into an overwrite.
    final plan = planImport(
      const {
        'gdrive': {'type': 'drive'},
      },
      const {
        'gdrive': {'type': 'drive'},
      },
    );
    expect(plan.single.collision, isTrue);
    expect(plan.single.renamedTo, 'gdrive-imported');
    expect(plan.single.replaceExisting, isFalse);
  });
}
