import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';

import '../state/android_native.dart' show androidIsTelevision;

/// Turns a remote into transport controls.
///
/// A Google TV user, 2026-09-21: *"If we listen music we cannot go to the next
/// or previous track. If we watch video we cannot skip forward or backward in
/// the video while it's playing."*
///
/// The buttons for the first half have existed since 2026-09-09 and production
/// ships them — the user has them and still could not change track, because a
/// 480px card of 28px icons in the middle of a television, reachable only by
/// hunting with a D-pad, is not how anyone changes a track. The second half was
/// absent outright: `AdaptiveVideoControls` routes Android to media_kit's TOUCH
/// controls, which contain no key handling and only appear from `onTap` — an
/// input a D-pad cannot produce. So on a television a film played and the only
/// thing the remote could do was leave.
///
/// Both halves are the same missing thing: the keys. This file owns them.
///
/// MEASURED, not assumed (spike 2026-09-21, `sdk_google_atv64_x86_64`): Android
/// hands every transport keycode to the foreground app — 85 PLAY_PAUSE, 126
/// PLAY, 127 PAUSE, 86 STOP, 89 REWIND, 90 FAST_FORWARD, 87 NEXT, 88 PREVIOUS —
/// and Flutter maps all of them to `LogicalKeyboardKey.media*`. No MediaSession
/// is needed to receive them. (A *foreign* MediaSession on a real television can
/// still claim them before the app; that case cannot be staged on an emulator,
/// and the D-pad path does not depend on it.)
///
/// The behaviour lives here and the pixels live in `tv_video_controls.dart` /
/// `tv_now_playing.dart`, so every timing rule below is testable without
/// libmpv, a television, or a rendered frame.

/// Everything the key layer needs from a player.
///
/// An interface rather than a direct [Player] dependency for one reason that
/// matters: constructing a real [Player] in a widget test initialises libmpv.
/// Every rule in [TvPlaybackController] — coalescing, acceleration, clamping —
/// is arithmetic over these five members, so with this seam the rules are
/// provable on a fake in milliseconds instead of unprovable on a television.
abstract interface class TvPlaybackTarget {
  bool get playing;
  Duration get position;

  /// [Duration.zero] when unknown, which is the live-stream case: nothing to
  /// seek within, so seeking is disabled rather than silently doing nothing.
  Duration get duration;

  /// How much is buffered ahead, for the overlay's second track. Never more
  /// than [duration].
  Duration get buffer;

  void playOrPause();
  void seek(Duration to);

  // The same four values as streams, so the overlay can rebuild on its own
  // without the controller having to poll or notify per frame. They are part
  // of this seam rather than read off a [Player] directly for exactly the
  // reason the seam exists: the overlay is then provable on a fake too, and
  // "the controls appeared" stops needing a television to check.
  Stream<bool> get playingStream;
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<Duration> get bufferStream;
}

/// [TvPlaybackTarget] backed by media_kit.
///
/// Every call is wrapped: libmpv reports transient control failures by throwing
/// from an otherwise healthy player, and a remote press must never be able to
/// take the preview down (the lesson of `MediaPreviewBody`'s whole error path).
class MediaKitPlaybackTarget implements TvPlaybackTarget {
  MediaKitPlaybackTarget(this.player);

  final Player player;

  @override
  bool get playing => player.state.playing;

  @override
  Duration get position => player.state.position;

  @override
  Duration get duration => player.state.duration;

  @override
  Duration get buffer => player.state.buffer;

  @override
  Stream<bool> get playingStream => player.stream.playing;

  @override
  Stream<Duration> get positionStream => player.stream.position;

  @override
  Stream<Duration> get durationStream => player.stream.duration;

  @override
  Stream<Duration> get bufferStream => player.stream.buffer;

  @override
  void playOrPause() {
    try {
      player.playOrPause();
    } catch (_) {
      // Transient control failure; the next press will try again.
    }
  }

