import 'package:airclone_rc/airclone_rc.dart';
import 'package:test/test.dart';

/// `instanceTag` decides which `rcd` processes this client is willing to kill.
///
/// It is also a file-name prefix and a Basic-auth username, so a tag carrying a
/// path separator or a colon would not fail here — it would fail much later,
/// as a marker written somewhere unexpected or a malformed header.
void main() {
  HttpRcloneClient build(String tag) =>
      HttpRcloneClient(instanceTag: tag, rclonePath: 'rclone');

  test('an ordinary tag is accepted', () {
    expect(build('airclone').instanceTag, 'airclone');
    expect(build('my_app-2').instanceTag, 'my_app-2');
  });

  test('a tag that is not safe as a file name or a header is refused', () {
    for (final bad in <String>[
      '', // no prefix at all: every marker in temp would match
      'my app', // a space, in a Basic-auth username
      'my:app', // the separator inside Basic auth's own encoding
      'my/app', // a path separator, so the marker lands somewhere else
      '../etc', // the same, pointed somewhere worse
      'x' * 33, // unbounded, for a name that goes in a shared directory
    ]) {
      expect(
        () => build(bad),
        throwsA(isA<AssertionError>()),
        reason: 'accepted $bad',
      );
    }
  });
}
