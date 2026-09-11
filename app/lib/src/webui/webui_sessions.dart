/// Session tokens and login throttling for the Web UI.
///
/// Pure Dart with an injected clock, so every expiry and backoff rule is
/// testable without waiting for wall-clock time.
///
/// Sessions live in memory only. Restarting Airclone signs everyone out, which
/// is deliberate: the alternative is a persisted token store, which is a second
/// credential on disk that outlives the process that issued it. Signing in
/// again costs a password paste; getting persistent tokens wrong costs rather
/// more.
library;

import 'dart:convert';
import 'dart:math';

/// How long a session survives without being used. Refreshed on every
/// authenticated request, so an operator with a tab open stays signed in and an
/// abandoned one does not.
const Duration kSessionIdleTimeout = Duration(hours: 12);

/// Failed attempts from one peer before that peer is made to wait.
const int kLoginFailuresBeforeBackoff = 5;

/// First backoff, doubling per subsequent failure up to [kMaxLoginBackoff].
const Duration kInitialLoginBackoff = Duration(seconds: 15);

/// Ceiling on the backoff. Long enough to make online guessing hopeless against
/// a 138-bit password, short enough that an operator who fat-fingered their own
/// password five times is not locked out for the afternoon.
const Duration kMaxLoginBackoff = Duration(minutes: 15);

/// Opaque, in-memory session tokens with a sliding idle expiry.
class WebUiSessions {
  WebUiSessions({
    Duration? idleTimeout,
    Random? random,
    DateTime Function()? clock,
  }) : _idleTimeout = idleTimeout ?? kSessionIdleTimeout,
       _random = random ?? Random.secure(),
       _now = clock ?? DateTime.now;

  final Duration _idleTimeout;
  final Random _random;
  final DateTime Function() _now;

  /// token -> last-seen time.
  final Map<String, DateTime> _sessions = {};

  /// Mints a new session token.
  ///
  /// 32 bytes from a CSPRNG, base64url. The token is the entire credential for
  /// every later request, so it carries at least as much entropy as the
  /// password it was traded for.
  String issue() {
    _sweep();
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    final token = base64Url.encode(bytes).replaceAll('=', '');
    _sessions[token] = _now();
    return token;
  }

  /// Whether [token] is a live session, refreshing its idle clock if so.
  ///
  /// An unknown or expired token is simply false — callers must not distinguish
  /// the two to the client, since "expired" tells an attacker a token was once
  /// real.
  bool validate(String? token) {
    if (token == null || token.isEmpty) return false;
    _sweep();
    final seen = _sessions[token];
    if (seen == null) return false;
    _sessions[token] = _now();
    return true;
  }

  /// Ends one session (sign out). Unknown tokens are ignored.
  void revoke(String? token) {
    if (token != null) _sessions.remove(token);
  }

  /// Ends every session — used when the credentials are rotated, so an old
  /// session cannot outlive the password that created it.
  void revokeAll() => _sessions.clear();

  int get activeCount {
    _sweep();
    return _sessions.length;
  }

  void _sweep() {
    final cutoff = _now().subtract(_idleTimeout);
    _sessions.removeWhere((_, seen) => seen.isBefore(cutoff));
  }
}

/// Per-peer login backoff.
///
/// Keyed by remote address rather than by username: there is only one account,
/// so counting per-username would be one global counter that any attacker could
/// use to lock the real operator out.
class LoginThrottle {
  LoginThrottle({
    DateTime Function()? clock,
    int? failuresBeforeBackoff,
    Duration? initialBackoff,
    Duration? maxBackoff,
  }) : _now = clock ?? DateTime.now,
       _threshold = failuresBeforeBackoff ?? kLoginFailuresBeforeBackoff,
       _initial = initialBackoff ?? kInitialLoginBackoff,
       _max = maxBackoff ?? kMaxLoginBackoff;

  final DateTime Function() _now;
  final int _threshold;
  final Duration _initial;
  final Duration _max;

  final Map<String, _PeerState> _peers = {};

  /// How much longer [key] must wait, or null if it may attempt now.
  Duration? retryAfter(String key) {
    final peer = _peers[key];
    if (peer == null) return null;
    final until = peer.lockedUntil;
    if (until == null) return null;
    final left = until.difference(_now());
    return left.isNegative ? null : left;
  }

  /// Whether [key] may attempt a login right now.
  bool allow(String key) => retryAfter(key) == null;

  /// Records a failed attempt and arms the next backoff if the threshold is
  /// crossed.
  void recordFailure(String key) {
    final peer = _peers.putIfAbsent(key, _PeerState.new);
    peer.failures++;
    peer.lastSeen = _now();
    if (peer.failures < _threshold) return;
    final over = peer.failures - _threshold;
    // Double per failure past the threshold, clamped. Computed in microseconds
    // so a long-running attacker cannot overflow the shift.
    var micros = _initial.inMicroseconds;
    for (var i = 0; i < over && micros < _max.inMicroseconds; i++) {
      micros *= 2;
    }
    final wait = Duration(microseconds: micros.clamp(0, _max.inMicroseconds));
    peer.lockedUntil = _now().add(wait);
  }

  /// Clears [key]'s history after a successful login.
  void recordSuccess(String key) => _peers.remove(key);

  /// Drops peers that have gone quiet, so a long run against a public port
  /// cannot grow this map without bound.
  ///
  /// Staleness is judged on [_PeerState.lastSeen], NOT on whether the peer is
  /// currently locked out. Judging it on the lock was a real bug, caught by
  /// `webui_sessions_test.dart`: a peer below the failure threshold has no
  /// lock yet, so sweeping "everything not locked" deleted its failure count —
  /// and since the server sweeps after every failed sign-in, the count reset
  /// each time and the threshold was never reached. The throttle silently did
  /// nothing at all.
  void sweep({Duration retain = const Duration(hours: 1)}) {
    final cutoff = _now().subtract(retain);
    _peers.removeWhere((_, p) {
      final until = p.lockedUntil;
      // Never drop a peer that is still serving a lockout, however old.
      if (until != null && until.isAfter(_now())) return false;
      return p.lastSeen.isBefore(cutoff);
    });
  }
}

class _PeerState {
  int failures = 0;
  DateTime? lockedUntil;

  /// When this peer last attempted a sign-in. Drives [LoginThrottle.sweep];
  /// see the note there for why it cannot be inferred from [lockedUntil].
  DateTime lastSeen = DateTime.now();
}
