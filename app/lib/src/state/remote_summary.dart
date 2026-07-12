/// A best-effort, human-readable "endpoint" for a remote's config [section] — the
/// first location-ish key present (host, url, …), formatted `key: value`.
///
/// Surfacing this in an import review is a config-portability plan §5 requirement:
/// an import source can be swapped or poisoned (a picked QR image, or any file, is
/// untrusted), and showing the endpoint means a remote silently re-pointed at an
/// attacker's target is visible in the mandatory review before anything is
/// written. The key list is deliberately location-only — it NEVER surfaces a
/// secret (tokens, passwords, keys are not in it). Returns '' when the section has
/// no location-ish key to show.
///
/// Shared by both import reviews (the desktop file/QR dialog and the phone camera
/// scan) so they present the same information.
String remoteEndpointSummary(Map<String, String> section) {
  for (final k in const [
    'host',
    'url',
    'endpoint',
    'remote',
    'account',
    'region',
    'provider',
  ]) {
    final v = section[k];
    if (v != null && v.isNotEmpty) return '$k: $v';
  }
  return '';
}
