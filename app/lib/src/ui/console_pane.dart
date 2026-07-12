import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../rclone/http_rclone_client.dart';
import '../rclone/models/job.dart';
import '../state/console/console_autocomplete.dart';
import '../state/console/console_command.dart';
import '../state/console/console_controller.dart';
import '../state/console/console_redaction.dart';
import '../state/console/rclone_commands.dart';
import '../state/engine_controller.dart';
import '../state/jobs_controller.dart';
import '../state/remotes_provider.dart';
import 'theme/tokens.dart';

/// The rclone command console — a pane that runs an arbitrary rclone command and
/// shows its output, instead of a folder view. Keyed by [consoleId] so it keeps
/// its own scrollback across tab switches.
///
/// Phase 2: token-aware autocomplete (subcommands / flags / remotes) with
/// rclone.org doc links, a redacted exact-command preview, and secret redaction
/// applied to output. Streaming + Stop (Phase 3) and the mobile RC-method
/// console (Phase 4) come later.
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
  final _popScroll = ScrollController(); // the suggestion popover's own scroll
  int _lastLogLen = 0;
  int _sel = 0; // selected suggestion index

  /// Fixed row height of a suggestion, so keyboard nav can scroll the popover to
  /// keep the highlighted row in view.
  static const double _suggestionExtent = 30;
  bool _popClosed = false; // Escape hides the popover until the next edit

  /// Command-history cursor: null = editing the live buffer (not recalling);
  /// otherwise an index into the controller's history (oldest → newest).
  int? _histIdx;

  /// The partial line stashed when recall started, restored on ↓ past the newest.
  String _histStash = '';

  String get _id => widget.consoleId;

  @override
  void initState() {
    super.initState();
    // The popover's visibility gates on _inputFocus.hasFocus (in _suggestions),
    // so rebuild when focus changes — hide the suggestions on blur, restore them
    // on refocus — instead of leaving a stale popover until the next keystroke.
    _inputFocus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _inputFocus.removeListener(_onFocusChange);
    _input.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    _popScroll.dispose();
    super.dispose();
  }

  List<String> get _remoteNames =>
      ref.read(remotesProvider).valueOrNull?.map((r) => r.name).toList() ??
      const [];

  List<Suggestion> _suggestions() {
    // No popover on an empty prompt: it would just be the full command menu, and
    // it must stay clear so ↑/↓ recall command history (terminal-style) there.
    if (_popClosed || !_inputFocus.hasFocus || _input.text.trim().isEmpty) {
      return const [];
    }
    return suggestFor(_input.text, remotes: _remoteNames);
  }

  void _apply(Suggestion s) {
    _input.text = applySuggestion(_input.text, s.value);
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
    setState(() {
      _sel = 0;
      _popClosed = false;
      _histIdx = null;
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final sug = _suggestions();
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.escape) {
      if (sug.isNotEmpty) {
        setState(() => _popClosed = true);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    // Popover open → arrows drive the suggestion list; Tab accepts.
    if (sug.isNotEmpty) {
      if (k == LogicalKeyboardKey.arrowDown) {
        setState(() => _sel = (_sel + 1) % sug.length);
        _revealSelected();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowUp) {
        setState(() => _sel = (_sel - 1 + sug.length) % sug.length);
        _revealSelected();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.tab) {
        _apply(sug[_sel.clamp(0, sug.length - 1)]);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    // Popover closed → arrows walk the command history (terminal-style).
    if (k == LogicalKeyboardKey.arrowUp) return _historyPrev();
    if (k == LogicalKeyboardKey.arrowDown) return _historyNext();
    return KeyEventResult.ignored;
  }

  /// Recall the previous (older) command into the input.
  KeyEventResult _historyPrev() {
    final hist = ref.read(consoleControllerProvider(_id)).history;
    if (hist.isEmpty) return KeyEventResult.ignored;
    if (_histIdx == null) {
      _histStash = _input.text; // remember the in-progress line
      _histIdx = hist.length - 1;
    } else if (_histIdx! > 0) {
      _histIdx = _histIdx! - 1;
    } else {
      return KeyEventResult.handled; // already at the oldest
    }
    _recall(hist[_histIdx!]);
    return KeyEventResult.handled;
  }

  /// Move toward newer commands; stepping past the newest restores the stash.
  KeyEventResult _historyNext() {
    if (_histIdx == null) return KeyEventResult.ignored; // not recalling
    final hist = ref.read(consoleControllerProvider(_id)).history;
    if (_histIdx! < hist.length - 1) {
      _histIdx = _histIdx! + 1;
      _recall(hist[_histIdx!]);
    } else {
      _histIdx = null;
      _recall(_histStash);
      _histStash = '';
    }
    return KeyEventResult.handled;
  }

  /// Drop [text] into the input (cursor at end) without opening the popover.
  void _recall(String text) {
    _input.text = text;
    _input.selection = TextSelection.collapsed(offset: text.length);
    setState(() => _popClosed = true);
  }

  /// Keep the highlighted suggestion in view while arrowing through a long list.
  void _revealSelected() {
    if (!_popScroll.hasClients) return;
    final pos = _popScroll.position;
    final top = _sel * _suggestionExtent;
    final bottom = top + _suggestionExtent;
    double? to;
    if (top < pos.pixels) {
      to = top; // above the viewport → bring it to the top edge
    } else if (bottom > pos.pixels + pos.viewportDimension) {
      to =
          bottom - pos.viewportDimension; // below → bring it to the bottom edge
    }
    if (to != null) _popScroll.jumpTo(to.clamp(0.0, pos.maxScrollExtent));
  }

  Future<void> _submit() async {
    final ctrl = ref.read(consoleControllerProvider(_id).notifier);
    final cmd = ConsoleCommand.parse(_input.text.trim());
    if (cmd.isEmpty) return;
    if (cmd.tier == CommandTier.destructive) {
      final ok = await _confirmDestructive(cmd);
      if (ok != true) return;
    }
    ctrl.setDraft(_input.text);
    _input.clear();
    setState(() {
      _popClosed = false;
      _histIdx = null;
      _histStash = '';
    });
    await ctrl.run();
    if (mounted) _inputFocus.requestFocus();
  }

  Future<void> _openDoc(String? url) async {
    if (url == null) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
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
              'This can delete or overwrite data and cannot be undone. Consider '
              'adding --dry-run first.',
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
                redactedPreview(cmd),
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

    if (st.log.length != _lastLogLen) {
      _lastLogLen = st.log.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }

    final live = ConsoleCommand.parse(_input.text.trim());
    final suggestions = _suggestions();

    // Stable keys are load-bearing here, not cosmetic. The popover + preview are
    // CONDITIONAL siblings rendered directly above the input row, and every child
    // is a Container — so without keys, when the popover appears/disappears the
    // children list length changes and Flutter re-matches by position+type,
    // repurposing the input row's element (with its TextField) as the popover.
    // That tears down the field, drops its focus, which empties the suggestion
    // list (it gates on hasFocus), which removes the popover — a focus thrash
    // that reads as "I typed and suddenly couldn't type anymore". Keys pin each
    // child's identity so the input keeps its element + focus across the change.
    return Container(
      color: c.surfaceSunken,
      child: Column(
        children: [
          KeyedSubtree(
            key: const ValueKey('console-header'),
            child: _header(c),
          ),
          KeyedSubtree(
            key: const ValueKey('console-banner'),
            child: _engineBanner(c),
          ),
          Expanded(
            key: const ValueKey('console-output'),
            child: _output(c, st),
          ),
          KeyedSubtree(
            key: const ValueKey('console-progress'),
            child: _progressRow(c, st),
          ),
          if (suggestions.isNotEmpty)
            KeyedSubtree(
              key: const ValueKey('console-popover'),
              child: _popover(c, suggestions),
            ),
          if (!live.isEmpty)
            KeyedSubtree(
              key: const ValueKey('console-preview'),
              child: _previewBar(c, live),
            ),
          KeyedSubtree(
            key: const ValueKey('console-input'),
            child: _inputRow(c, st),
          ),
        ],
      ),
    );
  }

  /// Honest degradation strip on the in-process/FFI engine: it runs the curated
  /// RC-method console, so text-output commands (cat/tree/raw streams) aren't
  /// available. Absent on the desktop/Android binary engine (full CLI).
  Widget _engineBanner(AircloneColors c) {
    final client = ref.watch(engineControllerProvider).client;
    if (client == null || client is HttpRcloneClient) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      color: c.info.withValues(alpha: 0.10),
      padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: 5),
      child: Row(
        children: [
          Icon(Icons.memory, size: 13, color: c.info),
          const SizedBox(width: Space.x2),
          Expanded(
            child: Text(
              'In-process engine — structured RC-method console. Text-output '
              'commands (cat, tree, raw streams) run only on the desktop binary '
              'engine.',
              style: TextStyle(color: c.textMuted, fontSize: 11, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  /// Live progress for a Path-B async command (in-process engine), driven by the
  /// same job the Jobs panel shows. Absent for streaming / instant / idle.
  Widget _progressRow(AircloneColors c, ConsoleState st) {
    final id = st.activeJobId;
    if (id == null) return const SizedBox.shrink();
    final jobs = ref.watch(jobsControllerProvider);
    Job? job;
    for (final j in jobs) {
      if (j.id == id) {
        job = j;
        break;
      }
    }
    if (job == null || !job.isRunning) return const SizedBox.shrink();
    final j = job;
    final pct = j.total > 0 ? j.progress : null;
    final detail = j.total > 0
        ? '${(j.progress * 100).toStringAsFixed(0)}%  ·  ETA ${j.etaLabel}'
        : 'working…';
    return Container(
      width: double.infinity,
      color: c.surface,
      padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(detail, style: TextStyle(color: c.textMuted, fontSize: 11)),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.sm),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 3,
              backgroundColor: c.surfaceSunken,
            ),
          ),
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
          'e.g.  lsjson gdrive:   ·   size s3:backup   ·   about gdrive:\n'
          '↑ / ↓ recall previous commands · Tab accepts a suggestion',
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

  Widget _popover(AircloneColors c, List<Suggestion> sug) {
    final sel = _sel.clamp(0, sug.length - 1);
    return Container(
      constraints: const BoxConstraints(maxHeight: 240),
      margin: const EdgeInsets.fromLTRB(Space.x3, 0, Space.x3, 0),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: c.border),
      ),
      child: Scrollbar(
        controller: _popScroll,
        child: ListView.builder(
          controller: _popScroll,
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemExtent: _suggestionExtent,
          itemCount: sug.length,
          itemBuilder: (_, i) {
            final s = sug[i];
            final on = i == sel;
            final vColor = s.destructive ? c.error : c.text;
            return InkWell(
              onTap: () => _apply(s),
              child: Container(
                color: on ? c.primary.withValues(alpha: 0.10) : null,
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.x3,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    Icon(
                      switch (s.kind) {
                        SuggestionKind.command => Icons.chevron_right,
                        SuggestionKind.flag => Icons.flag_outlined,
                        SuggestionKind.remote => Icons.cloud_outlined,
                      },
                      size: 13,
                      color: c.textFaint,
                    ),
                    const SizedBox(width: Space.x2),
                    Text(
                      s.value,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12.5,
                        color: vColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: Space.x3),
                    Expanded(
                      child: Text(
                        s.help,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.textFaint, fontSize: 11.5),
                      ),
                    ),
                    if (s.docUrl != null)
                      InkWell(
                        onTap: () => _openDoc(s.docUrl),
                        borderRadius: BorderRadius.circular(Radii.sm),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          child: Text(
                            'docs ↗',
                            style: TextStyle(color: c.primary, fontSize: 11),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
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
              redactedPreview(cmd),
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
          child: Focus(
            onKeyEvent: _onKey,
            child: TextField(
              controller: _input,
              focusNode: _inputFocus,
              autofocus: true,
              enabled: !st.running,
              // A real edit exits history recall + re-arms the popover, and
              // re-selects the top match (scrolled back into view).
              onChanged: (_) {
                setState(() {
                  _popClosed = false;
                  _histIdx = null;
                  _sel = 0;
                });
                if (_popScroll.hasClients) _popScroll.jumpTo(0);
              },
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
        ),
        const SizedBox(width: Space.x2),
        if (st.running) ...[
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: Space.x2),
          OutlinedButton(
            onPressed: () =>
                ref.read(consoleControllerProvider(_id).notifier).stop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: c.error,
              side: BorderSide(color: c.error.withValues(alpha: 0.5)),
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: Space.x3),
            ),
            child: const Text('Stop'),
          ),
        ] else
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
