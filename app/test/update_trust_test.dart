import 'dart:io';

import 'package:airclone/src/update/sums.dart';
import 'package:crypto/crypto.dart';
import 'package:airclone/src/update/update_trust.dart';
import 'package:flutter_test/flutter_test.dart';

/// What this build trusts, and what it reads out of a verified manifest.
void main() {
  group('trusted keys', () {
    /// A fork that has not set a key must end with installs refused. Failing
    /// closed here is the difference between "no in-app update" and "installs
    /// whatever it downloaded".
    test('no key configured means nothing is trusted', () {
      expect(updateTrustedKeys(primary: '', next: ''), isEmpty);
      expect(updateTrustedKeys(primary: '   ', next: ''), isEmpty);
    });

    /// A typo in a build command must produce a build that cannot install, not
    /// one that trusts something it could not parse.
    test('a malformed key is no key, not a broken one', () {
      expect(updateTrustedKeys(primary: 'not-a-key', next: ''), isEmpty);
      expect(updateTrustedKeys(primary: 'RWQ', next: ''), isEmpty);
    });

    test('a real key is accepted, and a second one for rotation', () {
      final line = File(
        'test/fixtures/update/public_key.txt',
      ).readAsStringSync().trim();
      expect(updateTrustedKeys(primary: line, next: '').length, 1);
      expect(updateTrustedKeys(primary: line, next: line).length, 2);
      // One good, one broken: keep the good one rather than refusing both.
      expect(updateTrustedKeys(primary: line, next: 'rubbish').length, 1);
    });
  });

  group('where it looks', () {
    /// A fork's app must never quietly download this project's builds. Both
    /// URLs are built from the same define for exactly that reason.
    test('both URLs come from the configured repository', () {
      expect(latestReleaseApiUrl().toString(), contains(kUpdateRepo));
      final asset = releaseAssetUrl(tag: 'v1.2.3', asset: 'a.AppImage');
      expect(asset.toString(), contains(kUpdateRepo));
      expect(
        asset.toString(),
        contains('/releases/download/v1.2.3/a.AppImage'),
      );
      expect(asset.scheme, 'https');
    });

    test('the default is this project', () {
      expect(kUpdateRepo, 'GigaionLLC/Airclone');
    });
  });

  group('reading a verified manifest', () {
    final manifest = File('test/fixtures/update/SHA256SUMS').readAsStringSync();

    test('finds the asset it was asked for', () {
      // The AppImage entry is the REAL hash of test/fixtures/update/asset.bin,
      // so the fetch tests can verify a download end to end; the others are
      // placeholders, there to be looked past.
      final asset = File('test/fixtures/update/asset.bin').readAsBytesSync();
      expect(
        hashForAsset(manifest, 'Airclone-x86_64.AppImage'),
        sha256.convert(asset).toString(),
      );
      expect(hashForAsset(manifest, 'airclone-setup-x64.exe'), '1' * 64);
    });

    /// THE POINT OF LOOKING UP BY NAME. A signed manifest carries a hash for
    /// every asset in the release, so a client that took "some hash in this
    /// file" could be handed the Windows installer as a Linux AppImage with a
    /// perfectly valid signature over it.
    test('a name that is not in the manifest gets nothing', () {
      expect(hashForAsset(manifest, 'airclone-linux-arm64.tar.gz'), isNull);
      expect(hashForAsset(manifest, ''), isNull);
      expect(hashForAsset(manifest, 'Airclone-x86_64.AppImage '), isNull);
    });

    test('parses every line of a real manifest', () {
      final entries = parseSums(manifest);
      expect(entries.length, 6);
      expect(entries.first.hash.length, 64);
      expect(entries.map((e) => e.name), contains('airclone.flatpak'));
    });
  });

  group('lines that must not parse', () {
    test('a short, long or non-hex digest', () {
      expect(parseSumsLine('${'a' * 63}  file'), isNull);
      expect(parseSumsLine('${'a' * 65}  file'), isNull);
      expect(parseSumsLine('${'z' * 64}  file'), isNull);
    });

    test('a single space, which is not the format', () {
      expect(parseSumsLine('${'a' * 64} file'), isNull);
    });

    /// A path in a checksum file is either a different kind of manifest or an
    /// attempt to point the verifier somewhere else entirely.
    test('a name with a path separator', () {
      expect(parseSumsLine('${'a' * 64}  ../evil'), isNull);
      expect(parseSumsLine('${'a' * 64}  dir/file'), isNull);
      expect(parseSumsLine('${'a' * 64}  dir\\file'), isNull);
    });

    test('blank lines and comments', () {
      expect(parseSumsLine(''), isNull);
      expect(parseSumsLine('   '), isNull);
      expect(parseSumsLine('# a comment'), isNull);
    });

    test('the binary-mode asterisk is accepted, as sha256sum writes it', () {
      final entry = parseSumsLine('${'a' * 64} *file.bin');
      expect(entry, isNotNull);
      expect(entry!.name, 'file.bin');
    });
  });
}
