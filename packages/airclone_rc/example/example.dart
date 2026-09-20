// Drive rclone from Dart, both ways, and list a directory.
//
//   dart run example/example.dart --rclone C:/tools/rclone.exe .
//   dart run example/example.dart --librclone build/librclone.dll .
//
// The first spawns `rclone rcd` and talks to it over loopback HTTP; the second
// loads librclone into this process. Everything after `client` is the same
// code, which is the whole point of the seam.
import 'dart:io';

import 'package:airclone_rc/airclone_rc.dart';

Future<void> main(List<String> args) async {
  final rclone = _option(args, '--rclone');
  final librclone = _option(args, '--librclone');
  final target = args.isEmpty ? '.' : args.last;

  if (rclone == null && librclone == null) {
    stderr.writeln('Pass --rclone <path to rclone> or --librclone <path to lib>.');
    stderr.writeln('This package ships neither: you bring your own.');
    exitCode = 64;
    return;
  }

  final RcloneClient client = rclone != null
      ? HttpRcloneClient(
          // Required, and never 'airclone'. It names the PID markers this
          // client writes to the temp dir, and the orphan reaper kills the
          // PIDs in the markers carrying its own tag. Share a tag with another
          // app and you kill its engine.
          instanceTag: 'example',
          rclonePath: rclone,
          // Engine failures are dropped unless you ask for them — these lines
          // can carry the rc credentials.
          logSink: (level, area, message, {detail}) =>
              stderr.writeln('[$level] $area: $message'),
        )
      : FfiRcloneClient(libraryPath: librclone!);

  await client.start();
  try {
    final version = await client.rpc('core/version');
    stdout.writeln('rclone ${version['version']}');

    // A local directory is just another rclone filesystem, so this works with
    // no config at all. Point `fs` at 'gdrive:' and it is the same call.
    final listing = await client.rpc('operations/list', {
      'fs': Directory(target).absolute.path,
      'remote': '',
    });
    for (final item in (listing['list'] as List)) {
      final file = RcloneFile.fromJson(item as Map<String, dynamic>);
      stdout.writeln('${file.isDir ? 'd' : '-'} ${file.size}\t${file.name}');
    }
  } finally {
    await client.quit();
  }
}

String? _option(List<String> args, String name) {
  final i = args.indexOf(name);
  return (i < 0 || i + 1 >= args.length) ? null : args[i + 1];
}
