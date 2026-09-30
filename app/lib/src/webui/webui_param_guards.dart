/// Server-side checks on the PARAMETERS of allowlisted RC methods.
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

import 'dart:convert';
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

// ── Every forwarded method: program-running options and on-the-fly remotes ──

/// Why any forwarded RC request must be refused, or null when it may proceed.
///
/// The method allowlist keeps `core/command` out, but rclone has other ways to
/// make the HOST run a program, and every one of them rides in a parameter of
/// a method that is allowed:
///
///  * **Backend options that name a program.** `sftp`'s `ssh`, `webdav`'s
///    `bearer_token_command`. Create a remote with
///    one (`config/create`, `config/update`) and the next `operations/list` on
///    it runs that program as the user running rclone.
///  * **The same options, inline.** An `fs` of `:sftp,ssh='...':` or
///    `gdrive,ssh=...:` defines them on the fly with no `config/create` at
///    all, and rclone also accepts an `fs` given as a JSON OBJECT of options.
///    A wrapper remote (`alias`, `crypt`, `union`...) whose `remote` or
///    `upstreams` is such a spec does the same one level down.
///  * **Global options.** `password_command`, `metadata_mapper` and a
///    `name_transform` with a `command=` step all run a program. rclone reads
///    them from a `_config` block on ANY call, and - since 1.75 - also from a
///    top-level parameter of the same name.
///
/// None of these is anything the app sends. The one inline form it does send
/// is `copy_links=true` on a LOCAL listing (`listFsFor` in
/// `rclone/models/remote.dart`), which [kSafeInlineFsParams] admits.
///
/// What this does NOT change: a session can still create a `local` remote and
/// read or write any file the Airclone user can - browsing the host's own
/// disk is a Web UI feature. See the header of `webui_rc_policy.dart`.
///
/// [existingRemote] is the saved config of the remote a `config/update` (or a
/// `config/create` over an existing name) targets, when the caller could read
/// it. A program-running option whose value is UNCHANGED from it is allowed:
/// the Web UI's edit form re-sends every field, and re-saving a remote that
/// was set up with a custom `ssh` on this machine is no escalation. Only a new
/// or changed value is refused. See [configCommandKeys].
String? rcParamsViolation(
  String method,
  Map<String, dynamic> params, {
  Map<String, dynamic>? existingRemote,
}) {
  final commandKey = _commandOptionIn(params);
  if (commandKey != null) return _runsAProgram(commandKey);

  if (params.containsKey('_config')) {
    final config = _asMap(params['_config']);
    if (config == null) return 'The Web UI could not read the _config block.';
    final key = _commandOptionIn(config);
    if (key != null) return _runsAProgram(key);
  }

  for (final key in kFsParamKeys) {
    if (!params.containsKey(key)) continue;
    final problem = fsValueViolation(params[key]);
    if (problem != null) return problem;
  }

  if (method == 'config/create' || method == 'config/update') {
    if (params.containsKey('parameters')) {
      final parameters = _asMap(params['parameters']);
      if (parameters == null) {
        return 'The Web UI could not read the remote parameters.';
      }
      final key = _commandOptionIn(parameters, unchangedFrom: existingRemote);
      if (key != null) {
        return 'The Web UI cannot set "$key" on a remote: it makes rclone run '
            'a program on the host. Set it from the Airclone app on that '
            'machine instead.';
      }
      for (final nested in const ['remote', 'upstreams']) {
        final value = parameters[nested];
        if (value == null) continue;
        if (value is! String) return 'The "$nested" parameter must be text.';
        // A quoted inline option can hide a space, which the split below
        // would cut in half. Quotes AND a comma is never something the app
        // writes, so it is refused rather than parsed.
        if (value.contains(',') &&
            (value.contains('"') || value.contains("'"))) {
          return 'The Web UI does not accept inline remote options in '
              '"$nested".';
        }
        for (final token in _upstreamTokens(value)) {
          final problem = fsValueViolation(token);
          if (problem != null) return problem;
        }
      }
    }
  }
  return null;
}

String _runsAProgram(String key) =>
    'The Web UI does not accept the "$key" option: it makes rclone run a '
    'program on the host.';

/// RC parameters rclone resolves as a remote (`fs.Fs`), not as a path in one.
///
/// `remote`, `srcRemote` and `dstRemote` are NOT here: rclone reads those as a
/// plain path inside the `fs` (`rc.GetFsAndRemote`), never as a remote spec,
/// so a file genuinely named `a,b:c` must keep working.
const Set<String> kFsParamKeys = {
  'fs',
  'srcFs',
  'dstFs',
  'path1',
  'path2',
  'backupdir1',
  'backupdir2',
};

