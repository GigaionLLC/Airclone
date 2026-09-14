/// `--version` and `--help`: the two things a command-line tool is expected to
/// answer without doing anything else.
///
/// Airclone is a GUI first, so these did not exist. That was not merely a
/// missing nicety: passing ANY flag still booted the whole GUI stack, and on a
/// machine without a display that is fatal. A user running the Linux AppImage
/// got this from `--version`:
///
/// ```
/// Couldn't open libGLESv2.so.2: cannot open shared object file
/// ```
///
/// The window is stopped in the platform runners (see
/// `linux/runner/my_application.cc`); this is what answers once Dart is
/// running, with no engine, no window and no rclone.
///
/// Pure except for the write itself, so the text is unit-testable.
library;

import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

/// `--version`: print the version and exit 0.
const String kVersionFlag = '--version';

/// `--help` / `-h`: print usage and exit 0.
const String kHelpFlag = '--help';
const String kHelpFlagShort = '-h';

/// True when [args] asks for version or usage.
///
/// Checked before every other branch in `main()`, because answering "what
/// version are you" must never depend on an engine starting, a config loading,
/// or a display existing.
bool isCliInfoInvocation(List<String> args) {
  for (final a in args) {
    if (a == kVersionFlag || a == kHelpFlag || a == kHelpFlagShort) return true;
  }
  return false;
}

/// Whether [args] asked for usage rather than the bare version.
bool wantsHelp(List<String> args) =>
    args.contains(kHelpFlag) || args.contains(kHelpFlagShort);

/// The usage text. A deliberately SHORT list: only the flags that change what
/// the binary does on startup, not every setting reachable once it is running.
///
/// `--run-task` and `--run-due` are included even though the OS scheduler is
/// their only real caller, because somebody reading a crontab or a systemd unit
/// will find them there and come here to ask what they are.
String usageText(String version) =>
    '''
Airclone $version - a desktop and mobile interface for rclone.

Usage: airclone [options]

With no options, Airclone opens its window.

Options:
  --webui                 Serve the interface to browsers instead of opening a
                          window. Prints its URL and the generated password on
                          first run. (On Linux no window is shown either, but
                          the engine still needs a display server: run it under
                          xvfb-run on a machine with none.)
  --webui-bind ADDRESS    Address for --webui to listen on. Default 127.0.0.1
                          (loopback only). Use 0.0.0.0 to accept connections
                          from the network, which is a deliberate choice.
  --webui-port PORT       Port for --webui. Default 5799.

  --run-due               Run every scheduled task that is due, then exit. This
                          is what the OS scheduler invokes; it opens no window.
  --run-task ID           Run one saved task by id, then exit.

  --log-input             Print one line per key event, and whether a text
                          field had focus to receive it. For working out why a
                          machine will not type. Changes nothing else.

  --version               Print the version and exit.
  --help, -h              Print this and exit.

Everything else - remotes, transfers, mounts, schedules - is configured in the
interface, not here.

Documentation: https://github.com/GigaionLLC/Airclone
''';

/// Answers `--version` / `--help` on stdout and exits.
///
/// Never returns. Exits 0 in both cases: being asked for the version is not an
/// error, and a shell script doing `airclone --version || exit 1` should not
/// trip over it.
Future<Never> runCliInfo(List<String> args) async {
  // PackageInfo rather than a constant, so this cannot drift from the version
  // the app reports everywhere else. It reads bundled metadata, not the
  // network, and needs no window.
  var version = 'unknown';
  try {
    version = (await PackageInfo.fromPlatform()).version;
  } catch (_) {
    // A build where the bundle metadata is unreadable should still answer, and
    // "unknown" is a better answer than a stack trace on stderr.
  }
  stdout.write(wantsHelp(args) ? usageText(version) : 'Airclone $version\n');
  exit(0);
}
