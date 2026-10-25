/// The sign-in launch (#54): which builds offer it, and the Linux autostart
/// entry, whose Exec line must only ever be this app's own quoted path.
library;

import 'package:airclone/src/state/autostart.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('autostartSupportFor', () {
    AutostartSupport s({
      bool win = false,
      bool mac = false,
      bool linux = false,
      bool msix = false,
      bool flatpak = false,
      bool snap = false,
      bool native = true,
    }) => autostartSupportFor(
      isWindows: win,
      isMacOS: mac,
      isLinux: linux,
      msix: msix,
      flatpak: flatpak,
      snap: snap,
      nativeAvailable: native,
    );

    test('Windows desktop builds', () {
      expect(s(win: true).supported, isTrue);
      expect(s(win: true, native: false).supported, isFalse);
    });

    test('MSIX is hidden with a reason', () {
      final r = s(win: true, msix: true);
      expect(r.supported, isFalse);
      expect(r.reason, contains('Microsoft Store'));
    });

    test('macOS needs the native API', () {
      expect(s(mac: true).supported, isTrue);
      final r = s(mac: true, native: false);
      expect(r.supported, isFalse);
      expect(r.reason, contains('macOS 13'));
    });

    test('Linux, but not Flatpak or Snap', () {
      expect(s(linux: true, native: false).supported, isTrue);
      expect(s(linux: true, flatpak: true).supported, isFalse);
      expect(s(linux: true, flatpak: true).reason, contains('--tray'));
      expect(s(linux: true, snap: true).supported, isFalse);
    });

    test('mobile and web', () {
      expect(s().supported, isFalse);
    });
  });

  group('desktopExecQuote', () {
    test('plain path', () {
      expect(
        desktopExecQuote('/opt/airclone/airclone'),
        '"/opt/airclone/airclone"',
      );
    });

    test('space stays inside the quotes', () {
      expect(
        desktopExecQuote('/home/a b/Airclone.AppImage'),
        '"/home/a b/Airclone.AppImage"',
      );
    });

    test('reserved characters are escaped, then backslashes doubled', () {
      // Inside quotes: " ` $ \ take a backslash; then the string-value
      // escaping writes every backslash twice.
      expect(desktopExecQuote(r'/x/"a"'), r'"/x/\\"a\\""');
      expect(desktopExecQuote(r'/x/$HOME'), r'"/x/\\$HOME"');
      expect(desktopExecQuote('/x/`id`'), r'"/x/\\`id\\`"');
      expect(desktopExecQuote(r'/x/a\b'), r'"/x/a\\\\b"');
    });

    test('a percent is never a field code', () {
      expect(desktopExecQuote('/x/100%u'), '"/x/100%%u"');
    });

    test('control characters are refused', () {
      expect(() => desktopExecQuote('/x/a\nExec=evil'), throwsArgumentError);
      expect(() => desktopExecQuote('/x/a\rb'), throwsArgumentError);
      expect(() => desktopExecQuote('/x/\x00'), throwsArgumentError);
      expect(() => desktopExecQuote('/x/\x7f'), throwsArgumentError);
    });
  });

  group('linuxAutostartEntry', () {
    test('one Exec line with the quoted path and --tray', () {
      final e = linuxAutostartEntry('/opt/airclone/airclone');
      final lines = e.trim().split('\n');
      expect(lines.first, '[Desktop Entry]');
      expect(lines.where((l) => l.startsWith('Exec=')).toList(), [
        'Exec="/opt/airclone/airclone" --tray',
      ]);
      expect(e, contains('Type=Application\n'));
      expect(e, contains('Terminal=false\n'));
      expect(e, endsWith('\n'));
    });
  });

  group('linuxAutostartExecutable', () {
    bool all(String _) => true;

    test('prefers the AppImage file', () {
      expect(
        linuxAutostartExecutable(
          {'APPIMAGE': '/home/u/Airclone.AppImage'},
          '/tmp/.mount_x/airclone',
          exists: all,
        ),
        '/home/u/Airclone.AppImage',
      );
    });

    test('falls back to this executable', () {
      expect(
        linuxAutostartExecutable({}, '/opt/airclone/airclone', exists: all),
        '/opt/airclone/airclone',
      );
    });

    test('ignores relative and missing paths', () {
      expect(
        linuxAutostartExecutable(
          {'APPIMAGE': 'Airclone.AppImage'},
          '/opt/airclone/airclone',
          exists: all,
        ),
        '/opt/airclone/airclone',
      );
      expect(
        linuxAutostartExecutable(
          {'APPIMAGE': '/gone.AppImage'},
          '/opt/airclone/airclone',
          exists: (p) => p != '/gone.AppImage',
        ),
        '/opt/airclone/airclone',
      );
      expect(linuxAutostartExecutable({}, 'airclone', exists: all), isNull);
    });
  });

  group('linuxAutostartDir', () {
    test('XDG_CONFIG_HOME when absolute', () {
      expect(
        linuxAutostartDir({'XDG_CONFIG_HOME': '/c', 'HOME': '/h'}),
        '/c/autostart',
      );
    });

    test('HOME otherwise', () {
      expect(
        linuxAutostartDir({'XDG_CONFIG_HOME': 'rel', 'HOME': '/h'}),
        '/h/.config/autostart',
      );
      expect(linuxAutostartDir({'HOME': '/h'}), '/h/.config/autostart');
    });

    test('nothing to go on', () {
      expect(linuxAutostartDir({}), isNull);
    });
  });
}