  @override
  void seek(Duration to) {
    try {
      player.seek(to);
    } catch (_) {
      // Seeking past the end of a still-buffering stream can throw.
    }
  }
}

/// Which controls a surface shows, and therefore what the arrows mean.
///
/// This is the whole reason LEFT/RIGHT can be both "seek" and "move focus"
/// without ambiguity, and it mirrors what every television media app does:
///
/// * [hidden] — a film is playing and nothing is on screen. LEFT/RIGHT scrub.
/// * [scrubbing] — the overlay is up *because* the user is seeking. LEFT/RIGHT
///   keep scrubbing, so a run of presses is one gesture rather than one seek
///   followed by focus wandering into a button.
/// * [browsing] — the overlay is up and the transport row has focus. LEFT/RIGHT
///   belong to focus traversal now, and seeking is the ⏪/⏩ keys' job. An audio
///   surface is always in this mode: its controls never hide.
enum TvControlsMode { hidden, scrubbing, browsing }

/// The key semantics, the seek arithmetic, and the two timers.
///
/// Owns no widgets on purpose. A [ChangeNotifier] so the overlay can rebuild
/// from it, and so a test can drive keys in and assert on state without
/// pumping anything.
class TvPlaybackController extends ChangeNotifier {
  TvPlaybackController({
    required this.target,
    this.onPrevious,
    this.onNext,
    this.alwaysVisible = false,
    this.tvKeysEnabled = true,
  }) : _mode = alwaysVisible ? TvControlsMode.browsing : TvControlsMode.hidden {
    _mediaKeyOwners.add(this);
  }

  final TvPlaybackTarget target;

  /// Move to the sibling before / after this file, or null at the ends. Same
  /// contract as `AudioSkipButton`: null means *disabled*, not absent, so the
  /// control row does not reflow as you move through an album.
  ///
  /// Mutable, because the host rebuilds with new closures — and at the ends of
  /// the list with a *null* one — while this controller and its player live on.
  /// Final fields would pin the row to whatever the first build happened to
  /// pass, which at the start of an album is "previous is dead, forever".
  VoidCallback? onPrevious;
  VoidCallback? onNext;

  /// True for the audio surface, whose controls are the screen rather than an
  /// overlay. Keeps the mode in [TvControlsMode.browsing] for good.
  final bool alwaysVisible;

  /// False off a television. The MEDIA keys still work — a keyboard's transport
  /// keys and a Bluetooth remote paired to a phone are the same keys, and
  /// honouring them costs nothing — but the D-pad and OK bindings are gated,
  /// because on a desktop those arrows already mean something else.
  final bool tvKeysEnabled;

  /// How long after the last press a coalesced seek commits.
  ///
  /// The point of a debounce here is not smoothness, it is the network: every
  /// commit can force a fresh ranged request for a cloud object through the
  /// engine, so ten fast presses must be ONE seek of −100s and not ten seeks.
  static const Duration commitDelay = Duration(milliseconds: 350);

  /// How long the overlay stays up after the last press. Never applies while
  /// paused — a paused film with no controls is the dead end this file exists
  /// to remove.
  static const Duration autoHideDelay = Duration(seconds: 5);

  /// The steps a burst walks through. A two-hour film is unusable at a fixed
  /// 10s, and a 30-second clip is unusable at 60.
  static const List<int> stepSeconds = [10, 30, 60];

  /// Presses per step before moving to the next one.
  static const int pressesPerStep = 4;

  /// What ⏪ / ⏩ move by. Deliberately not the accelerating D-pad step: a
  /// dedicated key is pressed deliberately, and its meaning should not depend
  /// on how fast the last one was.
  static const Duration transportStep = Duration(seconds: 30);

  /// How long ⏪/⏩ must stay held before a tap becomes a continuous scan.
  ///
  /// A Google TV user, 2026-09-25: *"as long as the Skip Forward or Skip
  /// Backward button remains pressed, the video continues moving forward or
  /// backward. It would stop when the button is released."* A tap is still one
  /// [transportStep]; holding past this keeps going.
  static const Duration holdDelay = Duration(milliseconds: 400);

