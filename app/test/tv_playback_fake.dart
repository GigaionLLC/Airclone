import 'dart:async';

import 'package:airclone/src/ui/tv_player_keys.dart';
import 'package:flutter/services.dart';

/// A player that is not a player.
///
/// Shared by every TV playback test, and the reason [TvPlaybackTarget] is an
/// interface at all: constructing a real media_kit `Player` initialises libmpv,
/// so without this seam none of the timing rules — coalescing, acceleration,
/// clamping, auto-hide — could be tested anywhere except on a television.
///
/// The streams are broadcast controllers rather than empty ones so a test can
/// also drive what the overlay *displays*, not only what the controller decides.
class FakeTarget implements TvPlaybackTarget {
  FakeTarget({
    this.playing = true,
    this.position = const Duration(minutes: 5),
    this.duration = const Duration(hours: 2),
  });

  @override
  bool playing;
  @override
  Duration position;
  @override
  Duration duration;
  @override
  Duration buffer = Duration.zero;

  /// Every seek that actually reached the player, in order. The assertion for
  /// "ten presses are one seek" is the length of this list.
  final List<Duration> seeks = [];
  int playPauseCalls = 0;

  final _playing = StreamController<bool>.broadcast();
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _buffer = StreamController<Duration>.broadcast();

  @override
  void playOrPause() {
    playPauseCalls++;
    playing = !playing;
    _playing.add(playing);
  }

  @override
  void seek(Duration to) {
    seeks.add(to);
    position = to;
    _position.add(to);
  }

  @override
  Stream<bool> get playingStream => _playing.stream;
  @override
  Stream<Duration> get positionStream => _position.stream;
  @override
  Stream<Duration> get durationStream => _duration.stream;
  @override
  Stream<Duration> get bufferStream => _buffer.stream;

  void dispose() {
    _playing.close();
    _position.close();
    _duration.close();
    _buffer.close();
  }
}

/// A key event shaped like the ones Android actually delivers.
///
/// The physical key is deliberately irrelevant: every rule under test is keyed
/// off the LOGICAL key, which is what Flutter's android mapping produces and
/// what the bindings match on.
KeyDownEvent down(LogicalKeyboardKey key) => KeyDownEvent(
  logicalKey: key,
  physicalKey: PhysicalKeyboardKey.f13,
  timeStamp: Duration.zero,
);
