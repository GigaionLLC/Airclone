import 'package:airclone/src/state/console/console_command.dart';
import 'package:airclone/src/state/console/console_rc_translate.dart';
import 'package:flutter_test/flutter_test.dart';

RcTranslation tr(String line) => translateToRc(ConsoleCommand.parse(line));
RcDispatch dispatch(String line) => tr(line) as RcDispatch;

void main() {
  group('splitFsRemote', () {
    test('remote:path / remote: / connection string / refusals', () {
      expect(splitFsRemote('gdrive:Photos'), ('gdrive:', 'Photos'));
      expect(splitFsRemote('gdrive:'), ('gdrive:', ''));
      expect(
        splitFsRemote(':s3,env_auth=true:bucket/key'),
        (':s3,env_auth=true:', 'bucket/key'),
      );
      expect(splitFsRemote('C:/Users/x'), isNull, reason: 'windows path');
      expect(splitFsRemote(r'C:\Users\x'), isNull);
      expect(splitFsRemote('noremote'), isNull);
      // A single-letter remote with a real path segment is still a remote.
      expect(splitFsRemote('x:dir'), ('x:', 'dir'));
    });
  });

  group('verb → method + params', () {
    test('copy / move / sync map to sync/* over whole fs', () {
      expect(dispatch('copy gdrive:a s3:b').method, 'sync/copy');
      expect(dispatch('copy gdrive:a s3:b').params, {
        'srcFs': 'gdrive:a',
        'dstFs': 's3:b',
      });
      expect(dispatch('move a: b:').method, 'sync/move');
      expect(dispatch('sync a: b:').method, 'sync/sync');
      expect(dispatch('copy a: b:').kind, RcKind.asyncJob);
    });

    test('list verbs split fs+remote; lsd sets dirsOnly', () {
      final ls = dispatch('lsjson gdrive:Photos');
      expect(ls.method, 'operations/list');
      expect(ls.params['fs'], 'gdrive:');
      expect(ls.params['remote'], 'Photos');
      expect(ls.kind, RcKind.instant);
      expect((dispatch('lsd gdrive:').params['opt'] as Map)['dirsOnly'], true);
    });

    test('mkdir/rmdir/deletefile/touch split the target', () {
      expect(dispatch('mkdir gdrive:New').method, 'operations/mkdir');
      expect(dispatch('mkdir gdrive:New').params, {'fs': 'gdrive:', 'remote': 'New'});
      expect(dispatch('rmdir s3:b/old').method, 'operations/rmdir');
      expect(dispatch('deletefile a:f.txt').method, 'operations/deletefile');
    });

    test('about/size/hashsum shapes; heavy reads are async', () {
      expect(dispatch('about gdrive:').method, 'operations/about');
      expect(dispatch('about gdrive:').kind, RcKind.instant);
      final size = dispatch('size s3:b');
      expect(size.method, 'operations/size');
      expect(size.kind, RcKind.asyncJob);
      expect(size.asyncResult, isTrue);
      expect(dispatch('md5sum s3:b').params, {'fs': 's3:b', 'hashType': 'MD5'});
      expect(dispatch('sha1sum s3:b').params['hashType'], 'SHA-1');
      expect(dispatch('hashsum SHA-256 s3:b').params, {
        'hashType': 'SHA-256',
        'fs': 's3:b',
      });
    });

    test('copyto/moveto carry a source-probe + file/whole params', () {
      final c = dispatch('copyto a:f b:g');
      expect(c.needsSourceProbe, isTrue);
      expect(c.method, 'operations/copyfile');
      expect(c.params['srcRemote'], 'f');
      expect(c.params['_srcFsWhole'], 'a:f');
      expect(dispatch('moveto a:f b:g').method, 'operations/movefile');
    });

    test('delete/purge/cleanup/rmdirs/check', () {
      expect(dispatch('delete s3:b').method, 'operations/delete');
      expect(dispatch('purge s3:b/junk').method, 'operations/purge');
      expect(dispatch('purge s3:b/junk').params, {'fs': 's3:', 'remote': 'b/junk'});
      expect(dispatch('cleanup s3:b').method, 'operations/cleanup');
      expect((dispatch('rmdirs s3:b').params)['leaveRoot'], false);
      expect(dispatch('check a: b:').method, 'operations/check');
    });

    test('version / listremotes take no positional', () {
      expect(dispatch('version').method, 'core/version');
      expect(dispatch('listremotes').method, 'config/listremotes');
    });
  });

  group('flag mapping (the curated table)', () {
    test('--dry-run/-n → _config.DryRun', () {
      expect(
        (dispatch('sync a: b: --dry-run').params['_config'] as Map)['DryRun'],
        true,
      );
      expect((dispatch('sync a: b: -n').params['_config'] as Map)['DryRun'], true);
    });

    test('int flags parse; = and space forms; clusters', () {
      expect(
        (dispatch('copy a: b: --transfers 8').params['_config'] as Map)['Transfers'],
        8,
      );
      expect(
        (dispatch('copy a: b: --transfers=8').params['_config'] as Map)['Transfers'],
        8,
      );
      final cfg = dispatch('copy a: b: -cP').params['_config'] as Map;
      expect(cfg['Checksum'], true);
      // -P is progress (a note), not a config key.
      expect(cfg.containsKey('Progress'), isFalse);
    });

    test('--include/--exclude accumulate into _filter lists', () {
      final f =
          dispatch('copy a: b: --include *.jpg --exclude *.tmp').params['_filter']
              as Map;
      expect(f['IncludeRule'], ['*.jpg']);
      expect(f['ExcludeRule'], ['*.tmp']);
    });

    test('list flags land in opt and flip a recursive list to async', () {
      final r = dispatch('lsjson gdrive: --recursive');
      expect(r.kind, RcKind.asyncJob);
      expect((r.params['opt'] as Map)['recurse'], true);
      expect((dispatch('ls a: --dirs-only').params['opt'] as Map)['dirsOnly'], true);
    });

    test('--progress/--stats are noted, never dropped silently', () {
      final d = dispatch('copy a: b: --progress --stats 1s');
      expect(d.notes, containsAll(['--progress', '--stats']));
      // --stats consumed its value (1s) — it did not become a positional.
      expect(d.params['srcFs'], 'a:');
      expect(d.params['dstFs'], 'b:');
    });
  });

  group('fail-closed refusals (the safety guarantee)', () {
    test('an unknown/unmapped flag REFUSES (never a silent drop)', () {
      for (final line in [
        'copy a: b: --frobnicate',
        'sync a: b: --delete-excluded',
        'copy a: b: --min-age 1d',
        'copy a: b: --max-depth 2',
        'sync a: b: --sftp-pass hunter2',
        'copy a: b: --drive-chunk-size 64M',
      ]) {
        expect(tr(line), isA<RcRefusal>(), reason: line);
      }
    });

    test('a refused verb (no faithful RC method) REFUSES', () {
      // touch has no operations/touch RC method in v1.74 → refuse (not silent-fail).
      for (final v in [
        'cat',
        'tree',
        'rcat',
        'dedupe',
        'backend',
        'settier',
        'touch',
      ]) {
        expect(tr('$v a:x'), isA<RcRefusal>(), reason: v);
      }
    });

    test('an int flag with a non-number value REFUSES', () {
      expect(tr('copy a: b: --transfers abc'), isA<RcRefusal>());
      expect(tr('copy a: b: --max-delete x'), isA<RcRefusal>());
    });

    test('a value flag missing its value REFUSES', () {
      expect(tr('copy a: b: --transfers'), isA<RcRefusal>());
    });

    test('a Windows path on a SPLIT verb, or a missing remote, REFUSES', () {
      // A split verb needs a real remote:path — a Windows drive path can't split.
      expect(tr('mkdir C:/Users/x'), isA<RcRefusal>());
      expect(tr('ls notaremote'), isA<RcRefusal>());
      expect(tr('copy a:'), isA<RcRefusal>(), reason: 'move/copy need two args');
      // NB: `copy C:/local remote:` is intentionally allowed — copy/move/sync take
      // whole fs strings, and a local path is a legitimate rclone source.
      expect(dispatch('copy C:/local b:').method, 'sync/copy');
    });

    test('list-only flags on a non-list verb REFUSE', () {
      expect(tr('copy a: b: --dirs-only'), isA<RcRefusal>());
    });
  });
}