  /// How often a held ⏪/⏩ advances the pending target. The steps accelerate
  /// through [stepSeconds] exactly as a D-pad burst does, so a long hold
  /// crosses a film in seconds while a short one stays precise.
  static const Duration scanInterval = Duration(milliseconds: 250);

  /// A hold with no key event for this long is treated as released.
  ///
  /// Android repeats a held key continuously, so silence means the key-up was
  /// lost (focus moved, the route changed). Without this a lost key-up would
  /// scan on to the end of the film.
  static const Duration holdWatchdog = Duration(milliseconds: 1200);

  TvControlsMode _mode;
  TvControlsMode get mode => _mode;
  bool get controlsVisible => alwaysVisible || _mode != TvControlsMode.hidden;

  /// Where a committed seek would land, or null when nothing is pending. The
  /// overlay shows this immediately, which is what makes a scrub feel instant
  /// while the actual seek is still being coalesced.
  Duration? get pendingTarget => _pending == null ? null : _clamp(_pending!);

  /// True when the media has a known length. A live stream has none, so its
  /// overlay says so instead of offering a scrub bar that cannot move.
  bool get seekable => target.duration > Duration.zero;

  Duration? _pending;
  Duration _burstBaseline = Duration.zero;
  int _burstPresses = 0;
  Timer? _commitTimer;
  Timer? _hideTimer;

  /// Direction of a held ⏪/⏩ (−1 / +1), or 0 when nothing is held.
  int _holdDirection = 0;
  int get holdDirection => _holdDirection;
  int _scanTicks = 0;
  Timer? _holdTimer;
  Timer? _scanTimer;
  Timer? _watchdog;

  // ── media-key ownership ────────────────────────────────────────────────────
  //
  // The D-pad bindings are focus-scoped: they live on an ancestor Focus of the
  // player, so they cannot hijack arrows anywhere else in the app. The MEDIA
  // keys must work wherever focus happens to be inside the preview route —
  // including on Quick Look's own close button, which is outside the media body
  // — so those are delivered globally while mounted instead.
  //
  // Global means two controllers can exist at once: a PageView builds the
  // neighbouring page during a swipe, and each page has its own player. Newest
  // wins, which is the one the user is looking at, and disposal pops back to
  // the previous owner rather than leaving the keys dead.
  static final List<TvPlaybackController> _mediaKeyOwners = [];
  bool get ownsMediaKeys =>
      _mediaKeyOwners.isNotEmpty && _mediaKeyOwners.last == this;

  @override
  void dispose() {
    _commitTimer?.cancel();
    _hideTimer?.cancel();
    _cancelHoldTimers();
    _mediaKeyOwners.remove(this);
    super.dispose();
  }

  // ── keys ───────────────────────────────────────────────────────────────────

