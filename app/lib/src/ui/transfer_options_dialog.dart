import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/advanced_mode.dart';
import '../state/transfer_options.dart';
import 'theme/tokens.dart';

/// Shows the advanced Copy/Move/Sync dialog (the power path).
///
/// Resolves to the chosen [TransferOptions], or `null` if cancelled. The
/// "Dry run" footer button returns a copy with `dryRun: true`.
///
/// [isRunNow] tells the dialog whether Run dispatches a transfer immediately
/// (the ad-hoc browser flow) or merely returns options to be saved (task
/// definition). The destructive one-way-Sync confirm only fires when true —
/// at definition time nothing runs, so a confirm there is misleading and its
/// "Dry run first" nudge would bake `dryRun: true` into the saved task,
/// turning a scheduled backup into a permanent no-op.
Future<TransferOptions?> showTransferOptionsDialog(
  BuildContext context, {
  required String fromLabel,
  required String toLabel,
  TransferOptions initial = const TransferOptions(),
  bool isRunNow = false,
}) => showDialog<TransferOptions>(
  context: context,
  builder: (_) => _TransferOptionsDialog(
    fromLabel: fromLabel,
    toLabel: toLabel,
    initial: initial,
    isRunNow: isRunNow,
  ),
);

/// Outcome of the one-way Sync destructive confirm: [dryRun] previews first,
/// [run] proceeds with the real (deleting) sync. Cancel returns `null`.
enum _SyncRunChoice { dryRun, run }

