import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/browser_controller.dart';
import 'file_row.dart';
import 'pane_drag.dart';
import 'theme/tokens.dart';
import 'touch.dart';

/// The pane's one search box (dev/plans/search-scope-plan.md).
///
/// It replaced two tools that disagreed: a desktop-only Filter box over the
/// folder on screen, and a Search dialog that always looked through every
/// subfolder behind a button labelled "Search this folder" — a Google TV user
/// never found that it searched subfolders at all. Now there is one box and
/// one string ([BrowserState.filter]); the scope switch under it decides how
/// far it reaches.
///
/// Bound to [paneFilterFocusProvider], so Ctrl+F still focuses it.
class PaneSearchBox extends ConsumerStatefulWidget {
  const PaneSearchBox({super.key, required this.index, this.touch = false});
  final int index;

  /// The phone/TV header form: taller, focused on open, and ✕ closes the
  /// whole search rather than only clearing the text.
  final bool touch;

  @override
  ConsumerState<PaneSearchBox> createState() => _PaneSearchBoxState();
}

class _PaneSearchBoxState extends ConsumerState<PaneSearchBox> {
  late final TextEditingController _controller = TextEditingController(
    text: ref.read(paneProvider(widget.index)).filter,
  );

  @override
  void initState() {
    super.initState();
    // The header form opens from its magnifier, which this box replaces. The
    // focus that leaves the removed icon lands on a neighbour (on the TV
    // emulator, the ⋯ button) before `autofocus` gets a turn, so the field is
    // focused explicitly once it is laid out.
    if (widget.touch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(paneFilterFocusProvider(widget.index)).requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Esc steps out of the search one level at a time — results, then text —
  /// and only then lets go of the field.
  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    final ctrl = ref.read(paneProvider(widget.index).notifier);
    if (!ctrl.stepOutOfSearch()) {
      ref.read(paneFilterFocusProvider(widget.index)).unfocus();
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final ctrl = ref.read(paneProvider(widget.index).notifier);
    final focus = ref.watch(paneFilterFocusProvider(widget.index));
    final filter = ref.watch(
      paneProvider(widget.index).select((s) => s.filter),
    );
    final subfolders = ref.watch(
      paneProvider(widget.index).select((s) => s.search.inSubfolders),
    );
    // Both ways: navigation clears the text, and switching to a tab whose
    // search has text shows that text (the old box only handled the first).
    ref.listen(paneProvider(widget.index).select((s) => s.filter), (_, next) {
      if (next != _controller.text) {
        _controller.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
      }
    });
    final touch = widget.touch;
    final fontSize = touch ? 15.0 : 12.0;
    final iconSize = touch ? 20.0 : 14.0;
    final height = touch ? 40.0 : 28.0;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: SizedBox(
        height: height,
        child: TextField(
          controller: _controller,
          focusNode: focus,
          autofocus: touch,
          style: TextStyle(color: c.text, fontSize: fontSize),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: Space.x2),
            prefixIcon: Icon(Icons.search, size: iconSize, color: c.textFaint),
            prefixIconConstraints: BoxConstraints(
              minWidth: height,
              minHeight: height,
            ),
            hintText: subfolders
                ? 'Search here and in subfolders'
                : 'Search this folder',
            hintStyle: TextStyle(color: c.textFaint, fontSize: fontSize),
            suffixIcon: filter.isEmpty && !touch
                ? null
                : InkWell(
                    onTap: () {
                      if (touch) {
                        ctrl.closeSearch();
                      } else {
                        ctrl.setFilter('');
                      }
                    },
                    child: Tooltip(
                      message: touch ? 'Close search' : 'Clear',
                      child: Icon(
                        Icons.close,
                        size: iconSize,
                        color: c.textFaint,
                      ),
                    ),
                  ),
            suffixIconConstraints: BoxConstraints(
              minWidth: touch ? 40 : 24,
              minHeight: touch ? 40 : 24,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.md),
            ),
          ),
          onChanged: ctrl.setFilter,
        ),
      ),
    );
  }
}

