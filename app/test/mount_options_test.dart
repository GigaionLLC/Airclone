import 'package:airclone/src/rclone/models/mount_options.dart';
import 'package:flutter_test/flutter_test.dart';

/// The wire format is the part that fails SILENTLY.
///
/// rclone reshapes `vfsOpt`/`mountOpt` by marshalling JSON into a Go struct,
/// and `encoding/json` drops keys it does not recognise — so a misspelled
/// option name is accepted, ignored, and indistinguishable from success. These
/// tests pin the exact keys and the exact value shapes; the live read-back
/// against a running engine covers the other half (that rclone agrees).
void main() {
  const d = MountOptions.defaults;

  group('vfsOpt', () {
    test('sends every tuned option, with rclone Go field names', () {
      expect(d.toVfsOpt(), {
        'CacheMode': 3, // full
        'CacheMaxSize': '10Gi',
        'CacheMaxAge': '24h',
        'ChunkSize': '32Mi',
        'ChunkSizeLimit': '1Gi',
        'DirCacheTime': '5m',
        'FastFingerprint': true,
      });
    });

    test('CacheMode stays an INT — the one option that is not a string', () {
      for (final (mode, value) in const [
        ('off', 0),
        ('minimal', 1),
        ('writes', 2),
        ('full', 3),
      ]) {
        expect(d.copyWith(cacheMode: mode).toVfsOpt()['CacheMode'], value);
      }
    });

    test('defaults are the ones the plan chose, not rclone stock', () {
      // Each of these differs from rclone's own default ON PURPOSE; a silent
      // revert to stock is the regression this catches.
      expect(d.cacheMode, 'full'); // rclone: off
      expect(d.cacheMaxAge, '24h'); // rclone: 1h
      expect(d.chunkSize, '32Mi'); // rclone: 128Mi
      expect(d.chunkSizeLimit, '1Gi'); // rclone: off (unbounded)
      expect(d.attrTimeout, '5s'); // rclone: 1s
      expect(d.fastFingerprint, isTrue); // rclone: false
      expect(d.cacheMaxSize, '10Gi'); // rclone: off (unbounded)
    });
  });

  group('mountOpt', () {
    test('carries the attr timeout and, on Windows, the network mode', () {
      expect(d.toMountOpt(windows: true), {
        'AttrTimeout': '5s',
        'NetworkMode': false,
      });
      expect(
        d.copyWith(networkMode: true).toMountOpt(windows: true)['NetworkMode'],
        isTrue,
      );
    });

    test('omits NetworkMode entirely off Windows', () {
      final opt = d.copyWith(networkMode: true).toMountOpt(windows: false);
      expect(opt.containsKey('NetworkMode'), isFalse);
      expect(opt, {'AttrTimeout': '5s'});
    });
  });

  group('changedFrom', () {
    test('counts only real differences', () {
      expect(d.changedFrom(d), 0);
      expect(d.copyWith(cacheMaxSize: '20Gi').changedFrom(d), 1);
      expect(
        d.copyWith(cacheMaxSize: '20Gi', networkMode: true).changedFrom(d),
        2,
      );
      // copyWith with the same value is not a change.
      expect(d.copyWith(cacheMode: 'full').changedFrom(d), 0);
    });

    test('equality is defined by it, so a rebuilt copy is equal', () {
      expect(d.copyWith(), d);
      expect(d.copyWith().hashCode, d.hashCode);
      expect(d.copyWith(cacheMode: 'writes'), isNot(d));
    });
  });

  group('summary line', () {
    test(
      'reads as a summary, and names the cache size only when there is one',
      () {
        expect(d.summary, 'Cache: full · 10Gi · 24h');
        expect(
          d.copyWith(networkMode: true).summary,
          'Cache: full · 10Gi · 24h · network drive on',
        );
        // 'off' and 'minimal' keep no file cache, so a size would be a lie.
        expect(d.copyWith(cacheMode: 'off').summary, 'Cache: off · 24h');
      },
    );
  });

  group('persistence', () {
    test('round-trips', () {
      final tuned = d.copyWith(
        cacheMode: 'writes',
        cacheMaxSize: '2Gi',
        networkMode: true,
        fastFingerprint: false,
      );
      expect(MountOptions.fromJson(tuned.toJson()), tuned);
    });

    test('a corrupt or partial preference falls back per field', () {
      // Wrong types, an unknown cache mode, and missing keys — none of it may
      // throw, because a bad preference must not stop the dialog opening.
      final got = MountOptions.fromJson(const {
        'cacheMode': 'wormhole',
        'cacheMaxSize': 42,
        'fastFingerprint': 'yes',
        'networkMode': true,
      });
      expect(got.cacheMode, d.cacheMode);
      expect(got.cacheMaxSize, d.cacheMaxSize);
      expect(got.fastFingerprint, d.fastFingerprint);
      expect(got.networkMode, isTrue); // the one valid value survives
      expect(MountOptions.fromJson(const {}), d);
    });
  });
}
