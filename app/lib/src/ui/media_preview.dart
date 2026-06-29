import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'theme/tokens.dart';

/// Embeddable video / audio player powered by media_kit.
///
/// Designed to live inside the fixed-size preview dialog (~720x600). It owns a
/// single [Player] for its lifetime and tears it down in [dispose]. For video
/// it renders a [Video] surface on a black backdrop; for [audioOnly] it shows a
/// themed audio card with transport controls.
///
/// Robustness: opening the media is guarded; if anything goes wrong (or the
/// player surface fails to attach) a centered "Couldn't play this media"
/// message is shown instead. [build] never throws.
///
/// NOTE: `MediaKit.ensureInitialized()` is expected to be called once in
/// `main()` by the integrator — this widget does not initialize the library.
class MediaPreviewBody extends StatefulWidget {
  const MediaPreviewBody({
    super.key,
    required this.url,
    this.headers = const {},
    this.audioOnly = false,
  });

  /// Direct/streamable URL of the media to play.
  final String url;

  /// Optional HTTP headers (e.g. auth) forwarded to the media source.
  final Map<String, String> headers;

  /// When true, render the compact audio card instead of a video surface.
  final bool audioOnly;

  @override
  State<MediaPreviewBody> createState() => _MediaPreviewBodyState();
}

class _MediaPreviewBodyState extends State<MediaPreviewBody> {
  late final Player _player;
  VideoController? _controller;

  /// Set if construction/open failed; drives the error fallback in [build].
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    try {
      _player = Player();
      if (!widget.audioOnly) {
        _controller = VideoController(_player);
      }
      _player.open(Media(widget.url, httpHeaders: widget.headers), play: true);
    } catch (_) {
      _failed = true;
    }
  }

  @override
  void dispose() {
    // Player is created unless construction itself threw; guard regardless.
    try {
      _player.dispose();
    } catch (_) {
      // Already disposed or never constructed — nothing to do.
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AircloneTheme.of(context);
    if (_failed) return _error(colors);
    try {
      return widget.audioOnly ? _audio(colors) : _video(colors);
    } catch (_) {
      return _error(colors);
    }
  }

  /// Black-backed video surface filling the available space.
  Widget _video(AircloneColors colors) {
    final controller = _controller;
    if (controller == null) return _error(colors);
    return Container(
      color: const Color(0xFF000000),
      alignment: Alignment.center,
      child: Video(controller: controller, controls: AdaptiveVideoControls),
    );
  }

  /// Centered audio card: art, play/pause, and a seek slider.
  Widget _audio(AircloneColors colors) {
    return Container(
      color: colors.surfaceSunken,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(Space.x6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceRaised,
            borderRadius: BorderRadius.circular(Radii.lg),
            border: Border.all(color: colors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(Space.x6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: colors.surfaceSunken,
                    borderRadius: BorderRadius.circular(Radii.full),
                  ),
                  child: Icon(
                    Icons.music_note_rounded,
                    size: 48,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(height: Space.x5),
                _PlayPauseButton(player: _player, colors: colors),
                const SizedBox(height: Space.x4),
                _SeekBar(player: _player, colors: colors),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Shared fallback when playback can't be set up or rendered.
  Widget _error(AircloneColors colors) {
    return Container(
      color: colors.surfaceSunken,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(Space.x6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, size: 40, color: colors.textFaint),
          const SizedBox(height: Space.x3),
          Text(
            "Couldn't play this media",
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textMuted, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

/// Round play/pause control bound to [Player.stream.playing].
class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({required this.player, required this.colors});

  final Player player;
  final AircloneColors colors;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: player.stream.playing,
      initialData: player.state.playing,
      builder: (context, snapshot) {
        final playing = snapshot.data ?? false;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: colors.primary,
            borderRadius: BorderRadius.circular(Radii.full),
          ),
          child: IconButton(
            iconSize: 32,
            color: colors.onPrimary,
            tooltip: playing ? 'Pause' : 'Play',
            icon: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            ),
            onPressed: () {
              try {
                player.playOrPause();
              } catch (_) {
                // Ignore transient control errors.
              }
            },
          ),
        );
      },
    );
  }
}

/// Position/duration slider with elapsed/total labels.
class _SeekBar extends StatelessWidget {
  const _SeekBar({required this.player, required this.colors});

  final Player player;
  final AircloneColors colors;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.stream.duration,
      initialData: player.state.duration,
      builder: (context, durationSnap) {
        final duration = durationSnap.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: player.stream.position,
          initialData: player.state.position,
          builder: (context, positionSnap) {
            var position = positionSnap.data ?? Duration.zero;
            final totalMs = duration.inMilliseconds;
            // Clamp position into [0, duration] to keep the slider valid.
            if (totalMs <= 0) {
              position = Duration.zero;
            } else if (position > duration) {
              position = duration;
            }
            final maxValue = totalMs <= 0 ? 1.0 : totalMs.toDouble();
            final value = position.inMilliseconds
                .clamp(0, maxValue.toInt())
                .toDouble();
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: colors.primary,
                    inactiveTrackColor: colors.surfaceSunken,
                    thumbColor: colors.primary,
                    overlayColor: colors.primary.withValues(alpha: 0.15),
                    trackHeight: 3,
                  ),
                  child: Slider(
                    value: value,
                    min: 0,
                    max: maxValue,
                    onChanged: totalMs <= 0
                        ? null
                        : (v) {
                            try {
                              player.seek(Duration(milliseconds: v.round()));
                            } catch (_) {
                              // Ignore seek failures.
                            }
                          },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.x2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _fmt(position),
                        style: TextStyle(color: colors.textMuted, fontSize: 12),
                      ),
                      Text(
                        _fmt(duration),
                        style: TextStyle(color: colors.textFaint, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// `m:ss` (or `h:mm:ss` past an hour) clock formatting.
  String _fmt(Duration d) {
    final neg = d.isNegative;
    final secs = d.inSeconds.abs();
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    final s = secs % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    final body = h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
    return neg ? '-$body' : body;
  }
}
