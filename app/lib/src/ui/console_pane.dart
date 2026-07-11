import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/console/console_command.dart';
import '../state/console/console_controller.dart';
import '../state/console/rclone_commands.dart';
import 'theme/tokens.dart';

/// The rclone command console — a pane that runs an arbitrary rclone command
/// and shows its output, instead of a folder view. Keyed by [consoleId] so it
/// keeps its own scrollback across tab switches. Phase-1 MVP: a raw command box
/// + buffered output; autocomplete/streaming/mobile come later.
class ConsolePane extends ConsumerStatefulWidget {
  const ConsolePane({super.key, required this.consoleId});
  final String consoleId;

  @override
  ConsumerState<ConsolePane> createState() => _ConsolePaneState();
}

class _ConsolePaneState extends ConsumerState<ConsolePane> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final _scroll = ScrollController();
  int _lastLogLen = 0;

  String get _id => widget.consoleId;

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final ctrl = ref.read(consoleControllerProvider(_id).notifier);
    final cmd = ConsoleCommand.parse(_input.text.trim());
    if (cmd.isEmpty) return;
    // Destructive verbs demand an explicit confirm before running. (Phase 2
    // upgrades this to a dry-run preview + typed confirm.) Blocked verbs are
    // refused by the controller itself.
    if (cmd.tier == CommandTier.destructive) {
      final ok = await _confirmDestructive(cmd);
      if (ok != true) return;
    }
    ctrl.setDraft(_input.text);
    _input.clear();
    await ctrl.run();
    if (mounted) _inputFocus.requestFocus();
  }

  Future<bool?> _confirmDestructive(ConsoleCommand cmd) {
    final c = AircloneTheme.of(context);
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: c.surfaceRaised,
        title: const Text('Run a destructive command?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This can delete or overwrite data and cannot be undone.',
              style: TextStyle(color: c.textMuted, fontSize: 13),
            ),
            const SizedBox(height: Space.x3),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Space.x3),
              decoration: BoxDecoration(
                color: c.surfaceSunken,
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: Text(
                cmd.preview(),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: c.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Run anyway'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    final st = ref.watch(consoleControllerProvider(_id));

    // Auto-scroll to the bottom when new output arrives.
    if (st.log.length != _lastLogLen) {
      _lastLogLen = st.log.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }

    final live = ConsoleCommand.parse(_input.text.trim());

    return Container(
      color: c.surfaceSunken,
      child: Column(
        children: [
          _header(c),
          Expanded(child: _output(c, st)),
          if (!live.isEmpty) _previewBar(c, live),
          _inputRow(c, st),
        ],
      ),
    );
  }

  Widget _header(AircloneColors c) => Container(
    height: 30,
    color: c.surface,
    padding: const EdgeInsets.symmetric(horizontal: Space.x3),
    child: Row(
      children: [
        Icon(Icons.terminal, size: 15, color: c.textMuted),
        const SizedBox(width: Space.x2),
        Text(
          'CONSOLE',
          style: TextStyle(
            color: c.textFaint,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const Spacer(),
        InkWell(
          onTap: () =>
              ref.read(consoleControllerProvider(_id).notifier).clear(),
          borderRadius: BorderRadius.circular(Radii.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Text(
              'Clear',
              style: TextStyle(color: c.textMuted, fontSize: 11.5),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _output(AircloneColors c, ConsoleState st) {
    if (st.log.isEmpty) {
      return Center(
        child: Text(
          'Type an rclone command below and press Enter.\n'
          'e.g.  lsjson gdrive:   ·   size s3:backup   ·   about gdrive:',
          textAlign: TextAlign.center,
          style: TextStyle(color: c.textFaint, fontSize: 12.5, height: 1.6),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.x3,
        vertical: Space.x2,
      ),
      itemCount: st.log.length,
      itemBuilder: (_, i) {
        final line = st.log[i];
        final color = switch (line.kind) {
          ConsoleLineKind.input => c.primary,
          ConsoleLineKind.error => c.error,
          ConsoleLineKind.system => c.textFaint,
          ConsoleLineKind.output => c.text,
        };
        return SelectableText(
          line.text.isEmpty ? ' ' : line.text,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12.5,
            height: 1.4,
            color: color,
            fontWeight: line.kind == ConsoleLineKind.input
                ? FontWeight.w600
                : FontWeight.w400,
          ),
        );
      },
    );
  }

  Widget _previewBar(AircloneColors c, ConsoleCommand cmd) {
    final (label, badge) = switch (cmd.tier) {
      CommandTier.safe => ('runs', c.textMuted),
      CommandTier.destructive => ('destructive', c.error),
      CommandTier.blocked => ('blocked', c.error),
    };
    return Container(
      width: double.infinity,
      color: c.surface,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.x3,
        vertical: Space.x2,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: badge.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: badge,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: Space.x2),
          Expanded(
            child: Text(
              cmd.preview(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: c.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputRow(AircloneColors c, ConsoleState st) => Container(
    color: c.surface,
    padding: const EdgeInsets.fromLTRB(Space.x3, Space.x2, Space.x2, Space.x3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '›',
          style: TextStyle(
            color: c.primary,
            fontFamily: 'monospace',
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: Space.x2),
        Expanded(
          child: TextField(
            controller: _input,
            focusNode: _inputFocus,
            autofocus: true,
            enabled: !st.running,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: st.running ? 'running…' : 'rclone command…',
              hintStyle: TextStyle(color: c.textFaint, fontSize: 13),
            ),
            inputFormatters: [
              FilteringTextInputFormatter.deny(RegExp('[\n\r]')),
            ],
          ),
        ),
        const SizedBox(width: Space.x2),
        if (st.running)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          FilledButton(
            onPressed: _submit,
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: Space.x3),
            ),
            child: const Text('Run'),
          ),
      ],
    ),
  );
}
