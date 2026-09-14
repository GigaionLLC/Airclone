import 'package:airclone/src/update/version_compare.dart';
import 'package:flutter_test/flutter_test.dart';

/// Telling one Airclone version from another.
///
/// The update check used to ask whether the latest tag CONTAINED the running
/// version. These exist because that is not a comparison, and because an
/// updater built on a wrong answer would either hide a release or walk someone
/// backwards into an old one.
void main() {
  group('parsing', () {
    test('a tag, with or without its v', () {
      expect(parseAppVersion('v0.13.6').toString(), '0.13.6');
      expect(parseAppVersion('0.13.6').toString(), '0.13.6');
    });

    /// The build number changes for the stores without the release changing.
    test('build metadata is not part of the version', () {
      expect(parseAppVersion('0.13.6+141').toString(), '0.13.6');
      expect(compareAppVersions('0.13.6+141', '0.13.6+999'), 0);
    });

    test('a prerelease keeps its identifiers', () {
      final v = parseAppVersion('v0.14.0-rc.1')!;
      expect(v.isPrerelease, isTrue);
      expect(v.prerelease, ['rc', '1']);
    });

    /// Anything unparseable must come back null so a caller has to decide what
    /// "cannot tell" means, rather than being handed a plausible-looking zero.
    test('refuses what is not a version', () {
      for (final bad in [
        '',
        'v',
        'latest',
        '1.2',
        '1.2.3.4',
        '1.2.x',
        'v 1.2.3',
        '1.-2.3',
        '1.2.3-',
      ]) {
        expect(parseAppVersion(bad), isNull, reason: bad);
      }
    });
  });

  group('ordering', () {
    /// THE BUG. "v0.9.10".contains("0.9.1") is true, so every 0.9.1 user was
    /// told they were up to date for the whole of 0.9.10's life.
    test('0.9.10 is newer than 0.9.1, however it reads as a substring', () {
      expect(compareAppVersions('0.9.10', '0.9.1'), greaterThan(0));
      expect(isNewerAppVersion(candidate: 'v0.9.10', current: '0.9.1'), isTrue);
    });

    test('by major, then minor, then patch', () {
      expect(compareAppVersions('1.0.0', '0.99.99'), greaterThan(0));
      expect(compareAppVersions('0.14.0', '0.13.99'), greaterThan(0));
      expect(compareAppVersions('0.13.6', '0.13.7'), lessThan(0));
      expect(compareAppVersions('0.13.6', '0.13.6'), 0);
    });

    /// A release candidate leads to the release, so the release is newer -
    /// otherwise an rc user is offered a "downgrade" to the final build.
    test('a prerelease is older than the release it leads to', () {
      expect(compareAppVersions('0.14.0-rc.1', '0.14.0'), lessThan(0));
      expect(
        isNewerAppVersion(candidate: '0.14.0', current: '0.14.0-rc.1'),
        isTrue,
      );
    });

    test('prereleases order among themselves', () {
      expect(compareAppVersions('0.2.0-beta.3', '0.2.0-beta.4'), lessThan(0));
      expect(compareAppVersions('0.2.0-alpha.84', '0.2.0-beta.1'), lessThan(0));
      // Numeric identifiers rank below alphanumeric ones (semver 11.4.3).
      expect(compareAppVersions('0.2.0-beta.2', '0.2.0-beta.rc'), lessThan(0));
      // More identifiers, everything else equal, is later.
      expect(compareAppVersions('0.2.0-beta', '0.2.0-beta.1'), lessThan(0));
    });

    test('the same version is never newer than itself', () {
      expect(
        isNewerAppVersion(candidate: 'v0.13.6', current: '0.13.6+141'),
        isFalse,
      );
      expect(
        isNewerAppVersion(candidate: '0.13.5', current: '0.13.6'),
        isFalse,
      );
    });

    /// Garbage from a release feed must not read as an upgrade. This is the
    /// one that matters for an updater: "latest" is not newer than anything.
    test('unreadable input is never newer', () {
      expect(
        isNewerAppVersion(candidate: 'latest', current: '0.13.6'),
        isFalse,
      );
      expect(isNewerAppVersion(candidate: '', current: '0.13.6'), isFalse);
      expect(isNewerAppVersion(candidate: 'nightly', current: ''), isFalse);
    });
  });
}
