/// Which rclone RC methods the Web UI is allowed to forward to the engine.
///
/// This is the single most important file in the Web UI. rclone's own
/// documentation is blunt about what its rc API is:
///
/// > Access to the rc API is equivalent to shell access as the user running
/// > rclone.
///
/// So the Web UI never forwards the RC transparently. It forwards [kAllowedRcMethods]
/// and refuses everything else, including methods that do not exist — the list
/// is an **allowlist**, and anything unrecognised is denied without being asked
/// about. A new rclone release cannot widen this surface, and neither can a
/// typo.
///
/// The allowlist is not a guess: it is every RC method the app itself calls,
/// gathered from the call sites and from the console's argv→RC translator.
/// Adding to it is a deliberate act, and [kDeniedRcMethods] exists so that
/// three of those additions can never happen by accident.
///
/// **What this does and does not protect.** The operator is authenticated and is
/// the administrator of this Airclone; the allowlist is not there to restrain
/// them. It is defence in depth for the cases that actually happen: a stolen or
/// leaked session, a compromised browser, and an accidentally exposed port. In
/// each of those, the difference between "can browse and copy files" and "can
/// run arbitrary commands as the user running rclone" is the whole game.
library;

/// Methods that must NEVER be reachable from a browser, with the reason.
///
/// Kept as data rather than a comment so [debugAssertRcPolicyConsistent] can
/// prove none of them ever drifts into [kAllowedRcMethods].
const Map<String, String> kDeniedRcMethods = {
  'core/command':
      'Runs an arbitrary rclone command on the host. This is the method that '
      'makes the rc API equivalent to shell access, and it is the reason this '
      'allowlist exists.',
  'core/quit':
      'Shuts down the host engine. Engine lifecycle belongs to the host — a '
      'browser tab must not be able to stop the app serving it.',
  'config/setpath':
      'Repoints the engine at a different rclone config file, which is both a '
      'host-level decision and an arbitrary-path read.',
};

/// Every RC method the Web UI will forward.
///
/// Grouped by what the user is doing when the app calls it, because that is how
/// anyone reviewing this will want to read it.
const Set<String> kAllowedRcMethods = {
  // ── Engine identity and health ──────────────────────────────────────────
  'core/version',
  'core/stats',
  'core/transferred',
  'core/memstats',
  'core/bwlimit',
  'options/get',

  // ── Remotes and configuration ───────────────────────────────────────────
  // config/create and config/update can define a `local` remote pointing
  // anywhere on the host. That grants nothing new: browsing the host's own
  // filesystem is the entire point of the Web UI, and is already reachable
  // through operations/list.
  'config/listremotes',
  'config/dump',
  'config/get',
  'config/create',
  'config/update',
  'config/delete',
  'config/paths',
  'config/providers',

  // ── Browsing and metadata ───────────────────────────────────────────────
  'operations/list',
  'operations/stat',
  'operations/about',
  'operations/fsinfo',
  'operations/size',
  'operations/hashsum',
  'operations/publiclink',

  // ── Modifying files ─────────────────────────────────────────────────────
  'operations/mkdir',
  'operations/rmdir',
  'operations/rmdirs',
  'operations/purge',
  'operations/delete',
  'operations/deletefile',
  'operations/cleanup',
  'operations/copyfile',
  'operations/movefile',
  'operations/check',
  // Makes the HOST fetch a URL and save it — a server-side request by design.
  // It is a first-class rclone feature the app already exposes, and it is
  // reachable only by an authenticated operator, but it is the one allowed
  // method that talks to the outside world on the host's behalf. Noted here so
  // the next person to audit this does not have to rediscover it.
  'operations/copyurl',

  // ── Transfers ───────────────────────────────────────────────────────────
  'sync/copy',
  'sync/move',
  'sync/sync',
  'sync/bisync',
  'job/status',
  'job/stop',
  'job/list',

  // ── Mounting, on the host ───────────────────────────────────────────────
  // A mount created here appears on the machine running Airclone, never on the
  // machine running the browser. That is the intended behaviour, not a caveat.
  'mount/mount',
  'mount/unmount',
  'mount/unmountall',
  'mount/listmounts',
  'mount/types',
  'vfs/refresh',
  'vfs/stats',

  // ── rclone's own serve endpoints ────────────────────────────────────────
  // serve/start can expose a remote over HTTP/WebDAV/FTP from the host, and
  // rclone will happily do that without authentication if asked. That is a
  // real escalation from "reads files" to "republishes them", so every
  // serve/start is logged at WARNING level by the server rather than silently
  // allowed. It stays permitted because it is an existing desktop feature and
  // the Web UI is meant to be the same app.
  'serve/start',
  'serve/stop',
  'serve/stopall',
  'serve/list',
  'serve/types',
};

/// Why a method was refused, for the log and for the response body.
class RcPolicyDecision {
  const RcPolicyDecision.allowed() : allowed = true, reason = null;
  const RcPolicyDecision.denied(String this.reason) : allowed = false;

  final bool allowed;

  /// Null when [allowed]. Safe to show the operator: it explains the product's
  /// own rule and leaks nothing about the host.
  final String? reason;
}

/// Whether the Web UI may forward [method].
RcPolicyDecision rcPolicyFor(String method) {
  final denied = kDeniedRcMethods[method];
  if (denied != null) {
    return RcPolicyDecision.denied(
      'The Web UI does not allow "$method". $denied',
    );
  }
  if (kAllowedRcMethods.contains(method)) {
    return const RcPolicyDecision.allowed();
  }
  return RcPolicyDecision.denied(
    'The Web UI does not allow "$method". Only the rclone methods Airclone '
    'itself uses can be reached from a browser; everything else is refused, '
    'including methods that do not exist.',
  );
}

/// Convenience predicate for call sites that do not need the reason.
bool isRcMethodAllowed(String method) => rcPolicyFor(method).allowed;

/// Throws if the two lists ever overlap.
///
/// Called once at server start. The failure it guards against is somebody
/// pasting a method into [kAllowedRcMethods] to fix a bug without noticing it
/// is on the denied list — at which point the deny comment is still sitting
/// there, still true, and no longer enforcing anything.
void debugAssertRcPolicyConsistent() {
  final overlap = kAllowedRcMethods
      .where(kDeniedRcMethods.containsKey)
      .toList();
  if (overlap.isNotEmpty) {
    throw StateError(
      'Web UI RC policy is inconsistent: ${overlap.join(', ')} appear in both '
      'kAllowedRcMethods and kDeniedRcMethods. The denied list wins by '
      'construction, but the contradiction means one of them is a mistake.',
    );
  }
}
