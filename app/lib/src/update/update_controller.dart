/// The state of an update the user asked for.
///
/// Nothing here starts by itself. Airclone checks for updates when somebody
/// presses a button and downloads one when they press another, the same way the
/// rclone engine is updated - an app that quietly fetches a hundred megabytes
/// because it noticed a release is an app that decides for you.
///
/// The install half is deliberately narrow: this only offers to install what it
/// can verify (a signing key at build time, `update_trust.dart`) into a package
/// it can replace (`self_update_target.dart`). Everything else keeps today's
/// behaviour - a link to the release page - which is the correct answer for a
/// store build and an honest one everywhere else.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../state/diagnostics.dart';
import '../state/host_platform.dart';
import 'install_appimage.dart';
import 'install_windows.dart';
import 'self_update_target.dart';
import 'update_fetch.dart';
import 'update_trust.dart';

/// Where an update is up to.
@immutable
sealed class UpdateJob {
  const UpdateJob();
}

/// Nothing asked for yet.
class UpdateIdle extends UpdateJob {
  const UpdateIdle();
}

class UpdateDownloading extends UpdateJob {
  const UpdateDownloading({required this.received, this.total});

  final int received;
  final int? total;

  /// Null when the server did not say how big the file is, which is why the UI
  /// has to cope with an indeterminate bar.
  double? get fraction =>
      (total == null || total == 0) ? null : received / total!;
}

/// Downloaded, verified, and waiting to be installed.
class UpdateReady extends UpdateJob {
  const UpdateReady(this.file, {required this.target});

  final File file;
  final SelfUpdateTarget target;

  /// False when the package cannot replace itself yet - the file is still
  /// verified, and the user is told where it is rather than offered a button
  /// that would do nothing.
  bool get canInstall => installableTargets.contains(target);
}

/// The packages that can install over themselves today. The rest download and
/// verify, and say so.
///
/// The Windows portable zip and the macOS app are deliberately absent: both mean
/// replacing a locked directory tree from inside it, which needs a helper
/// process, and a half-finished swap of those costs somebody their install.
const Set<SelfUpdateTarget> installableTargets = {
  SelfUpdateTarget.linuxAppImage,
  SelfUpdateTarget.windowsInstaller,
};

/// The Windows installer is running and needs Airclone closed to finish.
///
/// Airclone does not close itself: an app that vanishes mid-sentence because it
/// was updating is one nobody trusts twice. The installer's own
/// `/CLOSEAPPLICATIONS` will handle a user who ignores this.
class UpdateAwaitingExit extends UpdateJob {
  const UpdateAwaitingExit();
}

/// Installed. The app has to be restarted, and [relaunchPath] is what to start.
class UpdateInstalled extends UpdateJob {
  const UpdateInstalled(this.relaunchPath);

  final String relaunchPath;
}

class UpdateFailed extends UpdateJob {
  const UpdateFailed(this.refusal, {this.detail});

  final UpdateRefusal refusal;
  final String? detail;

  /// What a person is told. Deliberately the same for every way a download can
  /// fail to prove itself: to a user "the signature is wrong" and "the hash is
  /// wrong" mean one thing, which is that this file is not to be trusted. The
  /// distinction goes in the diagnostics log, where it is useful.
  String get message => switch (refusal) {
    UpdateRefusal.notConfigured =>
      'This build cannot check that a download is genuine, so it will not '
          'install one. Download it from the release page instead.',
    UpdateRefusal.network =>
      "The download didn't finish. Check your connection and try again.",
    UpdateRefusal.cannotWrite =>
      'There was nowhere to save the download. Check you have free space.',
    UpdateRefusal.installFailed =>
      'The update downloaded and checked out, but could not be installed. '
          'Your current version is untouched. Install it by hand from the '
          'release page instead.',
    UpdateRefusal.tooLarge ||
    UpdateRefusal.badSignature ||
    UpdateRefusal.wrongRelease ||
    UpdateRefusal.unknownAsset ||
    UpdateRefusal.hashMismatch =>
      "That download didn't match what this release is supposed to contain, so "
          'Airclone stopped and deleted it. Try again, and if it keeps '
          'happening, download from the release page instead.',
  };
}

