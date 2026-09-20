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
    test(
      'an empty listing and an unreadable one are different answers',
      () async {
        // Both come back from the same method string; only the answer differs.
        client.answer = {'list': []};
        expect(await api.operations.listOrNull('a:', ''), isEmpty);
        expectCall('operations/list', {'fs': 'a:', 'remote': ''});

        // No `list` key at all: the engine did not answer with a listing.
        client.answer = const {};
        expect(await api.operations.listOrNull('a:', ''), isNull);
        // `list` flattens that to empty, which is why the choice has to be the
        // caller's - a crypt remote with the wrong password2 lists as empty.
        expect(await api.operations.list('a:', ''), isEmpty);
      },
    );

    test('mount', () async {
      await api.mount.mount(
        fs: 'gdrive:',
        mountPoint: 'X:',
        vfsOpt: const {'CacheMode': 2, 'DirCacheTime': '24h'},
        mountOpt: const {'NetworkMode': true},
      );
      expectCall('mount/mount', {
        'fs': 'gdrive:',
        'mountPoint': 'X:',
        'vfsOpt': const {'CacheMode': 2, 'DirCacheTime': '24h'},
        'mountOpt': const {'NetworkMode': true},
      });

      // No options at all is not the same as empty ones: rclone treats an
      // empty vfsOpt as "reset every field to its zero value".
      await api.mount.mount(fs: 'a:', mountPoint: '/mnt/a');
      expectCall('mount/mount', {'fs': 'a:', 'mountPoint': '/mnt/a'});

      await api.mount.unmount('X:');
      expectCall('mount/unmount', {'mountPoint': 'X:'});

      await api.mount.unmountAll();
      expectCall('mount/unmountall', <String, dynamic>{});

      client.answer = {
        'mountPoints': [
          {'MountPoint': 'X:', 'Fs': 'gdrive:'},
          'Y:', // rclone has answered with bare strings; both parse.
        ],
      };
      final mounts = await api.mount.listMounts();
      expectCall('mount/listmounts', <String, dynamic>{});
      expect(mounts.map((m) => m.mountPoint), ['X:', 'Y:']);
      expect(mounts.first.fs, 'gdrive:');

      client.answer = {
        'mountTypes': ['mount', 'cmount'],
      };
      expect(await api.mount.types(), ['mount', 'cmount']);
      expectCall('mount/types', <String, dynamic>{});

      // A build with no mount support answers without the key at all.
      client.answer = const {};
      expect(await api.mount.types(), isEmpty);
    });

    test('serve', () async {
      client.answer = {'id': 'srv-1', 'addr': '127.0.0.1:8080'};
      await api.serve.start(
        type: 'webdav',
        fs: 'gdrive:',
        addr: '127.0.0.1:0',
        user: 'u',
        pass: 'p',
        readOnly: true,
        vfsCacheMode: 'writes',
      );
      // snake_case, because these are rclone's wire names and not Dart's.
      expectCall('serve/start', {
        'type': 'webdav',
        'fs': 'gdrive:',
        'addr': '127.0.0.1:0',
        'user': 'u',
        'pass': 'p',
        'read_only': true,
        'vfs_cache_mode': 'writes',
      });

      // Read-only off sends nothing, rather than `false`: a server started
      // writable is rclone's default, and this keeps the two forms identical.
      await api.serve.start(type: 'dlna', fs: 'a:', addr: ':0');
      expectCall('serve/start', {'type': 'dlna', 'fs': 'a:', 'addr': ':0'});

      await api.serve.stop('srv-1');
      expectCall('serve/stop', {'id': 'srv-1'});

      await api.serve.stopAll();
      expectCall('serve/stopall', <String, dynamic>{});

      client.answer = {
        'list': [
          {
            'id': 'srv-1',
            'addr': '127.0.0.1:8080',
            'params': {
              'type': 'webdav',
              'fs': 'gdrive:',
              'opt': {'ListenAddr': '127.0.0.1:0'},
            },
          },
        ],
      };
      final servers = await api.serve.list();
      expectCall('serve/list', <String, dynamic>{});
      expect(servers.single.id, 'srv-1');
      // The bound address wins over the requested one - port 0 became 8080.
      expect(servers.single.addr, '127.0.0.1:8080');
      expect(servers.single.type, 'webdav');

      client.answer = {
        'types': ['http', 'webdav'],
      };
      expect(await api.serve.types(), ['http', 'webdav']);
      expectCall('serve/types', <String, dynamic>{});
    });

    test('vfs', () async {
      await api.vfs.refresh(
        fs: 'gdrive:',
        recursive: true,
        options: const RcOptions(async: true),
      );
      // 'true' the string, not true the bool: this is the form that has
      // shipped, and vfs/refresh's parameters are flags.
      expectCall('vfs/refresh', {
        'fs': 'gdrive:',
        'recursive': 'true',
        '_async': true,
      });

      await api.vfs.refresh();
      expectCall('vfs/refresh', <String, dynamic>{});

      await api.vfs.forget(fs: 'gdrive:', dir: 'papers');
      expectCall('vfs/forget', {'fs': 'gdrive:', 'dir': 'papers'});

      client.answer = {
        'vfses': ['gdrive:', 'dropbox:'],
      };
      expect(await api.vfs.list(), ['gdrive:', 'dropbox:']);
      expectCall('vfs/list', <String, dynamic>{});

      await api.vfs.stats(fs: 'gdrive:');
      expectCall('vfs/stats', {'fs': 'gdrive:'});
    });

    test('the destructive and comparing operations', () async {
      await api.operations.check(
        srcFs: 'a:',
        dstFs: 'b:',
        options: const RcOptions(
          async: true,
          filter: {
            'IncludeRule': ['*.pdf'],
          },
        ),
      );
      // All five buckets on: a caller that only wanted counts would be
      // reading core/stats instead.
      expectCall('operations/check', {
        'srcFs': 'a:',
        'dstFs': 'b:',
        'download': false,
        'match': true,
        'missingOnSrc': true,
        'missingOnDst': true,
        'differ': true,
        'error': true,
        '_async': true,
        '_filter': const {
          'IncludeRule': ['*.pdf'],
        },
      });

      await api.operations.copyUrl(
        fs: 'gdrive:',
        remote: 'inbox',
        url: 'https://example.com/a.pdf',
        autoFilename: true,
      );
      expectCall('operations/copyurl', {
        'fs': 'gdrive:',
        'remote': 'inbox',
        'url': 'https://example.com/a.pdf',
        'autoFilename': true,
      });

      // Without autoFilename the flag is absent, not false, and `remote` is
      // the full destination path.
      await api.operations.copyUrl(
        fs: 'gdrive:',
        remote: 'inbox/a.pdf',
        url: 'https://example.com/a.pdf',
      );
      expectCall('operations/copyurl', {
        'fs': 'gdrive:',
        'remote': 'inbox/a.pdf',
        'url': 'https://example.com/a.pdf',
      });

      await api.operations.cleanup('gdrive:');
      expectCall('operations/cleanup', {'fs': 'gdrive:'});

      await api.operations.delete('gdrive:junk');
      expectCall('operations/delete', {'fs': 'gdrive:junk'});
    });

    test('sync/bisync names its sides path1 and path2', () async {
      client.answer = {'jobid': 12};
      final job = await api.sync.bisync(path1: 'a:', path2: 'b:');
      expect(job.id, 12);
      expectCall('sync/bisync', {'path1': 'a:', 'path2': 'b:', '_async': true});
    });

    test('job/stopgroup stops by group, not by id', () async {
      await api.job.stopGroup('airclone/copy');
      expectCall('job/stopgroup', {'group': 'airclone/copy'});
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
