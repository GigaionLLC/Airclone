import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' show Tracks;
import 'package:media_kit_video/media_kit_video.dart';

import '../state/host_platform.dart';
import '../state/media_tracks.dart';
import 'theme/tokens.dart';
import 'tv.dart' show tvOverscan;
import 'tv_player_keys.dart';

/// The audio and subtitle pickers, on every surface that has a video frame.
///
/// One decision per surface, and everything else shared through
/// [TvPlaybackController] and its [TvPlaybackTarget] (player format plan, A2):
///
///  * **desktop** — a menu anchored on the button in media_kit's desktop bar;
///  * **touch** — a bottom sheet from media_kit's touch bar;
///  * **television** — [TvTrackPanel], a focus-trapping side panel opened from
///    two more buttons in the transport row.
///
/// The rows themselves come from `state/media_tracks.dart`, so the three can
/// never disagree about what a track is called or whether it can be picked.
///
/// Not on the web: media_kit's web backend never lists tracks, and a browser
/// `<track>` only takes WebVTT, so a picker there would always be empty.

/// The icon and the words for each picker, shared by every surface.
IconData trackKindIcon(TrackKind kind) => kind == TrackKind.audio
    ? Icons.audiotrack_outlined
    : Icons.subtitles_outlined;

String trackKindTitle(TrackKind kind) =>
    kind == TrackKind.audio ? 'Audio' : 'Subtitles';

String _tooltip(TrackKind kind) =>
    kind == TrackKind.audio ? 'Audio track' : 'Subtitles';

/// The rows for [kind] as [controller] sees the file right now.
List<TrackChoice> choicesFor(TvPlaybackController controller, TrackKind kind) {
  final tracks = controller.target.tracks;
  return kind == TrackKind.audio
      ? audioChoices(tracks)
      : subtitleChoices(
          tracks,
          imageSubsRenderable: controller.imageSubsRenderable,
          externalTitles: controller.externalSubtitleTitles,
        );
}

/// Whether the button for [kind] has anything to offer.
bool trackButtonVisible(
  TvPlaybackController controller,
  TrackKind kind,
  Tracks tracks,
) => kind == TrackKind.audio
    ? hasAudioChoice(tracks)
    : hasSubtitleChoice(
        tracks,
        sidecarsExpected: controller.expectedSidecars > 0,
      );

/// The selected id for [kind] out of [s].
String _selectedId(TrackSelection s, TrackKind kind) =>
    kind == TrackKind.audio ? s.audio : s.subtitle;

/// Opens the pointer/touch picker for [kind] from the button at [context].
Future<void> showTrackPicker(
  BuildContext context,
  TvPlaybackController controller,
  TrackKind kind, {
  required bool touch,
}) async {
  final choices = choicesFor(controller, kind);
  if (choices.isEmpty) return;
  // Where the menu hangs from, measured before anything is awaited.
  final box = context.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  final c = AircloneTheme.of(context);
  final selected = _selectedId(await controller.target.selection(), kind);
  if (!context.mounted) return;
  final TrackChoice? picked;
  if (touch) {
    picked = await showModalBottomSheet<TrackChoice>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: SingleChildScrollView(
          child: _TrackList(
            title: trackKindTitle(kind),
            choices: choices,
            selectedId: selected,
            onPick: (c) => Navigator.pop(sheetCtx, c),
          ),
        ),
      ),
    );
  } else {
    if (box == null || overlay == null) return;
    final rect = Rect.fromPoints(
      box.localToGlobal(Offset.zero, ancestor: overlay),
      box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
    );
    picked = await showMenu<TrackChoice>(
      context: context,
      position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
      items: [
        for (final choice in choices)
          PopupMenuItem<TrackChoice>(
            value: choice,
            enabled: choice.enabled,
            child: _TrackRowContent(
              choice: choice,
              selected: choice.id == selected,
              colors: c,
            ),
          ),
      ],
    );
  }
  if (picked != null) await controller.selectTrack(picked);
}

/// The track button for media_kit's control bars — touch or [desktop] — or
/// nothing at all when there is no choice to make, or on the web.
///
/// Rebuilds from the tracks stream: libmpv lists a file's tracks a moment after
/// it opens, and sidecars arrive after the first frame.
class TrackPickerButton extends StatelessWidget {
  const TrackPickerButton({
    super.key,
    required this.controller,
    required this.kind,
    this.desktop = false,
    this.isWeb = HostPlatform.isWeb,
  });

