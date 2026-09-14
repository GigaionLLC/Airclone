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
        '--log-input',
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

  /// The native runners, read as text.
  ///
  /// READ THIS BEFORE TRUSTING A PASS. A test that greps C++ proves what the
  /// source SAYS, never that it compiles. The first version of this group
  /// asserted the Linux runner contained `fl_engine_new_headless` - and it
  /// passed happily on a runner calling `fl_engine_start`, a PRIVATE
  /// flutter_linux symbol absent from the public headers, which then failed to
  /// compile in the v0.13.4 release job. This group was enforcing the bug.
  ///
  /// Compilation is `.github/workflows/linux-runner.yml`, which builds the
  /// runner on every change to app/linux and runs `--version` with no display.
  /// What stays here is what text CAN prove: the design, and flag parity.
  group('the native runners', () {
    final flags = ['--webui', '--run-due', '--run-task', '--version', '--help'];

    test('the Linux runner uses no private flutter_linux API', () {
      final f = File('linux/runner/my_application.cc');
      if (!f.existsSync()) return; // not checked out in this context
      final src = f.readAsStringSync();
      // A CALL, with its opening paren. The symbol may still be NAMED in a
      // comment explaining why it is not used, and that is the point of it.
      expect(
        src,
        isNot(contains('fl_engine_start(')),
        reason:
            'fl_engine_start is private to flutter_linux; the public API '
            'cannot start an engine without realizing an FlView',
      );
    });

    /// On Linux Dart cannot answer these without a GL context, so C++ does, and
    /// it must do so BEFORE g_application_register - which is where GTK
    /// initialises and opens the display.
    test('the Linux runner answers --version before GTK starts', () {
      final f = File('linux/runner/my_application.cc');
      if (!f.existsSync()) return;
      final src = f.readAsStringSync();
      final answered = src.indexOf('if (WantsCliInfo(');
      final register = src.indexOf('g_application_register(');
      expect(answered, greaterThan(0), reason: 'the C++ answer is gone');
      expect(register, greaterThan(0));
      expect(
        answered,
        lessThan(register),
        reason:
            'answering after register means GTK has already opened a display',
      );
    });

    /// The reporter's WSL machine had a display and lacked only libGLESv2.
    /// libepoxy aborts the process when it cannot open that exact name, so the
    /// runner checks the same name first and says what to install.
    test('the Linux runner turns a missing GLES library into a message', () {
      final f = File('linux/runner/my_application.cc');
      if (!f.existsSync()) return;
      final src = f.readAsStringSync();
      expect(src, contains('"libGLESv2.so.2"'));
      expect(src, contains('GlesAvailable()'));
      expect(src, contains('apt install libgles2'));
    });

    /// --help is written twice: Dart's usageText for Windows and macOS, and the
    /// C++ PrintHelp for Linux. They cannot share a string, so they are held to
    /// the same flags.
    test('the Linux --help lists every startup flag Dart does', () {
      final f = File('linux/runner/my_application.cc');
      if (!f.existsSync()) return;
      final src = f.readAsStringSync();
      final help = src.substring(src.indexOf('static void PrintHelp()'));
      for (final flag in [...flags, '--webui-bind', '--webui-port']) {
        expect(help, contains(flag), reason: 'Linux --help omits $flag');
        expect(
          usageText('x'),
          contains(flag),
          reason: 'Dart --help omits $flag',
        );
      }
    });

    /// macOS answers --version and --help in Swift, before the engine exists.
    /// THE BUG THIS PINS: it used to reach Dart, which meant starting an engine
    /// inside a view inside a window - and a process launched to ask one
    /// question simply sat there. A CI run waited 25 minutes for a version
    /// string before it was killed.
    test('the macOS runner answers --version without an engine', () {
      final f = File('macos/Runner/AppDelegate.swift');
      if (!f.existsSync()) return;
      final src = f.readAsStringSync();
      expect(src, contains('applicationWillFinishLaunching'));
      expect(src, contains('"--version"'));
      expect(src, contains('"--help"'));
      expect(src, contains('exit(0)'));
    });

    test('the macOS --help lists every startup flag Dart does', () {
      final f = File('macos/Runner/AppDelegate.swift');
      if (!f.existsSync()) return;
      final src = f.readAsStringSync();
      for (final flag in [...flags, '--webui-bind', '--webui-port']) {
        expect(src, contains(flag), reason: 'macOS --help omits $flag');
      }
    });

    /// Flags that need Dart must not show a window on macOS either. Hiding one
    /// is not enough: the engine lives in the window's content view, and AppKit
    /// loads that lazily when the window is about to appear, so a hidden window
    /// is an app that never runs - CI watched --webui sit for 90 seconds
    /// having printed nothing. A windowless run builds no window at all and
    /// starts a headless engine instead.
    test('the macOS runner runs windowless flags without a window', () {
      final delegate = File('macos/Runner/AppDelegate.swift');
      final window = File('macos/Runner/MainFlutterWindow.swift');
      if (!delegate.existsSync() || !window.existsSync()) return;
      final d = delegate.readAsStringSync();
      expect(d, contains('allowHeadlessExecution: true'));
      expect(d, contains('setActivationPolicy(.accessory)'));
      expect(
        d,
        contains('dartEntrypointArguments'),
        reason: 'without argv, --webui would start the ordinary app',
      );

      final w = window.readAsStringSync();
      expect(w, contains('wantsNoWindow'));
      // Every route to the screen, because the nib is visible-at-launch and
      // AppKit orders the window front after awakeFromNib has run.
      expect(w, contains('makeKeyAndOrderFront'));
      expect(w, contains('orderFront'));
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