  /// The focus-scoped half: D-pad, OK and BACK.
  ///
  /// Returns [KeyEventResult.ignored] for everything it does not act on, so
  /// focus traversal and every other binding in the app keep working. Getting
  /// this wrong is how a TV fix becomes the next "the D-pad does nothing"
  /// report.
  KeyEventResult handleKey(KeyEvent event) {
    // Media keys first: they mean the same thing in every mode, and they are
    // the only keys honoured off a television. Checked before the key-up
    // filter because a held ⏪/⏩ ends on its key-up.
    if (_handleMediaKey(event)) return KeyEventResult.handled;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (!tvKeysEnabled) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      // In browsing mode the arrows belong to the transport row's own focus
      // traversal. Seeking from there is what ⏪/⏩ are for.
      if (_mode == TvControlsMode.browsing) return KeyEventResult.ignored;
      nudge(key == LogicalKeyboardKey.arrowLeft ? -1 : 1);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      // Reveal the controls and hand the keys on, so the same press that
      // summons the row also moves into it.
      if (controlsVisible && _mode == TvControlsMode.browsing) {
        _armAutoHide();
        return KeyEventResult.ignored;
      }
      commitPending();
      _show(TvControlsMode.browsing);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.gameButtonA) {
      // A HELD OK is one press. Its repeats are swallowed here, in every mode:
      // on the surface each repeat would toggle playback again, and in the row
      // Flutter's activation fires on repeats too, so a held OK on play/pause
      // flickered between play and pause and landed wherever it stopped. The
      // ⏪/⏩ buttons see a hold before this does (see `_TvSeekHold` in tv_video_controls.dart).
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      // With the row up, OK belongs to whatever button holds focus.
      if (_mode == TvControlsMode.browsing) return KeyEventResult.ignored;
      commitPending();
      playPause();
      _show(TvControlsMode.browsing);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.browserBack) {
      // Hide the overlay if it is up; otherwise let the route close, which is
      // what BACK means everywhere else on a television.
      if (!alwaysVisible && controlsVisible) {
        commitPending();
        hideControls();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    return KeyEventResult.ignored;
  }

  /// The global half. Returns true when the key was ours.
  ///
  /// Also the [HardwareKeyboard] entry point — see [ownsMediaKeys].
  bool handleMediaKeyGlobally(KeyEvent event) {
    if (!ownsMediaKeys) return false;
    return _handleMediaKey(event);
  }

  bool _handleMediaKey(KeyEvent event) {
    final key = event.logicalKey;
    // ⏪/⏩ are the one pair where the key-UP matters: holding them scans, and
    // releasing stops. Every phase of them is ours.
    if (key == LogicalKeyboardKey.mediaFastForward ||
        key == LogicalKeyboardKey.mediaRewind) {
      final direction = key == LogicalKeyboardKey.mediaRewind ? -1 : 1;
      if (event is KeyDownEvent) {
        beginHold(direction);
      } else if (event is KeyRepeatEvent) {
        holdHeartbeat();
      } else if (event is KeyUpEvent) {
        endHold();
      }
      return true;
    }
    if (event is KeyUpEvent) return false;
    if (event is KeyRepeatEvent) {
      // A held transport key is one press, same as a held OK. Claimed so the
      // repeat cannot fall through to a focused button either.
      return _isMediaKey(key);
    }

    if (key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause) {
      // One binding for all three. A remote that sends PLAY while already
      // playing is asking for nothing; toggling is what the user meant, and
      // media_kit exposes no idempotent play on this seam.
      commitPending();
      playPause();
      if (!alwaysVisible) _show(TvControlsMode.browsing);
      return true;
    }
    if (key == LogicalKeyboardKey.mediaStop) {
      // Pause, not close. A stream we cannot cheaply restart is worse to stop
      // than to pause, and BACK already means leave.
      if (target.playing) playPause();
      if (!alwaysVisible) _show(TvControlsMode.browsing);
      return true;
    }
    if (key == LogicalKeyboardKey.mediaTrackNext) {
      onNext?.call();
      return true;
    }
    if (key == LogicalKeyboardKey.mediaTrackPrevious) {
      onPrevious?.call();
      return true;
    }
    return false;
  }

  static bool _isMediaKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.mediaPlayPause ||
      key == LogicalKeyboardKey.mediaPlay ||
      key == LogicalKeyboardKey.mediaPause ||
      key == LogicalKeyboardKey.mediaStop ||
      key == LogicalKeyboardKey.mediaTrackNext ||
      key == LogicalKeyboardKey.mediaTrackPrevious;

  // ── actions────────────────────────────────────────────────────────────────

  void playPause() {
    target.playOrPause();
    // A paused surface keeps its controls: see [autoHideDelay].
    _armAutoHide();
    notifyListeners();
  }

  /// One D-pad press in [direction] (−1 back, +1 forward).
  ///
  /// Accelerates within a burst and coalesces into a single committed seek.
  /// The pending offset is measured from the position at the START of the
  /// burst, not from a freshly-read position: playback keeps advancing while
  /// the user presses, and re-reading would make each press land somewhere
  /// slightly different from where the overlay said it would.
  ///
  /// A "burst" is simply the run of presses that has not committed yet — there
  /// is no separate press-timing window, because there does not need to be
  /// one. A pause longer than [commitDelay] commits and resets by definition,
  /// so the uncommitted run already *is* "how fast are you pressing". Measuring
  /// it any other way would mean a second clock that a test cannot move, and
  /// two clocks that can disagree about the same press.
  void nudge(int direction) {
    if (!seekable) {
      // Nothing to seek within. Show the controls so the overlay can say why,
      // rather than leaving the press looking dropped.
      _show(TvControlsMode.scrubbing);
      return;
    }
    if (_pending == null) {
      _burstPresses = 0;
      _burstBaseline = target.position;
    }
    _burstPresses++;

    final tier = ((_burstPresses - 1) ~/ pressesPerStep).clamp(
      0,
      stepSeconds.length - 1,
    );
    var step = Duration(seconds: stepSeconds[tier]);
    // Never jump more than a tenth of the media per press: on a 30-second clip
    // a 60-second step is the end of the file every time.
    final cap = target.duration ~/ 10;
    if (cap > Duration.zero && step > cap) step = cap;

    _pending = (_pending ?? _burstBaseline) + step * direction;
    _show(TvControlsMode.scrubbing);
    _commitTimer?.cancel();
    _commitTimer = Timer(commitDelay, commitPending);
    notifyListeners();
  }

  /// A single deliberate jump (the ⏪/⏩ keys, and the overlay's own buttons).
  /// Coalesced like [nudge], so a run of taps is still one seek.
  ///
  /// Does NOT leave [TvControlsMode.browsing]. It used to switch to scrubbing,
  /// which hands focus from the row to the video surface — so after one press
  /// of the on-screen ⏩ the next OK landed on the surface, toggled playback
  /// and put focus back on Play. The user could skip once and never again
  /// (field report, 2026-09-25). Pressed from the row, focus now stays on the
  /// button that was pressed.
  void seekBy(Duration delta) {
    _addToPending(delta);
    _commitTimer?.cancel();
    _commitTimer = null;
    // A hold owns the commit: it lands on release, never mid-scan.
    if (_pending != null && _holdDirection == 0) {
      _commitTimer = Timer(commitDelay, commitPending);
    }
  }

  void _addToPending(Duration delta) {
    final mode = _mode == TvControlsMode.browsing
        ? TvControlsMode.browsing
        : TvControlsMode.scrubbing;
    if (!seekable) {
      _show(mode);
      return;
    }
    // Clamped as it accumulates, so a scan pinned at an end stops there
    // instead of banking minutes that the first press the other way must undo.
    _pending = _clamp((_pending ?? target.position) + delta);
    _show(mode);
    notifyListeners();
  }

  /// ⏪/⏩ went down (−1 back, +1 forward). A tap is one [transportStep]; held
  /// past [holdDelay] it scans until [endHold].
  void beginHold(int direction) {
    if (_holdDirection == direction) {
      // A second key-down with no key-up between is a repeat by another name.
      holdHeartbeat();
      return;
    }
    if (_holdDirection != 0) endHold();
    if (!seekable) {
      seekBy(transportStep * direction); // shows the overlay's "Live" state
      return;
    }
    _holdDirection = direction;
    _scanTicks = 0;
    seekBy(transportStep * direction);
    _holdTimer = Timer(holdDelay, () {
      _holdTimer = null;
      _scanTimer = Timer.periodic(scanInterval, (_) => _scanTick());
      _scanTick();
    });
    holdHeartbeat();
  }

  /// The held key is still down. Only feeds the watchdog: the scan keeps its
  /// own pace rather than the remote's repeat rate, which varies by remote.
  void holdHeartbeat() {
    if (_holdDirection == 0) return;
    _watchdog?.cancel();
    _watchdog = Timer(holdWatchdog, endHold);
  }

  /// ⏪/⏩ came up. Commits after [commitDelay] like any other seek, so quick
  /// taps still coalesce into one request.
  void endHold() {
    if (_holdDirection == 0) return;
    _holdDirection = 0;
    _cancelHoldTimers();
    _commitTimer?.cancel();
    _commitTimer = _pending == null ? null : Timer(commitDelay, commitPending);
    notifyListeners();
  }

  void _scanTick() {
    if (_holdDirection == 0) return;
    final tier = (_scanTicks ~/ pressesPerStep).clamp(
      0,
      stepSeconds.length - 1,
    );
    _scanTicks++;
    var step = Duration(seconds: stepSeconds[tier]);
    final cap = target.duration ~/ 10;
    if (cap > Duration.zero && step > cap) step = cap;
    _addToPending(step * _holdDirection);
  }

  void _cancelHoldTimers() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _scanTimer?.cancel();
    _scanTimer = null;
    _watchdog?.cancel();
    _watchdog = null;
  }

