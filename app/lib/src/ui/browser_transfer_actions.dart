/// Browser-side file transfer: the Web UI's answer to "Download" and "Upload".
///
/// Everywhere else in Airclone those words mean "move bytes between two remotes
/// the host can see". In a browser they mean something different and narrower:
/// between the remote and *this browser*, over the same session that is already
/// serving the page. This file is the only place that distinction lives.
library;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../rclone/models/remote.dart';
import '../rclone/rclone_client.dart';
import '../rclone/web_rclone_client.dart';
import '../state/engine_controller.dart';

/// Hands each selected file to the browser to save.
///
/// One navigation per file, because a browser's save is per-response: there is
/// no "download these six" without zipping them, which is a different feature
/// with its own memory and cancellation story (see the plan).
///
/// The URL carries `download=1`, which is what makes the server send
/// `Content-Disposition: attachment` — the difference between saving a video and
/// playing it in the tab.
Future<void> downloadToBrowser(
  BuildContext context,
  WidgetRef ref,
  Remote remote,
  List<dynamic> groups,
) async {
  final client = ref.read(engineControllerProvider).client;
  if (client is! WebRcloneClient) return;
  var count = 0;
  for (final g in groups) {
    final parent = (g.parentPath as String);
    for (final f in (g.files as List)) {
      final name = (f as dynamic).name as String;
      final path = parent.isEmpty ? name : '$parent/$name';
      await launchUrl(
        client.downloadUrl(remote.fs, path),
        webOnlyWindowName: '_blank',
      );
      count++;
    }
  }
  if (context.mounted && count > 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          count == 1 ? 'Downloading 1 file.' : 'Downloading $count files.',
        ),
      ),
    );
  }
}

/// Picks a file in the browser and writes it to [remote] under [folderPath].
///
/// Goes through [ObjectUploader], so the UI never learns whether the host
/// streamed the bytes to rclone or staged them first — that is the engine's
/// business and it differs between them.
Future<void> uploadFromBrowser(
  BuildContext context,
  WidgetRef ref,
  Remote remote,
  String folderPath,
) async {
  final picked = await openFile();
  if (picked == null || !context.mounted) return;

  final client = ref.read(engineControllerProvider).client;
  if (client is! ObjectUploader) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This engine cannot accept uploads.')),
    );
    return;
  }

  final name = picked.name;
  final dest = folderPath.isEmpty ? name : '$folderPath/$name';
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(SnackBar(content: Text('Uploading $name…')));
  try {
    final size = await picked.length();
    await (client as ObjectUploader).putObject(
      remote.fs,
      dest,
      picked.openRead(),
      length: size,
    );
    messenger.showSnackBar(SnackBar(content: Text('Uploaded $name.')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Upload failed: $e')));
  }
}
