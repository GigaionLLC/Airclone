import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// The running app version (e.g. `0.1.0-alpha.2`), read from the bundle.
final appVersionProvider = FutureProvider<String>(
  (ref) async => (await PackageInfo.fromPlatform()).version,
);

/// Result of comparing the running version against the latest GitHub release.
class UpdateInfo {
  const UpdateInfo({
    required this.hasUpdate,
    required this.currentVersion,
    required this.latestTag,
    required this.url,
  });

  /// True when the latest release tag differs from the running version.
  final bool hasUpdate;

  /// The version this build is running.
  final String currentVersion;

  /// The newest published release tag (e.g. `v0.1.0`).
  final String latestTag;

  /// Browser URL for the latest release.
  final String url;
}

/// GitHub releases endpoint for the Airclone repository.
const _kReleasesUrl =
    'https://api.github.com/repos/GigaionLLC/Airclone/releases/latest';

/// Queries GitHub for the latest release and reports whether it is newer than
/// the running build. Throws on a network/parse failure so the UI can surface it.
final updateCheckProvider = FutureProvider<UpdateInfo>((ref) async {
  final current = (await PackageInfo.fromPlatform()).version;
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
  return UpdateInfo(
    hasUpdate: hasUpdate,
    currentVersion: current,
    latestTag: tag,
    url: url,
  );
});
