import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/rclone_file.dart';
import '../rclone/models/remote.dart';
import '../state/browser_controller.dart';
import '../state/clipboard_controller.dart';
import '../state/engine_controller.dart';
import '../state/file_ops.dart';
import '../state/pane_layout.dart';
import '../state/remotes_provider.dart';
import '../state/thumbnail_prefs.dart';
import '../state/thumbnail_reload.dart';
import 'add_remote_dialog.dart';
import 'browser_pane.dart';
import 'column_header.dart';
import 'connection_test_dialog.dart';
import 'encrypt_remote_dialog.dart';
import 'file_op_dialogs.dart';
import 'folder_tools.dart';
import 'paste_action.dart';
import 'scan_from_desktop_sheet.dart';
import 'search_dialog.dart';
import 'storage_breakdown.dart';
import 'theme/tokens.dart';

/// Phone action surfaces, all as modal BOTTOM SHEETS (big touch targets, a drag
/// handle, one tap to reach) rather than the desktop's small anchored dropdowns:
///
///  • [showMobileCreateSheet] — the browser's `+` FAB: add content (new folder,
///    upload from URL, paste).
///  • [showMobileActionsSheet] — the header `⋯`: everything else about the current
///    view (refresh, sort, view mode, thumbnails, split, folder tools). Flattened
///    — no more `⋯ → "All features…" →` second hop.
///  • [showMobileAddRemoteSheet] — the Cloud `+`: add / encrypt / import a remote.
///  • [showMobileRemoteSheet] — a remote row's `⋯`: test / edit / delete.
///
/// Every action reuses the exact desktop handler. Sheets that only fire-and-close
/// read state once; the actions sheet wraps its body in a [Consumer] so the sort
/// and view toggles update in place.

// ── shared building blocks ───────────────────────────────────────────────────

Widget _tile(
  AircloneColors c,
  IconData icon,
  String text,
  VoidCallback? onTap, {
  Widget? trailing,
  Color? tint,
}) => ListTile(
  enabled: onTap != null,
  leading: Icon(
    icon,
    size: 22,
    color: onTap == null ? c.textFaint : (tint ?? c.textMuted),
  ),
  title: Text(
    text,
    style: TextStyle(
      color: onTap == null ? c.textFaint : (tint ?? c.text),
      fontSize: 15,
    ),
  ),
  trailing: trailing,
  onTap: onTap,
);

Widget _sectionLabel(AircloneColors c, String text) => Padding(
  padding: const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x4, Space.x1),
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

Future<T?> _sheet<T>(BuildContext context, WidgetBuilder body) =>
    showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              body(ctx),
              const SizedBox(height: Space.x2),
            ],
          ),
        ),
      ),
    );

// ── + FAB: add content ───────────────────────────────────────────────────────

/// The browser FAB sheet — the "add something here" actions for pane [index]:
/// new folder, upload from a URL, and (only when the clipboard holds something)
/// paste. Fires against the CALLER's still-mounted [context]/[ref] after the
/// sheet pops.
Future<void> showMobileCreateSheet(
  BuildContext context,
  WidgetRef ref,
  int index,
) => _sheet<void>(context, (sheetCtx) {
  final c = AircloneTheme.of(sheetCtx);
  final state = ref.read(paneProvider(index));
  final remote = state.remote;
  final clipEmpty = ref.read(clipboardControllerProvider).isEmpty;
  void close() => Navigator.pop(sheetCtx);
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _tile(
        c,
        Icons.create_new_folder_outlined,
        'New folder',
        remote == null
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
                await ref.read(paneProvider(index).notifier).refresh();
              },
      ),
      _tile(
        c,
        Icons.cloud_download_outlined,
        'Upload from URL',
        remote == null
            ? null
            : () {
                close();
                showCopyUrlDialog(context, ref, index);
              },
      ),
      if (!clipEmpty)
        _tile(c, Icons.content_paste, 'Paste here', () async {
          close();
          await pasteClipboardInto(
            context,
            ref,
            dest: ref.read(paneProvider(index)),
            paneIndex: index,
          );
        }),
    ],
  );
});

// ── ⋯ header overflow: everything about the current view ─────────────────────