/// `This folder | Subfolders` — the switch that sets how far the box reaches.
/// Text segments, not icons: on a television there is no tooltip to explain
/// an icon, and this is the control the whole redesign exists to make obvious.
class SearchScopeToggle extends ConsumerWidget {
  const SearchScopeToggle({super.key, required this.index});
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(paneProvider(index).select((s) => s.search.scope));
    final ctrl = ref.read(paneProvider(index).notifier);
    final compact = !isTouchPrimary;
    return SegmentedButton<SearchScope>(
      segments: const [
        ButtonSegment(value: SearchScope.folder, label: Text('This folder')),
        ButtonSegment(value: SearchScope.subfolders, label: Text('Subfolders')),
      ],
      selected: {scope},
      showSelectedIcon: false,
      onSelectionChanged: (s) => ctrl.setSearchScope(s.first),
      style: compact
          ? const ButtonStyle(
              visualDensity: VisualDensity(horizontal: -2, vertical: -4),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
            )
          : null,
    );
  }
}

/// The line under the box while a search is engaged: the scope switch, what
/// the search found or is doing, and its one action (Cancel / Try again).
/// Lives in the pane body, not the toolbar, so it is the same on every skin
/// (the OS skins hoist their toolbar away from the pane), on the phone and on
/// a television, where DOWN from the box lands on it.
class SearchStrip extends ConsumerWidget {
  const SearchStrip({super.key, required this.index, required this.state});
  final int index;
  final BrowserState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    final ctrl = ref.read(paneProvider(index).notifier);
    final search = state.search;
    final muted = TextStyle(color: c.textMuted, fontSize: 12);
    Widget? status;
    Widget? action;
    if (!search.inSubfolders) {
      if (state.filter.trim().isNotEmpty) {
        final n = state.visibleEntries.length;
        status = Text('$n in this folder', style: muted);
      }
    } else {
      switch (search.status) {
        case SearchScanStatus.scanning:
          status = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: Space.x2),
              Flexible(
                child: _Elapsed(
                  startedAt: search.startedAt,
                  label: 'Scanning ${_folderLabel(state)}…',
                  style: muted,
                ),
              ),
            ],
          );
          action = TextButton(
            onPressed: ctrl.cancelSearch,
            child: const Text('Cancel'),
          );
        case SearchScanStatus.done:
          final n = search.scanned;
          status = Text(
            state.filter.trim().isEmpty
                ? '${_count(n, 'item')} — type to search'
                : '${_count(search.hits.length, 'match', plural: 'matches')} '
                      'in ${_count(n, 'item')}',
            style: muted,
          );
        case SearchScanStatus.cancelled:
          status = Text('Search cancelled', style: muted);
          action = TextButton(
            onPressed: ctrl.retrySearch,
            child: const Text('Search again'),
          );
        case SearchScanStatus.error:
          status = Text(
            search.error ?? 'Search failed',
            style: TextStyle(color: c.error, fontSize: 12),
          );
          action = TextButton(
            onPressed: ctrl.retrySearch,
            child: const Text('Try again'),
          );
        case SearchScanStatus.idle:
          break;
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.x3,
        vertical: Space.x1,
      ),
      decoration: BoxDecoration(
        color: c.surfaceSunken.withValues(alpha: 0.5),
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          SearchScopeToggle(index: index),
          const SizedBox(width: Space.x3),
          Expanded(
            child: DefaultTextStyle.merge(
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              child: status ?? const SizedBox.shrink(),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// Where the search started, as the user reads it.
String _folderLabel(BrowserState state) {
  final r = state.remote;
  if (r == null) return '';
  return state.path.isEmpty ? r.name : state.path.split('/').last;
}

String _count(int n, String one, {String? plural}) =>
    '$n ${n == 1 ? one : (plural ?? '${one}s')}';

/// [label] followed by the time since [startedAt], ticking once a second.
class _Elapsed extends StatefulWidget {
  const _Elapsed({
    required this.startedAt,
    required this.label,
    required this.style,
  });
  final DateTime? startedAt;
  final String label;
  final TextStyle style;

  @override
  State<_Elapsed> createState() => _ElapsedState();
}

class _ElapsedState extends State<_Elapsed> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final start = widget.startedAt;
    final secs = start == null
        ? 0
        : DateTime.now().difference(start).inSeconds.clamp(0, 359999);
    final clock = '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
    return Text(
      '${widget.label}  $clock',
      style: widget.style,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// `Search subfolders for "…"` — the second way into Subfolders, under any
/// This-folder result list and under "No matches". It sits at the bottom of
/// the pane rather than at the end of the list so it is always on screen, and
/// a remote reaches it with DOWN however long the list is.
class SearchSubfoldersRow extends StatelessWidget {
  const SearchSubfoldersRow({
    super.key,
    required this.query,
    required this.onTap,
  });
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return Material(
      color: c.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: isTouchPrimary ? 48 : 34,
          padding: const EdgeInsets.symmetric(horizontal: Space.x3),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.border)),
          ),
          child: Row(
            children: [
              Icon(Icons.manage_search, size: 18, color: c.primary),
              const SizedBox(width: Space.x2),
              Expanded(
                child: Text(
                  'Search subfolders for "${query.trim()}"',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.primary, fontSize: 13),
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: c.primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Subfolders results: one row per match with the folder it lives in. Every
/// callback hands over the [SearchHit], whose path is already absolute — a
/// result is never resolved against the pane's folder.
class SearchResultsList extends StatelessWidget {
  const SearchResultsList({
    super.key,
    required this.state,
    required this.onOpen,
    required this.onPreview,
    required this.onSelect,
    required this.onContextMenu,
    this.physics,
  });

  final BrowserState state;
  final void Function(SearchHit hit) onOpen;
  final void Function(SearchHit hit) onPreview;
  final void Function(SearchHit hit) onSelect;
  final void Function(SearchHit hit, Offset globalPosition) onContextMenu;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final search = state.search;
    final remote = state.remote;
    Widget message(String text, {Color? color}) => Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.x6),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: color ?? c.textFaint, fontSize: 13),
        ),
      ),
    );
    if (remote == null) return const SizedBox.shrink();
    switch (search.status) {
      case SearchScanStatus.scanning:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(height: Space.x3),
              Text(
                'Scanning ${_folderLabel(state)} and every folder in it…',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textMuted, fontSize: 12),
              ),
            ],
          ),
        );
      case SearchScanStatus.error:
        return message(search.error ?? 'Search failed', color: c.error);
      case SearchScanStatus.cancelled:
        return message('Search cancelled.');
      case SearchScanStatus.idle:
        return const SizedBox.shrink();
      case SearchScanStatus.done:
        break;
    }
    final notices = <Widget>[
      if (search.hiddenNames > 0)
        _notice(
          c,
          Icons.lock_outline,
          '${_count(search.hiddenNames, 'name')} could not be decrypted — '
          'results may be incomplete.',
        ),
      if (search.truncated)
        _notice(
          c,
          Icons.info_outline,
          'Only the first $kSearchScanCap items were searched — start from a '
          'smaller folder.',
        ),
    ];
    final Widget body;
    if (state.filter.trim().isEmpty) {
      body = message(
        'Type to search ${_count(search.scanned, 'item')} in '
        '${_folderLabel(state)} and its subfolders.',
      );
    } else if (search.hits.isEmpty) {
      body = message('No matches in subfolders.');
    } else {
      final hits = search.hits;
      body = ListView.builder(
        physics: physics,
        itemCount: hits.length,
        itemBuilder: (_, i) {
          final h = hits[i];
          return FileRow(
            key: ValueKey(h.absPath),
            file: h.entry,
            selected: search.selectedPath == h.absPath,
            selectionMode: false,
            subtitle: h.relParent.isEmpty ? _folderLabel(state) : h.relParent,
            dragData: PaneDragData(remote, h.parentPath, [h.entry]),
            onOpen: () => onOpen(h),
            onToggle: () => onSelect(h),
            onPreview: () => onPreview(h),
            onContextMenu: (pos) => onContextMenu(h, pos),
            // A drop onto a result folder is a copy into it; the pane offers
            // the same through the row's menu, so here it is simply not taken.
            onDropInto: (_) {},
          );
        },
      );
    }
    if (notices.isEmpty) return body;
    return Column(
      children: [
        ...notices,
        Expanded(child: body),
      ],
    );
  }

  Widget _notice(AircloneColors c, IconData icon, String text) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(
      horizontal: Space.x3,
      vertical: Space.x2,
    ),
    color: c.warningBg,
    child: Row(
      children: [
        Icon(icon, size: 16, color: c.warning),
        const SizedBox(width: Space.x2),
        Expanded(
          child: Text(text, style: TextStyle(color: c.textMuted, fontSize: 11)),
        ),
      ],
    ),
  );
}
