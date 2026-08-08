import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'theme/tokens.dart';

/// How long a media file may sit without ever reaching "playing" before we stop
/// showing a spinner and offer a way out. Cloud objects come through the local
/// engine and can genuinely take a while to start, so this is deliberately
/// generous — it exists to kill the *infinite* black screen, not to be strict.
const Duration _startTimeout = Duration(seconds: 45);

/// Embeddable video / audio player powered by media_kit.
///
/// Designed to live inside the preview surface (the dialog, or Quick Look's
/// fullscreen page). It owns a single [Player] for its lifetime and tears it
/// down in [dispose]. For video it renders a [Video] surface on a black
/// backdrop; for [audioOnly] it shows a themed audio card with transport
/// controls.
///
/// FAILURE HANDLING is the point of most of this class. libmpv reports almost
/// nothing by throwing: [Player.open] resolves a Future that rejects
/// asynchronously, and decode/transport problems arrive later on
/// [PlayerStream.error]. Anything not observed shows up to the user as a black
/// rectangle that never plays, which is indistinguishable from a hang. So we
///
///  * await [Player.open] and catch its async rejection,
///  * subscribe to [PlayerStream.error],
///  * track [PlayerStream.buffering] so a slow start looks like loading, and
///  * arm a [_startTimeout] watchdog for the case where libmpv reports nothing
///    at all.
///
/// Every one of those paths lands on the same error card, which offers Retry
/// and — when the host supplies [onOpenExternally] — a hand-off to another app.
///
/// NOTE: `MediaKit.ensureInitialized()` is expected to be called once in
/// `main()` by the integrator — this widget does not initialize the library.
class MediaPreviewBody extends StatefulWidget {
  const MediaPreviewBody({
    super.key,
    required this.url,
    this.headers = const {},
    this.audioOnly = false,
    this.onOpenExternally,
  });

  /// Direct/streamable URL of the media to play.
  final String url;

  /// Optional HTTP headers (e.g. auth) forwarded to the media source.
  final Map<String, String> headers;

  /// When true, render the compact audio card instead of a video surface.
  final bool audioOnly;

  /// Hands this file to another app. When non-null the error card offers it as
  /// a fallback — the codec libmpv can't handle is often one the phone's own
  /// video player can.
  final VoidCallback? onOpenExternally;

  @override
  State<MediaPreviewBody> createState() => _MediaPreviewBodyState();
}

class _MediaPreviewBodyState extends State<MediaPreviewBody> {
  Player? _player;
  VideoController? _controller;

  StreamSubscription<String>? _errorSub;
  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<bool>? _playingSub;
  Timer? _watchdog;

  /// Non-null once anything has gone wrong; drives the error card.
  String? _error;

  /// True from open until the first frame actually plays.
  bool _loading = true;

  /// Set once playback has genuinely started. After that we STOP treating
  /// [PlayerStream.error] as fatal: libmpv also reports non-fatal problems
  /// there, and tearing a playing video down for one of those would be a worse
  /// bug than the black screen this class exists to fix.
  bool _started = false;

