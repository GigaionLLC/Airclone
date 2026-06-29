import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/rclone_file.dart';
import '../rclone/models/remote.dart';
import '../state/engine_controller.dart';
import '../state/folder_preview.dart';
import 'file_icon.dart';

/// A tile that shows a Windows-style folder preview — a composite of the
/// folder's first few images — falling back to [placeholder] (a folder icon)
/// while loading or when the folder contains no thumbnailable images.
class FolderThumbnail extends ConsumerStatefulWidget {
  const FolderThumbnail({
    super.key,
    required this.remote,
    required this.parentPath,
    required this.folder,
    required this.placeholder,
    this.fit = BoxFit.cover,
  });

  final Remote remote;
  final String parentPath;
  final RcloneFile folder;
  final Widget placeholder;
  final BoxFit fit;

  @override
  ConsumerState<FolderThumbnail> createState() => _FolderThumbnailState();
}

class _FolderThumbnailState extends ConsumerState<FolderThumbnail> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final client = ref.read(engineControllerProvider).client;
      if (client == null) return;

      final remote = widget.remote;
      final folder = widget.folder;
      final folderPath = widget.parentPath.isEmpty
          ? folder.name
          : '${widget.parentPath}/${folder.name}';

      final res = await client.rpc(
        'operations/list',
        remote.listParams(folderPath),
      );
      if (!mounted) return;

      final list = (res['list'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(RcloneFile.fromJson)
          .toList();

      final images = list
          .where((e) => !e.isDir && isImageThumbnailable(e))
          .take(4)
          .toList();
      if (images.isEmpty) return;

      final refs = images.map((e) {
        final o = client.objectRef(remote.fs, '$folderPath/${e.name}');
        return FolderImageRef(url: o.url, headers: o.headers);
      }).toList();

      final key = folderThumbCacheKey(
        remote.fs,
        folderPath,
        folder.modTime,
        list.length,
      );
      final bytes = await ref
          .read(folderPreviewServiceProvider)
          .compose(cacheKey: key, images: refs, remoteSecret: remote.name);
      if (bytes != null && mounted) {
        setState(() => _bytes = bytes);
      }
    } catch (_) {
      // Keep the placeholder on any failure.
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: bytes == null
          ? KeyedSubtree(
              key: const ValueKey('placeholder'),
              child: widget.placeholder,
            )
          : Image.memory(
              bytes,
              key: const ValueKey('preview'),
              fit: widget.fit,
              gaplessPlayback: true,
              width: double.infinity,
              height: double.infinity,
            ),
    );
  }
}