  final TvPlaybackController controller;
  final TrackKind kind;
  final bool desktop;

  /// Overridable so a test can prove the web build gets no button.
  final bool isWeb;

  @override
  Widget build(BuildContext context) {
    if (isWeb) return const SizedBox.shrink();
    // The controller too, not only the stream: it learns how many sidecars
    // are coming from a listing that may finish after this was built.
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _button(context),
    );
  }

  Widget _button(BuildContext context) {
    return StreamBuilder<Tracks>(
      stream: controller.target.tracksStream,
      initialData: controller.target.tracks,
      builder: (context, snap) {
        final tracks = snap.data ?? const Tracks();
        if (!trackButtonVisible(controller, kind, tracks)) {
          return const SizedBox.shrink();
        }
        // White like the rest of media_kit's bar: it sits on a video frame,
        // not on a themed surface.
        final icon = Tooltip(
          message: _tooltip(kind),
          child: Icon(trackKindIcon(kind), color: Colors.white),
        );
        void open() =>
            showTrackPicker(context, controller, kind, touch: !desktop);
        return desktop
            ? MaterialDesktopCustomButton(onPressed: open, icon: icon)
            : MaterialCustomButton(onPressed: open, icon: icon);
      },
    );
  }
}

/// One row's content: a radio mark and the label, dimmed when disabled.
class _TrackRowContent extends StatelessWidget {
  const _TrackRowContent({
    required this.choice,
    required this.selected,
    required this.colors,
    this.fontSize = 14,
    this.iconSize = 20,
    this.foreground,
    this.faint,
  });

  final TrackChoice choice;
  final bool selected;
  final AircloneColors colors;
  final double fontSize;
  final double iconSize;

  /// Overrides for the television panel, which sits on a dark scrim rather
  /// than a themed surface.
  final Color? foreground;
  final Color? faint;

