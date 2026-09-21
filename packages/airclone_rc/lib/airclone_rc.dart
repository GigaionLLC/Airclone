/// Drive rclone from Dart, over its remote-control (rc) API.
///
/// One seam, [RcloneClient], with two implementations that differ entirely in
/// HOW they reach rclone and not at all in what a caller writes:
///
///   * [HttpRcloneClient] spawns `rclone rcd` on loopback with per-session
///     credentials and drives it over HTTP;
///   * [FfiRcloneClient] runs `librclone` in-process through `dart:ffi`, which
///     is the only legal engine on iOS and the Mac App Store.
///
/// This package ships no rclone. The host supplies the binary or the shared
/// library — see the README.
///
/// **The interface does not grow.** New abilities arrive as separate capability
/// interfaces ([ObjectUploader] is the precedent), because every fake and every
/// outside implementation of [RcloneClient] would otherwise have to grow a
/// member it does not care about. A typed API will sit OVER [RcloneClient.rpc]
/// for the same reason.
library;

export 'src/oauth_flow.dart';
export 'src/ffi_rclone_client.dart';
export 'src/http_rclone_client.dart';
export 'src/librclone_ffi.dart';
export 'src/librclone_object_server.dart';
export 'src/models/mount_info.dart';
export 'src/models/provider.dart';
export 'src/models/rclone_file.dart';
export 'src/models/serve_server.dart';
export 'src/models/transfer_item.dart';
export 'src/models/transferred_item.dart';
export 'src/playlist_exts.dart';
export 'src/rc_api.dart';
export 'src/rc_options.dart';
export 'src/rclone_client.dart';
export 'src/rclone_log.dart';
export 'src/windows_child_job.dart';

// src/platform.dart is deliberately NOT exported: a host has its own answer to
// "which OS is this", and this one exists only so the engine layer need not ask
// the app.