/// Inline (connection-string) parameters an `fs` may carry from the Web UI.
///
/// Only what the app itself sends. Anything else a user needs on a remote
/// belongs in its saved config, where [rcParamsViolation] checks it.
const Set<String> kSafeInlineFsParams = {'copy_links'};

/// On-the-fly backends (`:type:path`) an `fs` may name from the Web UI.
const Set<String> kSafeInlineBackends = {'local'};

/// Why an `fs`-style value must be refused, or null when it may proceed.
///
/// Mirrors rclone's own `fspath.Parse`, because the question is not what the
/// string looks like but what rclone will do with it: `/a,b:c` is a local
/// path, `C:\x` is a drive letter, `gdrive:` is a named remote, and
/// `gdrive,ssh=x:` and `:sftp:` are remotes defined on the fly.
String? fsValueViolation(Object? value) {
  if (value == null) return null;
  if (value is! String) {
    // rclone turns a JSON object into `:type,key=value:root` - an on-the-fly
    // remote with arbitrary options - so the object form is refused outright.
    return 'The Web UI only accepts a remote as text, not as a set of options.';
  }
  final parsed = parseFsSpec(value);
  if (parsed == null) return 'That remote could not be read.';
  if (parsed.onTheFly && !kSafeInlineBackends.contains(parsed.name)) {
    return 'The Web UI does not accept on-the-fly remotes like '
        '":${parsed.name}:". Add the remote in Airclone first, then use it by '
        'name.';
  }
  final extra = parsed.params.keys.where(
    (k) => !kSafeInlineFsParams.contains(k.toLowerCase()),
  );
  if (extra.isNotEmpty) {
    return 'The Web UI does not accept inline remote options '
        '(${extra.join(', ')}). Save them in the remote instead.';
  }
  return null;
}

/// A remote spec as rclone splits it: `name,key=value,...:path`.
class FsSpec {
  const FsSpec({
    required this.name,
    required this.onTheFly,
    required this.params,
  });

  /// The remote name, the backend type when [onTheFly], or empty for a local
  /// path.
  final String name;

  /// True for `:type...:` - a backend with no saved config behind it.
  final bool onTheFly;

  /// Inline parameters, empty when there are none.
  final Map<String, String> params;
}

/// Splits [path] the way rclone's `fspath.Parse` (1.75.1) does, or returns
/// null where rclone would refuse it too.
///
/// Only the NAME and PARAMETER part is modelled - the path after the colon
/// does not change which backend rclone builds.
FsSpec? parseFsSpec(String path) {
  const local = FsSpec(name: '', onTheFly: false, params: {});
  if (path.isEmpty) return null;
  if (!path.contains(':')) return local;
  final onTheFly = path.startsWith(':');
  var i = onTheFly ? 1 : 0;
  // The name, up to the first ':' or ','.
  while (i < path.length) {
    final c = path[i];
    if (c == '/' || c == '\\') {
      // A separator before any ':' or ',' makes it a local path - unless it
      // started with ':', which rclone rejects.
      return onTheFly ? null : local;
    }
    if (c == ':' || c == ',') break;
    i++;
  }
  if (i >= path.length) return null;
  final name = path.substring(onTheFly ? 1 : 0, i);
  if (name.isEmpty) return null;
  if (path[i] == ':') {
    // `C:` and friends: rclone treats a single-letter name as a drive.
    if (!onTheFly && _isDriveLetter(name)) return local;
    return FsSpec(name: name, onTheFly: onTheFly, params: const {});
  }
  // Parameters: key[=value][,key[=value]]...:  with optional '' or "" quoting.
  final params = <String, String>{};
  i++; // past the ','
  while (true) {
    final keyStart = i;
    while (i < path.length && !':,='.contains(path[i])) {
      i++;
    }
    if (i >= path.length) return null;
    final key = path.substring(keyStart, i);
    if (key.isEmpty) return null;
    if (path[i] != '=') {
      params[key] = 'true';
      if (path[i] == ':') break;
      i++;
      continue;
    }
    i++; // past '='
    String value;
    if (i < path.length && (path[i] == '"' || path[i] == "'")) {
      final quote = path[i];
      final buf = StringBuffer();
      i++;
      while (true) {
        if (i >= path.length) return null;
        if (path[i] == quote) {
          if (i + 1 < path.length && path[i + 1] == quote) {
            buf.write(quote);
            i += 2;
            continue;
          }
          i++;
          break;
        }
        buf.write(path[i]);
        i++;
      }
      if (i >= path.length || (path[i] != ':' && path[i] != ',')) return null;
      value = buf.toString();
    } else {
      final valueStart = i;
      while (i < path.length && path[i] != ':' && path[i] != ',') {
        i++;
      }
      if (i >= path.length) return null;
      value = path.substring(valueStart, i);
    }
    params[key] = value;
    if (path[i] == ':') break;
    i++;
  }
  return FsSpec(name: name, onTheFly: onTheFly, params: params);
}

