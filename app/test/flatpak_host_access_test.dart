import 'dart:io';

import 'package:airclone/src/state/build_flavor.dart';
import 'package:airclone/src/state/console/rclone_commands.dart';
import 'package:airclone/src/state/flatpak_host_access.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opt-in mounting from the Flatpak.
///
/// A mount made inside the sandbox is invisible to every other program, so the
/// Flatpak mounts through a fusermount wrapper that runs on the host. That needs
/// `org.freedesktop.Flatpak`, which lets the app run ANY command on the host.
/// Airclone never requests it; a user grants it knowingly, and the app reads
/// what they granted from /.flatpak-info.
///
/// Precedent: rclone-manager on Flathub mounts this way, and its users hit an
/// unexplained `fusermount: exit status 1` until they found the permission
/// (Zarestia-Dev/rclone-manager#52, #113). These pin the check that lets
/// Airclone explain first instead.
void main() {
  group('reading what the user granted from /.flatpak-info', () {
    const header = '[Application]\nname=com.gigaionllc.airclone\n\n';

    /// What `flatpak override --user --talk-name=org.freedesktop.Flatpak` writes.
    test('the talk permission grants it', () {
      expect(
        flatpakHostCommandsAllowed(
          '$header[Session Bus Policy]\norg.freedesktop.Flatpak=talk\n',
        ),
        isTrue,
      );
    });

    test('own grants it too', () {
      expect(
        flatpakHostCommandsAllowed(
          '$header[Session Bus Policy]\norg.freedesktop.Flatpak=own\n',
        ),
        isTrue,
      );
    });

    /// Flatseal's "D-Bus session bus" toggle. Broader than the talk name, and
    /// it includes it - an rclone-manager user fixed mounting with exactly this.
    test('the whole session bus socket grants it', () {
      expect(
        flatpakHostCommandsAllowed(
          '$header[Context]\nsockets=x11;wayland;session-bus;\n',
        ),
        isTrue,
      );
    });

    test('a wildcard covering the name grants it', () {
      expect(
        flatpakHostCommandsAllowed(
          '$header[Session Bus Policy]\norg.freedesktop.*=talk\n',
        ),
        isTrue,
      );
    });

    group('and what does not', () {
      test('a plain install, as the manifest ships', () {
        expect(
          flatpakHostCommandsAllowed(
            '$header[Context]\nshared=network;ipc;\nsockets=x11;wayland;pulseaudio;\n'
            'filesystems=host;\n\n'
            '[Session Bus Policy]\norg.freedesktop.secrets=talk\n',
          ),
          isFalse,
        );
      });

      test('see and none do not allow calling it', () {
        for (final v in ['see', 'none', '']) {
          expect(
            flatpakHostCommandsAllowed(
              '$header[Session Bus Policy]\norg.freedesktop.Flatpak=$v\n',
            ),
            isFalse,
            reason: 'value "$v"',
          );
        }
      });

      test('an explicitly removed session-bus socket', () {
        expect(
          flatpakHostCommandsAllowed(
            '$header[Context]\nsockets=!session-bus;\n',
          ),
          isFalse,
        );
      });

      /// A name that merely STARTS the same way is a different service.
      test('a longer name that shares the prefix is not the same service', () {
        expect(
          flatpakHostCommandsAllowed(
            '$header[Session Bus Policy]\norg.freedesktop.FlatpakHelper=talk\n',
          ),
          isFalse,
        );
      });

      /// The right key in the wrong section is not a grant.
      test('the name under the wrong section', () {
        expect(
          flatpakHostCommandsAllowed(
            '$header[System Bus Policy]\norg.freedesktop.Flatpak=talk\n',
          ),
          isFalse,
        );
      });

      /// Guessing yes would offer a mount that fails at its first step.
      test('empty or garbled content is treated as not granted', () {
        expect(flatpakHostCommandsAllowed(''), isFalse);
        expect(flatpakHostCommandsAllowed('not an ini file at all'), isFalse);
        expect(flatpakHostCommandsAllowed('[Session Bus Policy'), isFalse);
      });
    });

    test('Windows line endings do not hide a grant', () {
      expect(
        flatpakHostCommandsAllowed(
          '[Session Bus Policy]\r\norg.freedesktop.Flatpak=talk\r\n',
        ),
        isTrue,
      );
    });
  });

  group('the command shown to the user', () {
    test('names the real app ID and grants only for this user', () {
      final cmd = flatpakHostAccessCommand(appId: 'com.gigaionllc.airclone');
      expect(
        cmd,
        'flatpak override --user --talk-name=org.freedesktop.Flatpak '
        'com.gigaionllc.airclone',
      );
    });

    /// An earlier draft of the mount dialog told users to remove the
    /// permission with `flatpak override --user --reset`. With no app ID that
    /// resets the user's overrides for EVERY Flatpak they have installed.
    test('taking it away is scoped to this one name and this one app', () {
      final cmd = flatpakHostAccessRevokeCommand(
        appId: 'com.gigaionllc.airclone',
      );
      expect(
        cmd,
        'flatpak override --user --no-talk-name=org.freedesktop.Flatpak '
        'com.gigaionllc.airclone',
      );
      expect(cmd, isNot(contains('--reset')));
    });

    /// What --no-talk-name writes must read back as not granted, or revoking
    /// would leave the app still offering a mount it can no longer perform.
    test('a revoked permission reads as not granted', () {
      expect(
        flatpakHostCommandsAllowed(
          '[Session Bus Policy]\norg.freedesktop.Flatpak=none\n',
        ),
        isFalse,
      );
    });

    test('falls back to the published ID when none is known', () {
      expect(
        flatpakHostAccessCommand(appId: ''),
        endsWith(' com.gigaionllc.airclone'),
      );
    });
  });

  group('mounting follows the grant', () {
    test('a Flatpak without it cannot mount', () {
      expect(mountPossibleFor(macAppStore: false, flatpak: true), isFalse);
    });

    test('a Flatpak with it can', () {
      expect(
        mountPossibleFor(
          macAppStore: false,
          flatpak: true,
          flatpakHostMount: true,
        ),
        isTrue,
      );
    });

    /// The grant is meaningless outside a Flatpak and must not unlock the Mac
    /// App Store, where FUSE is impossible whatever anyone grants.
    test('the grant never unlocks the Mac App Store', () {
      expect(
        mountPossibleFor(
          macAppStore: true,
          flatpak: false,
          flatpakHostMount: true,
        ),
        isFalse,
      );
    });

    test('an ordinary desktop build mounts either way', () {
      expect(mountPossibleFor(macAppStore: false, flatpak: false), isTrue);
    });
  });

  group('the console', () {
    const flatpak = {'FLATPAK_ID': 'com.gigaionllc.airclone'};

    test('without the grant, it explains the permission', () {
      final msg = blockedMessage(
        'mount',
        const [],
        environment: flatpak,
        flatpakHostMount: false,
      );
      expect(msg.toLowerCase(), contains('permission'));
    });

    /// Telling a user who already granted it that they need a permission sends
    /// them looking for a problem they have already solved.
    test(
      'with the grant, it points at Mount as a drive like anywhere else',
      () {
        final msg = blockedMessage(
          'mount',
          const [],
          environment: flatpak,
          flatpakHostMount: true,
        );
        expect(msg, contains('Mount as a drive'));
        expect(msg.toLowerCase(), isNot(contains('permission')));
      },
    );
  });

  /// The one line that must never appear. Requesting this permission in the
  /// manifest would grant every user of the bundle host command access silently,
  /// which is the opposite of the design, and Flathub would reject it.
  group('the manifest', () {
    final manifest = File('linux/packaging/com.gigaionllc.airclone.yml');

    test('never requests host command access itself', () {
      if (!manifest.existsSync()) return;
      final text = manifest.readAsStringSync();
      final finishArgs = text.substring(
        text.indexOf('finish-args:'),
        text.indexOf('modules:'),
      );
      expect(
        finishArgs,
        isNot(contains('org.freedesktop.Flatpak')),
        reason: 'the user grants this knowingly; the app never requests it',
      );
      expect(finishArgs, isNot(contains('session-bus')));
      expect(finishArgs, isNot(contains('--device=all')));
    });

    /// rclone looks up fusermount3 first, then fusermount. Both names must be
    /// the wrapper, or rclone finds nothing in the sandbox and mounting fails
    /// even with the permission granted.
    test('installs the host fusermount wrapper under both names', () {
      if (!manifest.existsSync()) return;
      final text = manifest.readAsStringSync();
      expect(text, contains('fusermount-wrapper.sh /app/bin/fusermount3'));
      expect(text, contains('fusermount-wrapper.sh /app/bin/fusermount'));
    });

    test('the build script copies the wrapper into the build context', () {
      final script = File('../dev/linux/build-flatpak.sh');
      if (!script.existsSync()) return;
      expect(
        script.readAsStringSync(),
        contains(r'cp "$PKG/fusermount-wrapper.sh"'),
      );
    });
  });
}