/// The flattened header-overflow sheet for pane [index]: refresh, sort, view
/// mode, thumbnails, the split-view controls, and the folder tools — in ONE
/// sheet. [compact] (a forced side-by-side narrow pane) also folds in Search,
/// which the roomy header shows as a dedicated icon.
Future<void> showMobileActionsSheet(
  BuildContext context,
  WidgetRef ref,
  int index, {
  required bool primary,
  required bool compact,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  builder: (sheetCtx) => Consumer(
    builder: (_, wref, _) {
      final c = AircloneTheme.of(sheetCtx);
      final state = wref.watch(paneProvider(index));
      final ctrl = wref.read(paneProvider(index).notifier);
      final remote = state.remote;
      final hasRemote = remote != null;
      final split = wref.watch(mobileSplitProvider);
      final orientation = wref.watch(paneSplitOrientationProvider);
      final disabled = wref.watch(thumbnailsDisabledProvider);
      final thumbsToggleable = hasRemote && !remote.isLocal;
      final thumbsOn = hasRemote && thumbnailsOn(remote, disabled);
      void close() => Navigator.pop(sheetCtx);

      Widget viewItem(String name, IconData icon, ViewMode mode) => _tile(
        c,
        icon,
        name,
        () => ctrl.setViewMode(mode), // stays open so you can compare
        trailing: state.viewMode == mode
            ? Icon(Icons.check, size: 18, color: c.primary)
            : null,
      );
      Widget sortItem(String name, SortKey key) => _tile(
        c,
        state.sortKey == key
            ? (state.ascending ? Icons.arrow_upward : Icons.arrow_downward)
            : Icons.swap_vert,
        name,
        () => ctrl.setSort(key), // stays open so you can flip direction
        trailing: state.sortKey == key
            ? Icon(Icons.check, size: 18, color: c.primary)
            : null,
      );
      Widget orientItem(String name, PaneSplitOrientation mode) => _tile(
        c,
        _orientationIcon(mode),
        name,
        () => wref.read(paneSplitOrientationProvider.notifier).set(mode),
        trailing: orientation == mode
            ? Icon(Icons.check, size: 18, color: c.primary)
            : null,
      );

      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasRemote) ...[
                _tile(c, Icons.refresh, 'Refresh', () {
                  close();
                  ctrl.refresh();
                }),
                if (compact)
                  _tile(c, Icons.search, 'Search this folder', () {
                    close();
                    mobileFolderSearch(context, ref, index);
                  }),
                _sectionLabel(c, 'Sort by'),
                sortItem('Name', SortKey.name),
                sortItem('Size', SortKey.size),
                sortItem('Modified', SortKey.modified),
                _sectionLabel(c, 'View'),
                viewItem('List', Icons.view_list_outlined, ViewMode.list),
                viewItem('Grid', Icons.grid_view_outlined, ViewMode.grid),
                viewItem(
                  'Gallery',
                  Icons.photo_library_outlined,
                  ViewMode.media,
                ),
                _tile(
                  c,
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
              ],
              if (primary) ...[
                _sectionLabel(c, 'Layout'),
                _tile(
                  c,
                  split ? Icons.splitscreen : Icons.splitscreen_outlined,
                  split ? 'Close split view' : 'Split view',
                  () {
                    close();
                    _toggleSplit(ref);
                  },
                  tint: split ? c.primary : null,
                ),
                if (split) ...[
                  orientItem('Adaptive', PaneSplitOrientation.adaptive),
                  orientItem('Side by side', PaneSplitOrientation.sideBySide),
                  orientItem('Stacked', PaneSplitOrientation.stacked),
                ],
              ],
              if (!primary)
                _tile(c, Icons.close_fullscreen, 'Close second pane', () {
                  close();
                  _closeSplit(ref);
                }),
              if (hasRemote) ...[
                _sectionLabel(c, 'Tools'),
                _tile(c, Icons.straighten, 'Folder size', () {
                  close();
                  showFolderSizeDialog(context, ref, index);
                }),
                _tile(c, Icons.donut_small, 'Storage breakdown', () {
                  close();
                  showStorageBreakdown(context, ref, index);
                }),
                _tile(c, Icons.delete_sweep_outlined, 'Empty trash', () {
                  close();
                  confirmEmptyTrash(context, ref, index);
                }),
                // Everything the desktop View/Tools menus have that isn't an
                // everyday action, folded behind one collapsed row so the sheet
                // stays short until you go looking.
                _AdvancedSection(
                  colors: c,
                  callerContext: context,
                  callerRef: ref,
                  index: index,
                  thumbsOn: thumbsOn,
                  onClose: close,
                ),
              ],
            ],
          ),
        ),
      );
    },
  ),
);

