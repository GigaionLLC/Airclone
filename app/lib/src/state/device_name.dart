import 'dart:io';

import 'package:flutter/services.dart';

import 'host_platform.dart';

/// This device's own name, for the per-device segment of a backup path.
///
/// **One answer, shared by every backup feature on purpose.** The device
/// segment exists so two machines backing up to one remote do not merge into
/// each other's tree (see `wiki/features/feat-backup.md` §2), and two features
/// that compute it differently defeat that as surely as omitting it: a folder
/// backup and a camera-roll backup from the same phone would land under two
/// different names, and — far worse — two *different* phones can land under the
/// same one.
///
/// That is not hypothetical. `Platform.localHostname` returns the constant
/// `localhost` on Android, so every Android device shares it. The name has to
/// come from the platform instead: `Settings.Global.DEVICE_NAME`, falling back
/// to make + model. Off Android the host name is a real per-machine name and
/// stands in.
///
/// Never throws: this runs inside a setup flow, and any failure yields a usable
/// placeholder rather than an exception the user cannot act on.
Future<String> backupDeviceName() async {
  if (!HostPlatform.isAndroid) {
    try {
      return Platform.localHostname;
    } catch (_) {
      return 'device';
    }
  }
  try {
    const channel = MethodChannel('airclone/native');
    final name = await channel.invokeMethod<String>('deviceName');
    if (name != null && name.trim().isNotEmpty) return name;
  } catch (_) {
    // an old native build without the method
  }
  return 'Android';
}
