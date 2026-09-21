/// "Add a cloud" — the first screen.
///
/// Ten tiles people recognise, then everything rclone can do behind an
/// expander. The tiles are a curated list rather than the first ten of
/// `config/providers`, because that list is alphabetical and starts at `alias`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:airclone_rc/airclone_rc.dart';

import '../../state/add_remote_controller.dart';
import '../../state/providers_provider.dart';
import '../../state/remote_setup_recipes.dart';
import '../theme/tokens.dart';
import 'fields.dart';

class ProviderPicker extends ConsumerStatefulWidget {
  const ProviderPicker({super.key});

  @override
  ConsumerState<ProviderPicker> createState() => _ProviderPickerState();
}

class _ProviderPickerState extends ConsumerState<ProviderPicker> {
  String _query = '';
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final providers = ref.watch(providersProvider);
    final ctrl = ref.read(addRemoteControllerProvider.notifier);
    final matches = kCuratedClouds
        .where((x) => cloudMatches(x, _query))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Add a cloud',
          style: TextStyle(
            color: c.text,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: Space.x1),
        Text(
          'Pick where your files live. You can change the details later.',
          style: TextStyle(color: c.textMuted, fontSize: 13),
        ),
        const SizedBox(height: Space.x4),
        TextEntry(
          initial: '',
          hint: 'Search — Wasabi, Nextcloud, S3…',
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: Space.x3),
        Expanded(
          child: providers.when(
            data: (list) => ListView(
              children: [
                if (matches.isEmpty && _query.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.x2),
                    child: Text(
                      'Nothing popular matches "$_query" — it may still be in '
                      'the full list below.',
                      style: TextStyle(color: c.textFaint, fontSize: 12),
                    ),
                  ),
                for (final choice in matches)
                  _CloudTile(
                    choice: choice,
                    onTap: () => ctrl.pickCloud(choice),
                    onAdvanced: () => _advanced(list, choice.type, ctrl),
                  ),
                const SizedBox(height: Space.x2),
                _AllTypesHeader(
                  expanded: _showAll || _query.isNotEmpty,
                  count: list.length,
                  onToggle: () => setState(() => _showAll = !_showAll),
                ),
                if (_showAll || _query.isNotEmpty) ..._allTypes(list, ctrl, c),
              ],
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text('$e', style: TextStyle(color: c.error)),
            ),
          ),
        ),
      ],
    );
  }

  /// Every backend rclone reports, minus the ones already shown as tiles when
  /// nothing is being searched for.
  List<Widget> _allTypes(
    List<RcloneProvider> list,
    AddRemoteController ctrl,
    AircloneColors c,
  ) {
    final q = _query.toLowerCase();
    final shown = <Widget>[];
    for (final p in list) {
      if (q.isNotEmpty &&
          !p.name.toLowerCase().contains(q) &&
          !p.description.toLowerCase().contains(q)) {
        continue;
      }
      shown.add(
        _RawTypeTile(
          provider: p,
          onTap: () => ctrl.pickProviderGuided(p),
          onAdvanced: () => ctrl.pickProvider(p),
        ),
      );
    }
    if (shown.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(Space.x3),
          child: Text(
            'No storage type matches "$_query".',
            style: TextStyle(color: c.textFaint, fontSize: 12),
          ),
        ),
      ];
    }
    return shown;
  }

  void _advanced(
    List<RcloneProvider> list,
    String type,
    AddRemoteController ctrl,
  ) {
    for (final p in list) {
      if (p.name == type) {
        ctrl.pickProvider(p);
        return;
      }
    }
  }
}

/// One curated tile: friendly name, one line of why, and a way past us.
class _CloudTile extends StatelessWidget {
  const _CloudTile({
    required this.choice,
    required this.onTap,
    required this.onAdvanced,
  });

  final CloudChoice choice;
  final VoidCallback onTap;
  final VoidCallback onAdvanced;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return InkWell(
      key: ValueKey('cloud-${choice.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.x2,
          vertical: Space.x3,
        ),
        child: Row(
          children: [
            Icon(iconForCloud(choice.id), size: 20, color: c.primary),
            const SizedBox(width: Space.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    choice.label,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (choice.blurb.isNotEmpty)
                    Text(
                      choice.blurb,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.textFaint, fontSize: 12),
                    ),
                ],
              ),
            ),
            // The secondary route, on every tile: somebody who knows exactly
            // which options they want should never have to go through a guide
            // first.
            _AdvancedAction(onPressed: onAdvanced),
            Icon(Icons.chevron_right, size: 18, color: c.textFaint),
          ],
        ),
      ),
    );
  }
}

/// A backend from rclone's own list, named as rclone names it.
class _RawTypeTile extends StatelessWidget {
  const _RawTypeTile({
    required this.provider,
    required this.onTap,
    required this.onAdvanced,
  });

  final RcloneProvider provider;
  final VoidCallback onTap;
  final VoidCallback onAdvanced;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return InkWell(
      key: ValueKey('type-${provider.name}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.x2,
          vertical: Space.x3,
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_outlined, size: 18, color: c.textMuted),
            const SizedBox(width: Space.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    provider.name,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    provider.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.textFaint, fontSize: 11),
                  ),
                ],
              ),
            ),
            _AdvancedAction(onPressed: onAdvanced),
          ],
        ),
      ),
    );
  }
}

/// The per-tile way past the guide.
///
/// Spelled out where there is room and reduced to an icon where there is not.
/// A tile row on a phone is about 295dp wide once the dialog's insets are
/// taken off, and a text button plus a chevron plus two lines of label does
/// not fit in it — which a widget test at 375dp is how we know.
class _AdvancedAction extends StatelessWidget {
  const _AdvancedAction({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final narrow = MediaQuery.sizeOf(context).width < 480;
    if (narrow) {
      return IconButton(
        tooltip: 'Advanced',
        visualDensity: VisualDensity.compact,
        icon: Icon(Icons.tune, size: 18, color: c.textMuted),
        onPressed: onPressed,
      );
    }
    return TextButton(
      onPressed: onPressed,
      child: Text(
        'Advanced',
        style: TextStyle(color: c.textMuted, fontSize: 12),
      ),
    );
  }
}

class _AllTypesHeader extends StatelessWidget {
  const _AllTypesHeader({
    required this.expanded,
    required this.count,
    required this.onToggle,
  });

  final bool expanded;
  final int count;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.x2,
          vertical: Space.x3,
        ),
        child: Row(
          children: [
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              size: 18,
              color: c.textMuted,
            ),
            const SizedBox(width: Space.x2),
            Expanded(
              child: Text(
                'All storage types ($count)',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A generic glyph per tile.
///
/// Deliberately NOT provider logos: those are trademarks, and shipping them
/// would be a licensing question rather than a design one. Names are nominative
/// use and are fine.
IconData iconForCloud(String id) => switch (id) {
  'drive' => Icons.add_to_drive_outlined,
  'onedrive' => Icons.cloud_outlined,
  'dropbox' => Icons.inventory_2_outlined,
  'iclouddrive' => Icons.cloud_queue,
  'googlephotos' => Icons.photo_library_outlined,
  's3' || 'r2' || 'wasabi' || 'minio' || 'spaces' => Icons.storage_outlined,
  'b2' => Icons.backup_outlined,
  'sftp' => Icons.terminal_outlined,
  'webdav' => Icons.dns_outlined,
  'storj' => Icons.hub_outlined,
  _ => Icons.cloud_outlined,
};
