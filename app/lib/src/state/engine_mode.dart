/// Which rclone engine Airclone runs.
///
/// Airclone has two [RcloneClient] implementations behind one seam: the spawned
/// `rclone rcd` subprocess (HttpRcloneClient) and the in-process `librclone`
/// engine (FfiRcloneClient). This is the user's preference; the concrete engine
/// is [resolveEngineMode], which folds in platform constraints + availability.
enum EngineMode {
  /// Decide automatically (default): the bundled binary on desktop where a
  /// subprocess is allowed, the in-process library where it is not (iOS / the
  /// Mac App Store) or where no binary is available but the library is bundled.
  auto,

  /// Always the spawned `rclone rcd` subprocess (HttpRcloneClient).
  binary,

  /// Always the in-process librclone engine (FfiRcloneClient) — no subprocess,
  /// no loopback HTTP. UI-labelled "In-process".
  inProcess,
}

/// Parses a persisted [EngineMode] name, defaulting to [EngineMode.auto] for an
/// absent/unknown value (matches the settings store's forgiving enum handling).
EngineMode engineModeFromName(String? name) => switch (name) {
  'binary' => EngineMode.binary,
  'inProcess' => EngineMode.inProcess,
  _ => EngineMode.auto,
};

/// The concrete engine to run, after applying platform constraints + what is
/// actually available. Pure — unit-tested without any I/O.
///
/// - Where a subprocess is disallowed ([subprocessAllowed] false — iOS / MAS),
///   the in-process library is the ONLY legal engine, whatever the setting says.
/// - An explicit [EngineMode.inProcess] is honoured when the library is present,
///   else it falls back to the binary (a friendlier result than a hard failure).
/// - [EngineMode.auto] prefers the binary on desktop, but picks the library when
///   no binary is available and the library is bundled (skips the download).
/// - [EngineMode.binary] always resolves to the binary.
EngineMode resolveEngineMode({
  required EngineMode setting,
  required bool subprocessAllowed,
  required bool libraryAvailable,
  required bool binaryAvailable,
}) {
  if (!subprocessAllowed) return EngineMode.inProcess;
  final wantLibrary =
      setting == EngineMode.inProcess ||
      (setting == EngineMode.auto && !binaryAvailable && libraryAvailable);
  if (wantLibrary && libraryAvailable) return EngineMode.inProcess;
  return EngineMode.binary;
}
