import 'dart:io';

import 'package:airclone/src/headless/cli_info.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reported against the Linux AppImage:
///
/// ```
/// $ ./Airclone-x86_64.AppImage --webui
/// Couldn't open libGLESv2.so.2: cannot open shared object file
/// Aborted (core dumped)
/// $ ./Airclone-x86_64.AppImage --version
/// Couldn't open libGLESv2.so.2: cannot open shared object file
/// ```
///
/// Two separate faults wearing one error message.
///
/// The first is that `--version` did not exist at all - it fell through to the
/// normal GUI launch, which is why it crashed the same way `--webui` did rather
/// than printing anything.
///
/// The second is that the GTK runner built a window and realized an FlView
/// BEFORE Dart ran, and realizing a view creates a GL context. `main.dart`
/// branches on `--webui` before it calls `runApp`, but it never got the chance.
/// On a headless box, a container, or WSL with no GPU stack, that is fatal -
/// which is precisely where somebody runs `--webui`.
///
/// The window half lives in `linux/runner/my_application.cc` and cannot be
/// tested from here. This covers the Dart half, and the flag list they must
/// agree on.
void main() {
  group('the flags that must not open a window', () {
    test('--version and --help are recognised', () {
      expect(isCliInfoInvocation(['--version']), isTrue);
      expect(isCliInfoInvocation(['--help']), isTrue);
      expect(isCliInfoInvocation(['-h']), isTrue);
    });

    test('and are found wherever they sit in the arguments', () {
      expect(isCliInfoInvocation(['--webui', '--version']), isTrue);
      expect(isCliInfoInvocation(['--webui-port', '5799', '-h']), isTrue);
    });

    test('an ordinary launch is not one', () {
      expect(isCliInfoInvocation([]), isFalse);
      expect(isCliInfoInvocation(['--webui']), isFalse);
      expect(isCliInfoInvocation(['--run-due']), isFalse);
    });

    /// Near-misses, because a loose `contains('version')` would swallow these
    /// and silently print usage instead of starting the app.
    test('a flag that merely looks similar is not one', () {
      expect(isCliInfoInvocation(['--versions']), isFalse);
      expect(isCliInfoInvocation(['--version-check']), isFalse);
      expect(isCliInfoInvocation(['--helper']), isFalse);
      expect(isCliInfoInvocation(['version']), isFalse);
    });

    test('help is distinguished from a bare version request', () {
      expect(wantsHelp(['--version']), isFalse);
      expect(wantsHelp(['--help']), isTrue);
      expect(wantsHelp(['-h']), isTrue);
    });
  });

  group('the usage text', () {
    final text = usageText('0.13.4');

    test('names the version it was built for', () {
      expect(text, contains('0.13.4'));
    });

    /// Every flag that changes what the binary does at startup has to appear,
    /// or --help is actively misleading about what the program accepts.
    test('documents every startup flag', () {
      for (final flag in [
        '--webui',
        '--webui-bind',
        '--webui-port',
        '--run-due',
        '--run-task',
        '--version',
        '--help',
      ]) {
        expect(text, contains(flag), reason: '$flag missing from --help');
      }
    });

    /// The bind default is a security-relevant fact: somebody reading --help
    /// should learn that --webui is loopback-only until they say otherwise.
    test('states that --webui is loopback by default', () {
      expect(text, contains('127.0.0.1'));
      expect(text.toLowerCase(), contains('loopback'));
    });

    test('is plain text, not markdown', () {
      expect(text, isNot(contains('```')));
      expect(text, isNot(contains('**')));
    });
  });

  /// The window-suppression list is written THREE times: here in Dart, in
  /// `linux/runner/my_application.cc`, and in `windows/runner/main.cpp`. They
  /// cannot import each other, so this reads the two native files and checks
  /// they still name every flag that must not open a window.
  ///
  /// A drift costs a stray empty window, or on a headless Linux box the crash
  /// this whole change is about - so it is worth a test that reads the C++.
  group('the native runners suppress the same flags', () {
    final flags = ['--webui', '--run-due', '--run-task', '--version', '--help'];

    test('the Linux runner', () {
      final f = File('linux/runner/my_application.cc');
      if (!f.existsSync()) return; // not checked out in this context
      final src = f.readAsStringSync();
      expect(
        src,
        contains('IsWindowlessInvocation'),
        reason: 'the headless branch is gone',
      );
      expect(
        src,
        contains('fl_engine_new_headless'),
        reason: 'a window would be created again, and with it a GL context',
      );
      for (final flag in flags) {
        expect(src, contains('"$flag"'), reason: '$flag would open a window');
      }
    });

    test('the Windows runner', () {
      final f = File('windows/runner/main.cpp');
      if (!f.existsSync()) return;
      final src = f.readAsStringSync();
      for (final flag in flags) {
        expect(src, contains('"$flag"'), reason: '$flag would show a window');
      }
    });
  });
}
