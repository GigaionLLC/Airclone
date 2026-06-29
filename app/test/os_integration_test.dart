import 'dart:io';

import 'package:airclone/src/state/os_integration.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('revealCommand argv (pure, no process launched)', () {
    test('Windows joins /select and the path into ONE argv element', () {
      final c = revealCommand(TargetPlatform.windows, r'C:\Users\me\file.txt');
      expect(c.exe, 'explorer.exe');
      expect(c.args, [r'/select,C:\Users\me\file.txt']);
      expect(c.args.length, 1); // switch + path travel together
    });

    test('Windows quotes the path when it contains a comma or =', () {
      final c = revealCommand(TargetPlatform.windows, r'C:\a,b\f=1.txt');
      expect(c.args, [r'/select,"C:\a,b\f=1.txt"']);
    });

    test('Windows handles spaces without manual quoting', () {
      final c = revealCommand(TargetPlatform.windows, r'C:\My Docs\a b.txt');
      expect(c.args, [r'/select,C:\My Docs\a b.txt']);
    });

    test('Windows converts forward slashes to backslashes (regression)', () {
      // rclone's local fs gives forward slashes; explorer.exe needs backslashes
      // or it ignores /select and opens the Desktop.
      final c = revealCommand(TargetPlatform.windows, 'C:/Users/me/sub/f.txt');
      expect(c.args, [r'/select,C:\Users\me\sub\f.txt']);
    });

    test('macOS uses open -R with the path as a separate element', () {
      final c = revealCommand(TargetPlatform.macOS, '/Users/me/a b.txt');
      expect(c.exe, 'open');
      expect(c.args, ['-R', '/Users/me/a b.txt']);
    });

    test(
      'Linux uses dbus-send FileManager1.ShowItems with a file:// array',
      () {
        final c = revealCommand(TargetPlatform.linux, '/home/me/a b.txt');
        expect(c.exe, 'dbus-send');
        expect(c.args, contains('org.freedesktop.FileManager1.ShowItems'));
        // URI is percent-encoded and wrapped in a dbus array literal.
        expect(c.args, contains('array:string:file:///home/me/a%20b.txt'));
        expect(c.args.last, 'string:'); // empty startup-id
      },
    );
  });

  test('revealFallbackCommand opens the parent DIRECTORY, not the file', () {
    final c = revealFallbackCommand('/home/me/sub/a.txt');
    expect(c.exe, 'xdg-open');
    expect(c.args, ['/home/me/sub']);
  });

  group('isSpawnSuccess per-OS exit-code policy', () {
    ProcessResult res(int code) => ProcessResult(0, code, '', '');

    test('Windows ignores the exit code (explorer returns 1 on success)', () {
      expect(isSpawnSuccess(TargetPlatform.windows, res(1), null), isTrue);
      expect(isSpawnSuccess(TargetPlatform.windows, res(0), null), isTrue);
    });

    test('Windows fails only when the process threw (binary not found)', () {
      expect(
        isSpawnSuccess(TargetPlatform.windows, null, ProcessException('x', [])),
        isFalse,
      );
    });

    test('macOS/Linux require exit code 0', () {
      expect(isSpawnSuccess(TargetPlatform.macOS, res(0), null), isTrue);
      expect(isSpawnSuccess(TargetPlatform.macOS, res(1), null), isFalse);
      expect(isSpawnSuccess(TargetPlatform.linux, res(0), null), isTrue);
      expect(isSpawnSuccess(TargetPlatform.linux, res(2), null), isFalse);
    });
  });

  group('OsIntegration.revealInFileManager (injected runner)', () {
    test('invokes the exact per-OS command and reports success', () async {
      final calls = <(String, List<String>)>[];
      final os = OsIntegration(
        platform: TargetPlatform.macOS,
        runner: (e, a) async {
          calls.add((e, a));
          return ProcessResult(0, 0, '', '');
        },
      );
      final ok = await os.revealInFileManager('/Users/me/a.txt');
      expect(ok, isTrue);
      expect(calls.single.$1, 'open');
      expect(calls.single.$2, ['-R', File('/Users/me/a.txt').absolute.path]);
    });

    test('Windows success ignores a non-zero explorer exit code', () async {
      final os = OsIntegration(
        platform: TargetPlatform.windows,
        runner: (e, a) async => ProcessResult(0, 1, '', ''),
      );
      expect(await os.revealInFileManager(r'C:\a\b.txt'), isTrue);
    });

    test('Linux falls back to xdg-open when dbus-send fails', () async {
      final calls = <String>[];
      final os = OsIntegration(
        platform: TargetPlatform.linux,
        runner: (e, a) async {
          calls.add(e);
          // dbus-send "fails" (no FileManager1 service) → non-zero.
          return ProcessResult(0, e == 'dbus-send' ? 1 : 0, '', '');
        },
      );
      final ok = await os.revealInFileManager('/home/me/a.txt');
      expect(ok, isTrue);
      expect(calls, ['dbus-send', 'xdg-open']);
    });

    test('failure when the runner throws and there is no fallback', () async {
      final os = OsIntegration(
        platform: TargetPlatform.windows,
        runner: (e, a) async => throw ProcessException(e, a),
      );
      expect(await os.revealInFileManager(r'C:\a\b.txt'), isFalse);
    });
  });

  group('OsIntegration.openWithDefaultApp', () {
    test('returns false for a missing file without launching', () async {
      var launched = false;
      final os = OsIntegration(
        launch: (u) async {
          launched = true;
          return true;
        },
      );
      final ok = await os.openWithDefaultApp(
        '/definitely/missing/${DateTime(2020).microsecondsSinceEpoch}.txt',
      );
      expect(ok, isFalse);
      expect(launched, isFalse);
    });

    test('launches a file:// URI for an existing file', () async {
      final tmp = File('${Directory.systemTemp.path}/airclone_open_test.txt')
        ..writeAsStringSync('x');
      addTearDown(() => tmp.existsSync() ? tmp.deleteSync() : null);
      Uri? launchedWith;
      final os = OsIntegration(
        launch: (u) async {
          launchedWith = u;
          return true;
        },
      );
      final ok = await os.openWithDefaultApp(tmp.path);
      expect(ok, isTrue);
      expect(launchedWith?.scheme, 'file');
      // Same path → identical Uri.file (avoids separator-normalization skew).
      expect(launchedWith, Uri.file(tmp.absolute.path));
    });
  });

  test('copyToClipboard sends the path over the platform channel', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (m) async {
          calls.add(m);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await OsIntegration().copyToClipboard(r'C:\a\b.txt');
    final call = calls.firstWhere((c) => c.method == 'Clipboard.setData');
    expect((call.arguments as Map)['text'], r'C:\a\b.txt');
  });
}
