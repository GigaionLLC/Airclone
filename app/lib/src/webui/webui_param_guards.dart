/// Server-side checks on the PARAMETERS of two allowlisted RC methods.
///
/// The allowlist in `webui_rc_policy.dart` decides which methods a Web UI
/// session may call. It never sees their parameters, and for these two that is
/// the whole problem: the method is safe to allow, and some argument values are
/// not.
///
/// Both were found by an adversarial pass over the authorization surface and
/// are reachable by the single admin session today, with no multi-user work
/// involved. The threat is the one the allowlist itself names: a stolen session.
///
/// ## Why the client's checks do not count
///
/// `ServeController.start` already enforces sensible rules - a password to
/// serve on the network, an acknowledgement for DLNA, a whitelisted parameter
/// map. But in the Web UI that controller is compiled into the web bundle and
/// runs IN THE BROWSER. Anyone who posts to `/api/rc` directly never runs it.
/// A rule enforced only by the page that asked is advice, not a control; the
/// server is the only place that sees every request.
///
/// These guards only ever run on the Web UI server's path. The desktop app
/// talks to its own engine directly, where the operator is at the keyboard,
/// and is unaffected.
library;

import 'dart:io';

/// Resolves a hostname to addresses. Injected so tests never touch DNS.
typedef HostLookup = Future<List<InternetAddress>> Function(String host);

// ── serve/start ────────────────────────────────────────────────────────────

/// Protocols that authenticate with a username and password. Mirrors
/// `serveAuthCapable` in `rclone/models/serve_server.dart`; duplicated rather
/// than imported so this file stays free of the client model.
const Set<String> kServeAuthCapable = {'http', 'webdav', 'ftp', 'sftp'};

/// Serve types that can take no password at all.
const Set<String> kServeNoAuth = {'dlna', 'nfs'};

/// The only parameters `serve/start` may carry from the Web UI.
///
/// A WHITELIST, because the dangerous ones are the ones nobody thinks to list:
/// `_config` and `_filter` are accepted by rclone on every method and address
/// host paths named in no `fs` parameter. `ServeController` already sends
/// exactly this set, so nothing the app does is refused.
const Set<String> kServeStartParams = {
  'type',
  'fs',
  'addr',
  'user',
  'pass',
  'read_only',
  'vfs_cache_mode',
};

/// Why a `serve/start` request must be refused, or null when it may proceed.
///
/// The rule, in one line: **anything reachable beyond this machine needs a
/// password, and a protocol that cannot take one cannot leave this machine
/// through the Web UI.**
///
/// That second clause is stricter than the desktop app, which lets you serve
/// DLNA on the network after ticking an acknowledgement. The acknowledgement is
/// a human confirming, locally, that they understand. A remote session cannot
/// prove a human did anything, so from the Web UI it is refused outright and
/// the message says where to do it instead.
String? serveStartViolation(Map<String, dynamic> params) {
  final unknown = params.keys.where((k) => !kServeStartParams.contains(k));
  if (unknown.isNotEmpty) {
    return 'serve/start does not accept ${unknown.join(', ')} from the Web UI.';
  }

  final type = params['type'];
  if (type is! String || type.isEmpty) {
    return 'serve/start needs a protocol type.';
  }
  if (!kServeAuthCapable.contains(type) && !kServeNoAuth.contains(type)) {
    // Fail closed on a protocol this guard has not been taught about, rather
    // than let a future rclone serve type through with no rule applied.
    return 'Serving over "$type" is not available from the Web UI.';
  }

  final fs = params['fs'];
  if (fs is! String || fs.isEmpty) {
    return 'serve/start needs something to serve.';
  }

  final addr = params['addr'];
  if (addr is! String || addr.trim().isEmpty) {
    // Required rather than defaulted: rclone's own default address differs by
    // protocol and version, and a guard that has to guess what it is approving
    // is not approving anything.
    return 'serve/start needs an explicit address to listen on.';
  }
  final local = isLoopbackListenAddress(addr);
  if (local == null) {
    return 'That listen address is not one the Web UI can serve on.';
  }
  if (local) return null;

  // Beyond loopback from here on.
  if (kServeNoAuth.contains(type)) {
    return '$type has no password, so the Web UI will not make it reachable '
        'from the network. Start it from the Airclone app on this machine, '
        'where you can confirm that yourself.';
  }
  final user = params['user'];
  final pass = params['pass'];
  if (user is! String || user.isEmpty || pass is! String || pass.isEmpty) {
    return 'A username and password are required to serve on your network.';
  }
  return null;
}

