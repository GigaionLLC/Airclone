/// `airclone --update` — the same update the app offers, from a terminal.
///
/// Modelled on `rclone selfupdate`, which the people who use this already know:
/// `--check` looks without touching anything, `--version` asks for a particular
/// release, `--output` saves the file instead of installing it, and a successful
/// update prints what it came from as well as what it went to.
///
/// WHAT IT WILL NOT DO, and why each one matters:
///
///   * **A store-installed copy is refused outright.** The Microsoft Store,
///     Google Play, the App Store, Flathub and Snap deliver their own updates,
///     and their rules forbid an app going around them - Airclone's v0.6.0
///     submission failed certification for merely linking to a download. The
///     refusal names the store instead.
///   * **A build with no signing key is refused.** Without one there is nothing
///     to check a download against, and installing something unverified is worse
///     than not updating at all.
///   * **A package that cannot replace itself does not pretend to.** It
///     downloads, verifies, and tells you where the file is - which is the
///     honest version of "done", and exactly what `--output` is for.
///
/// Everything it does install has been through the same checks the app uses:
/// the signature over the release's checksum manifest first, then the manifest's
/// hash for this exact asset (update/update_fetch.dart).
library;

import 'dart:io';

import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../state/host_platform.dart';
import '../state/install_source.dart';
import '../update/install_appimage.dart';
import '../update/install_windows.dart';
import '../update/self_update_target.dart';
import '../update/update_controller.dart';
import '../update/update_fetch.dart';
import '../update/update_trust.dart';
import '../update/version_compare.dart';

/// The flag that starts all this.
const String kUpdateFlag = '--update';

/// Look, do not touch. `rclone selfupdate --check` means the same.
const String kUpdateCheckFlag = '--check';

/// Save the verified file here instead of installing it.
const String kUpdateOutputFlag = '--output';

/// Install this release rather than the newest one.
const String kUpdateVersionFlag = '--version-tag';

const int kUpdateOk = 0;
const int kUpdateFailed = 1;

/// Whether [args] ask for an update. Kept in step with the native runners, which
/// scan for the same flag to keep the window off the screen.
bool isUpdateInvocation(List<String> args) => args.contains(kUpdateFlag);

/// What the flags asked for. Pure, so the parsing is tested without a network.
class UpdateCliOptions {
  const UpdateCliOptions({this.checkOnly = false, this.output, this.tag});

  /// Report what would happen and stop.
  final bool checkOnly;

  /// Where to put the verified file instead of installing it.
  final String? output;

  /// A specific release, or null for the newest.
  final String? tag;
}

/// Parses `--check`, `--output <path>` and `--version-tag <tag>`.
///
/// A value that looks like another flag is treated as missing rather than
/// consumed: `--output --check` should not write a file called `--check`.
UpdateCliOptions parseUpdateArgs(List<String> args) {
  String? valueAfter(String flag) {
    final i = args.indexOf(flag);
    if (i < 0 || i + 1 >= args.length) return null;
    final v = args[i + 1];
    if (v.startsWith('-') || v.isEmpty) return null;
    return v;
  }

  return UpdateCliOptions(
    checkOnly: args.contains(kUpdateCheckFlag),
    output: valueAfter(kUpdateOutputFlag),
    tag: valueAfter(kUpdateVersionFlag),
  );
}

/// Everything the CLI needs from the outside world, so a test can supply all of
/// it and none of it has to be real.
class UpdateCliEnvironment {
  const UpdateCliEnvironment({
    required this.currentVersion,
    required this.source,
    required this.target,
    required this.latestTag,
    required this.fetcher,
    this.trustedKeyCount = 1,
    this.processEnvironment = const {},
  });

  final String currentVersion;
  final InstallSource source;
  final SelfUpdateTarget target;

  /// Null when the release could not be asked for at all.
  final Future<String?> Function() latestTag;

  final UpdateFetcher Function() fetcher;

  /// Zero means this build cannot verify anything, so it must not install.
  final int trustedKeyCount;

  /// For the AppImage install, which needs `APPIMAGE`.
  final Map<String, String> processEnvironment;
}

