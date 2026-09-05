import 'dart:io';

import 'package:flutter/material.dart';

import '../rclone/models/mount_info.dart';
import '../rclone/models/mount_options.dart';
import 'theme/tokens.dart';

/// The ONE editor for [MountOptions], used by both surfaces that offer them:
/// the mount dialog (for the mount about to be started) and Settings (for the
/// defaults new mounts inherit). One widget rather than two so the two places
/// cannot drift into disagreeing about what an option is called or does.
///
/// Purely controlled — it owns no state and persists nothing. The dialog binds
/// it to a transient copy, Settings binds it to the persisted defaults, and
/// neither behaviour is encoded here.
class MountOptionsEditor extends StatelessWidget {
  const MountOptionsEditor({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final MountOptions value;
  final ValueChanged<MountOptions> onChanged;

  /// Offered sizes for the read cache. Values are rclone size suffixes.
  static const _cacheSizes = ['1Gi', '5Gi', '10Gi', '25Gi', '50Gi', 'off'];

  /// How long a cached file survives without being read.
  static const _cacheAges = ['1h', '12h', '24h', '72h', '168h', 'off'];

  /// First-chunk sizes. Small is cheap for a thumbnail; [_chunkLimits] is what
  /// lets a big sequential read still reach full speed.
  static const _chunkSizes = ['8Mi', '16Mi', '32Mi', '64Mi', '128Mi'];
  static const _chunkLimits = ['128Mi', '512Mi', '1Gi', '4Gi', 'off'];
  static const _dirCacheTimes = ['1m', '5m', '15m', '1h', '24h'];
  static const _attrTimeouts = ['1s', '5s', '20s', '1m'];

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _row(
          c,
          left: _choice(
            c,
            label: 'Cache mode',
            help: 'full caches reads, so a folder is only downloaded once.',
            value: value.cacheMode,
            options: mountCacheModes,
            labelFor: (m) => m == 'full' ? 'full (recommended)' : m,
            onChanged: (v) => onChanged(value.copyWith(cacheMode: v)),
          ),
          right: _choice(
            c,
            label: 'Cache size',
            // The single most surprising fact about this screen: the cap is
            // per VFS, so three mounts is three times this.
            help: 'Per mount, not shared.',
            value: value.cacheMaxSize,
            options: _cacheSizes,
            enabled: value.cacheMode == 'full' || value.cacheMode == 'writes',
            onChanged: (v) => onChanged(value.copyWith(cacheMaxSize: v)),
          ),
        ),
        _row(
          c,
          left: _choice(
            c,
            label: 'Keep cached for',
            help: 'Time since a file was last read.',
            value: value.cacheMaxAge,
            options: _cacheAges,
            enabled: value.cacheMode == 'full' || value.cacheMode == 'writes',
            onChanged: (v) => onChanged(value.copyWith(cacheMaxAge: v)),
          ),
          right: _choice(
            c,
            label: 'Directory cache',
            help: 'How long a folder listing is reused.',
            value: value.dirCacheTime,
            options: _dirCacheTimes,
            onChanged: (v) => onChanged(value.copyWith(dirCacheTime: v)),
          ),
        ),
        _row(
          c,
          left: _choice(
            c,
            label: 'Read chunk',
            help: 'Smaller is faster to open a file.',
            value: value.chunkSize,
            options: _chunkSizes,
            onChanged: (v) => onChanged(value.copyWith(chunkSize: v)),
          ),
          right: _choice(
            c,
            label: 'Chunk grows to',
            help: 'Chunks double up to here for big reads.',
            value: value.chunkSizeLimit,
            options: _chunkLimits,
            onChanged: (v) => onChanged(value.copyWith(chunkSizeLimit: v)),
          ),
        ),
        _row(
          c,
          left: _choice(
            c,
            label: 'Attribute cache',
            help: 'How long file details are reused.',
            value: value.attrTimeout,
            options: _attrTimeouts,
            onChanged: (v) => onChanged(value.copyWith(attrTimeout: v)),
          ),
          right: const SizedBox.shrink(),
        ),
        _toggle(
          c,
          label: 'Fast change detection',
          help:
              'Fewer round-trips deciding whether a file changed. Slightly '
              'less precise.',
          value: value.fastFingerprint,
          onChanged: (v) => onChanged(value.copyWith(fastFingerprint: v)),
        ),
        // Windows-only in rclone, and the model omits it elsewhere — so do not
        // offer a control that would do nothing.
        if (Platform.isWindows)
          _toggle(
            c,
            label: 'Mount as a network drive',
            help:
                'Windows stops treating it as local storage, so the search '
                'indexer leaves it alone. It appears under Network rather '
                'than as a normal drive.',
            value: value.networkMode,
            onChanged: (v) => onChanged(value.copyWith(networkMode: v)),
          ),
      ],
    );
  }

  Widget _row(
    AircloneColors c, {
    required Widget left,
    required Widget right,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: Space.x3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: Space.x3),
        Expanded(child: right),
      ],
    ),
  );

  Widget _choice(
    AircloneColors c, {
    required String label,
    required String help,
    required String value,
    required List<String> options,
    required ValueChanged<String> onChanged,
    String Function(String)? labelFor,
    bool enabled = true,
  }) {
    // A stored value outside the offered list (hand-edited prefs, or a list
    // trimmed in a later version) must still be selectable, or the dropdown
    // would assert and take the dialog down with it.
    final items = options.contains(value) ? options : [value, ...options];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: enabled ? c.textMuted : c.textFaint,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          dropdownColor: c.surfaceRaised,
          decoration: InputDecoration(
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.md),
            ),
          ),
          items: [
            for (final o in items)
              DropdownMenuItem(value: o, child: Text(labelFor?.call(o) ?? o)),
          ],
          onChanged: enabled ? (v) => onChanged(v ?? value) : null,
        ),
        const SizedBox(height: 3),
        Text(help, style: TextStyle(color: c.textFaint, fontSize: 11)),
      ],
    );
  }

  Widget _toggle(
    AircloneColors c, {
    required String label,
    required String help,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: Space.x2),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: c.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(help, style: TextStyle(color: c.textFaint, fontSize: 11)),
            ],
          ),
        ),
        const SizedBox(width: Space.x3),
        Switch(value: value, onChanged: onChanged),
      ],
    ),
  );
}