/// The destructive-run confirm shown before a real one-way Sync. Sync makes the
/// destination exactly match the source, so destination-only files are deleted
/// for good — this makes that consequence explicit and nudges a dry run first.
Future<_SyncRunChoice?> _showSyncConfirm(BuildContext context) =>
    showDialog<_SyncRunChoice>(
      context: context,
      builder: (ctx) {
        final c = AircloneTheme.of(ctx);
        return AlertDialog(
          backgroundColor: c.surfaceRaised,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          title: Text(
            'Sync deletes destination files',
            style: TextStyle(
              color: c.text,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            'Sync makes the destination exactly match the source. Any files '
            'that exist only on the destination are permanently deleted — this '
            'cannot be undone. If the source is wrong or empty this can wipe '
            'the destination, so run a dry run first to preview the changes.',
            style: TextStyle(color: c.textMuted, fontSize: 13),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(
            Space.x4,
            0,
            Space.x4,
            Space.x4,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel', style: TextStyle(color: c.textMuted)),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(ctx).pop(_SyncRunChoice.dryRun),
              style: OutlinedButton.styleFrom(
                foregroundColor: c.text,
                side: BorderSide(color: c.borderStrong),
              ),
              child: const Text('Dry run first'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: c.error,
                foregroundColor: c.onPrimary,
              ),
              onPressed: () => Navigator.of(ctx).pop(_SyncRunChoice.run),
              child: const Text('Run sync'),
            ),
          ],
        );
      },
    );

class _TransferOptionsDialog extends StatefulWidget {
  const _TransferOptionsDialog({
    required this.fromLabel,
    required this.toLabel,
    required this.initial,
    required this.isRunNow,
  });

  final String fromLabel;
  final String toLabel;
  final TransferOptions initial;
  final bool isRunNow;

  @override
  State<_TransferOptionsDialog> createState() => _TransferOptionsDialogState();
}

class _TransferOptionsDialogState extends State<_TransferOptionsDialog> {
  late TransferOptions _o = widget.initial;

  late final TextEditingController _includes = TextEditingController(
    text: widget.initial.includes.join('\n'),
  );
  late final TextEditingController _excludes = TextEditingController(
    text: widget.initial.excludes.join('\n'),
  );
  late final TextEditingController _filters = TextEditingController(
    text: widget.initial.filters.join('\n'),
  );

  @override
  void dispose() {
    _includes.dispose();
    _excludes.dispose();
    _filters.dispose();
    super.dispose();
  }

  /// Folds the live filter text fields back into [_o] before previewing/run.
  TransferOptions get _current => _o.copyWith(
    includes: _lines(_includes.text),
    excludes: _lines(_excludes.text),
    filters: _lines(_filters.text),
  );

  static List<String> _lines(String text) => [
    for (final l in text.split('\n'))
      if (l.trim().isNotEmpty) l.trim(),
  ];

  void _set(TransferOptions next) => setState(() => _o = next);

  /// Run button. A real (non-dry) one-way Sync permanently deletes every file
  /// that exists only on the destination, so make the user acknowledge that —
  /// and offer a dry run — before returning the options. Copy/Move (and any run
  /// already marked dry) pop straight through. Two-way (bisync) is guarded by
  /// its own baseline confirm at the dispatch site, not here. The confirm only
  /// fires for run-now consumers ([isRunNow]) — at task-definition time nothing
  /// runs on save, and the "Dry run first" choice must never be persisted into
  /// a saved task (it would make every scheduled run a silent no-op).
  Future<void> _onRun() async {
    final current = _current;
    if (widget.isRunNow &&
        current.mode == TransferMode.sync &&
        !current.dryRun) {
      final choice = await _showSyncConfirm(context);
      if (!mounted || choice == null) return;
      Navigator.of(context).pop(
        choice == _SyncRunChoice.dryRun
            ? current.copyWith(dryRun: true)
            : current,
      );
      return;
    }
    Navigator.of(context).pop(current);
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return Dialog(
      backgroundColor: c.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: SizedBox(
        width: 720,
        height: 560,
        child: DefaultTabController(
          length: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(c),
              _tabBar(c),
              Divider(height: 1, color: c.border),
              Expanded(
                child: TabBarView(
                  children: [
                    _SettingsTab(options: _o, onChanged: _set),
                    _FiltersTab(
                      includes: _includes,
                      excludes: _excludes,
                      filters: _filters,
                      onChanged: () => setState(() {}),
                    ),
                    _CmdTab(
                      cmd: rcloneCmdPreview(
                        _current,
                        widget.fromLabel,
                        widget.toLabel,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: c.border),
              _footer(c),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(AircloneColors c) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.x5, Space.x4, Space.x5, Space.x3),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Transfer options',
          style: TextStyle(
            color: c.text,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: Space.x2),
        _endpointRow(c, 'From', widget.fromLabel),
        const SizedBox(height: 2),
        _endpointRow(c, 'To', widget.toLabel),
      ],
    ),
  );

  Widget _endpointRow(AircloneColors c, String label, String value) => Row(
    children: [
      SizedBox(
        width: 40,
        child: Text(label, style: TextStyle(color: c.textFaint, fontSize: 12)),
      ),
      Expanded(
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: c.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );

  Widget _tabBar(AircloneColors c) => TabBar(
    labelColor: c.primary,
    unselectedLabelColor: c.textMuted,
    indicatorColor: c.primary,
    labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    unselectedLabelStyle: const TextStyle(fontSize: 13),
    tabs: const [
      Tab(text: 'Settings'),
      Tab(text: 'Filters'),
      Tab(text: 'rclone cmd'),
    ],
  );

  Widget _footer(AircloneColors c) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: Space.x5,
      vertical: Space.x3,
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: c.textMuted)),
        ),
        const SizedBox(width: Space.x2),
        OutlinedButton(
          onPressed: () =>
              Navigator.of(context).pop(_current.copyWith(dryRun: true)),
          style: OutlinedButton.styleFrom(
            foregroundColor: c.text,
            side: BorderSide(color: c.borderStrong),
          ),
          child: const Text('Dry run'),
        ),
        const SizedBox(width: Space.x2),
        FilledButton(onPressed: _onRun, child: const Text('Run')),
      ],
    ),
  );
}

// ── Settings tab ──────────────────────────────────────────────────────────────

class _SettingsTab extends ConsumerWidget {
  const _SettingsTab({required this.options, required this.onChanged});

  final TransferOptions options;
  final ValueChanged<TransferOptions> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AircloneTheme.of(context);
    // Two-way sync is destructive on its first run, so only expose it in
    // advanced mode (this dialog is itself reachable without advanced mode).
    final advanced = ref.watch(advancedModeProvider);
    final bisync = options.mode == TransferMode.bisync;
    return ListView(
      padding: const EdgeInsets.all(Space.x5),
      children: [
        _label(c, 'Mode'),
        const SizedBox(height: Space.x2),
        for (final m in TransferMode.values)
          if (m != TransferMode.bisync || advanced) _modeRadio(c, m),
        const SizedBox(height: Space.x4),
        if (bisync) ..._bisyncSection(c) else ..._oneWaySection(c),
      ],
    );
  }

  List<Widget> _oneWaySection(AircloneColors c) => [
    _label(c, 'Options'),
    const SizedBox(height: Space.x1),
    _check(
      c,
      'Skip newer files',
      'Don\'t overwrite files newer on the destination (--update).',
      options.skipNewer,
      (v) => onChanged(options.copyWith(skipNewer: v)),
    ),
    _check(
      c,
      'Skip existing files',
      'Leave files that already exist untouched (--ignore-existing).',
      options.skipExisting,
      (v) => onChanged(options.copyWith(skipExisting: v)),
    ),
    _check(
      c,
      'Keep replaced files',
      'Rename overwritten/deleted files (.replaced) instead of losing '
          'them — makes Move/Sync recoverable (--suffix).',
      options.keepReplaced,
      (v) => onChanged(options.copyWith(keepReplaced: v)),
    ),
    _check(
      c,
      'Dry run',
      'Report what would happen without changing anything (--dry-run).',
      options.dryRun,
      (v) => onChanged(options.copyWith(dryRun: v)),
    ),
    // Sync is the only one-way mode that deletes destination-only files, so its
    // delete cap belongs here and only here.
    if (options.mode == TransferMode.sync) ...[
      const SizedBox(height: Space.x3),
      _maxDeleteField(c),
    ],
    const SizedBox(height: Space.x4),
    _label(c, 'Compare by'),
    const SizedBox(height: Space.x2),
    _compareDropdown(c),
    const SizedBox(height: Space.x4),
    _label(c, 'Performance'),
    const SizedBox(height: Space.x2),
    Row(
      children: [
        Expanded(
          child: _intField(
            c,
            'Parallel transfers',
            options.transfers,
            (v) => onChanged(options.copyWith(transfers: v)),
          ),
        ),
        const SizedBox(width: Space.x3),
        Expanded(
          child: _intField(
            c,
            'Parallel checkers',
            options.checkers,
            (v) => onChanged(options.copyWith(checkers: v)),
          ),
        ),
      ],
    ),
    const SizedBox(height: Space.x3),
    Text('Sort order', style: TextStyle(color: c.textMuted, fontSize: 12)),
    const SizedBox(height: 4),
    _strDropdown(
      c,
      options.orderBy,
      const [
        '',
        'name',
        'name,descending',
        'size',
        'size,descending',
        'modtime',
        'modtime,descending',
      ],
      (v) => onChanged(options.copyWith(orderBy: v)),
      labels: const {
        '': 'Default order',
        'name': 'Name (A→Z)',
        'name,descending': 'Name (Z→A)',
        'size': 'Size (small → large)',
        'size,descending': 'Size (large → small)',
        'modtime': 'Oldest first',
        'modtime,descending': 'Newest first',
      },
    ),
    const SizedBox(height: Space.x2),
    _check(
      c,
      'Track renames',
      'Detect server-side renames instead of re-uploading (--track-renames).',
      options.trackRenames,
      (v) => onChanged(options.copyWith(trackRenames: v)),
    ),
    _check(
      c,
      'Immutable',
      'Abort rather than modify any file that already exists (--immutable).',
      options.immutable,
      (v) => onChanged(options.copyWith(immutable: v)),
    ),
  ];

  Widget _intField(
    AircloneColors c,
    String label,
    int value,
    ValueChanged<int> onPick,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(color: c.textMuted, fontSize: 12)),
      const SizedBox(height: 4),
      TextFormField(
        initialValue: value == 0 ? '' : '$value',
        keyboardType: TextInputType.number,
        style: TextStyle(color: c.text, fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'default',
          hintStyle: TextStyle(color: c.textFaint, fontSize: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Radii.md),
          ),
        ),
        onChanged: (v) => onPick(int.tryParse(v) ?? 0),
      ),
    ],
  );

  /// Sync-only delete cap. Empty field = no cap (`maxDeleteFiles == null`); any
  /// number aborts a run that would delete more than that many destination
  /// files. Teaches the `--max-delete` flag inline like the neighbouring
  /// options do.
  Widget _maxDeleteField(AircloneColors c) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Flexible(
            child: Text(
              'Abort if more than N files would be deleted',
              style: TextStyle(
                color: c.text,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: Space.x2),
          Tooltip(
            message:
                '--max-delete — cap destination deletes; the run aborts '
                'rather than exceed it.',
            child: Text(
              '--max-delete',
              style: TextStyle(
                color: c.textFaint,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      TextFormField(
        initialValue: options.maxDeleteFiles?.toString() ?? '',
        keyboardType: TextInputType.number,
        style: TextStyle(color: c.text, fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'no cap',
          hintStyle: TextStyle(color: c.textFaint, fontSize: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Radii.md),
          ),
        ),
        onChanged: (v) {
          final n = int.tryParse(v.trim());
          // Empty, unparseable, or NEGATIVE ⇒ clear the cap (explicit null via
          // copyWith). A negative MaxDelete means "unlimited" to rclone — the
          // opposite of a safety cap — so it must never slip through.
          onChanged(
            options.copyWith(maxDeleteFiles: (n == null || n < 0) ? null : n),
          );
        },
      ),
      const SizedBox(height: 4),
      Text(
        'Sync deletes files that exist only on the destination. A wrong or '
        'empty source can wipe it — cap that here (empty = no cap).',
        style: TextStyle(color: c.textFaint, fontSize: 11),
      ),
    ],
  );

  List<Widget> _bisyncSection(AircloneColors c) => [
    Container(
      padding: const EdgeInsets.all(Space.x3),
      decoration: BoxDecoration(
        color: c.warningBg,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        children: [
          Icon(Icons.swap_vert, size: 16, color: c.warning),
          const SizedBox(width: Space.x2),
          Expanded(
            child: Text(
              'Two-way: changes flow both ways. The first run establishes a '
              'baseline (one side wins on conflicts) and overwrites differing '
              'files — save this as a task to run it with a confirmation.',
              style: TextStyle(color: c.textMuted, fontSize: 11),
            ),
          ),
        ],
      ),
    ),
    const SizedBox(height: Space.x4),
    _label(c, 'When both sides changed'),
    const SizedBox(height: Space.x2),
    _strDropdown(
      c,
      options.conflictResolve,
      const ['none', 'newer', 'older', 'larger', 'smaller', 'path1', 'path2'],
      (v) => onChanged(options.copyWith(conflictResolve: v)),
      labels: const {'none': 'Keep both versions (numbered)'},
    ),
    const SizedBox(height: Space.x3),
    _label(c, 'First-run baseline winner'),
    const SizedBox(height: Space.x2),
    _strDropdown(
      c,
      options.resyncMode,
      const ['path1', 'path2', 'newer', 'older', 'larger', 'smaller'],
      (v) => onChanged(options.copyWith(resyncMode: v)),
      labels: const {
        'path1': 'path1 — the "From" / active side',
        'path2': 'path2 — the other side',
      },
    ),
    const SizedBox(height: Space.x4),
    _label(c, 'Max delete: ${options.maxDeletePercent}%'),
    Slider(
      value: options.maxDeletePercent.toDouble(),
      max: 100,
      divisions: 20,
      label: '${options.maxDeletePercent}%',
      onChanged: (v) =>
          onChanged(options.copyWith(maxDeletePercent: v.round())),
    ),
    Text(
      'Abort a run that would delete more than this share of files (safety).',
      style: TextStyle(color: c.textFaint, fontSize: 11),
    ),
    const SizedBox(height: Space.x3),
    _check(
      c,
      'Check access first',
      'Require RCLONE_TEST files on both sides before running (--check-access).',
      options.checkAccess,
      (v) => onChanged(options.copyWith(checkAccess: v)),
    ),
    _check(
      c,
      'Create empty directories',
      'Propagate empty folders (--create-empty-src-dirs).',
      options.createEmptySrcDirs,
      (v) => onChanged(options.copyWith(createEmptySrcDirs: v)),
    ),
    _check(
      c,
      'Dry run',
      'Report what would happen without changing anything (--dry-run).',
      options.dryRun,
      (v) => onChanged(options.copyWith(dryRun: v)),
    ),
  ];

  Widget _strDropdown(
    AircloneColors c,
    String value,
    List<String> values,
    ValueChanged<String> onPick, {
    Map<String, String> labels = const {},
  }) => DropdownButtonFormField<String>(
    initialValue: value,
    isExpanded: true,
    dropdownColor: c.surfaceRaised,
    decoration: InputDecoration(
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.md)),
    ),
    items: [
      for (final v in values)
        DropdownMenuItem(
          value: v,
          child: Text(
            labels[v] ?? v,
            style: TextStyle(color: c.text, fontSize: 13),
          ),
        ),
    ],
    onChanged: (v) {
      if (v != null) onPick(v);
    },
  );

  Widget _label(AircloneColors c, String text) => Text(
    text,
    style: TextStyle(color: c.text, fontSize: 13, fontWeight: FontWeight.w600),
  );

  Widget _modeRadio(AircloneColors c, TransferMode m) {
    final (title, help) = switch (m) {
      TransferMode.copy => ('Copy', 'Add source files to the destination.'),
      TransferMode.move => ('Move', 'Copy, then delete from the source.'),
      TransferMode.sync => (
        'Sync',
        'Make destination match source (deletes extras).',
      ),
      TransferMode.bisync => (
        'Two-way sync',
        'Keep both locations mirrored — changes flow both directions.',
      ),
    };
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.md),
      onTap: () => onChanged(options.copyWith(mode: m)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.x1),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Radio<TransferMode>(
              value: m,
              // ignore: deprecated_member_use
              groupValue: options.mode,
              // ignore: deprecated_member_use
              onChanged: (v) =>
                  onChanged(options.copyWith(mode: v ?? options.mode)),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: Space.x2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      title,
                      style: TextStyle(
                        color: c.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    help,
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

  Widget _check(
    AircloneColors c,
    String title,
    String help,
    bool value,
    ValueChanged<bool> onTap,
  ) => InkWell(
    borderRadius: BorderRadius.circular(Radii.md),
    onTap: () => onTap(!value),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.x1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: value,
            onChanged: (v) => onTap(v ?? false),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          const SizedBox(width: Space.x2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    title,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(help, style: TextStyle(color: c.textFaint, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _compareDropdown(AircloneColors c) {
    const items = <(CompareMode?, String)>[
      (null, '(default) — size + mod-time'),
      (CompareMode.size, 'Size only (--size-only)'),
      (CompareMode.checksum, 'Checksum (--checksum)'),
    ];
    return DropdownButtonFormField<CompareMode?>(
      initialValue: options.compare,
      isExpanded: true,
      dropdownColor: c.surfaceRaised,
      decoration: InputDecoration(
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
      ),
      items: [
        for (final (mode, text) in items)
          DropdownMenuItem<CompareMode?>(
            value: mode,
            child: Text(text, style: TextStyle(color: c.text, fontSize: 13)),
          ),
      ],
      onChanged: (v) => onChanged(options.copyWith(compare: v)),
    );
  }
}

// ── Filters tab ───────────────────────────────────────────────────────────────

class _FiltersTab extends StatelessWidget {
  const _FiltersTab({
    required this.includes,
    required this.excludes,
    required this.filters,
    required this.onChanged,
  });

  final TextEditingController includes;
  final TextEditingController excludes;
  final TextEditingController filters;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return ListView(
      padding: const EdgeInsets.all(Space.x5),
      children: [
        Text(
          'One glob pattern per line (e.g. *.jpg, photos/**). '
          'Empty lines are ignored.',
          style: TextStyle(color: c.textFaint, fontSize: 11),
        ),
        const SizedBox(height: Space.x3),
        _field(
          c,
          'Include',
          '--include',
          'Only transfer matching files.',
          '*.jpg',
          includes,
        ),
        const SizedBox(height: Space.x4),
        _field(
          c,
          'Exclude',
          '--exclude',
          'Skip matching files.',
          '*.tmp',
          excludes,
        ),
        const SizedBox(height: Space.x4),
        _field(
          c,
          'Filter',
          '--filter',
          'Combined rules, prefixed + (include) or - (exclude).',
          '+ *.png',
          filters,
        ),
      ],
    );
  }

  Widget _field(
    AircloneColors c,
    String label,
    String flag,
    String help,
    String hint,
    TextEditingController controller,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: c.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: Space.x2),
          Tooltip(
            message: '$flag — $help',
            child: Text(
              flag,
              style: TextStyle(
                color: c.textFaint,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: Space.x2),
      TextField(
        controller: controller,
        onChanged: (_) => onChanged(),
        minLines: 3,
        maxLines: 5,
        style: TextStyle(color: c.text, fontSize: 12, fontFamily: 'monospace'),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: TextStyle(color: c.textFaint, fontFamily: 'monospace'),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Radii.md),
          ),
        ),
      ),
    ],
  );
}

// ── rclone cmd tab ────────────────────────────────────────────────────────────

class _CmdTab extends StatefulWidget {
  const _CmdTab({required this.cmd});

  final String cmd;

  @override
  State<_CmdTab> createState() => _CmdTabState();
}

class _CmdTabState extends State<_CmdTab> {
  bool _copied = false;

  @override
  void didUpdateWidget(_CmdTab old) {
    super.didUpdateWidget(old);
    if (old.cmd != widget.cmd && _copied) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return Padding(
      padding: const EdgeInsets.all(Space.x5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Run this yourself from a terminal or a cron job:',
                  style: TextStyle(color: c.textMuted, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: widget.cmd));
                  setState(() => _copied = true);
                },
                icon: Icon(_copied ? Icons.check : Icons.copy, size: 15),
                label: Text(_copied ? 'Copied' : 'Copy'),
              ),
            ],
          ),
          const SizedBox(height: Space.x2),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Space.x4),
            decoration: BoxDecoration(
              color: c.surfaceSunken,
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(color: c.border),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                widget.cmd,
                style: TextStyle(
                  color: c.text,
                  fontSize: 12,
                  height: 1.5,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
