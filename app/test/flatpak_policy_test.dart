import 'dart:io';

import 'package:airclone/src/state/build_flavor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:airclone/src/state/console/rclone_commands.dart';

/// Mounting a remote as a drive is FUSE, and two shipped builds cannot do it:
/// the Mac App Store build (the App Sandbox forbids it) and the Flatpak (our
/// manifest deliberately does not request `--device=all`, because blanket device
/// access is a much larger permission than the feature is worth).
///
/// Both must HIDE the feature rather than fail when it is used. A button that
/// cannot work is the dead end an Android TV review already failed this project
/// on once, and it is worth not repeating on Linux.
void main() {
  group('detecting a Flatpak sandbox', () {
    test('FLATPAK_ID present means yes', () {
      expect(
        runningInFlatpak({'FLATPAK_ID': 'com.gigaionllc.airclone'}),
        isTrue,
      );
    });

    test('an ordinary desktop environment means no', () {
      expect(runningInFlatpak({}), isFalse);
      expect(runningInFlatpak({'HOME': '/home/someone'}), isFalse);
    });

    test('an empty value is not a sandbox', () {
      // An exported-but-empty variable would otherwise disable mounting on a
      // machine that can perfectly well do it.
      expect(runningInFlatpak({'FLATPAK_ID': ''}), isFalse);
    });
  });

  group('whether mounting is possible', () {
    test('an ordinary desktop build can mount', () {
      expect(mountPossibleFor(macAppStore: false, flatpak: false), isTrue);
    });

    test('a Flatpak cannot — no /dev/fuse in the sandbox', () {
      expect(mountPossibleFor(macAppStore: false, flatpak: true), isFalse);
    });

    test('a Mac App Store build cannot', () {
      expect(mountPossibleFor(macAppStore: true, flatpak: false), isFalse);
    });

    test('either one alone is enough to rule it out', () {
      expect(mountPossibleFor(macAppStore: true, flatpak: true), isFalse);
    });
  });

  /// Two questions that used to be answered by one check, FLATPAK_ID, and must
  /// not be. "Am I sandboxed?" decides what the app CAN do - it cannot mount,
  /// there is no /dev/fuse - and is true of every Flatpak. "Did Flathub ship
  /// me?" decides who owns updates, and is true only of a build that says so.
  /// The GitHub-release .flatpak is the first and not the second.
  group('sandboxed is not the same as distributed by Flathub', () {
    const bundle = {'FLATPAK_ID': 'com.gigaionllc.airclone'};
    const flathub = {
      'FLATPAK_ID': 'com.gigaionllc.airclone',
      kInstallChannelEnv: kFlathubChannelValue,
    };

    test('both are sandboxed, so neither can mount', () {
      expect(runningInFlatpak(bundle), isTrue);
      expect(runningInFlatpak(flathub), isTrue);
      expect(
        mountPossibleFor(macAppStore: false, flatpak: runningInFlatpak(bundle)),
        isFalse,
        reason: 'the sandbox limit applies to the bundle too',
      );
    });

    test('only the marked build is Flathub', () {
      expect(flathubChannelMarked(bundle), isFalse);
      expect(flathubChannelMarked(flathub), isTrue);
    });

    test('the marker without a sandbox is not Flathub', () {
      expect(
        flathubChannelMarked({kInstallChannelEnv: kFlathubChannelValue}),
        isFalse,
      );
    });
  });

  /// The manifest in app/linux/packaging builds the DIRECT-DOWNLOAD bundle.
  /// If it ever sets the Flathub marker, the GitHub .flatpak is misreported as
  /// Flathub again and loses its update check - the bug this test guards.
  test('the release-bundle manifest does not claim to be Flathub', () {
    final f = File('linux/packaging/com.gigaionllc.airclone.yml');
    if (!f.existsSync()) return;
    expect(
      f.readAsStringSync(),
      isNot(contains(kInstallChannelEnv)),
      reason:
          'marking the direct-download manifest recreates the Flatpak update '
          'bug; only a Flathub-submitted manifest may set it',
    );
  });

  /// A Flatpak cannot mount, and that is not Airclone's to fix. What IS
  /// Airclone's to fix is a user concluding it is broken. Reported as: "make it
  /// obvious for the shortcomings of Flatpak so they don't blame Airclone".
  ///
  /// Three places a user runs into mounting. Before this, only one explained
  /// itself, and that one needed Advanced mode to be found.
  group('a Flatpak user is told, wherever they look', () {
    const flatpak = {'FLATPAK_ID': 'com.gigaionllc.airclone'};

    /// The console's generic answer to `rclone mount` pointed at the toolbar's
    /// Mount button - hidden without Advanced mode, and unable to mount inside
    /// the sandbox even when shown.
    test('the console does not send them to a button that cannot work', () {
      final msg = blockedMessage('mount', const [], environment: flatpak);
      expect(msg, isNot(contains('toolbar')));
      expect(msg, contains('AppImage'));
      expect(msg.toLowerCase(), contains('sandbox'));
    });

    test('outside a Flatpak the console still points at Mount as a drive', () {
      final msg = blockedMessage('mount', const [], environment: const {});
      expect(msg, contains('Mount as a drive'));
      expect(msg, isNot(contains('AppImage')));
    });

    test('the hint names the limit as the sandbox, not as Airclone', () {
      expect(kFlatpakMountConsoleHint.toLowerCase(), contains('sandbox'));
      expect(kFlatpakMountConsoleHint, contains('AppImage'));
    });

    /// The dialog links out only for the direct-download bundle. A build shipped
    /// by Flathub must not send users to download a different package: the
    /// Microsoft Store already rejected an Airclone submission for a GitHub link.
    test('the releases link is the latest page, not a pinned version', () {
      expect(kReleasesPageUrl, endsWith('/releases/latest'));
      expect(kReleasesPageUrl, startsWith('https://'));
    });

    test('the link is withheld from a marked Flathub build', () {
      // The dialog gates on kFlathubChannel; this pins the predicate it reads.
      expect(
        flathubChannelMarked(flatpak),
        isFalse,
        reason: 'bundle: link shown',
      );
      expect(
        flathubChannelMarked({
          ...flatpak,
          kInstallChannelEnv: kFlathubChannelValue,
        }),
        isTrue,
        reason: 'Flathub: link withheld',
      );
    });

    /// Settings used to drop the Mounts group entirely in a Flatpak. That is the
    /// worst of the three: somebody who read that Airclone mounts drives looks
    /// there first and finds nothing. The source is read directly because the
    /// branch depends on kRunningInFlatpak, a process-wide getter.
    test('Settings explains the missing Mounts group instead of hiding it', () {
      final f = File('lib/src/ui/settings_screen.dart');
      if (!f.existsSync()) return;
      final src = f.readAsStringSync();
      expect(src, contains('_FlatpakMountNotice'));
      expect(
        src,
        contains('else if (desktop && kRunningInFlatpak)'),
        reason:
            'the Flatpak branch must sit beside the Mounts group, not vanish',
      );
    });
  });
}