/// Whether an rclone listen address binds only to this machine.
///
/// Returns true for loopback, false for anything reachable from elsewhere, and
/// null for a form this guard does not accept at all.
///
/// The forms that matter, because they look alike and are not:
///
///   `127.0.0.1:8080`  loopback
///   `localhost:8080`  loopback
///   `[::1]:8080`      loopback
///   `:8080`           EVERY interface - an empty host is not "local"
///   `0.0.0.0:8080`    every interface
///   `192.168.1.5:80`  one LAN interface
///
/// rclone accepts a comma-separated list; it counts as loopback only if every
/// entry is. Unix sockets are refused, because a socket path is a host
/// filesystem write that the address is not the place to grant.
bool? isLoopbackListenAddress(String addr) {
  final entries = addr
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty);
  if (entries.isEmpty) return null;
  var allLocal = true;
  for (final entry in entries) {
    if (entry.startsWith('unix:') || entry.startsWith('/')) return null;
    final host = _hostOfListenAddress(entry);
    if (host == null) return null;
    if (host.isEmpty) {
      allLocal = false; // ":8080" - listens everywhere
      continue;
    }
    if (host.toLowerCase() == 'localhost') continue;
    final ip = InternetAddress.tryParse(host);
    if (ip == null) {
      // A hostname other than localhost could resolve anywhere, and resolving
      // it here would only race the resolution rclone does when it binds.
      allLocal = false;
      continue;
    }
    if (!ip.isLoopback) allLocal = false;
  }
  return allLocal;
}

/// The host part of `host:port` / `[v6]:port` / `:port`, or null if malformed.
String? _hostOfListenAddress(String entry) {
  if (entry.startsWith('[')) {
    final close = entry.indexOf(']');
    if (close < 0) return null;
    return entry.substring(1, close);
  }
  final colon = entry.lastIndexOf(':');
  if (colon < 0) return null; // a bare host with no port is not a listen addr
  return entry.substring(0, colon);
}

/// [params] with any password removed, for logging.
///
/// The server logged `serve/start` parameters verbatim as a warning, which
/// wrote the serve password into the Web UI log. The diagnostics ring redacts
/// at ingest, but the headless `--webui` host logs to stdout, where nothing
/// does - and stdout is exactly what ends up in a systemd journal.
Map<String, dynamic> redactServeParams(Map<String, dynamic> params) => {
  for (final e in params.entries)
    e.key: e.key == 'pass' ? '<redacted>' : e.value,
};

// ── operations/copyurl ─────────────────────────────────────────────────────

