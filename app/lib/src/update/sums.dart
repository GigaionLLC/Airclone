/// Reading a `SHA256SUMS` manifest, once its signature has been verified.
///
/// The format is `sha256sum`'s own: a 64-character hex digest, two spaces (or a
/// space and an asterisk, which is how `sha256sum -b` writes a binary file), and
/// the file name. rclone publishes the same shape, and Airclone already parses
/// it to verify the engine it bundles.
///
/// LOOK UP BY NAME, ALWAYS. The one attack a signed manifest still allows is
/// substitution WITHIN a release: a manifest legitimately carries a hash for
/// every asset, so a client that accepted "any hash in this file" could be fed
/// the Windows installer as a Linux AppImage, signed and all. Matching the exact
/// asset name is what closes that, which is why there is no "find the hash"
/// helper here - only [hashForAsset].
library;

/// The digest for [asset] in [manifest], or null when the manifest does not
/// mention that file. Null must always be a refusal, never a shrug.
String? hashForAsset(String manifest, String asset) {
  for (final line in manifest.split('\n')) {
    final entry = parseSumsLine(line);
    if (entry == null) continue;
    if (entry.name == asset) return entry.hash;
  }
  return null;
}

/// One parsed line.
class SumsEntry {
  const SumsEntry(this.hash, this.name);

  /// Lower-case hex, 64 characters.
  final String hash;
  final String name;
}

/// Parses a single line. Null for blank lines, comments, and anything whose
/// shape is not exactly right - a manifest is machine-written, so there is no
/// reason to be generous with one that is not.
SumsEntry? parseSumsLine(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty || trimmed.startsWith('#')) return null;

  final space = trimmed.indexOf(' ');
  if (space != 64) return null;
  final hash = trimmed.substring(0, 64).toLowerCase();
  if (!_isHex(hash)) return null;

  // `sha256sum` writes two spaces for a text file and " *" for a binary one.
  var rest = trimmed.substring(space);
  if (rest.startsWith('  ')) {
    rest = rest.substring(2);
  } else if (rest.startsWith(' *')) {
    rest = rest.substring(2);
  } else {
    return null;
  }

  // A name is a bare file name here. A path would mean the manifest is talking
  // about somewhere other than the release's own asset list, and a name with a
  // separator in it is exactly what a path-traversal attempt looks like.
  final name = rest.trim();
  if (name.isEmpty || name.contains('/') || name.contains(r'\')) return null;
  return SumsEntry(hash, name);
}

/// Every entry, in order. For diagnostics and tests; verification itself must
/// go through [hashForAsset] so the name is part of the question.
List<SumsEntry> parseSums(String manifest) => [
  for (final line in manifest.split('\n')) ?parseSumsLine(line),
];

bool _isHex(String s) {
  for (final unit in s.codeUnits) {
    final isDigit = unit >= 0x30 && unit <= 0x39;
    final isLower = unit >= 0x61 && unit <= 0x66;
    if (!isDigit && !isLower) return false;
  }
  return true;
}
