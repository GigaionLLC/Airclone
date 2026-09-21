/// The sign-in link an OAuth flow is waiting on, and the one shape it may have.
///
/// rclone completes an OAuth flow by binding a listener on a FIXED loopback
/// address and having the provider redirect back to it. Both halves of that
/// address are rclone constants — `lib/oauthutil/oauthutil.go` declares
/// `bindPort = "53682"` and builds every auth URL as
/// `http://127.0.0.1:53682/auth?state=<random>` — which is what makes
/// [parseAuthUrl] safe to key on.
///
/// **Preferred route first.** rclone 1.75 answers `config/oauthstatus` with the
/// live `authUrl`, so an engine that has that method needs none of this. This
/// capability exists for the engines that do not: `RcloneEngine.minRcloneVersion`
/// is 1.73.5, and on desktop the user may point Airclone at their own binary.
/// See `dev/plans/guided-remote-setup-plan.md` §2.4.
library;

import 'package:http/http.dart' as http;

import 'rclone_client.dart';

/// The loopback endpoint rclone always redirects an OAuth sign-in to.
const String kOAuthHost = '127.0.0.1';
const int kOAuthPort = 53682;
const String kOAuthPath = '/auth';

/// An engine that can report the sign-in URL it is waiting on.
///
/// A CAPABILITY interface rather than a widening of `RcloneClient`, for the
/// reason `ObjectUploader` gives: every fake in the test suite implements the
/// client, and none of them care about OAuth.
///
/// The stream carries a parsed [Uri] and never a log line. That is deliberate:
/// the only thing above this package that should be able to say "open this"
/// is an address already checked against rclone's own constants.
abstract interface class AuthUrlObserver {
  /// Auth URLs as the engine reports them. Broadcast; a late listener misses
  /// what it did not hear, so a caller subscribes BEFORE starting the flow.
  Stream<Uri> get authUrls;
}

/// The exact prefix an rclone auth URL starts with. Everything before `state=`
/// is a constant in rclone, so an anchored search cannot be walked off the
/// loopback host by anything appearing earlier in the line.
const String _prefix = 'http://$kOAuthHost:$kOAuthPort$kOAuthPath?state=';

/// Extracts rclone's OAuth URL from one engine log line, or null.
///
/// **This is a security boundary, not a convenience.** What it returns gets
/// handed to the platform URL launcher, and engine log lines are not a trusted
/// channel: at high verbosity rclone echoes back strings it was given, so a
/// remote's name or a server's error text can reach this function. So the
/// scheme, host, port and path are all pinned to rclone's constants and a
/// `state` is required — a line can therefore yield rclone's own loopback
/// listener or nothing at all, never an address of someone else's choosing.
///
/// Covers all three wordings rclone uses (`oauthutil.go`): "Please go to the
/// following link", "If your browser doesn't open automatically go to the
/// following link", and the `Failed to open browser automatically (%v) - please
/// go to the following link" error variant.
Uri? parseAuthUrl(String line) {
  // A log line is one line. Anything this long is not one, and scanning it is
  // work done on behalf of whoever made it long.
  if (line.length > 4096) return null;
  final start = line.indexOf(_prefix);
  if (start < 0) return null;

  var end = start;
  while (end < line.length && !_endsUrl(line.codeUnitAt(end))) {
    end++;
  }
  // rclone writes the URL last on the line, but a wrapping logger may add
  // sentence punctuation; none of it is part of a URL.
  while (end > start && _trailingPunctuation.contains(line[end - 1])) {
    end--;
  }
  return asAuthUrl(line.substring(start, end));
}

/// The same check as [parseAuthUrl], applied to a candidate that arrived whole
/// rather than inside a log line — `config/oauthstatus`'s `authUrl` field.
///
/// Checked even though it comes from our own engine. It costs one comparison,
/// it means there is exactly ONE definition of "a URL this app may open", and
/// a field we merely trust is how the definition drifts.
Uri? asAuthUrl(String candidate) {
  if (candidate.length > 4096) return null;
  final uri = Uri.tryParse(candidate);
  if (uri == null) return null;
  // Every part re-checked AFTER parsing. A prefix match says the text looked
  // right; only the parse says what a URL library will actually resolve it to.
  if (uri.scheme != 'http') return null;
  if (uri.host != kOAuthHost) return null;
  if (uri.port != kOAuthPort) return null;
  if (uri.path != kOAuthPath) return null;
  if (uri.userInfo.isNotEmpty) return null;
  final state = uri.queryParameters['state'];
  if (state == null || state.isEmpty) return null;
  return uri;
}

/// Characters that cannot appear inside a URL and so end one.
bool _endsUrl(int codeUnit) =>
    codeUnit <= 0x20 || // space, tab, CR, LF and the rest of the controls
    codeUnit == 0x22 || // "
    codeUnit == 0x27 || // '
    codeUnit == 0x3C || // <
    codeUnit == 0x3E || // >
    codeUnit == 0x60; // `

const String _trailingPunctuation = '.,;:)]}';

/// The sign-in URL the engine is waiting on right now, or null if none is.
///
/// Asks `config/oauthstatus`, which rclone 1.75 added (plan §2.4). Returns null
/// — rather than throwing — when the engine does not have the method, so the
/// caller can decide once whether to fall back to [AuthUrlObserver].
///
/// [supported] reports whether the method exists, so a caller can stop asking.
Future<({Uri? url, bool supported})> fetchAuthUrl(RcloneClient client) async {
  try {
    final res = await client.rpc('config/oauthstatus');
    if (res['status'] != 'running') return (url: null, supported: true);
    final raw = res['authUrl'];
    return (url: raw is String ? asAuthUrl(raw) : null, supported: true);
  } on RcloneException {
    return (url: null, supported: false);
  }
}

/// Ends a sign-in that is waiting, and frees the port it holds.
///
/// Returns true when the flow is known to be stopped afterwards.
///
/// **An engine with nothing running counts as success.** `config/oauthstop`
/// answers HTTP 500 `no oauth authentication is in progress` in that case, which
/// is not a failed cancel — it is the state cancel was asked to reach. Treating
/// it as an error would put a scary message in front of someone who pressed
/// Cancel twice.
///
/// Pre-1.75 engines have no such method. For those there is still a way in:
/// rclone's redirect handler pushes a failure onto the same channel the flow is
/// blocked on for ANY request to `/` that carries no `code`, so a plain GET both
/// unblocks it and releases the listener (plan §2.1.8, verified §2.2).
Future<bool> cancelOAuth(RcloneClient client) async {
  try {
    await client.rpc('config/oauthstop');
    return true;
  } on RcloneException catch (e) {
    if (e.message.contains('no oauth authentication is in progress')) {
      return true;
    }
    // Any other failure — including "method not found" on an older engine —
    // falls through to the loopback route below.
  }
  try {
    await http
        .get(Uri.parse('http://$kOAuthHost:$kOAuthPort/'))
        .timeout(const Duration(seconds: 5));
    return true;
  } catch (_) {
    // Nothing listening is the outcome cancel wanted; anything else is a
    // genuine failure the caller reports rather than swallows.
    return false;
  }
}
