/// Whether this Flatpak may run commands on the host - which is what mounting a
/// drive from inside the sandbox requires.
///
/// A drive mounted inside a Flatpak is visible only to that Flatpak, so Airclone
/// mounts through a small fusermount wrapper that runs on the HOST
/// (app/linux/packaging/fusermount-wrapper.sh). Reaching the host takes
/// `flatpak-spawn --host`, and that takes a permission which lets the app run
/// ANY command on the host, not only the mount. Airclone does not request it:
/// Flathub will not accept an app that declares it, and silently granting it to
/// every user of the GitHub bundle would be worse than recommending the AppImage.
/// A user who wants mounting grants it themselves, having been told what it
/// allows.
///
/// This reads what they granted. `/.flatpak-info` is written by Flatpak at launch
/// with the app's EFFECTIVE permissions - the manifest merged with every
/// `flatpak override` and Flatseal change - so it is the authoritative answer, it
/// needs no subprocess, and it cannot change for the life of the process. A
/// change takes effect on the next launch, which the UI says.
///
/// Precedent, and why this is worth doing carefully: rclone-manager, an rclone GUI
/// on Flathub, mounts exactly this way. Its users hit `fusermount: exit status 1`
/// with no explanation, spent hours, and some switched to its AppImage, before
/// its maintainer documented the permission (Zarestia-Dev/rclone-manager#52,
/// #113). The difference here is checking first and explaining up front.
library;

import 'dart:io';

import 'build_flavor.dart';
import 'host_platform.dart';

/// The D-Bus name that grants `flatpak-spawn --host`.
const String kFlatpakHostSpawnName = 'org.freedesktop.Flatpak';

/// Whether a `/.flatpak-info` grants host command access.
///
/// Two routes grant it, and users take both:
///   - `[Session Bus Policy]` with `org.freedesktop.Flatpak` at `talk` or `own`,
///     which is what `flatpak override --talk-name=org.freedesktop.Flatpak`
///     writes, including through a wildcard such as `org.freedesktop.*`;
///   - `[Context] sockets=` containing `session-bus`, which is Flatseal's "D-Bus
///     session bus" toggle - unfiltered access to the whole bus, a broader grant
///     that includes this name. An rclone-manager user fixed mounting with exactly
///     that toggle.
///
/// `see` and `none` do not grant it, and `!session-bus` explicitly removes the
/// socket. Anything unparseable is treated as NOT granted: guessing yes would
/// offer a mount that then fails at the first step.
bool flatpakHostCommandsAllowed(String flatpakInfo) {
  var section = '';
  for (final rawLine in flatpakInfo.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) continue;
    if (line.startsWith('[') && line.endsWith(']')) {
      section = line.substring(1, line.length - 1).trim();
      continue;
    }
    final eq = line.indexOf('=');
    if (eq <= 0) continue;
    final key = line.substring(0, eq).trim();
    final value = line.substring(eq + 1).trim();

    if (section == 'Session Bus Policy' && _nameMatches(key)) {
      if (value == 'talk' || value == 'own') return true;
    }
    if (section == 'Context' && key == 'sockets') {
      final sockets = value.split(';').map((s) => s.trim());
      if (sockets.contains('session-bus')) return true;
    }
  }
  return false;
}

/// Whether a policy key covers [kFlatpakHostSpawnName], exactly or by a
/// trailing `.*` wildcard as Flatpak allows.
bool _nameMatches(String key) {
  if (key == kFlatpakHostSpawnName) return true;
  if (key.endsWith('.*')) {
    final prefix = key.substring(0, key.length - 1); // keep the dot
    return kFlatpakHostSpawnName.startsWith(prefix);
  }
  return false;
}

/// [flatpakHostCommandsAllowed] for the running process, read once.
///
/// Cached because the answer cannot change during a run: Flatpak fixes the
/// sandbox's permissions at launch.
bool get kFlatpakHostCommandsAllowed => _cached ??= _readOnce();
bool? _cached;

bool _readOnce() {
  // A browser has no /.flatpak-info and must never try: the Web UI compiles
  // this file too.
  if (HostPlatform.isWeb || !kRunningInFlatpak) return false;
  try {
    return flatpakHostCommandsAllowed(
      File('/.flatpak-info').readAsStringSync(),
    );
  } catch (_) {
    return false;
  }
}

/// The command that takes the permission away again.
///
/// `--no-talk-name` for this one name and this one app. NOT `--reset`: without
/// an app ID, `flatpak override --user --reset` wipes that user's overrides for
/// every Flatpak they have, which an earlier draft of the mount dialog suggested.
String flatpakHostAccessRevokeCommand({String? appId}) {
  final id = appId ?? HostPlatform.environment['FLATPAK_ID'];
  return 'flatpak override --user --no-talk-name=$kFlatpakHostSpawnName '
      '${(id == null || id.isEmpty) ? 'com.gigaionllc.airclone' : id}';
}

/// The command that grants the permission, for this app's real Flatpak ID.
///
/// `--user`, not system-wide: it affects only the person who ran it, and needs
/// no administrator password.
String flatpakHostAccessCommand({String? appId}) {
  final id = appId ?? HostPlatform.environment['FLATPAK_ID'];
  return 'flatpak override --user --talk-name=$kFlatpakHostSpawnName '
      '${(id == null || id.isEmpty) ? 'com.gigaionllc.airclone' : id}';
}
