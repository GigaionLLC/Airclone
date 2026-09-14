/// Comparing two Airclone versions.
///
/// THE BUG THIS FIXES. The update check asked whether the latest release tag
/// CONTAINED the running version (`app_info.dart`: `!tag.contains(current)`).
/// `v0.9.10` contains `0.9.1`, so a user on 0.9.1 was told they were up to date
/// for the whole of 0.9.10's life - and `v0.13.6` contains `0.13.6`, which is
/// the only reason the check ever appeared to work. Substring matching is not
/// version comparison.
///
/// Semver, with the parts this project actually uses: an optional `v`, three
/// numbers, an optional `-prerelease` (alpha.84, beta.3, rc.1 all shipped), and
/// build metadata after `+` which is ignored - `0.13.6+141` and `0.13.6+142`
/// are the same release, differing only in the build number the stores need.
///
/// A prerelease is LOWER than the release it leads to (`0.14.0-rc.1 < 0.14.0`),
/// which is what stops someone on a release candidate being offered a
/// "downgrade" to the final build - and, more importantly, what makes an
/// updater able to tell "newer" from "different".
library;

/// A parsed version. Null from [parseAppVersion] means "not a version", and
/// callers must treat that as "cannot tell", never as "up to date".
class AppVersion {
  const AppVersion(this.major, this.minor, this.patch, this.prerelease);

  final int major;
  final int minor;
  final int patch;

  /// The dot-separated identifiers after `-`, empty for a final release.
  final List<String> prerelease;

  bool get isPrerelease => prerelease.isNotEmpty;

  @override
  String toString() => [
    '$major.$minor.$patch',
    if (prerelease.isNotEmpty) '-${prerelease.join('.')}',
  ].join();
}

/// Parses `v0.13.6`, `0.13.6+141`, `v0.14.0-rc.1`. Null when it is not one.
AppVersion? parseAppVersion(String raw) {
  var s = raw.trim();
  if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
  // Build metadata is not part of ordering, by the spec and by common sense:
  // the store build number changes without the release changing.
  final plus = s.indexOf('+');
  if (plus >= 0) s = s.substring(0, plus);
  if (s.isEmpty) return null;

  List<String> pre = const [];
  final dash = s.indexOf('-');
  if (dash >= 0) {
    final tail = s.substring(dash + 1);
    if (tail.isEmpty) return null;
    pre = tail.split('.');
    if (pre.any((p) => p.isEmpty)) return null;
    s = s.substring(0, dash);
  }

  final parts = s.split('.');
  if (parts.length != 3) return null;
  final numbers = <int>[];
  for (final p in parts) {
    // Digits only: int.tryParse would accept "+5" and " 5", and a version that
    // parsed loosely here would compare confidently against nothing real.
    if (p.isEmpty || !_digitsOnly(p)) return null;
    final n = int.tryParse(p);
    if (n == null) return null;
    numbers.add(n);
  }
  return AppVersion(numbers[0], numbers[1], numbers[2], pre);
}

/// Negative when [a] is older than [b], zero when they are the same release,
/// positive when [a] is newer. Unparseable input sorts as older than anything
/// parseable, and two unparseable versions compare equal - so "I cannot read
/// this" never comes out as "you are up to date" on its own.
int compareAppVersions(String a, String b) {
  final x = parseAppVersion(a);
  final y = parseAppVersion(b);
  if (x == null && y == null) return 0;
  if (x == null) return -1;
  if (y == null) return 1;

  final byNumber = [
    x.major.compareTo(y.major),
    x.minor.compareTo(y.minor),
    x.patch.compareTo(y.patch),
  ].firstWhere((c) => c != 0, orElse: () => 0);
  if (byNumber != 0) return byNumber;

  // A release beats its own prereleases; two finals are equal.
  if (x.prerelease.isEmpty && y.prerelease.isEmpty) return 0;
  if (x.prerelease.isEmpty) return 1;
  if (y.prerelease.isEmpty) return -1;
  return _comparePrerelease(x.prerelease, y.prerelease);
}

/// True when [candidate] is a strictly newer release than [current]. The one
/// question an update check actually asks, and the one place the answer should
/// be decided - an updater that offered anything "different" would happily walk
/// a user backwards.
bool isNewerAppVersion({required String candidate, required String current}) =>
    compareAppVersions(candidate, current) > 0;

int _comparePrerelease(List<String> a, List<String> b) {
  for (var i = 0; i < a.length && i < b.length; i++) {
    final x = a[i];
    final y = b[i];
    final xn = int.tryParse(x);
    final yn = int.tryParse(y);
    if (xn != null && yn != null) {
      final c = xn.compareTo(yn);
      if (c != 0) return c;
      continue;
    }
    // Numeric identifiers are lower than alphanumeric ones (semver §11.4.3),
    // which is why beta.2 < beta.rc and alpha.84 < alpha.x.
    if (xn != null) return -1;
    if (yn != null) return 1;
    final c = x.compareTo(y);
    if (c != 0) return c;
  }
  // Everything equal so far: more identifiers means a later prerelease.
  return a.length.compareTo(b.length);
}

bool _digitsOnly(String s) {
  for (final unit in s.codeUnits) {
    if (unit < 0x30 || unit > 0x39) return false;
  }
  return true;
}