  @override
  Widget build(BuildContext context) {
    final fg = choice.enabled
        ? (foreground ?? colors.text)
        : (faint ?? colors.textFaint);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          size: iconSize,
          color: selected ? (foreground ?? colors.primary) : fg,
        ),
        const SizedBox(width: Space.x3),
        Flexible(
          child: Text(
            choice.label,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
            style: TextStyle(
              color: fg,
              fontSize: fontSize,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }
}

/// The touch sheet's body.
class _TrackList extends StatelessWidget {
  const _TrackList({
    required this.title,
    required this.choices,
    required this.selectedId,
    required this.onPick,
  });

  final String title;
  final List<TrackChoice> choices;
  final String selectedId;
  final ValueChanged<TrackChoice> onPick;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
          child: Text(
            title,
            style: TextStyle(
              color: c.text,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        for (final choice in choices)
          InkWell(
            onTap: choice.enabled ? () => onPick(choice) : null,
            child: ConstrainedBox(
              // 44px touch targets (DESIGN.md rule 5).
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.x4,
                  vertical: Space.x2,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _TrackRowContent(
                    choice: choice,
                    selected: choice.id == selectedId,
                    colors: c,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: Space.x2),
      ],
    );
  }
}

/// The television picker: a full-height panel on the right edge, at 10-foot
/// scale, that holds focus until it is dismissed.
///
/// The rules it exists to keep, each one a way a TV picker goes wrong:
///
///  * **Focus cannot leave it.** It is a [FocusScope], so LEFT/RIGHT/UP/DOWN
///    move between its rows and nowhere else. Arrowing out of a half-open
///    panel into the transport row behind it is how a remote user loses track
///    of what OK will do.
///  * **The overlay stays up** — the host holds it with
///    [TvPlaybackController.holdControls] for as long as this is open.
///  * **BACK closes the panel**, and only the panel. It is consumed here, so it
///    never reaches the controller's own BACK, which would hide the overlay.
///  * **OK picks and closes**, in one press, and the host returns focus to the
///    button that opened it.
///  * A row that cannot work (an image subtitle while libass is off) is shown,
///    saying so, but is not a focus stop.
class TvTrackPanel extends StatefulWidget {
  const TvTrackPanel({
    super.key,
    required this.controller,
    required this.kind,
    required this.onClose,
  });

  final TvPlaybackController controller;
  final TrackKind kind;

  /// Called once, after a pick has reached the player or on BACK.
  final VoidCallback onClose;

  @override
  State<TvTrackPanel> createState() => _TvTrackPanelState();
}

class _TvTrackPanelState extends State<TvTrackPanel> {
  late final List<TrackChoice> _choices = choicesFor(
    widget.controller,
    widget.kind,
  );
  String? _selected;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    widget.controller.target.selection().then((s) {
      if (mounted) setState(() => _selected = _selectedId(s, widget.kind));
    });
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    widget.onClose();
  }

  Future<void> _pick(TrackChoice choice) async {
    await widget.controller.selectTrack(choice);
    _close();
  }

  static bool _isBack(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.goBack ||
      key == LogicalKeyboardKey.escape ||
      key == LogicalKeyboardKey.browserBack;

  @override
  Widget build(BuildContext context) {
    final c = AircloneTheme.of(context);
    // Focus lands on the selected row, or the first that can be picked.
    final selected = _selected;
    var autofocus = _choices.indexWhere((x) => x.enabled && x.id == selected);
    if (autofocus < 0) autofocus = _choices.indexWhere((x) => x.enabled);
    return Align(
      alignment: Alignment.centerRight,
      child: FractionallySizedBox(
        widthFactor: 0.42,
        heightFactor: 1,
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent && _isBack(event.logicalKey)) {
              _close();
              return KeyEventResult.handled;
            }
            // Its key-up must not reach the controller either.
            if (_isBack(event.logicalKey)) return KeyEventResult.handled;
            return KeyEventResult.ignored;
          },
          child: FocusScope(
            debugLabel: 'tv track panel',
            autofocus: true,
            child: DecoratedBox(
              // Near-opaque black, like the transport scrim: the panel reads
              // over any frame, and the film stays faintly visible behind it.
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.92),
              ),
              child: Padding(
                padding: EdgeInsets.only(
                  top: tvOverscan.top,
                  bottom: tvOverscan.bottom,
                  right: tvOverscan.right,
                  left: Space.x6,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          trackKindIcon(widget.kind),
                          color: Colors.white,
                          size: 32,
                        ),
                        const SizedBox(width: Space.x3),
                        Text(
                          trackKindTitle(widget.kind),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Space.x4),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _choices.length,
                        itemBuilder: (context, i) {
                          final choice = _choices[i];
                          return _TvTrackRow(
                            // Rebuilt once the selection is known, so the
                            // autofocus lands on the current track.
                            key: ValueKey('${choice.id}/${selected ?? ''}'),
                            autofocus: i == autofocus,
                            onPressed: choice.enabled
                                ? () => _pick(choice)
                                : null,
                            child: _TrackRowContent(
                              choice: choice,
                              selected: choice.id == selected,
                              colors: c,
                              fontSize: 22,
                              iconSize: 28,
                              foreground: Colors.white,
                              faint: Colors.white38,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One focusable row of [TvTrackPanel]. The focus ring is `TvFocusOverlay`'s,
/// like every other control on a television, so this stays a real focusable
/// widget rather than a painted highlight.
class _TvTrackRow extends StatelessWidget {
  const _TvTrackRow({
    super.key,
    required this.autofocus,
    required this.onPressed,
    required this.child,
  });

  final bool autofocus;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) => InkWell(
    autofocus: autofocus,
    onTap: onPressed,
    borderRadius: BorderRadius.circular(Radii.md),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.x3,
          vertical: Space.x2,
        ),
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    ),
  );
}

/// How media_kit draws text subtitles while libmpv's own renderer (libass) is
/// off — which, until plan spike A0.2 passes on a real television, is
/// everywhere.
///
/// **Television: not at all.** The TV overlay draws the line itself
/// ([TvSubtitleLine] in `tv_video_controls.dart`) so it can sit above the
/// transport row while that is up. Doing it here instead meant rebuilding
/// `Video` on every overlay change, which re-created the controls and dropped
/// their focus — found on the TV emulator, where the remote went dead one
/// press after Play.
///
/// **Everywhere else** keeps media_kit's default, which is sized for a window
/// and follows it into fullscreen. A fixed size there would be wrong in one of
/// the two, and the fullscreen route reuses whatever is passed here.
SubtitleViewConfiguration subtitleViewConfigurationFor({required bool tv}) => tv
    ? const SubtitleViewConfiguration(visible: false)
    : const SubtitleViewConfiguration();
