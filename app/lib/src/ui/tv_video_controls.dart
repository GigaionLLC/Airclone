import 'package:flutter/material.dart';

import 'theme/tokens.dart';
import 'tv.dart' show tvOverscan;
import 'tv_player_keys.dart';

/// The player controls a television actually gets.
///
/// Passed to media_kit as `Video(controls: (state) => TvVideoControls(...))`,
/// replacing `AdaptiveVideoControls` on a TV only. Every other platform keeps
/// media_kit's own bars byte-for-byte — this file cannot run off a television.
///
/// Why ours rather than media_kit's: `AdaptiveVideoControls` sends Android to
/// the TOUCH controls, which have no key handling at all and only appear from
/// `onTap`. The desktop set does have keys, but it reveals itself on mouse
/// HOVER, which a remote cannot produce either — so neither is a TV control
/// set, and there is no third one to adopt. Confirmed in media_kit_video 1.3.1's
/// source, not inferred.
///
/// The shape is the one every television media app shares, because that is what
/// makes it legible without instruction: nothing on screen while a film plays,
/// any key summons a bottom overlay, the overlay auto-hides, and the transport
/// row is where focus lands. The behaviour — what each key means, when it
/// commits, when it hides — is [TvPlaybackController]'s, not this widget's.
class TvVideoControls extends StatefulWidget {
  const TvVideoControls({super.key, required this.controller});

  final TvPlaybackController controller;

  @override
  State<TvVideoControls> createState() => _TvVideoControlsState();
}

class _TvVideoControlsState extends State<TvVideoControls> {
  /// The node focus RETURNS to when the overlay hides.
  ///
  /// This is the load-bearing detail of the whole file. `TvFocusSeed` exists to
  /// make focus impossible to lose, and it will happily re-seed into a control
  /// that has just been hidden — at which point the ring is drawn around
  /// something nobody can see and the D-pad appears dead. So hiding the overlay
  /// must hand focus somewhere real, and the surface is the only honest answer.
  ///
  /// It also fills the frame, which is why a playing film shows no ring at all:
  /// `TvFocusOverlay` deliberately draws nothing for a target that covers the
  /// whole shell, because a ring around the screen is four stray arcs in the
  /// corners that say nothing about where the D-pad is.
  final FocusNode _surface = FocusNode(debugLabel: 'tv video surface');

  /// Focus lands here when the row appears, so OK is play/pause immediately.
  final FocusNode _playPause = FocusNode(debugLabel: 'tv play/pause');

