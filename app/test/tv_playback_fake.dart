import 'dart:async';

import 'package:airclone/src/state/media_tracks.dart';
import 'package:airclone/src/ui/tv_player_keys.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

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
  final _tracks = StreamController<Tracks>.broadcast();
  final _subtitle = StreamController<List<String>>.broadcast();

  /// The subtitle lines on screen. Assign through [setSubtitleLines].
  @override
  List<String> subtitle = const [];

  void setSubtitleLines(List<String> lines) {
    subtitle = lines;
    _subtitle.add(lines);
  }

  @override
  Stream<List<String>> get subtitleStream => _subtitle.stream;

  /// The file's tracks. Assign through [setTracks] so the stream hears it too.
  @override
  Tracks tracks = const Tracks();

  void setTracks(Tracks value) {
    tracks = value;
    _tracks.add(value);
  }

  /// What mpv would report as selected (`aid` / `sid`).
  String selectedAudio = 'auto';
  String selectedSubtitle = 'auto';

  /// Every track the player was told to switch to, in order.
  final List<AudioTrack> audioSets = [];
  final List<SubtitleTrack> subtitleSets = [];

  /// When true, [playOrPause] does not change [playing] until
  /// [reportPlaying] — the order a real player reports it in.
  bool lagPlayingState = false;

  @override
  void playOrPause() {
    playPauseCalls++;
    if (lagPlayingState) return;
    reportPlaying(!playing);
  }

  void reportPlaying(bool value) {
    playing = value;
    _playing.add(value);
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
  @override
  Stream<Tracks> get tracksStream => _tracks.stream;

  @override
  Future<TrackSelection> selection() async =>
      (audio: selectedAudio, subtitle: selectedSubtitle);

  @override
  Future<void> setAudio(AudioTrack track) async {
    audioSets.add(track);
    selectedAudio = track.id;
  }

  @override
  Future<void> setSubtitle(SubtitleTrack track) async {
    subtitleSets.add(track);
    selectedSubtitle = track.id;
  }

  void dispose() {
    _playing.close();
    _position.close();
    _duration.close();
    _buffer.close();
    _tracks.close();
    _subtitle.close();
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

/// The auto-repeat Android sends while a key stays down.
KeyRepeatEvent repeat(LogicalKeyboardKey key) => KeyRepeatEvent(
  logicalKey: key,
  physicalKey: PhysicalKeyboardKey.f13,
  timeStamp: Duration.zero,
);

/// The release. It matters for exactly one pair — a held ⏪/⏩ stops on it.
KeyUpEvent up(LogicalKeyboardKey key) => KeyUpEvent(
  logicalKey: key,
  physicalKey: PhysicalKeyboardKey.f13,
  timeStamp: Duration.zero,
);
