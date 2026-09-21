import 'package:flutter/material.dart';

import 'theme/tokens.dart';
import 'tv.dart' show tvOverscan;
import 'tv_player_keys.dart';
import 'tv_video_controls.dart' show TvScrubBar, TvTransportRow;

/// The audio player a television gets, in place of the pointer card.
///
/// A Google TV user, 2026-09-21: *"If we listen music we cannot go to the next
/// or previous track."* They were not missing a feature. Previous/next buttons
/// shipped on 2026-09-09 and the build in production has them — what they were
/// missing was any way to reach them: the card is capped at 480px in the middle
/// of a 1080p screen, its controls are 28px glyphs, and the only way to a
/// button is hunting with a D-pad. Across a room that is indistinguishable from
/// a player that has no skip controls at all.
///
/// So this is the same set of actions at the scale a television needs, with
/// play/pause already holding focus so the centre button works the instant the
/// screen appears — and with [TvPlaybackKeys] mounted around it, so the remote's
/// own ⏭/⏮ keys do the job without anyone having to find a button first.
///
/// Its controls never hide (`alwaysVisible`), which is why LEFT/RIGHT here move
/// focus along the row rather than scrubbing: on a screen whose whole content
/// IS the transport row, traversal is what the arrows obviously mean, and
/// seeking is the ⏪/⏩ keys' and the row's own job.
class TvNowPlaying extends StatefulWidget {
  const TvNowPlaying({
    super.key,
    required this.controller,
    required this.title,
    this.trailing,
  });

  final TvPlaybackController controller;

  /// The track, as the file is named. Empty renders no title rather than a
  /// placeholder, because a blank line reads better from a sofa than "Unknown".
  final String title;

  /// An extra control at the end of the row — the repeat toggle, built by the
  /// host.
  ///
  /// Passed in as a widget rather than imported: repeat is a preference this
  /// file has no business reading, and taking it as a parameter keeps this
  /// screen renderable in a test with no `ProviderScope` and no libmpv.
  final Widget? trailing;

  @override
  State<TvNowPlaying> createState() => _TvNowPlayingState();
}

class _TvNowPlayingState extends State<TvNowPlaying> {
  /// Focus starts here. On a television the centre button is the primary verb,
  /// and an audio screen whose OK does nothing until you have arrowed around
  /// looking for a target is the problem this whole screen exists to fix.
  final FocusNode _playPause = FocusNode(debugLabel: 'tv now playing play');

  @override
  void initState() {
    super.initState();
    // Post-frame: at build time the row has not been laid out, and a request
    // for an unlaid-out node lands nowhere (the lesson `TvFocusSeed` records).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _playPause.requestFocus();
    });
  }

  @override
  void dispose() {
    _playPause.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AircloneTheme.of(context);
    return ColoredBox(
      color: colors.surfaceSunken,
      child: Padding(
        padding: tvOverscan,
        // Every size below is DERIVED, not chosen. A 1080p television reports
        // 960x540dp at xhdpi, and the overscan inset takes 27dp off each end —
        // so this screen has 486dp of height, not 540. The first hand-tuned
        // version of this layout (240dp of art, 32dp gaps, two lines of 32sp
        // title) came to 493 and overflowed by 7, which is the same shape of
        // mistake as the fixed-width dialogs that clipped their own buttons on
        // a phone: a layout that fits the screen you happened to test on.
        //
        // Deriving it also covers the sets that are not 1080p, and a caller
        // that hands this less room than a full screen.
        child: LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.maxHeight;
            final art = (height * 0.34).clamp(96.0, 240.0);
            // Below this there is no room for two lines of title AND a row
            // that can still be aimed at; the row wins, because it is the
            // thing the user came here to press.
            final tight = height < 460;
            final gap = tight ? Space.x4 : Space.x6;
            return Center(
              child: ConstrainedBox(
                // Wide enough for a real scrub bar on a 1080p set, short of the
                // full width so the layout still reads as a composed screen.
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ArtTile(colors: colors, size: art),
                    SizedBox(height: gap),
                    if (widget.title.isNotEmpty)
                      Text(
                        widget.title,
                        textAlign: TextAlign.center,
                        maxLines: tight ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.text,
                          fontSize: tight ? 26 : 32,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    SizedBox(height: gap),
                    TvScrubBar(
                      controller: widget.controller,
                      onSurface: colors,
                    ),
                    const SizedBox(height: Space.x4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TvTransportRow(
                          controller: widget.controller,
                          playPauseFocus: _playPause,
                          onSurface: colors,
                        ),
                        ?widget.trailing,
                      ],
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
}

/// The album-art stand-in: there is no artwork to show, because reading tags
/// off a cloud object would mean downloading it (see the hydration rule the
/// thumbnail path follows), and a music glyph at this size is honest.
class _ArtTile extends StatelessWidget {
  const _ArtTile({required this.colors, required this.size});

  final AircloneColors colors;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: colors.surfaceRaised,
      borderRadius: BorderRadius.circular(Radii.lg),
      border: Border.all(color: colors.border),
    ),
    child: Icon(
      Icons.music_note_rounded,
      size: size / 2,
      color: colors.primary,
    ),
  );
}