  /// Commits whatever the scrub added up to. Safe to call with nothing pending.
  void commitPending() {
    _commitTimer?.cancel();
    _commitTimer = null;
    final pending = _pending;
    if (pending == null) return;
    _pending = null;
    _burstPresses = 0;
    target.seek(_clamp(pending));
    notifyListeners();
  }

  void showControls() => _show(TvControlsMode.browsing);

  void hideControls() {
    if (alwaysVisible) return;
    _hideTimer?.cancel();
    _hideTimer = null;
    if (_mode == TvControlsMode.hidden) return;
    _mode = TvControlsMode.hidden;
    notifyListeners();
  }

  void _show(TvControlsMode mode) {
    final changed = _mode != mode;
    _mode = alwaysVisible ? TvControlsMode.browsing : mode;
    _armAutoHide();
    if (changed) notifyListeners();
  }

  void _armAutoHide() {
    _hideTimer?.cancel();
    _hideTimer = null;
    if (alwaysVisible) return;
    // A paused film keeps its controls, and so does a pending scrub — both are
    // states the user is in the middle of.
    if (!target.playing || _pending != null) return;
    _hideTimer = Timer(autoHideDelay, hideControls);
  }

  Duration _clamp(Duration at) {
    if (at < Duration.zero) return Duration.zero;
    final end = target.duration;
    if (end > Duration.zero && at > end) return end;
    return at;
  }
}