/// Why an `operations/copyurl` request must be refused, or null when it may
/// proceed.
///
/// `copyurl` makes THE HOST fetch a URL and write the body into a remote. From
/// a browser session that is server-side request forgery: the host can be told
/// to fetch
///
///   - `http://169.254.169.254/...` - cloud instance metadata, which on a VM
///     hands out the machine's IAM credentials;
///   - `http://127.0.0.1:<port>/`   - services on the host itself, the engine
///     included; and the error text alone reveals which ports are open;
///   - `http://192.168.1.1/`        - anything on the network behind the host.
///
/// The body lands in a remote the session can read, so this is not only a
/// probe - it is a way to exfiltrate whatever answers.
///
/// **The check is on RESOLVED addresses, not on the string.** `127.1`,
/// `2130706433`, `0x7f000001` and a public name whose DNS points at 127.0.0.1
/// all reach loopback without ever spelling it, and string matching misses
/// every one. Every address a name resolves to must be public.
///
/// Residual risk, stated rather than hidden: rclone resolves the name again
/// when it fetches. A hostile DNS server can answer this lookup with a public
/// address and rclone's with a private one (DNS rebinding). Closing that fully
/// needs rclone to connect to the address checked here, which the RC API does
/// not offer. This removes every direct and encoded form, which is the bulk of
/// the attack.
Future<String?> copyUrlViolation(
  Map<String, dynamic> params, {
  HostLookup? lookup,
}) async {
  final raw = params['url'];
  if (raw is! String || raw.trim().isEmpty) {
    return 'copyurl needs a URL.';
  }
  final Uri uri;
  try {
    uri = Uri.parse(raw.trim());
  } on FormatException {
    return 'That is not a valid URL.';
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    return 'Only http and https URLs can be fetched.';
  }
  final host = uri.host;
  if (host.isEmpty) return 'That URL has no host.';

  final literal = InternetAddress.tryParse(host);
  final List<InternetAddress> addresses;
  if (literal != null) {
    addresses = [literal];
  } else {
    try {
      addresses = await (lookup ?? InternetAddress.lookup)(host);
    } catch (_) {
      // Refused rather than passed through: a name that fails to resolve here
      // and succeeds for rclone a moment later is the rebinding shape.
      return 'Could not resolve $host.';
    }
  }
  if (addresses.isEmpty) return 'Could not resolve $host.';

  for (final a in addresses) {
    if (isNonPublicAddress(a)) {
      // Deliberately does NOT say which address or which range. Naming it
      // turns the refusal itself into the internal-network oracle this check
      // exists to close.
      return 'The Web UI will not fetch from this machine or its private '
          'network. Use the Airclone app on this machine for local addresses.';
    }
  }
  return null;
}

/// True for any address that is not a routable public internet address.
///
/// Covers loopback, unspecified, link-local (which is where cloud metadata
/// lives), private and unique-local ranges, carrier-grade NAT, multicast, and
/// the IPv4-mapped IPv6 spelling of every one of those - `::ffff:127.0.0.1` is
/// loopback wearing a different address family.
bool isNonPublicAddress(InternetAddress a) {
  final b = a.rawAddress;
  if (a.type == InternetAddressType.IPv6) {
    // ::ffff:a.b.c.d - check the embedded IPv4 address instead.
    final mapped =
        b.length == 16 &&
        b.sublist(0, 10).every((x) => x == 0) &&
        b[10] == 0xff &&
        b[11] == 0xff;
    if (mapped) return _nonPublicV4(b.sublist(12));
    if (a.isLoopback || a.isLinkLocal || a.isMulticast) return true;
    if (b.every((x) => x == 0)) return true; // ::
    if ((b[0] & 0xfe) == 0xfc) return true; // fc00::/7 unique local
    if (b[0] == 0xfe && (b[1] & 0xc0) == 0xc0) return true; // fec0::/10
    return false;
  }
  return _nonPublicV4(b);
}

bool _nonPublicV4(List<int> b) {
  if (b.length != 4) return true; // not an address we understand: refuse
  final o0 = b[0], o1 = b[1];
  return o0 == 0 || // 0.0.0.0/8, "this network"
      o0 == 10 || // 10/8
      o0 == 127 || // loopback
      (o0 == 169 && o1 == 254) || // link-local, incl. 169.254.169.254
      (o0 == 172 && o1 >= 16 && o1 <= 31) || // 172.16/12
      (o0 == 192 && o1 == 168) || // 192.168/16
      (o0 == 100 && o1 >= 64 && o1 <= 127) || // 100.64/10 carrier-grade NAT
      (o0 == 192 && o1 == 0 && b[2] == 0) || // 192.0.0/24 IETF protocol
      (o0 == 198 && (o1 == 18 || o1 == 19)) || // 198.18/15 benchmarking
      o0 >= 224; // multicast, reserved, broadcast
}
