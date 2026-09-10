import 'package:airclone/src/rclone/rclone_client.dart';
import 'package:airclone/src/state/backup_prune.dart';
import 'package:airclone/src/state/engine_controller.dart' as engine;
import 'package:airclone/src/state/engine_controller.dart'
    show engineControllerProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The executor that actually deletes. The decision about WHAT to delete is
/// pure and tested next door; these cover the part that touches a remote.
///
/// Everything here is written from the same premise: this is the most
/// destructive operation in the app, so every uncertainty resolves to "do not
/// delete".
class _FakeClient implements RcloneClient {
  _FakeClient({this.list, this.listThrows = false, this.deleteThrowsAfter});

  final List<Object?>? list;
  final bool listThrows;

  /// Throw on the delete AFTER this many successes, to model a mid-run failure.
  final int? deleteThrowsAfter;

  final deleted = <String>[];

  @override
  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    if (method == 'operations/list') {
      if (listThrows) throw Exception('remote is not answering');
      return {'list': list};
    }
    if (method == 'operations/deletefile') {
      if (deleteThrowsAfter != null && deleted.length >= deleteThrowsAfter!) {
        throw Exception('permission denied');
      }
      deleted.add('${params?['remote']}');
      return {};
    }
    return {};
  }

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeEngine extends engine.EngineController {
  _FakeEngine(this._client);
  final RcloneClient? _client;
  @override
  engine.EngineUi build() =>
      engine.EngineUi(phase: engine.EnginePhase.ready, client: _client);
}

Map<String, dynamic> entry(String path, {String? modTime, int size = 10}) => {
  'Name': path.split('/').last,
  'Path': path,
  'IsDir': false,
  'Size': size,
  'ModTime': ?modTime,
};

void main() {
  final now = DateTime(2026, 9, 9, 12);
  final oldStamp = now.subtract(const Duration(days: 60)).toIso8601String();

  Future<PruneResult> run(
    _FakeClient? client, {
    bool dryRun = true,
    int maxPerPass = kMaxPrunePerPass,
    int retentionDays = 30,
  }) async {
    final c = ProviderContainer(
      overrides: [
        engineControllerProvider.overrideWith(() => _FakeEngine(client)),
      ],
    );
    addTearDown(c.dispose);
    return c
        .read(backupPrunerProvider)
        .prune(
          fs: 'gdrive:Airclone/Backups/laptop/Docs',
          retentionDays: retentionDays,
          dryRun: dryRun,
          maxPerPass: maxPerPass,
          now: now,
        );
  }

  test('DRY RUN IS THE DEFAULT — it reports without deleting', () async {
    // Calls prune() WITHOUT naming dryRun, so the production default is what is
    // under test. An earlier version of this passed `dryRun: true` explicitly
    // and therefore proved nothing: flipping the default to false left it green.
    final client = _FakeClient(
      list: [
        entry('report.pdf'),
        entry('report.replaced.pdf', modTime: oldStamp),
      ],
    );
    final c = ProviderContainer(
      overrides: [
        engineControllerProvider.overrideWith(() => _FakeEngine(client)),
      ],
    );
    addTearDown(c.dispose);
    final r = await c
        .read(backupPrunerProvider)
        .prune(
          fs: 'gdrive:Airclone/Backups/laptop/Docs',
          retentionDays: 30,
          now: now,
        );

    expect(r.candidates.map((e) => e.path), ['report.replaced.pdf']);
    expect(r.deleted, 0);
    expect(
      client.deleted,
      isEmpty,
      reason: 'the most destructive operation in the app must opt IN',
    );
  });

  test('deleting removes exactly the candidates, and reports bytes', () async {
    final client = _FakeClient(
      list: [
        entry('report.pdf'),
        entry('report.replaced.pdf', modTime: oldStamp, size: 400),
      ],
    );
    final r = await run(client, dryRun: false);
    expect(client.deleted, ['report.replaced.pdf']);
    expect(r.deleted, 1);
    expect(r.bytesFreed, 400);
  });

  test('a live file is never deleted, whatever else happens', () async {
    final client = _FakeClient(list: [entry('report.pdf', modTime: oldStamp)]);
    await run(client, dryRun: false, retentionDays: 0);
    expect(client.deleted, isEmpty);
  });

  test('A FAILED LISTING DELETES NOTHING', () async {
    // Not knowing what is there is the one state in which deleting is
    // indefensible.
    final client = _FakeClient(listThrows: true);
    final r = await run(client, dryRun: false);
    expect(client.deleted, isEmpty);
    expect(r.error, isNotNull);
    expect(r.candidates, isEmpty);
  });

  test('no engine deletes nothing', () async {
    final r = await run(null, dryRun: false);
    expect(r.error, contains('engine'));
    expect(r.deleted, 0);
  });

  test('a listing with no list key deletes nothing', () async {
    final client = _FakeClient();
    final r = await run(client, dryRun: false);
    expect(client.deleted, isEmpty);
    expect(r.error, isNotNull);
  });

  test('OVER THE CAP IT REFUSES ENTIRELY, rather than deleting some', () async {
    // A pass this large is more likely a bug than a real backlog. Truncating
    // would destroy data while hiding the reason.
    final client = _FakeClient(
      list: [
        for (var i = 0; i < 12; i++) ...[
          entry('f$i.txt'),
          entry('f$i.replaced.txt', modTime: oldStamp),
        ],
      ],
    );
    final r = await run(client, dryRun: false, maxPerPass: 5);
    expect(r.abortedOverCap, isTrue);
    expect(r.deleted, 0);
    expect(client.deleted, isEmpty);
    // The candidates are still reported, so a human can look at them.
    expect(r.candidates.length, 12);
  });

  test('a mid-run failure stops, and reports what it managed', () async {
    final client = _FakeClient(
      list: [
        for (var i = 0; i < 4; i++) ...[
          entry('f$i.txt'),
          entry('f$i.replaced.txt', modTime: oldStamp, size: 100),
        ],
      ],
      deleteThrowsAfter: 2,
    );
    final r = await run(client, dryRun: false);
    expect(r.deleted, 2);
    expect(r.bytesFreed, 200);
    expect(r.error, isNotNull);
    expect(client.deleted.length, 2);
  });

  test('a version in another folder is not pruned by a sibling', () async {
    // The recursive-grouping trap, end to end through the executor.
    final client = _FakeClient(
      list: [
        entry('a/report.pdf'),
        entry('b/report.replaced.pdf', modTime: oldStamp),
      ],
    );
    final r = await run(client, dryRun: false);
    expect(client.deleted, isEmpty);
    expect(r.candidates, isEmpty);
  });
}