/// Mounts [TvPlaybackController]'s two key paths around a player surface.
///
/// The split is deliberate and is explained at [TvPlaybackController.ownsMediaKeys]:
/// the D-pad is focus-scoped (an ancestor [Focus], so it cannot take arrows from
/// the rest of the app), while the media keys are global while mounted (so they
/// work wherever focus sits inside the preview).
///
/// This node never takes focus itself. It must not be a traversal stop — a
/// remote pressing DOWN should reach a control, not an invisible wrapper — and
/// key events bubble to it from whatever inside does hold focus.
class TvPlaybackKeys extends StatefulWidget {
  const TvPlaybackKeys({
    super.key,
    required this.controller,
    required this.child,
  });

  final TvPlaybackController controller;
  final Widget child;

  @override
  State<TvPlaybackKeys> createState() => _TvPlaybackKeysState();
}

class _TvPlaybackKeysState extends State<TvPlaybackKeys> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_global);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_global);
    super.dispose();
  }

  bool _global(KeyEvent event) =>
      widget.controller.handleMediaKeyGlobally(event);

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: (_, event) => widget.controller.handleKey(event),
    child: widget.child,
  );
}

/// True when this build should use the television player surfaces.
///
/// One gate, in one place, so the answer cannot drift between the three files
/// that ask it. False on every phone, tablet and desktop.
bool get tvPlayerEnabled => androidIsTelevision;