/// The "Advanced" group at the foot of the actions sheet: the desktop View menu's
/// thumbnail-cache controls plus the Tools menu's cross-pane operations.
///
/// Collapsed by default — the whole point of the phone sheet is that the common
/// actions are one tap away, and a dozen always-visible rows would bury them.
/// Every row calls the SAME function the desktop menu does, against the caller's
/// still-mounted context/ref (the sheet's own context dies with [onClose]).
class _AdvancedSection extends StatefulWidget {
  const _AdvancedSection({
    required this.colors,
    required this.callerContext,
    required this.callerRef,
    required this.index,
    required this.thumbsOn,
    required this.onClose,
  });

  final AircloneColors colors;
  final BuildContext callerContext;
  final WidgetRef callerRef;
  final int index;

  /// Thumbnail actions are pointless (and misleading) with thumbnails off, so
  /// they're hidden rather than disabled — matching the desktop View menu.
  final bool thumbsOn;

  /// Pops the sheet. Called before every action so the dialog/snackbar the
  /// action raises isn't stacked under it.
  final VoidCallback onClose;

  @override
  State<_AdvancedSection> createState() => _AdvancedSectionState();
}

class _AdvancedSectionState extends State<_AdvancedSection> {
  bool _open = false;

  void _run(VoidCallback action) {
    widget.onClose();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.x4,
              Space.x3,
              Space.x4,
              Space.x1,
            ),
            child: Row(
              children: [
                Text(
                  'ADVANCED',
                  style: TextStyle(
                    color: c.textFaint,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                const Spacer(),
                Icon(
                  _open ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: c.textFaint,
                ),
              ],
            ),
          ),
        ),
        if (_open) ...[
          if (widget.thumbsOn) ...[
            _tile(
              c,
              Icons.refresh,
              'Reload thumbnails',
              () => _run(
                widget.callerRef.read(thumbnailReloadProvider.notifier).reload,
              ),
            ),
            _tile(
              c,
              Icons.download_for_offline_outlined,
              'Load all in this folder',
              () => _run(
                () => prewarmFolderThumbnails(
                  widget.callerContext,
                  widget.callerRef,
                  widget.index,
                ),
              ),
            ),
            _tile(
              c,
              Icons.cached,
              'Rebuild thumbnails (clear cache)',
              () => _run(
                widget.callerRef.read(thumbnailReloadProvider.notifier).rebuild,
              ),
            ),
          ],
          _tile(
            c,
            Icons.sync,
            'Copy / Move / Sync this folder…',
            () => _run(
              () => runAdvancedTransfer(
                widget.callerContext,
                widget.callerRef,
                widget.index,
              ),
            ),
          ),
          _tile(
            c,
            Icons.compare_arrows,
            'Compare with other pane',
            () => _run(
              () => showCompareDialog(widget.callerContext, widget.callerRef),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Cloud + : add / encrypt / import a remote ────────────────────────────────

Future<void> showMobileAddRemoteSheet(BuildContext context) =>
    _sheet<void>(context, (sheetCtx) {
      final c = AircloneTheme.of(sheetCtx);
      void run(VoidCallback f) {
        Navigator.pop(sheetCtx);
        f();
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tile(
            c,
            Icons.add_link,
            'Add a remote',
            () => run(() => showAddRemoteDialog(context)),
          ),
          _tile(
            c,
            Icons.lock_outline,
            'Encrypt a remote',
            () => run(() => showEncryptRemoteDialog(context)),
          ),
          _tile(
            c,
            Icons.qr_code_scanner,
            'Import QR Config',
            // Phone-first on-ramp: pull remotes off a computer by scanning the
            // Offline QR it shows (its Settings → "Export QR Config").
            () => run(() => showScanFromDesktopSheet(context)),
          ),
        ],
      );
    });

// ── remote row ⋯ : test / edit / delete ──────────────────────────────────────

Future<void> showMobileRemoteSheet(
  BuildContext context,
  WidgetRef ref,
  Remote remote,
) => _sheet<void>(context, (sheetCtx) {
  final c = AircloneTheme.of(sheetCtx);
  void close() => Navigator.pop(sheetCtx);
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
        child: Text(
          remote.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: c.text,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      const Divider(height: 1),
      _tile(c, Icons.wifi_tethering, 'Test connection', () {
        close();
        final client = ref.read(engineControllerProvider).client;
        if (client != null) showConnectionTest(context, client, remote);
      }),
      _tile(c, Icons.edit_outlined, 'Edit remote', () {
        close();
        showEditRemoteDialog(context, remote);
      }),
      _tile(c, Icons.delete_outline, 'Delete remote', () {
        close();
        _deleteRemote(context, ref, remote);
      }, tint: c.error),
    ],
  );
});

/// Confirms then removes a remote from the rclone config (cloud files are
/// untouched). Ported from the old inline location-list menu.
Future<void> _deleteRemote(
  BuildContext context,
  WidgetRef ref,
  Remote remote,
) async {
  final c = AircloneTheme.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (dctx) => AlertDialog(
      title: Text('Delete "${remote.name}"?'),
      content: const Text(
        'This removes the remote from your rclone config. Files stored in the '
        'cloud are not affected.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: c.error),
          onPressed: () => Navigator.pop(dctx, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  // The caller (_MobileLocations) can unmount while the confirm dialog is up or
  // during the delete RPC — e.g. opening a remote swaps the locations list for
  // the browser — and its WidgetRef then throws a StateError if used. Guard every
  // post-await ref access on the caller's still-mounted context.
  if (!context.mounted) return;
  final client = ref.read(engineControllerProvider).client;
  if (client == null) return;
  try {
    await client.rpc('config/delete', {'name': remote.name});
  } catch (_) {
    /* surfaced via the (unchanged) list if it fails */
  }
  if (!context.mounted) return;
  if (ref.read(paneProvider(0)).remote == remote) {
    ref.read(paneProvider(0).notifier).clear();
  }
  ref.invalidate(remotesProvider);
}

// ── shared: folder search + split helpers (used by header + sheet) ───────────

/// Recursive search rooted at pane [index]'s current folder; opening a match
/// navigates to it (same behavior as the desktop Ctrl+Shift+F). Shared by the
/// header's search icon and the compact actions sheet.
void mobileFolderSearch(BuildContext context, WidgetRef ref, int index) {
  final state = ref.read(paneProvider(index));
  final remote = state.remote;
  final client = ref.read(engineControllerProvider).client;
  if (remote == null || client == null) return;
  final basePath = state.path;
  showSearchDialog(
    context,
    client: client,
    fs: remote.fs,
    label: basePath.isEmpty ? remote.name : '${remote.name}/$basePath',
    basePath: basePath,
    onOpen: (RcloneFile m) async {
      final pane = ref.read(paneProvider(index).notifier);
      final abs = basePath.isEmpty ? m.path : '$basePath/${m.path}';
      if (m.isDir) {
        await pane.navigateTo(abs);
        return;
      }
      final slash = abs.lastIndexOf('/');
      final parent = slash < 0 ? '' : abs.substring(0, slash);
      if (parent != ref.read(paneProvider(index)).path) {
        await pane.navigateTo(parent);
      }
      pane.selectOnly(m.name);
    },
  );
}

void _toggleSplit(WidgetRef ref) {
  final on = ref.read(mobileSplitProvider);
  ref.read(mobileSplitProvider.notifier).state = !on;
  if (on) ref.read(activePaneProvider.notifier).state = 0;
}

void _closeSplit(WidgetRef ref) {
  ref.read(mobileSplitProvider.notifier).state = false;
  ref.read(activePaneProvider.notifier).state = 0;
}

IconData _orientationIcon(PaneSplitOrientation o) => switch (o) {
  PaneSplitOrientation.adaptive => Icons.auto_awesome_mosaic_outlined,
  PaneSplitOrientation.sideBySide => Icons.view_column_outlined,
  PaneSplitOrientation.stacked => Icons.view_agenda_outlined,
};
