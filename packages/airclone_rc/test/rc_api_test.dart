import 'package:airclone_rc/airclone_rc.dart';
import 'package:test/test.dart';

/// What [RcApi] puts ON THE WIRE, method string and parameter map, exactly.
///
/// These are golden tests on purpose. The typed API exists so call sites can
/// move off hand-written method names, and that move is only safe if the
/// resulting call is byte-identical to the one it replaced. A convenience
/// wrapper that quietly renames a parameter, drops an option or flips `_async`
/// would pass any test that only checked the return value.
void main() {
  late _Recorder client;
  late RcApi api;

  setUp(() {
    client = _Recorder();
    api = RcApi(client);
  });

  /// Records compare maps by identity, so the call is checked part by part.
  void expectCall(String method, Map<String, dynamic> params) {
    expect(client.last.$1, method);
    expect(client.last.$2, equals(params));
  }

  group('the wire', () {
    test('core', () async {
      client.answer = {'version': 'v1.74.4'};
      expect(await api.core.version(), 'v1.74.4');
      expectCall('core/version', <String, dynamic>{});

      await api.core.stats(group: 'job/7');
      expectCall('core/stats', {'group': 'job/7'});

      // Absent, not null: rclone reads a null group as "the group named null".
      await api.core.stats();
      expectCall('core/stats', <String, dynamic>{});

      await api.core.bwlimit(rate: '10M');
      expectCall('core/bwlimit', {'rate': '10M'});
    });

    test('operations', () async {
      client.answer = {
        'list': [
          {'Name': 'a.pdf', 'Path': 'papers/a.pdf', 'IsDir': false, 'Size': 12},
        ],
      };
      final files = await api.operations.list('gdrive:', 'papers');
      expectCall('operations/list', {'fs': 'gdrive:', 'remote': 'papers'});
      expect(files.single.name, 'a.pdf');
      expect(files.single.size, 12);

      await api.operations.copyFile(
        srcFs: 'gdrive:',
        srcRemote: 'a.pdf',
        dstFs: '/tmp',
        dstRemote: 'a.pdf',
      );
      expectCall('operations/copyfile', {
        'srcFs': 'gdrive:',
        'srcRemote': 'a.pdf',
        'dstFs': '/tmp',
        'dstRemote': 'a.pdf',
      });

      client.answer = {'item': null};
      expect(await api.operations.stat('gdrive:', 'gone.pdf'), isNull);
    });

    test('config, including the parameters rule', () async {
      client.answer = {
        'remotes': ['work', 'photos'],
      };
      expect(await api.config.listRemotes(), ['work', 'photos']);

      // `parameters` goes on EVERY call, including continue steps: rclone 400s
      // on a provider question without it (the v0.5.6 store failure).
      client.answer = {};
      await api.config.create(
        name: 'work',
        type: 's3',
        parameters: {'provider': 'AWS'},
      );
      expectCall('config/create', {
        'name': 'work',
        'type': 's3',
        'parameters': {'provider': 'AWS'},
      });

      await api.config.update(name: 'work', parameters: const {});
      expectCall('config/update', {
        'name': 'work',
        'parameters': <String, Object?>{},
      });
    });

    test('sync is asynchronous unless told otherwise', () async {
      client.answer = {'jobid': 42};
      final job = await api.sync.copy(srcFs: 'a:', dstFs: 'b:');
      expect(job, const AsyncJob(42));
      expectCall('sync/copy', {'srcFs': 'a:', 'dstFs': 'b:', '_async': true});

      // A caller that wants to wait says so, and then there is no _async.
      client.answer = {'jobid': 43};
      await api.sync.sync(
        srcFs: 'a:',
        dstFs: 'b:',
        options: const RcOptions(group: 'nightly'),
      );
      expectCall('sync/sync', {
        'srcFs': 'a:',
        'dstFs': 'b:',
        '_group': 'nightly',
      });
    });

    test('a jobless async answer is an error, not a silent zero', () async {
      client.answer = {};
      expect(
        () => api.sync.move(srcFs: 'a:', dstFs: 'b:'),
        throwsA(isA<RcloneException>()),
      );
    });
  });

  group('extra and options', () {
    test('extra reaches the wire, so no call site loses a knob', () async {
      client.answer = {'list': []};
      // The real case this exists for: the v0.13.2 reparse-point fix passes
      // copy_links on the LISTING call only. If `extra` did not exist, moving
      // that call site to the typed API would have deleted the fix.
      await api.operations.list(
        'C:/',
        '',
        opt: {'recurse': false},
        extra: {
          '_config': {'Links': true},
        },
      );
      expectCall('operations/list', {
        'fs': 'C:/',
        'remote': '',
        'opt': {'recurse': false},
        '_config': {'Links': true},
      });
    });

    test('options are applied last, over extra', () async {
      client.answer = {'list': []};
      await api.operations.list(
        'a:',
        '',
        extra: {'_async': false},
        options: const RcOptions(async: true),
      );
      // _async decides whether the caller gets a result or a job id, so a
      // method's own parameters must not be able to flip it.
      expect(client.last.$2['_async'], isTrue);
    });

    test('an empty RcOptions adds nothing at all', () {
      expect(RcOptions.none.isEmpty, isTrue);
      expect(RcOptions.none.apply({'fs': 'a:'}), {'fs': 'a:'});
      expect(const RcOptions(async: true, group: 'g').apply(const {}), {
        '_async': true,
        '_group': 'g',
      });
    });
  });

  test('the raw client is still right there', () async {
    client.answer = {'ok': true};
    await api.client.rpc('backend/command', {'command': 'noop'});
    expectCall('backend/command', {'command': 'noop'});
  });
}

/// A fake at the `rpc` seam — which is the point: every existing fake in
/// Airclone already looks like this, and each one answers the typed API for
/// free.
class _Recorder implements RcloneClient {
  Map<String, dynamic> answer = const {};
  (String, Map<String, dynamic>) last = ('', const {});

  @override
  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic> params = const {},
  ]) async {
    last = (method, params);
    return answer;
  }

  @override
  Future<void> start() async {}

  @override
  Future<void> quit() async {}

  @override
  Future<void> restart() async {}

  @override
  Future<EngineStatus> status() async => EngineStatus.stopped;

  @override
  ObjectRef objectRef(String fs, String remote) => const ObjectRef('', {});
}