  /// Bumped by [_teardown] so a callback from a REPLACED player (a
  /// `waitUntilFirstFrameRendered` future that resolves after Retry swapped the
  /// player out) can't clear the new attempt's loading/watchdog state.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _teardown();
    super.dispose();
  }

  /// Builds a fresh player and starts playback. Safe to call again after
  /// [_teardown] (that is exactly what Retry does).
  Future<void> _start() async {
    final generation = _generation;
    final Player player;
    VideoController? controller;
    try {
      player = Player();
      _player = player;
      if (!widget.audioOnly) {
        controller = VideoController(player);
        _controller = controller;
      }
    } catch (e) {
      if (mounted) setState(() => _fail('$e'));
      return;
    }

    // libmpv surfaces decode/transport failures here, NOT by throwing.
    _errorSub = player.stream.error.listen((message) {
      if (_started) return; // see [_started] — non-fatal once it's playing
      if (mounted) setState(() => _fail(message));
    });
    _bufferingSub = player.stream.buffering.listen((buffering) {
      // `|| !_started` matters: libmpv stops "buffering" as soon as it has
      // demuxed enough, which for a video is well BEFORE (and sometimes
      // instead of) a frame reaching the screen. Clearing the spinner then
      // would leave a bare black rectangle with no sign anything is happening.
      if (mounted && _error == null) {
        setState(() => _loading = buffering || !_started);
      }
    });
    if (controller != null) {
      // VIDEO: the success signal is a rendered FRAME, not `playing`. libmpv
      // happily reports playing while its video output never comes up (the
      // Android emulator does exactly this — `eglCreateContext` fails with
      // EGL_BAD_ATTRIBUTE and every frame is dropped), and trusting `playing`
      // there would cancel the watchdog and hand the user the very black
      // rectangle this class exists to eliminate.
      controller.waitUntilFirstFrameRendered
          .then((_) => _markStarted(generation))
          // Swallowed on purpose: if the first frame never arrives, the
          // watchdog is what surfaces it, with Retry + the app hand-off.
          .catchError((_) {});
    } else {
      // AUDIO: there is no frame to wait for, so `playing` IS the signal.
      _playingSub = player.stream.playing.listen((playing) {
        if (playing) _markStarted(generation);
      });
    }
    _watchdog = Timer(_startTimeout, () {
      if (mounted && _error == null && !_started) {
        setState(
          () => _fail(
            "This media didn't start playing. It may use a format Airclone "
            "can't decode, or the connection may be too slow to stream it.",
          ),
        );
      }
    });

    try {
      // Awaited: open() rejects ASYNCHRONOUSLY, so a bare call would leave the
      // failure unobserved and the user staring at black forever.
      await player.open(
        Media(widget.url, httpHeaders: widget.headers),
        play: true,
      );
    } catch (e) {
      if (mounted) setState(() => _fail('$e'));
    }
  }

  /// Playback is genuinely up: disarm the watchdog, drop the spinner, and stop
  /// treating [PlayerStream.error] as fatal. Ignored if [generation] is stale.
  void _markStarted(int generation) {
    if (generation != _generation) return;
    _started = true;
    _watchdog?.cancel();
    if (mounted && _loading) setState(() => _loading = false);
  }

  /// Records a failure. Call inside setState — it only mutates fields.
  void _fail(String message) {
    _watchdog?.cancel();
    _error = message.trim().isEmpty ? 'Playback failed.' : message.trim();
    _loading = false;
  }

  /// Cancels every subscription and disposes the player. Awaited by [_retry] so
  /// a second libmpv instance never overlaps the first.
  Future<void> _teardown() async {
    // Invalidate any in-flight first-frame callback from the player we're
    // about to drop.
    _generation++;
    _watchdog?.cancel();
    _watchdog = null;
    await _errorSub?.cancel();
    await _bufferingSub?.cancel();
    await _playingSub?.cancel();
    _errorSub = null;
    _bufferingSub = null;
    _playingSub = null;
    final player = _player;
    _player = null;
    _controller = null;
    try {
      await player?.dispose();
    } catch (_) {
      // Already disposed, or never fully constructed.
    }
  }

  Future<void> _retry() async {
    setState(() {
      _error = null;
      _loading = true;
      _started = false;
    });
    await _teardown();
    if (!mounted) return;
    await _start();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AircloneTheme.of(context);
    if (_error != null) return _errorCard(colors, _error!);
    try {
      return widget.audioOnly ? _audio(colors) : _video(colors);
    } catch (e) {
      // Defensive: a render-time failure must not take the preview down.
      return _errorCard(colors, '$e');
    }
  }

  /// Black-backed video surface filling the available space, with a loading
  /// overlay until playback actually starts.
  Widget _video(AircloneColors colors) {
    final controller = _controller;
    return Container(
      color: const Color(0xFF000000),
      alignment: Alignment.center,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (controller != null)
            Positioned.fill(
              child: Video(
                controller: controller,
                controls: AdaptiveVideoControls,
              ),
            ),
          if (_loading) const _Spinner(),
        ],
      ),
    );
  }

  /// Centered audio card: art, play/pause, and a seek slider.
  Widget _audio(AircloneColors colors) {
    final player = _player;
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
                if (player == null)
                  const _Spinner()
                else ...[
                  _PlayPauseButton(player: player, colors: colors),
                  const SizedBox(height: Space.x4),
                  _SeekBar(player: player, colors: colors),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Shared fallback when playback can't be set up, rendered, or sustained.
  /// Always actionable: Retry, plus the hand-off when the host offers one.
  Widget _errorCard(AircloneColors colors, String message) {
    return Container(
      color: colors.surfaceSunken,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(Space.x6),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 40,
              color: colors.textFaint,
            ),
            const SizedBox(height: Space.x3),
            Text(
              "Couldn't play this media",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.text,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: Space.x2),
            Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textMuted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: Space.x4),
            Wrap(
              spacing: Space.x2,
              runSpacing: Space.x2,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Try again'),
                ),
                if (widget.onOpenExternally != null)
                  FilledButton.icon(
                    onPressed: widget.onOpenExternally,
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Open in another app'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Loading indicator sized to read clearly on the black video backdrop.
class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 36,
    height: 36,
    child: CircularProgressIndicator(strokeWidth: 3),
  );
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
