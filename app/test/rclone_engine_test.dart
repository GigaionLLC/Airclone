import 'package:airclone/src/rclone/rclone_engine.dart';
import 'package:flutter_test/flutter_test.dart';

// These exercise only the pure, network-free helpers on [RcloneEngine]:
// checksum parsing (the fail-closed verification decision) and the version
// comparator that backs the min-version gate. downloadLatest() itself needs a
// Process/network and is intentionally NOT driven end-to-end here.
void main() {
  group('parseSha256Sums', () {
    const zip = 'rclone-v1.74.4-windows-amd64.zip';
    // 64 hex chars — a well-formed SHA-256 digest.
    const digest =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

    test('returns the digest when the entry is present', () {
      final body = '$digest  $zip\n';
      expect(RcloneEngine.parseSha256Sums(body, zip), digest);
    });

    test('is case-insensitive on the digest, returning it lowercased', () {
      final body = '${digest.toUpperCase()}  $zip\n';
      expect(RcloneEngine.parseSha256Sums(body, zip), digest);
    });

    test('returns null when no line names the zip (absent)', () {
      final body =
          '${'a' * 64}  rclone-v1.74.4-linux-amd64.zip\n'
          '${'b' * 64}  rclone-v1.74.4-osx-arm64.zip\n';
      expect(RcloneEngine.parseSha256Sums(body, zip), isNull);
    });

    test('returns null when the matching line is malformed', () {
      // Digest present but not 64 hex chars (truncated / has a non-hex char).
      expect(RcloneEngine.parseSha256Sums('deadbeef  $zip', zip), isNull);
      expect(RcloneEngine.parseSha256Sums('${'z' * 64}  $zip', zip), isNull);
      // Filename-only line (no digest field) is malformed too.
      expect(RcloneEngine.parseSha256Sums(zip, zip), isNull);
      // Empty body.
      expect(RcloneEngine.parseSha256Sums('', zip), isNull);
    });

    test('picks the right entry out of many, exact-match on filename', () {
      final wanted = 'f' * 64;
      final body =
          '${'a' * 64}  rclone-v1.74.4-linux-amd64.zip\n'
          '${'b' * 64}  rclone-v1.74.4-osx-arm64.zip\n'
          '$wanted  $zip\n'
          '${'c' * 64}  rclone-v1.74.4-windows-arm64.zip\n';
      expect(RcloneEngine.parseSha256Sums(body, zip), wanted);
    });

    test('a short name does not accidentally match a longer entry', () {
      // 'rclone-v1.74.4-windows-amd64.zip' must NOT match the '.zip.asc' line.
      final body =
          '${'a' * 64}  rclone-v1.74.4-windows-amd64.zip.asc\n'
          '${'d' * 64}  rclone-v1.74.4-windows-amd64.zip\n';
      expect(RcloneEngine.parseSha256Sums(body, zip), 'd' * 64);
    });

    test('tolerates a binary-mode "*" filename prefix', () {
      final body = '$digest *$zip\n';
      expect(RcloneEngine.parseSha256Sums(body, zip), digest);
    });
  });

  group('fail-closed verification decision', () {
    const zip = 'rclone-v1.74.4-windows-amd64.zip';
    // downloadLatest refuses to install whenever parseSha256Sums returns null;
    // these lock in exactly which unverifiable inputs trigger that refusal.
    test('a body without our entry yields null → refuse', () {
      expect(
        RcloneEngine.parseSha256Sums('${'a' * 64}  something-else.zip', zip),
        isNull,
      );
    });

    test('a garbage/HTML error page yields null → refuse', () {
      expect(
        RcloneEngine.parseSha256Sums('<html>404 Not Found</html>', zip),
        isNull,
      );
    });
  });

  group('minRcloneVersion', () {
    test('is the documented floor', () {
      expect(RcloneEngine.minRcloneVersion, '1.73.5');
    });
  });

  group('compareRcloneVersions', () {
    test('orders by major.minor.patch', () {
      expect(
        RcloneEngine.compareRcloneVersions('1.73.4', '1.73.5'),
        lessThan(0),
      );
      expect(RcloneEngine.compareRcloneVersions('1.73.5', '1.73.5'), 0);
      expect(
        RcloneEngine.compareRcloneVersions('1.74.4', '1.73.5'),
        greaterThan(0),
      );
      // Minor/major dominate patch.
      expect(
        RcloneEngine.compareRcloneVersions('1.8.0', '1.10.0'),
        lessThan(0),
      );
      expect(
        RcloneEngine.compareRcloneVersions('2.0.0', '1.99.99'),
        greaterThan(0),
      );
    });

    test('tolerates v / rclone prefixes and beta suffixes', () {
      expect(RcloneEngine.compareRcloneVersions('v1.74.4', '1.74.4'), 0);
      expect(RcloneEngine.compareRcloneVersions('rclone v1.74.4', '1.74.4'), 0);
      expect(
        RcloneEngine.compareRcloneVersions('1.74.4-beta.1234.abcdef', '1.74.4'),
        0,
      );
    });

    test('unparseable input on either side yields 0', () {
      expect(RcloneEngine.compareRcloneVersions('not-a-version', '1.73.5'), 0);
      expect(RcloneEngine.compareRcloneVersions('1.73.5', 'garbage'), 0);
    });
  });

  group('meetsMinRclone', () {
    test('below the floor fails', () {
      expect(RcloneEngine.meetsMinRclone('1.73.4'), isFalse);
      expect(RcloneEngine.meetsMinRclone('v1.72.0'), isFalse);
    });

    test('equal to the floor passes', () {
      expect(RcloneEngine.meetsMinRclone('1.73.5'), isTrue);
      expect(RcloneEngine.meetsMinRclone('v1.73.5'), isTrue);
    });

    test('above the floor passes, incl. prefixed and beta-suffixed', () {
      expect(RcloneEngine.meetsMinRclone('1.74.4'), isTrue);
      expect(RcloneEngine.meetsMinRclone('rclone v1.74.4'), isTrue);
      expect(RcloneEngine.meetsMinRclone('1.74.4-beta.1234.abcdef'), isTrue);
    });

    test('garbage fails closed (treated as NOT meeting the minimum)', () {
      expect(RcloneEngine.meetsMinRclone('not-a-version'), isFalse);
      expect(RcloneEngine.meetsMinRclone(''), isFalse);
    });
  });
}