bool _isDriveLetter(String s) =>
    s.length == 1 && RegExp(r'^[A-Za-z]$').hasMatch(s);

/// The keys of a `config/create` / `config/update` [params] block that would
/// be refused as program-running options, ignoring any saved value.
///
/// The server uses this to decide whether it needs the remote's saved config
/// (`config/get`) before it can judge the request - see `existingRemote` on
/// [rcParamsViolation].
List<String> configCommandKeys(Map<String, dynamic> params) {
  final parameters = _asMap(params['parameters']);
  if (parameters == null) return const [];
  return [
    for (final e in parameters.entries)
      if (_isHostCommandOption(e.key, e.value)) e.key,
  ];
}

/// The first key in [m] that names an option which makes rclone run a
/// program on THIS machine, or null. A key whose value equals the one in
/// [unchangedFrom] is not counted.
String? _commandOptionIn(
  Map<String, dynamic> m, {
  Map<String, dynamic>? unchangedFrom,
}) {
  for (final entry in m.entries) {
    if (!_isHostCommandOption(entry.key, entry.value)) continue;
    final saved = unchangedFrom?[entry.key];
    if (saved != null && '$saved' == '${entry.value}') continue;
    return entry.key;
  }
  return null;
}

/// Whether option [key] with [value] makes rclone run a program on the host.
///
/// Matched on a normalised name - lower case, `_` and `-` removed - because
/// rclone accepts both the config spelling (`password_command`) and the Go
/// field spelling (`PasswordCommand`) depending on where the option rides.
///
/// Every option in rclone 1.75.1 whose value reaches a local `exec.Command`:
/// `ssh` (sftp), `bearer_token_command` (webdav), `password_command`,
/// `metadata_mapper`, and `name_transform` with a `command=` step. Anything
/// else ENDING in `command` is refused as well, so a future option that
/// follows rclone's naming is caught before anyone reads its release notes -
/// with two exceptions that run on the REMOTE server, not here:
///
///  * sftp's `server_command` and the `*sum_command` family (`md5sum_command`,
///    `sha1sum_command`...). rclone WRITES the latter into the config by
///    itself after probing a server, so an ordinary exported sftp remote
///    carries them and refusing them would break import and edit. They are
///    passed to the ssh session as the remote command - but with an external
///    `ssh` program they become one of its arguments, so a value starting
///    with `-` (an ssh option such as `-oProxyCommand=...`, which OpenSSH
///    accepts after the host name) is still refused.
bool _isHostCommandOption(String key, Object? value) {
  final n = key.toLowerCase().replaceAll(RegExp('[_-]'), '');
  if (n == 'servercommand' || RegExp(r'^[a-z0-9]+sumcommand$').hasMatch(n)) {
    return '$value'.trimLeft().startsWith('-');
  }
  if (n.endsWith('command') || n == 'ssh' || n == 'metadatamapper') {
    return true;
  }
  return n == 'nametransform' && '$value'.toLowerCase().contains('command');
}

/// [raw] as a map, whether it arrived as a JSON object or as a JSON string of
/// one (rclone accepts both), or null when it is neither.
Map<String, dynamic>? _asMap(Object? raw) {
  if (raw == null) return const {};
  if (raw is Map) return raw.cast<String, dynamic>();
  if (raw is String) {
    if (raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } on FormatException {
      return null;
    }
  }
  return null;
}

/// The remote specs inside a wrapper remote's `remote` / `upstreams` value.
///
/// `union` takes `a:path b:path:ro`, `combine` takes `dir=a:path`, both
/// space-separated with optional quotes; everything else is a single spec.
Iterable<String> _upstreamTokens(String value) sync* {
  for (var token in value.split(RegExp(r'\s+'))) {
    if (token.isEmpty) continue;
    token = token.replaceAll('"', '').replaceAll("'", '');
    // combine's `dir=remote:path`: drop the label, but only when the '=' comes
    // before any ':' or ',' - otherwise it belongs to an inline option.
    final eq = token.indexOf('=');
    if (eq >= 0) {
      final colon = token.indexOf(':');
      final comma = token.indexOf(',');
      if ((colon < 0 || eq < colon) && (comma < 0 || eq < comma)) {
        token = token.substring(eq + 1);
      }
    }
    if (token.isNotEmpty) yield token;
  }
}