/// Runs the update and returns a process exit code. Writes plain lines - this is
/// read in a terminal, and by scripts.
Future<int> runUpdateCli(
  List<String> args,
  UpdateCliEnvironment env, {
  void Function(String line)? out,
}) async {
  final write = out ?? stdout.writeln;
  final options = parseUpdateArgs(args);
  final package = env.target == SelfUpdateTarget.unsupported
      ? env.source.channel.name
      : env.target.name;
  write('Airclone ${env.currentVersion} ($package)');

  // A store owns its updates. First, and before any network call: a store build
  // must not even ask GitHub what exists.
  if (env.source.managedByStore) {
    write('This copy updates through ${env.source.storeName}.');
    write('Open it there to get the newest version.');
    return kUpdateFailed;
  }

  if (env.trustedKeyCount == 0) {
    write(
      'This build has no release key, so it cannot check that a download is '
      'genuine - and it will not install one it cannot check.',
    );
    write('Download it from the releases page instead.');
    return kUpdateFailed;
  }

  final tag = options.tag ?? await env.latestTag();
  if (tag == null || tag.isEmpty) {
    write('Could not find out what the newest release is.');
    return kUpdateFailed;
  }

  if (options.tag == null &&
      !isNewerAppVersion(candidate: tag, current: env.currentVersion)) {
    write('You are up to date.');
    return kUpdateOk;
  }

  write('Latest: $tag');
  if (options.checkOnly) {
    write('Run `airclone --update` to install it.');
    return kUpdateOk;
  }

  final asset = env.target.assetName;
  if (asset == null) {
    write('This package cannot be updated from here.');
    return kUpdateFailed;
  }

  write('Downloading $asset');
  final outcome = await env.fetcher().fetchAndVerify(
    tag: tag,
    assetName: asset,
    // A specific --version-tag is allowed to be older; the newest is not.
    currentVersion: options.tag != null ? '0.0.0' : env.currentVersion,
  );
  if (!outcome.ok) {
    write(UpdateFailed(outcome.refusal!).message);
    return kUpdateFailed;
  }
  final verified = outcome.update!;
  write('Verified: signature and checksum');

  // --output means "give me the file", and that is the whole job.
  if (options.output != null) {
    try {
      final saved = await verified.file.copy(options.output!);
      write('Saved ${saved.path}');
      return kUpdateOk;
    } catch (e) {
      write('Could not save it there: $e');
      return kUpdateFailed;
    }
  }

  switch (env.target) {
    case SelfUpdateTarget.linuxAppImage:
      final result = await installAppImage(
        verified: verified.file,
        environment: env.processEnvironment,
      );
      if (!result.ok) {
        write(_appImageProblem(result));
        write('Your current version is untouched: ${verified.file.path}');
        return kUpdateFailed;
      }
      write('Updated Airclone from ${env.currentVersion} to $tag');
      write('The previous version is at ${result.backupPath}');
      return kUpdateOk;

    case SelfUpdateTarget.windowsInstaller:
      final run = await runWindowsInstaller(verified: verified.file);
      if (!run.ok) {
        write('Could not start the installer: ${run.detail ?? run.outcome}');
        write('Your current version is untouched: ${verified.file.path}');
        return kUpdateFailed;
      }
      write(
        'The installer is running. Airclone will close to finish updating.',
      );
      return kUpdateOk;

    default:
      // Verified, but this package cannot replace itself: say so, and say where
      // the file is. `--output` exists to make that the intended outcome.
      write('This package cannot replace itself, so nothing was installed.');
      write('The verified download is at ${verified.file.path}');
      return kUpdateFailed;
  }
}

String _appImageProblem(AppImageInstallResult result) =>
    switch (result.outcome) {
      AppImageInstall.notWritable =>
        'Cannot write to the folder the AppImage is in. Move it somewhere you '
            'own, or run the update as the user that owns it.',
      AppImageInstall.notAnAppImage =>
        'This does not look like a running AppImage (no APPIMAGE in the '
            'environment), so there is nothing to replace.',
      AppImageInstall.failed || AppImageInstall.replaced =>
        'Could not put the new version in place: ${result.detail ?? "unknown"}',
    };

/// The production wiring: real install source, real network, real staging dir.
///
/// Never returns - like the other CLI entry points, it owns the process from
/// here.
Future<Never> runUpdateCliAndExit(List<String> args) async {
  // The binding, because PackageInfo reads it - and nothing else here needs a
  // frame, a window or a widget tree.
  WidgetsFlutterBinding.ensureInitialized();
  final source = await detectInstallSource();
  final version = (await PackageInfo.fromPlatform()).version;
  final target = currentSelfUpdateTarget(source);
  final code = await runUpdateCli(
    args,
    UpdateCliEnvironment(
      currentVersion: version,
      source: source,
      target: target,
      latestTag: () => newestReleaseTag(),
      fetcher: () => UpdateFetcher(
        client: http.Client(),
        stagingDir: Directory.systemTemp.createTempSync('airclone-update'),
      ),
      trustedKeyCount: updateTrustedKeys().length,
      processEnvironment: HostPlatform.environment,
    ),
  );
  exit(code);
}
