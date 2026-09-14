/// Who this build trusts to sign an update, and where it looks for one.
///
/// Both are set at BUILD time, not compiled in as literals, so a fork is a
/// first-class thing rather than a patch:
///
///     flutter build linux --release \
///       --dart-define=AIRCLONE_UPDATE_REPO=you/yourfork \
///       --dart-define=AIRCLONE_UPDATE_PUBKEY=RWQ...
///
/// CI fills both from repository variables, so a fork sets its own once in its
/// own repository settings and every build it makes afterwards points at itself.
///
/// WHAT HAPPENS WITH NO KEY. The app still checks for a release and still shows
/// what is new - that costs nothing and tells nobody anything they should not
/// know. It will not download or install, because there would be nothing to
/// check the download against. A fork that wants in-app installing signs its own
/// releases; a fork that does not gets the behaviour Airclone has today, which
/// is a link to the releases page. The one thing that must never happen is an
/// unsigned install, so "no key" fails closed.
///
/// The key here is a PUBLIC key. The private half signs one file per release,
/// belongs to a person rather than to CI, and never appears in this repository.
library;

import 'minisign.dart';

/// The repository the update check asks about. A fork overrides it; the default
/// is this project's own.
const String kUpdateRepo = String.fromEnvironment(
  'AIRCLONE_UPDATE_REPO',
  defaultValue: 'GigaionLLC/Airclone',
);

/// The release-signing public key, as minisign writes it (line 2 of a `.pub`).
const String kUpdatePublicKey = String.fromEnvironment(
  'AIRCLONE_UPDATE_PUBKEY',
);

/// A second accepted key, for rotation. During a changeover a release carries a
/// signature from each, so a build that knows either can still update - without
/// which rotating the key would strand everyone running an older build.
const String kUpdatePublicKeyNext = String.fromEnvironment(
  'AIRCLONE_UPDATE_PUBKEY_NEXT',
);

/// The keys this build accepts, parsed. Empty means installs are refused.
///
/// A malformed define yields NO key rather than a broken one: a typo in a build
/// command must not produce a build that trusts something unparseable.
List<MinisignPublicKey> updateTrustedKeys({
  String primary = kUpdatePublicKey,
  String next = kUpdatePublicKeyNext,
}) => [
  for (final raw in [primary, next])
    if (raw.trim().isNotEmpty) ?MinisignPublicKey.parse(raw),
];

/// True when this build can verify a download, and therefore may offer to
/// install one.
bool get kCanVerifyUpdates => updateTrustedKeys().isNotEmpty;

/// Where a release's files live. Built from [kUpdateRepo] so a fork's app never
/// silently downloads this project's builds.
Uri releaseAssetUrl({required String tag, required String asset}) =>
    Uri.https('github.com', '/$kUpdateRepo/releases/download/$tag/$asset');

/// The API endpoint for the newest release of [kUpdateRepo].
Uri latestReleaseApiUrl() =>
    Uri.https('api.github.com', '/repos/$kUpdateRepo/releases/latest');
