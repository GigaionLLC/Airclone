import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'install_source.dart';

/// The running app version (e.g. `0.1.0-alpha.2`), read from the bundle.
final appVersionProvider = FutureProvider<String>(
  (ref) async => (await PackageInfo.fromPlatform()).version,
);

/// The outcome of "Check for updates", which takes one of exactly two shapes
/// depending on how this copy was installed (see install_source.dart).
///
/// Sealed on purpose: every consumer must handle the store-managed case
/// explicitly, so a Store build can never fall through to rendering a download
/// link. That fall-through is what failed Microsoft Store certification for
/// v0.6.0 under policy 10.2.5.
@immutable
sealed class UpdateStatus {
  const UpdateStatus({required this.currentVersion, required this.source});

  /// The version this build is running.
  final String currentVersion;

  /// Where this copy came from, and therefore where its updates come from.
  final InstallSource source;
}

/// The install is managed by a platform store, which delivers updates itself.
/// Airclone deliberately performs NO version check here: it must not tell the
/// user about a version the store hasn't shipped yet, and must not link them
/// anywhere they could install one out of band.
class StoreManagedUpdates extends UpdateStatus {
  const StoreManagedUpdates({
    required super.currentVersion,
    required super.source,
  });
}

/// A direct download (installer, portable zip, sideloaded APK, dmg, tarball).
/// These builds have no store behind them, so Airclone checks the GitHub
/// release itself — the behaviour every non-store user installed it for.
class ReleaseUpdateInfo extends UpdateStatus {
  const ReleaseUpdateInfo({
    required super.currentVersion,
    required super.source,
    required this.hasUpdate,
    required this.latestTag,
    required this.url,
  });

  /// True when the latest release tag differs from the running version.
  final bool hasUpdate;

  /// The newest published release tag (e.g. `v0.1.0`).
  final String latestTag;

  /// Browser URL for the latest release.
  final String url;
}

/// GitHub releases endpoint for the Airclone repository.
const _kReleasesUrl =
    'https://api.github.com/repos/GigaionLLC/Airclone/releases/latest';

/// Resolves the update situation for this install.
///
/// Store-managed installs short-circuit BEFORE any network call — the request
/// to GitHub is not merely hidden from the UI, it never happens. Direct
/// downloads query the latest release and report whether it is newer, throwing
/// on a network/parse failure so the UI can surface it.
final updateCheckProvider = FutureProvider<UpdateStatus>((ref) async {
  final current = (await PackageInfo.fromPlatform()).version;
  final source = await ref.watch(installSourceProvider.future);
  if (source.managedByStore) {
    return StoreManagedUpdates(currentVersion: current, source: source);
  }
  final res = await http.get(
    Uri.parse(_kReleasesUrl),
    headers: const {'User-Agent': 'airclone'},
  );
  if (res.statusCode != 200) {
    throw Exception('Update check failed (HTTP ${res.statusCode}).');
  }
  final json = jsonDecode(res.body) as Map<String, dynamic>;
  final tag = (json['tag_name'] as String?) ?? '';
  final url = (json['html_url'] as String?) ?? '';
  // A release counts as an update when its tag doesn't contain our version.
  final hasUpdate = tag.isNotEmpty && !tag.contains(current);
  return ReleaseUpdateInfo(
    currentVersion: current,
    source: source,
    hasUpdate: hasUpdate,
    latestTag: tag,
    url: url,
  );
});
