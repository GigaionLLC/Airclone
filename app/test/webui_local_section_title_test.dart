import 'package:airclone/src/state/local_locations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // These run on the VM, where HostPlatform.isWeb is false, so they pin the
  // NATIVE answers. The web answer is pinned by the doc comment and by the
  // single `HostPlatform.isWeb` branch being the first line of the function —
  // there is no way to reach the strings below from a browser.
  group('localStorageSectionTitle (native)', () {
    test('a TV says so', () {
      expect(
        localStorageSectionTitle(isTelevision: true, phoneShell: true),
        'This TV',
      );
    });

    test('the phone shell says "This phone"', () {
      expect(
        localStorageSectionTitle(isTelevision: false, phoneShell: true),
        'This phone',
      );
    });

    test('the desktop shell says "This computer" on a desktop', () {
      expect(
        localStorageSectionTitle(isTelevision: false, phoneShell: false),
        'This computer',
      );
    });

    test('television wins over the phone shell', () {
      expect(
        localStorageSectionTitle(isTelevision: true, phoneShell: false),
        'This TV',
      );
    });
  });
}
