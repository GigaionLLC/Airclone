import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/browser_controller.dart';
import '../state/file_ops.dart';
import '../state/thumbnail_prefs.dart';
import 'column_header.dart';
import 'file_op_dialogs.dart';
import 'folder_tools.dart';
import 'storage_breakdown.dart';
import 'theme/tokens.dart';

/// A touch-friendly "all features" bottom sheet for the phone shell — it surfaces
/// the desktop command surface (New folder · Sort · Thumbnails · Tools) that the
/// slim phone header can't show inline. Every action reuses the exact desktop
/// handler.
///
/// [context] and [ref] are the CALLER's (the mounted header): live display state
/// is read through a local [Consumer] so sort/thumbnail toggles update in place,
/// while dialog actions pop the sheet first and then run against the caller's
/// still-mounted context/ref.
Future<void> showMobileFeaturesSheet(
  BuildContext context,
  WidgetRef ref,
  int index,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => Consumer(
      builder: (_, wref, _) {
        final c = AircloneTheme.of(sheetContext);
        final state = wref.watch(paneProvider(index));
        final ctrl = wref.read(paneProvider(index).notifier);
        final remote = state.remote;
        final hasRemote = remote != null;
        final disabled = wref.watch(thumbnailsDisabledProvider);
        final thumbsToggleable = hasRemote && !remote.isLocal;
        final thumbsOn = hasRemote && thumbnailsOn(remote, disabled);

        void close() => Navigator.pop(sheetContext);

        Widget label(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.x4,
            Space.x3,
            Space.x4,
            Space.x1,
          ),
          child: Text(
            text.toUpperCase(),
            style: TextStyle(
              color: c.textFaint,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        );

        Widget item(
          IconData icon,
          String text,
          VoidCallback? onTap, {
          Widget? trailing,
        }) => ListTile(
          dense: true,
          enabled: onTap != null,
          leading: Icon(
            icon,
            size: 20,
            color: onTap == null ? c.textFaint : c.textMuted,
          ),
          title: Text(
            text,
            style: TextStyle(
              color: onTap == null ? c.textFaint : c.text,
              fontSize: 14,
            ),
          ),
          trailing: trailing,
          onTap: onTap,
        );

        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                item(
                  Icons.create_new_folder_outlined,
                  'New folder…',
                  !hasRemote
                      ? null
                      : () async {
                          close();
                          final name = await showNewFolderDialog(
                            context,
                            taken: state.entries.map((e) => e.name).toSet(),
                          );
                          if (name == null) return;
                          await ref
                              .read(fileOpsProvider)
                              .newFolder(remote, state.path, name);
                          await ref
                              .read(paneProvider(index).notifier)
                              .refresh();
                        },
                ),
                const Divider(height: 1),
                label('Sort by'),
                for (final (key, name) in const [
                  (SortKey.name, 'Name'),
                  (SortKey.size, 'Size'),
                  (SortKey.modified, 'Modified'),
                ])
                  item(
                    state.sortKey == key
                        ? (state.ascending
                              ? Icons.arrow_upward
                              : Icons.arrow_downward)
                        : Icons.swap_vert,
                    name,
                    // Stays open + updates live so you can flip the direction.
                    () => ctrl.setSort(key),
                    trailing: state.sortKey == key
                        ? Icon(Icons.check, size: 18, color: c.primary)
                        : null,
                  ),
                const Divider(height: 1),
                label('View'),
                item(
                  Icons.image_outlined,
                  'Thumbnails',
                  thumbsToggleable
                      ? () => wref
                            .read(thumbnailsDisabledProvider.notifier)
                            .toggle(remote.fs)
                      : null,
                  trailing: Switch(
                    value: thumbsOn,
                    onChanged: thumbsToggleable
                        ? (_) => wref
                              .read(thumbnailsDisabledProvider.notifier)
                              .toggle(remote.fs)
                        : null,
                  ),
                ),
                const Divider(height: 1),
                label('Tools'),
                item(
                  Icons.straighten,
                  'Folder size',
                  !hasRemote
                      ? null
                      : () {
                          close();
                          showFolderSizeDialog(context, ref, index);
                        },
                ),
                item(
                  Icons.donut_small,
                  'Storage breakdown…',
                  !hasRemote
                      ? null
                      : () {
                          close();
                          showStorageBreakdown(context, ref, index);
                        },
                ),
                item(
                  Icons.cloud_download_outlined,
                  'Upload from URL…',
                  !hasRemote
                      ? null
                      : () {
                          close();
                          showCopyUrlDialog(context, ref, index);
                        },
                ),
                item(
                  Icons.delete_sweep_outlined,
                  'Empty trash…',
                  !hasRemote
                      ? null
                      : () {
                          close();
                          confirmEmptyTrash(context, ref, index);
                        },
                ),
                const SizedBox(height: Space.x2),
              ],
            ),
          ),
        );
      },
    ),
  );
}
