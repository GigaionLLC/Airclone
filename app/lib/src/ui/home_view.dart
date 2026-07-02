import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rclone/models/remote.dart';
import '../state/bookmarks_controller.dart';
import '../state/local_locations.dart';
import '../state/recent_locations.dart';
import '../state/remotes_provider.dart';
import 'add_remote_dialog.dart';
import 'theme/tokens.dart';

/// Icon for a local location kind — shared by the sidebar and the Home tiles
/// so the same place never wears two different icons.
IconData localKindIcon(LocalKind kind) => switch (kind) {
  LocalKind.home => Icons.home_outlined,
  LocalKind.desktop => Icons.desktop_windows_outlined,
  LocalKind.documents => Icons.description_outlined,
  LocalKind.downloads => Icons.download_outlined,
  LocalKind.pictures => Icons.image_outlined,
  LocalKind.videos => Icons.movie_outlined,
  LocalKind.music => Icons.library_music_outlined,
  LocalKind.drive => Icons.storage_outlined,
  LocalKind.root => Icons.computer_outlined,
  LocalKind.folder => Icons.folder_outlined,
};

/// Win11-style coloured "known folder" tints (Explorer/Finder chrome), shared
/// by the sidebar and the Home tiles.
Color localKindAccent(LocalKind kind) => switch (kind) {
  LocalKind.home => const Color(0xFF4DA3E0),
  LocalKind.desktop => const Color(0xFF4DA3E0),
  LocalKind.documents => const Color(0xFF4DA3E0),
  LocalKind.downloads => const Color(0xFF5BB561),
  LocalKind.pictures => const Color(0xFF5DB6A8),
  LocalKind.videos => const Color(0xFF6E8FE0),
  LocalKind.music => const Color(0xFFE06A9E),
  LocalKind.drive => const Color(0xFFB0B4BA),
  LocalKind.root => const Color(0xFFB0B4BA),
  LocalKind.folder => const Color(0xFFE8C15A),
};

/// The favorites star tint used when the skin colours its icons.
const Color favoriteStarGold = Color(0xFFE8C15A);

/// The pane's start page when no location is open — the equivalent of
/// Explorer's Home / Finder's Recents instead of a bare "pick something"
/// placeholder. Sections (each hidden when empty): pinned Favorites, Recent
/// folders, this device's drives + user folders, and cloud remotes.
class HomeView extends ConsumerWidget {
  const HomeView({super.key, required this.onOpen});

  /// Opens a location in the owning pane ([path] empty = the remote's root).
  final void Function(Remote remote, String path) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final chrome = AircloneTheme.chromeOf(context);
    final bookmarks = ref.watch(bookmarksProvider);
    final recents = ref.watch(recentLocationsProvider);
    final drives = ref.watch(drivesProvider);
    final locations = ref.watch(userLocationsProvider);
    final remotes = ref.watch(remotesProvider).valueOrNull ?? const <Remote>[];
    final cloud = remotes.where((r) => !r.isLocal).toList();
    final coloured = chrome.colouredFolderIcons;

    Widget section(String title, List<Widget> tiles) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: Space.x5, bottom: Space.x2),
          child: Text(
            chrome.sectionHeaderStyle == SectionHeaderStyle.caps
                ? title.toUpperCase()
                : title,
            style: TextStyle(
              color: c.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing:
                  chrome.sectionHeaderStyle == SectionHeaderStyle.caps
                  ? 0.6
                  : 0,
            ),
          ),
        ),
        Wrap(spacing: Space.x2, runSpacing: Space.x2, children: tiles),
      ],
    );

    final children = <Widget>[
      if (bookmarks.isNotEmpty)
        section('Favorites', [
          for (final b in bookmarks)
            _Tile(
              icon: Icons.star,
              iconColor: coloured ? favoriteStarGold : c.primary,
              title: b.path.isEmpty
                  ? b.remote.name
                  : b.path.split('/').last,
              subtitle: b.path.isEmpty ? null : b.remote.name,
              onTap: () => onOpen(b.remote, b.path),
            ),
        ]),
      if (recents.isNotEmpty)
        section('Recent', [
          for (final l in recents.take(8))
            _Tile(
              icon: Icons.history,
              title: l.path.isEmpty ? l.remote.name : l.path.split('/').last,
              subtitle: l.remote.name,
              onTap: () => onOpen(l.remote, l.path),
            ),
        ]),
      if (drives.isNotEmpty || locations.isNotEmpty)
        section(Platform.isAndroid ? 'This device' : 'This computer', [
          for (final d in drives)
            _Tile(
              icon: localKindIcon(d.kind),
              iconColor: coloured ? localKindAccent(d.kind) : null,
              title: d.remote.name,
              onTap: () => onOpen(d.remote, ''),
            ),
          for (final l in locations)
            _Tile(
              icon: localKindIcon(l.kind),
              iconColor: coloured ? localKindAccent(l.kind) : null,
              title: l.remote.name,
              onTap: () => onOpen(l.remote, ''),
            ),
        ]),
      section('Cloud', [
        for (final r in cloud)
          _Tile(
            icon: Icons.cloud_outlined,
            title: r.name,
            subtitle: chrome.tileShowsSubtitle ? r.type : null,
            onTap: () => onOpen(r, ''),
          ),
        _Tile(
          icon: Icons.add,
          title: 'Add a remote',
          outlined: true,
          onTap: () => showAddRemoteDialog(context),
        ),
      ]),
    ];

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.x5,
        vertical: Space.x3,
      ),
      children: children,
    );
  }
}

/// A quick-access tile: icon + title (+ optional subtitle), sized like
/// Explorer's Home tiles.
class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.iconColor,
    this.outlined = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? iconColor;
  final bool outlined;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Container(
        width: 210,
        padding: const EdgeInsets.symmetric(
          horizontal: Space.x3,
          vertical: Space.x2,
        ),
        decoration: BoxDecoration(
          color: outlined ? null : c.surfaceRaised,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(
            color: outlined ? c.borderStrong : c.border,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: iconColor ?? c.primary),
            const SizedBox(width: Space.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.textFaint, fontSize: 11),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