  TvControlsMode _last = TvControlsMode.hidden;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _last = widget.controller.mode;
  }

  @override
  void didUpdateWidget(TvVideoControls old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _surface.dispose();
    _playPause.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    final mode = widget.controller.mode;
    if (mode != _last) {
      final was = _last;
      _last = mode;
      // Post-frame in both directions: on the frame the row appears its
      // widgets have not been laid out yet, and focusing an unlaid-out node
      // lands nowhere.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (mode == TvControlsMode.browsing) {
          _playPause.requestFocus();
        } else if (was == TvControlsMode.browsing) {
          // Leaving the row — scrubbing or hidden. Either way the arrows must
          // reach the controller rather than the row's traversal.
          _surface.requestFocus();
        }
      });
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Bottom layer: the focusable surface. Also the reason a film plays
        // ring-free — see [_surface].
        Focus(
          focusNode: _surface,
          autofocus: true,
          child: const SizedBox.expand(),
        ),
        if (controller.pendingTarget != null)
          Center(child: _PendingSeekBadge(controller: controller)),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            ignoring: !controller.controlsVisible,
            child: AnimatedOpacity(
              opacity: controller.controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              child: _Scrim(
                child: Padding(
                  // Overscan: a television crops the edge of the picture by an
                  // amount no app can query, and controls hard against the
                  // bezel are the first thing a TV review fails on.
                  padding: tvOverscan,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TvScrubBar(controller: controller),
                      const SizedBox(height: Space.x4),
                      TvTransportRow(
                        controller: controller,
                        playPauseFocus: _playPause,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Bottom-up black gradient, so white controls stay legible over a bright frame.
class _Scrim extends StatelessWidget {
  const _Scrim({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [Color(0xE6000000), Color(0x00000000)],
      ),
    ),
    child: child,
  );
}

/// The transient "⏪ 30s → 1:12:04" badge while a scrub is being coalesced.
///
/// Its job is to make a pending seek feel like it already happened: the commit
/// is deliberately delayed (one ranged request instead of ten), so without this
/// a run of presses would look like nothing at all was happening.
class _PendingSeekBadge extends StatelessWidget {
  const _PendingSeekBadge({required this.controller});

  final TvPlaybackController controller;

  @override
  Widget build(BuildContext context) {
    final target = controller.pendingTarget;
    if (target == null) return const SizedBox.shrink();
    if (!controller.seekable) {
      return const _Badge(icon: Icons.sensors_rounded, label: 'Live');
    }
    final delta = target - controller.target.position;
    final back = delta.isNegative;
    final secs = delta.inSeconds.abs();
    return _Badge(
      icon: back ? Icons.fast_rewind_rounded : Icons.fast_forward_rounded,
      label: '${back ? '-' : '+'}${secs}s   ${formatMediaClock(target)}',
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xB3000000),
      borderRadius: BorderRadius.circular(Radii.lg),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.x5,
        vertical: Space.x3,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 32),
          const SizedBox(width: Space.x3),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Progress, buffer, the pending scrub marker, and the two clocks.
///
/// Not a [Slider]: a slider is a drag target, and a television has nothing to
/// drag with. Seeking here is the keys' job, so this is a readout — which also
/// means it is never a focus stop competing with the transport row.
class TvScrubBar extends StatelessWidget {
  const TvScrubBar({super.key, required this.controller, this.onSurface});

  final TvPlaybackController controller;

  /// Colours for the audio screen, which sits on a themed surface rather than
  /// over a video frame. Null renders the white-on-video palette.
  final AircloneColors? onSurface;

  @override
  Widget build(BuildContext context) {
    final fg = onSurface?.text ?? Colors.white;
    final dim = onSurface?.textMuted ?? Colors.white70;
    final track = onSurface?.surfaceSunken ?? const Color(0x4DFFFFFF);
    final accent = onSurface?.primary ?? Colors.white;

    return StreamBuilder<Duration>(
      stream: controller.target.durationStream,
      initialData: controller.target.duration,
      builder: (context, durationSnap) {
        final duration = durationSnap.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: controller.target.positionStream,
          initialData: controller.target.position,
          builder: (context, positionSnap) {
            final position = positionSnap.data ?? Duration.zero;
            final pending = controller.pendingTarget;
            // While a scrub is pending the bar shows where it WILL land, not
            // where playback still is: the badge and the bar must never
            // disagree about the same press.
            final shown = pending ?? position;
            final total = duration.inMilliseconds;
            final live = total <= 0;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                StreamBuilder<Duration>(
                  stream: controller.target.bufferStream,
                  initialData: controller.target.buffer,
                  builder: (context, bufferSnap) => _Bar(
                    fraction: live
                        ? 0
                        : (shown.inMilliseconds / total).clamp(0.0, 1.0),
                    bufferFraction: live
                        ? 0
                        : ((bufferSnap.data ?? Duration.zero).inMilliseconds /
                                  total)
                              .clamp(0.0, 1.0),
                    scrubbing: pending != null,
                    track: track,
                    accent: accent,
                  ),
                ),
                const SizedBox(height: Space.x2),
                Row(
                  children: [
                    Text(
                      live ? '--:--' : formatMediaClock(shown),
                      style: TextStyle(
                        color: fg,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      live ? 'Live' : formatMediaClock(duration),
                      style: TextStyle(color: dim, fontSize: 22),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.fraction,
    required this.bufferFraction,
    required this.scrubbing,
    required this.track,
    required this.accent,
  });

  final double fraction;
  final double bufferFraction;
  final bool scrubbing;
  final Color track;
  final Color accent;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      // 8px, not the 3px a pointer bar uses: this is read from a sofa.
      const height = 8.0;
      return SizedBox(
        height: 24,
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            _Track(width: width, height: height, color: track),
            _Track(
              width: width * bufferFraction,
              height: height,
              color: accent.withValues(alpha: 0.32),
            ),
            _Track(width: width * fraction, height: height, color: accent),
            // The head. Grows while scrubbing, so a pending seek is visible
            // even at a glance from across a room.
            Positioned(
              left: (width * fraction - (scrubbing ? 10 : 7)).clamp(
                0.0,
                width - 14,
              ),
              child: Container(
                width: scrubbing ? 20 : 14,
                height: scrubbing ? 20 : 14,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _Track extends StatelessWidget {
  const _Track({
    required this.width,
    required this.height,
    required this.color,
  });

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: width.isFinite ? width.clamp(0.0, double.infinity) : 0,
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(Radii.full),
    ),
  );
}

/// ⏮ ⏪ ⏯ ⏩ ⏭ at television scale.
///
/// Shared by the video overlay and the audio now-playing screen, so the two
/// cannot drift into different gestures for the same picture.
///
/// The end controls follow the rule `AudioSkipButton` established: at either end
/// of a real list the dead one stays VISIBLE but disabled, because a row that
/// changes shape as you move through an album is harder to aim at with a D-pad
/// than one that stays put. With no sibling list at all they are omitted, since
/// two permanently dead buttons are worse than none.
class TvTransportRow extends StatelessWidget {
  const TvTransportRow({
    super.key,
    required this.controller,
    this.playPauseFocus,
    this.onSurface,
  });

  final TvPlaybackController controller;

  /// The node the host focuses when this row appears.
  final FocusNode? playPauseFocus;

  /// Themed colours for the audio screen; null renders white-on-video.
  final AircloneColors? onSurface;

  @override
  Widget build(BuildContext context) {
    final inAList = controller.onPrevious != null || controller.onNext != null;
    final fg = onSurface?.text ?? Colors.white;
    final faint = onSurface?.textFaint ?? Colors.white38;

    return StreamBuilder<bool>(
      stream: controller.target.playingStream,
      initialData: controller.target.playing,
      builder: (context, snap) {
        final playing = snap.data ?? false;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (inAList)
              _TvControlButton(
                icon: Icons.skip_previous_rounded,
                tooltip: 'Previous',
                onPressed: controller.onPrevious,
                foreground: fg,
                disabled: faint,
              ),
            _TvControlButton(
              icon: Icons.fast_rewind_rounded,
              tooltip: 'Back 30 seconds',
              onPressed: controller.seekable
                  ? () => controller.seekBy(-TvPlaybackController.transportStep)
                  : null,
              foreground: fg,
              disabled: faint,
            ),
            _TvControlButton(
              icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              tooltip: playing ? 'Pause' : 'Play',
              onPressed: controller.playPause,
              foreground: fg,
              disabled: faint,
              focusNode: playPauseFocus,
              primary: true,
            ),
            _TvControlButton(
              icon: Icons.fast_forward_rounded,
              tooltip: 'Forward 30 seconds',
              onPressed: controller.seekable
                  ? () => controller.seekBy(TvPlaybackController.transportStep)
                  : null,
              foreground: fg,
              disabled: faint,
            ),
            if (inAList)
              _TvControlButton(
                icon: Icons.skip_next_rounded,
                tooltip: 'Next',
                onPressed: controller.onNext,
                foreground: fg,
                disabled: faint,
              ),
          ],
        );
      },
    );
  }
}

/// One control in [TvTransportRow].
///
/// 64dp of target and a 40dp glyph. Google's TV guidance is a minimum of 48dp
/// and this is a primary control on a 10-foot screen, where the 15px glyphs a
/// pointer UI can afford are the reason a remote user cannot tell what they are
/// aimed at. The focus RING is not drawn here: `TvFocusOverlay` draws one for
/// whatever holds focus anywhere in the app, which is also why this must stay
/// a real focusable widget rather than a painted icon.
class _TvControlButton extends StatelessWidget {
  const _TvControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.foreground,
    required this.disabled,
    this.focusNode,
    this.primary = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color foreground;
  final Color disabled;
  final FocusNode? focusNode;
  final bool primary;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: Space.x2),
    child: IconButton(
      focusNode: focusNode,
      onPressed: onPressed,
      tooltip: tooltip,
      iconSize: primary ? 48 : 40,
      constraints: const BoxConstraints(minWidth: 64, minHeight: 64),
      icon: Icon(icon, color: onPressed == null ? disabled : foreground),
    ),
  );
}

/// `m:ss`, or `h:mm:ss` past an hour.
///
/// Public and in one place because three surfaces render a clock — the video
/// overlay, the audio screen, and the pointer seek bar — and a film that says
/// `1:04:11` in one and `64:11` in another is a bug nobody will ever file.
String formatMediaClock(Duration d) {
  final negative = d.isNegative;
  final seconds = d.inSeconds.abs();
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  final body = h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  return negative ? '-$body' : body;
}
