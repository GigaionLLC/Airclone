/// How the Web UI server was asked to listen — parsed from the command line, or
/// built from the desktop app's saved settings.
///
/// Pure: no `dart:io`, no engine, no filesystem. That keeps the parsing —
/// including every way a bind address can be wrong — unit-testable without
/// opening a socket, which matters because a mistake here is a security
/// mistake: binding somewhere the operator did not ask for is exactly the
/// failure this feature must never have.
library;

/// Enables the Web UI server. Without it the other two flags are inert.
const String kWebUiFlag = '--webui';

/// Address to listen on. Default [kDefaultWebUiBind].
const String kWebUiBindFlag = '--webui-bind';

/// TCP port to listen on. Default [kDefaultWebUiPort].
const String kWebUiPortFlag = '--webui-port';

/// Loopback only. The default, and deliberately so: a Web UI reachable from the
/// network on first launch — before the operator has seen the generated
/// password — would be a hole opened by merely starting the app.
const String kDefaultWebUiBind = '127.0.0.1';

/// Airclone's own port. Not rclone's 5572: the rc daemon may well be listening
/// on that on the same host, and two things fighting over one port is a
/// confusing first five minutes.
const int kDefaultWebUiPort = 5799;

/// Spelled-out alias for "every interface", accepted because `0.0.0.0` is easy
/// to typo into something that silently means one specific interface.
const String kBindAllAlias = 'all';

/// A validated request to run the Web UI server.
class WebUiOptions {
  const WebUiOptions({
    this.enabled = false,
    this.bindAddress = kDefaultWebUiBind,
    this.port = kDefaultWebUiPort,
  });

  /// Whether `--webui` was present.
  final bool enabled;

  /// The resolved literal address to bind, after alias expansion.
  final String bindAddress;

  final int port;

  /// Whether [bindAddress] is reachable only from this machine.
  ///
  /// Drives the exposure warning, so it errs toward calling something exposed:
  /// an address this does not recognise as loopback is treated as reachable.
  bool get isLoopback =>
      bindAddress == '127.0.0.1' ||
      bindAddress == '::1' ||
      bindAddress.startsWith('127.');

  /// Whether this binds every interface on the machine.
  bool get isAllInterfaces => bindAddress == '0.0.0.0' || bindAddress == '::';

  /// The URL to hand a human. Loopback addresses are shown as `localhost`
  /// (what they will actually type); `0.0.0.0` is meaningless in a browser, so
  /// it too is shown as `localhost` — the operator reaches it that way from the
  /// host, and from elsewhere they must substitute the machine's real address,
  /// which this code cannot know.
  String get displayUrl {
    final host = (isLoopback || isAllInterfaces)
        ? 'localhost'
        : (bindAddress.contains(':') ? '[$bindAddress]' : bindAddress);
    return 'https://$host:$port/';
  }

  WebUiOptions copyWith({bool? enabled, String? bindAddress, int? port}) =>
      WebUiOptions(
        enabled: enabled ?? this.enabled,
        bindAddress: bindAddress ?? this.bindAddress,
        port: port ?? this.port,
      );
}

/// The outcome of parsing. [errors] being non-empty means **do not start** —
/// callers must not fall back to a default, because an operator who asked for
/// one address and silently got another has been misled about their exposure.
class WebUiOptionsParse {
  const WebUiOptionsParse(this.options, this.errors);

  final WebUiOptions options;
  final List<String> errors;

  bool get ok => errors.isEmpty;
}

/// Whether [args] request the Web UI server. Mirrors the shape of
/// `isHeadlessInvocation`, including the `=`-joined form.
bool isWebUiInvocation(List<String> args) {
  for (final a in args) {
    if (a == kWebUiFlag || a.startsWith('$kWebUiFlag=')) return true;
  }
  return false;
}

/// The value following [flag], accepting `--flag value` and `--flag=value`.
/// Null when absent or trailing with no value.
String? _flagValue(List<String> args, String flag) {
  final joined = '$flag=';
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == flag) return (i + 1 < args.length) ? args[i + 1] : null;
    if (a.startsWith(joined)) return a.substring(joined.length);
  }
  return null;
}

/// Whether [s] is a dotted-quad IPv4 literal.
bool _isIpv4(String s) {
  final parts = s.split('.');
  if (parts.length != 4) return false;
  for (final p in parts) {
    if (p.isEmpty || p.length > 3) return false;
    final n = int.tryParse(p);
    if (n == null || n < 0 || n > 255) return false;
    // Reject "01" so a padded octet can't be read as something it isn't.
    if (p.length > 1 && p[0] == '0') return false;
  }
  return true;
}

/// Loose IPv6 acceptance: hex groups and colons, with an optional `%zone`.
///
/// Deliberately not a full RFC 4291 parser. This rejects the things an operator
/// actually typos (a hostname, a URL, a port glued on) and leaves the final
/// judgement to the socket bind, which is authoritative and fails loudly.
///
/// The two-colon rule is what makes it safe rather than merely loose: every
/// legal IPv6 literal has at least two colons — `::` at minimum, or seven
/// between eight groups — while `127.0.0.1:5799`, the single likeliest typo
/// here, has exactly one. Without it that string parsed as "an IPv6 address"
/// and the operator was told their bind was fine when it was not.
bool _isIpv6(String s) {
  final body = s.split('%').first;
  if (':'.allMatches(body).length < 2) return false;
  return RegExp(r'^[0-9A-Fa-f:.]+$').hasMatch(body);
}

/// Parses the Web UI flags out of [args].
///
/// Unknown arguments are ignored — the Flutter toolchain and OS schedulers
/// inject their own — but a *malformed value* for a flag we own is an error,
/// never a silent default.
WebUiOptionsParse parseWebUiArgs(List<String> args) {
  final errors = <String>[];
  var options = WebUiOptions(enabled: isWebUiInvocation(args));

  final rawBind = _flagValue(args, kWebUiBindFlag);
  if (rawBind != null) {
    final resolved = resolveBindAddress(rawBind);
    if (resolved == null) {
      errors.add(
        '$kWebUiBindFlag: "$rawBind" is not an IP address. '
        'Use an address of this machine, $kDefaultWebUiBind for this machine '
        'only, or "$kBindAllAlias" (0.0.0.0) for every interface.',
      );
    } else {
      options = options.copyWith(bindAddress: resolved);
    }
  }

  final rawPort = _flagValue(args, kWebUiPortFlag);
  if (rawPort != null) {
    final port = int.tryParse(rawPort);
    if (port == null || port < 1 || port > 65535) {
      errors.add(
        '$kWebUiPortFlag: "$rawPort" is not a port between 1 and 65535.',
      );
    } else {
      options = options.copyWith(port: port);
    }
  }

  return WebUiOptionsParse(options, errors);
}

/// Expands the accepted spellings of a bind address to a literal IP, or null
/// when [raw] is not one.
///
/// Hostnames are refused on purpose. "Which interface did that resolve to?" is
/// not a question anyone should have to ask about the address their file
/// manager is listening on.
String? resolveBindAddress(String raw) {
  final v = raw.trim();
  if (v.isEmpty) return null;
  switch (v.toLowerCase()) {
    case kBindAllAlias:
      return '0.0.0.0';
    case 'localhost':
      return '127.0.0.1';
  }
  if (_isIpv4(v) || _isIpv6(v)) return v;
  return null;
}
