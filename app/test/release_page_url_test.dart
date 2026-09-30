import 'package:airclone/src/state/app_info.dart';
import 'package:flutter_test/flutter_test.dart';

/// "View release" hands this URL to the OS, and it comes from a network
/// response. Only this project's own GitHub pages may be opened.
void main() {
  const fallback = 'https://github.com/GigaionLLC/Airclone/releases/latest';

  test('the release page GitHub reports is used as-is', () {
    const page = 'https://github.com/GigaionLLC/Airclone/releases/tag/v0.22.1';
    expect(releasePageUrl(page), page);
  });

  test('anything else falls back to the latest-release page', () {
    for (final url in [
      null,
      '',
      'https://evil.example/GigaionLLC/Airclone/',
      'http://github.com/GigaionLLC/Airclone/releases/tag/v1',
      'https://github.com/GigaionLLC/AircloneX/releases/tag/v1',
      'https://github.com/other/repo/releases/tag/v1',
      'file:///etc/passwd',
      'https://github.com:444/GigaionLLC/Airclone/releases',
    ]) {
      expect(releasePageUrl(url), fallback, reason: '$url');
    }
  });
}