/// Drives one update at a time.
class UpdateJobController extends Notifier<UpdateJob> {
  @override
  UpdateJob build() => const UpdateIdle();

  /// Download [tag] for this package and verify it. Does not install.
  Future<void> download({
    required String tag,
    required SelfUpdateTarget target,
    required String currentVersion,
    @visibleForTesting UpdateFetcher? fetcher,
  }) async {
    final asset = target.assetName;
    if (asset == null) {
      state = const UpdateFailed(UpdateRefusal.notConfigured);
      return;
    }
    state = const UpdateDownloading(received: 0);

    final UpdateFetcher use;
    try {
      use = fetcher ?? await _defaultFetcher();
    } catch (e) {
      // No application-support directory, or no permission to make one: a
      // refusal with a reason, not an exception escaping into a button press.
      state = UpdateFailed(UpdateRefusal.cannotWrite, detail: '$e');
      return;
    }
    final outcome = await use.fetchAndVerify(
      tag: tag,
      assetName: asset,
      currentVersion: currentVersion,
      onProgress: (received, total) {
        // A late callback after a failure must not resurrect a download.
        if (state is UpdateDownloading) {
          state = UpdateDownloading(received: received, total: total);
        }
      },
    );

    if (!outcome.ok) {
      ref
          .read(diagnosticsProvider.notifier)
          .error(
            'update',
            'refused an update for $tag',
            detail: '${outcome.refusal}: ${outcome.detail ?? ""}',
          );
      state = UpdateFailed(outcome.refusal!, detail: outcome.detail);
      return;
    }
    ref
        .read(diagnosticsProvider.notifier)
        .info('update', 'verified $tag (${outcome.update!.sha256})');
    state = UpdateReady(outcome.update!.file, target: target);
  }

  /// Put a verified download in place, the way this package requires.
  Future<void> install({Map<String, String>? environment}) async {
    final ready = state;
    if (ready is! UpdateReady || !ready.canInstall) return;

    if (ready.target == SelfUpdateTarget.windowsInstaller) {
      final run = await runWindowsInstaller(verified: ready.file);
      if (!run.ok) {
        ref
            .read(diagnosticsProvider.notifier)
            .error(
              'update',
              'could not start the installer',
              detail: '${run.outcome}: ${run.detail ?? ""}',
            );
        state = UpdateFailed(UpdateRefusal.installFailed, detail: run.detail);
        return;
      }
      state = const UpdateAwaitingExit();
      return;
    }

    final result = await installAppImage(
      verified: ready.file,
      environment: environment ?? HostPlatform.environment,
    );
    if (!result.ok) {
      ref
          .read(diagnosticsProvider.notifier)
          .error(
            'update',
            'could not install the update',
            detail: '${result.outcome}: ${result.detail ?? ""}',
          );
      state = UpdateFailed(
        result.outcome == AppImageInstall.notWritable
            ? UpdateRefusal.cannotWrite
            : UpdateRefusal.installFailed,
        detail: result.detail,
      );
      return;
    }
    state = UpdateInstalled(result.imagePath!);
  }

  void reset() => state = const UpdateIdle();

  Future<UpdateFetcher> _defaultFetcher() async {
    final dir = await getApplicationSupportDirectory();
    return UpdateFetcher(
      client: http.Client(),
      // Its own folder, so a half-finished download is never mistaken for
      // anything else and can be cleared wholesale.
      stagingDir: Directory('${dir.path}${Platform.pathSeparator}updates'),
    );
  }
}

final updateJobProvider = NotifierProvider<UpdateJobController, UpdateJob>(
  UpdateJobController.new,
);

/// Whether this build may offer to download and install at all: it needs a key
/// to verify with AND a package it can replace.
bool canOfferSelfUpdate(SelfUpdateTarget target) =>
    kCanVerifyUpdates && target.canSelfUpdate;
