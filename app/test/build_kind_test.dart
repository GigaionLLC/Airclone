import 'package:airclone/src/state/build_kind.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which PACKAGE a bug report came from.
///
/// The install channel cannot answer this: the AppImage, the tar.gz and the
/// single-file `.flatpak` on each release are one channel (`directDownload`) and
/// three packages that fail in different ways — only one of them mounts through
/// a host helper, only one carries fallback graphics libraries. Reports that say
/// "the Linux build" cost a round trip every time.
void main() {
  group('Linux packages', () {
    /// The AppImage runtime exports this before AppRun runs; nothing else does.
    test('APPIMAGE means the AppImage', () {
      expect(
        linuxBuildKind(const {'APPIMAGE': '/home/u/Airclone-x86_64.AppImage'}),
        'AppImage',
      );
    });

    /// Both Flatpaks set FLATPAK_ID. Only Flathub's carries the marker, and the
    /// difference is real: the release bundle cannot update itself.
    test('a Flathub install and a release bundle are told apart', () {
      expect(
        linuxBuildKind(const {
          'FLATPAK_ID': 'com.gigaionllc.airclone',
          'AIRCLONE_INSTALL_CHANNEL': 'flathub',
        }),
        'Flatpak (Flathub)',
      );
      expect(
        linuxBuildKind(const {'FLATPAK_ID': 'com.gigaionllc.airclone'}),
        'Flatpak (release bundle)',
      );
    });

    test('SNAP means the Snap', () {
      expect(linuxBuildKind(const {'SNAP': '/snap/airclone/12'}), 'Snap');
    });

    /// The tar.gz announces nothing, so it is the fallthrough — which also
    /// means an unrecognised package is never mislabelled as something else.
    test('a bare environment is the tar.gz', () {
      expect(linuxBuildKind(const {}), 'tar.gz');
      expect(linuxBuildKind(const {'HOME': '/home/u'}), 'tar.gz');
    });

    /// An empty variable is not a package. Some launchers export names with no
    /// value, and treating that as "AppImage" would put a wrong fact in a report.
    test('an empty marker is not a package', () {
      expect(linuxBuildKind(const {'APPIMAGE': '', 'SNAP': ''}), 'tar.gz');
    });
  });

  group('Windows packages', () {
    test('a packaged app is the MSIX', () {
      expect(
        windowsBuildKind(packaged: true, uninstaller: false),
        'MSIX package',
      );
    });

    /// Inno leaves unins000.exe beside the executable; the zip never does.
    test('the uninstaller separates the installer from the portable zip', () {
      expect(windowsBuildKind(packaged: false, uninstaller: true), 'installer');
      expect(
        windowsBuildKind(packaged: false, uninstaller: false),
        'portable zip',
      );
    });
  });

  group('macOS packages', () {
    test('the sandboxed store build is named', () {
      expect(macBuildKind(masBuild: true, receipt: false), 'Mac App Store app');
      expect(macBuildKind(masBuild: false, receipt: true), 'Mac App Store app');
    });

    /// The .dmg and the .zip unpack to the same bundle, so claiming to know
    /// which one a user downloaded would be an invention.
    test('a direct download is just the bundle', () {
      expect(macBuildKind(masBuild: false, receipt: false), 'app bundle');
    });
  });

  group('mobile devices', () {
    test('a phone', () {
      expect(
        mobileBuildKind(television: false, width: 412, height: 915),
        'phone 412x915',
      );
    });

    /// 600dp shortest side is Android's own tablet line (sw600dp).
    test('a tablet, either way up', () {
      expect(
        mobileBuildKind(television: false, width: 800, height: 1280),
        'tablet 800x1280',
      );
      expect(
        mobileBuildKind(television: false, width: 1280, height: 800),
        'tablet 1280x800',
      );
    });

    /// The shell is chosen by WIDTH (<700), not device class, so a tablet in a
    /// narrow split gets the phone layout. "My tablet looks like a phone" is a
    /// real report, and this is the line that lets us reproduce it at the right
    /// size instead of guessing.
    test('a tablet narrow enough to get the phone layout says so', () {
      expect(
        mobileBuildKind(television: false, width: 600, height: 1024),
        'tablet 600x1024, phone layout',
      );
      expect(
        mobileBuildKind(television: false, width: 800, height: 1280),
        isNot(contains('phone layout')),
      );
    });

    /// A TV runs the same APK at tablet-ish sizes, and Android answers this
    /// directly, so it is never inferred from the size.
    test('a TV is named, not measured', () {
      expect(
        mobileBuildKind(television: true, width: 960, height: 540),
        'TV 960x540',
      );
    });

    test('fractional logical pixels are rounded, not printed raw', () {
      expect(
        mobileBuildKind(television: false, width: 411.4, height: 890.7),
        'phone 411x891',
      );
    });
  });

  group('the label for this process', () {
    /// Whatever the package, the architecture comes with it: it is what
    /// separates the Android split APKs from each other, and an Apple-silicon
    /// build from an Intel one.
    test('names a package and the architecture it was built for', () {
      final label = currentBuildKind(width: 1280, height: 720);
      expect(label, isNotEmpty);
      expect(label, contains('('));
      expect(label, endsWith(')'));
    });

    /// Called off the UI thread there is no window to measure. Inventing a size
    /// would be worse than omitting one.
    test('survives having no window size', () {
      expect(currentBuildKind(), isNotEmpty);
    });
  });
}
