import 'console_command.dart';

/// Translates a parsed console [ConsoleCommand] into a pure-data rclone RC call
/// (Path B) for the in-process/FFI engine, where `core/command` is categorically
/// impossible (librclone rejects NeedsRequest methods; no binary to re-exec). This
/// is the engine-agnostic substrate `TransferService` already proves on both
/// engines (`sync/copy`, `operations/*` with `_async`+`_group`).
///
/// SAFETY BY CONSTRUCTION — fail-closed: an unknown verb, an unknown/unmapped
/// FLAG, or a positional it can't confidently split → [RcRefusal], and NOTHING is
/// dispatched. A wrong Go-struct `_config` key is silently ignored by rclone, so a
/// flag we don't map is REFUSED rather than dropped — refusing the whole command
/// is the correct non-drop behavior (dispatching the rest while dropping a
/// `--max-delete`/`--delete-excluded` would be the data-loss disaster). This layer
/// assumes the tier gate (`classifyTier`) + `hasCredentialDump` already passed, so
/// blocked/unknown verbs and credential-dump verbosity never reach here.
sealed class RcTranslation {
  const RcTranslation();
}

enum RcKind { instant, asyncJob }

/// A resolved RC call ready for Path B. `_async`/`_group` are added by the
/// controller at dispatch time (async only), not here.
class RcDispatch extends RcTranslation {
  const RcDispatch({
    required this.method,
    required this.params,
    required this.kind,
    this.asyncResult = false,
    this.needsSourceProbe = false,
    this.notes = const [],
  });

  /// e.g. `sync/copy`, `operations/list`, `operations/mkdir`.
  final String method;

  /// fs / srcFs / remote / … plus optional `_config`, `_filter`, `opt`.
  final Map<String, dynamic> params;

  final RcKind kind;

  /// A heavy read (size/hashsum/check) whose result is read from
  /// `job/status['output']` when the async job finishes.
  final bool asyncResult;

  /// copyto/moveto: stat the source first — dir → `sync/*` over whole fs, file →
  /// `operations/copyfile`/`movefile` (the controller does the probe at dispatch).
  final bool needsSourceProbe;

  /// Recognized-but-effectless flags (`--progress`, `--stats`) surfaced in the
  /// preview so the user knows they were seen, never silently dropped.
  final List<String> notes;
}

/// A refusal with an honest, actionable message — no job, no dispatch.
class RcRefusal extends RcTranslation {
  const RcRefusal(this.reason);
  final String reason;
}

/// Splits a remote token into `(fs, remote)`. Connection-string aware:
///  - `gdrive:Photos`         → (`gdrive:`, `Photos`)
///  - `gdrive:`               → (`gdrive:`, ``)
///  - `:s3,env_auth=true:b/k` → (`:s3,env_auth=true:`, `b/k`)  (terminator = 2nd `:`)
///
/// Returns null when it can't confidently split — no colon, or a Windows local
/// path like `C:/foo` (`C:\foo`) — since the console domain is remotes, not local
/// drive paths (the caller then refuses).
(String fs, String remote)? splitFsRemote(String token) {
  if (token.isEmpty) return null;
  if (token.startsWith(':')) {
    // Connection string `:backend,params:path` — the 2nd colon terminates the fs.
    final second = token.indexOf(':', 1);
    if (second < 0) return null;
    return (token.substring(0, second + 1), token.substring(second + 1));
  }
  final colon = token.indexOf(':');
  if (colon < 0) return null; // not a remote:path token
  // Windows drive-path guard: `C:/…` / `C:\…` is a local path, not a remote.
  if (colon == 1) {
    final after = token.length > 2 ? token[2] : '';
    if (after == '/' || after == r'\') return null;
  }
  return (token.substring(0, colon + 1), token.substring(colon + 1));
}

// --- Flag table (fail-closed) ------------------------------------------------

enum _Target { config, filter, opt, note }

enum _Type { boolT, intT, strT, listT }

class _FlagSpec {
  const _FlagSpec(this.target, this.key, this.type);
  final _Target target;
  final String key;
  final _Type type;
}

/// The ONLY flags translated to the in-process engine. Anchored to `_config`/
/// `_filter` keys `buildRcCall` already dispatches in production (transfer_options),
/// so each is known-honored — everything else refuses. `opt.*` applies to
/// `operations/list` only.
const Map<String, _FlagSpec> _flagTable = {
  '--dry-run': _FlagSpec(_Target.config, 'DryRun', _Type.boolT),
  '--transfers': _FlagSpec(_Target.config, 'Transfers', _Type.intT),
  '--checkers': _FlagSpec(_Target.config, 'Checkers', _Type.intT),
  '--checksum': _FlagSpec(_Target.config, 'Checksum', _Type.boolT),
  '--size-only': _FlagSpec(_Target.config, 'SizeOnly', _Type.boolT),
  '--update': _FlagSpec(_Target.config, 'UpdateOlder', _Type.boolT),
  '--ignore-existing': _FlagSpec(_Target.config, 'IgnoreExisting', _Type.boolT),
  '--track-renames': _FlagSpec(_Target.config, 'TrackRenames', _Type.boolT),
  '--immutable': _FlagSpec(_Target.config, 'Immutable', _Type.boolT),
  '--max-delete': _FlagSpec(_Target.config, 'MaxDelete', _Type.intT),
  '--order-by': _FlagSpec(_Target.config, 'OrderBy', _Type.strT),
  '--suffix': _FlagSpec(_Target.config, 'Suffix', _Type.strT),
  '--suffix-keep-extension': _FlagSpec(
    _Target.config,
    'SuffixKeepExtension',
    _Type.boolT,
  ),
  '--include': _FlagSpec(_Target.filter, 'IncludeRule', _Type.listT),
  '--exclude': _FlagSpec(_Target.filter, 'ExcludeRule', _Type.listT),
  '--filter': _FlagSpec(_Target.filter, 'FilterRule', _Type.listT),
  '--recursive': _FlagSpec(_Target.opt, 'recurse', _Type.boolT),
  '--dirs-only': _FlagSpec(_Target.opt, 'dirsOnly', _Type.boolT),
  '--files-only': _FlagSpec(_Target.opt, 'filesOnly', _Type.boolT),
  '--hash': _FlagSpec(_Target.opt, 'showHash', _Type.boolT),
  '--progress': _FlagSpec(_Target.note, '', _Type.boolT),
  '--stats': _FlagSpec(_Target.note, '', _Type.strT),
  '--stats-one-line': _FlagSpec(_Target.note, '', _Type.boolT),
};

/// Short flags expanded to their long form (`-cP` → `--checksum` + `--progress`).
/// All are bool, so a short cluster never consumes a value.
const Map<String, String> _shortToLong = {
  'n': '--dry-run',
  'c': '--checksum',
  'P': '--progress',
  'u': '--update',
  'R': '--recursive',
};

String _refuseFlag(String flag) =>
    '$flag can\'t be safely translated to the in-process engine — remove it, or '
    'run this on the desktop binary engine.';

String _refuseVerb(String verb) =>
    '"$verb" isn\'t available on the in-process engine (no data-only RC method) — '
    'run it on the desktop binary engine.';

// --- Translate ---------------------------------------------------------------

/// Verbs with a real cross-engine pure-data RC method but no faithful one here
/// (CLI-formatting or unverified method names) — refused fail-closed.
const Set<String> _refusedVerbs = {
  'cat', 'tree', 'rcat', 'checksum', 'cryptcheck', 'cryptdecode', //
  'convmv', 'dedupe', 'backend', 'settier',
  // touch is CLI-only (cmd/touch) — there is no operations/touch RC method in
  // v1.74, so it would always error in-process. Refuse it (works on the binary
  // engine via core/command).
  'touch',
};

RcTranslation translateToRc(ConsoleCommand cmd) {
  final verb = cmd.verb;
  if (_refusedVerbs.contains(verb)) return RcRefusal(_refuseVerb(verb));

  // 1. Parse args → positionals + _config / _filter / opt / notes, fail-closed.
  final positionals = <String>[];
  final config = <String, dynamic>{};
  final filter = <String, List<String>>{};
  final opt = <String, dynamic>{};
  final notes = <String>[];
  final args = cmd.args;

  for (var i = 0; i < args.length; i++) {
    final tok = args[i];
    if (!tok.startsWith('-') || tok == '-') {
      positionals.add(tok);
      continue;
    }
    // Expand the token into one or more long flag names.
    final List<String> longs;
    String? inlineValue;
    if (tok.startsWith('--')) {
      final eq = tok.indexOf('=');
      if (eq >= 0) {
        longs = [tok.substring(0, eq)];
        inlineValue = tok.substring(eq + 1);
      } else {
        longs = [tok];
      }
    } else {
      longs = <String>[];
      for (final ch in tok.substring(1).split('')) {
        final lng = _shortToLong[ch];
        if (lng == null) return RcRefusal(_refuseFlag('-$ch'));
        longs.add(lng);
      }
    }
    for (final flag in longs) {
      final spec = _flagTable[flag];
      if (spec == null) return RcRefusal(_refuseFlag(flag));
      String? value;
      if (spec.type != _Type.boolT) {
        if (inlineValue != null && longs.length == 1) {
          value = inlineValue;
        } else if (i + 1 < args.length) {
          value = args[++i];
        } else {
          return RcRefusal('$flag needs a value.');
        }
      }
      switch (spec.target) {
        case _Target.config:
          switch (spec.type) {
            case _Type.intT:
              final n = int.tryParse(value!);
              if (n == null) return RcRefusal('$flag needs a whole number.');
              config[spec.key] = n;
            case _Type.strT:
              config[spec.key] = value;
            case _Type.boolT:
            case _Type.listT:
              config[spec.key] = true;
          }
        case _Target.filter:
          (filter[spec.key] ??= <String>[]).add(value!);
        case _Target.opt:
          opt[spec.key] = true;
        case _Target.note:
          notes.add(flag); // any value already consumed + intentionally ignored
      }
    }
  }

  // 2. Resolve the verb → method + method-specific params.
  final built = _buildVerb(verb, positionals);
  if (built is RcRefusal) return built;
  var d = built as RcDispatch;

  // 3. opt.* is only meaningful for operations/list.
  if (opt.isNotEmpty && d.method != 'operations/list') {
    return RcRefusal(
      'Listing flags (--recursive/--dirs-only/…) only apply to a listing command.',
    );
  }

  // 4. A recursive list is heavy → dispatch async (frees the FFI worker isolate).
  var kind = d.kind;
  var asyncResult = d.asyncResult;
  if (d.method == 'operations/list' && opt['recurse'] == true) {
    kind = RcKind.asyncJob;
    asyncResult = true;
  }

  // 5. Attach _config / _filter / opt.
  final params = <String, dynamic>{...d.params};
  if (config.isNotEmpty) params['_config'] = config;
  if (filter.isNotEmpty) params['_filter'] = filter;
  if (opt.isNotEmpty) {
    params['opt'] = {...?(d.params['opt'] as Map<String, dynamic>?), ...opt};
  }

  return RcDispatch(
    method: d.method,
    params: params,
    kind: kind,
    asyncResult: asyncResult,
    needsSourceProbe: d.needsSourceProbe,
    notes: notes,
  );
}

/// Builds the method + positional-derived params for [verb]. Returns [RcRefusal]
/// on a missing/unsplittable positional or an unknown verb.
RcTranslation _buildVerb(String verb, List<String> pos) {
  Map<String, dynamic>? split(String token) {
    final r = splitFsRemote(token);
    if (r == null) return null;
    return {'fs': r.$1, 'remote': r.$2};
  }

  String need(int n) => pos.length > n ? pos[n] : '';
  bool has(int n) => pos.length > n && pos[n].isNotEmpty;

  RcRefusal missing() => const RcRefusal(
    'This command needs a remote (e.g. `gdrive:folder`) — check the arguments.',
  );

  switch (verb) {
    case 'version':
      return const RcDispatch(
        method: 'core/version',
        params: {},
        kind: RcKind.instant,
      );
    case 'listremotes':
      return const RcDispatch(
        method: 'config/listremotes',
        params: {},
        kind: RcKind.instant,
      );
    case 'about':
      if (!has(0)) return missing();
      return RcDispatch(
        method: 'operations/about',
        params: {'fs': need(0)},
        kind: RcKind.instant,
      );
    case 'ls':
    case 'lsf':
    case 'lsl':
    case 'lsjson':
      if (!has(0)) return missing();
      final s = split(need(0));
      if (s == null) return missing();
      return RcDispatch(
        method: 'operations/list',
        params: s,
        kind: RcKind.instant,
      );
    case 'lsd':
      if (!has(0)) return missing();
      final s = split(need(0));
      if (s == null) return missing();
      return RcDispatch(
        method: 'operations/list',
        params: {
          ...s,
          'opt': <String, dynamic>{'dirsOnly': true},
        },
        kind: RcKind.instant,
      );
    case 'mkdir':
    case 'rmdir':
    case 'deletefile':
      if (!has(0)) return missing();
      final s = split(need(0));
      if (s == null) return missing();
      const method = {
        'mkdir': 'operations/mkdir',
        'rmdir': 'operations/rmdir',
        'deletefile': 'operations/deletefile',
      };
      return RcDispatch(method: method[verb]!, params: s, kind: RcKind.instant);
    case 'link':
      if (!has(0)) return missing();
      final s = split(need(0));
      if (s == null) return missing();
      return RcDispatch(
        method: 'operations/publiclink',
        params: s,
        kind: RcKind.instant,
      );
    case 'size':
      if (!has(0)) return missing();
      return RcDispatch(
        method: 'operations/size',
        params: {'fs': need(0)},
        kind: RcKind.asyncJob,
        asyncResult: true,
      );
    case 'md5sum':
    case 'sha1sum':
      if (!has(0)) return missing();
      return RcDispatch(
        method: 'operations/hashsum',
        params: {'fs': need(0), 'hashType': verb == 'md5sum' ? 'MD5' : 'SHA-1'},
        kind: RcKind.asyncJob,
        asyncResult: true,
      );
    case 'hashsum':
      if (!has(0) || !has(1)) return missing();
      return RcDispatch(
        method: 'operations/hashsum',
        params: {'hashType': need(0), 'fs': need(1)},
        kind: RcKind.asyncJob,
        asyncResult: true,
      );
    case 'copy':
    case 'move':
    case 'sync':
      if (!has(0) || !has(1)) return missing();
      const method = {
        'copy': 'sync/copy',
        'move': 'sync/move',
        'sync': 'sync/sync',
      };
      return RcDispatch(
        method: method[verb]!,
        params: {'srcFs': need(0), 'dstFs': need(1)},
        kind: RcKind.asyncJob,
      );
    case 'copyto':
    case 'moveto':
      if (!has(0) || !has(1)) return missing();
      final src = splitFsRemote(need(0));
      final dst = splitFsRemote(need(1));
      if (src == null || dst == null) return missing();
      return RcDispatch(
        // The controller probes the source and picks operations/copyfile|movefile
        // (file) or sync/copy|move (dir); this is the file default.
        method: verb == 'copyto'
            ? 'operations/copyfile'
            : 'operations/movefile',
        params: {
          'srcFs': src.$1,
          'srcRemote': src.$2,
          'dstFs': dst.$1,
          'dstRemote': dst.$2,
          // Whole-fs fallback the controller uses when the source is a directory.
          '_srcFsWhole': need(0),
          '_dstFsWhole': need(1),
        },
        kind: RcKind.asyncJob,
        needsSourceProbe: true,
      );
    case 'copyurl':
      if (!has(0) || !has(1)) return missing();
      final dst = split(need(1));
      if (dst == null) return missing();
      return RcDispatch(
        method: 'operations/copyurl',
        params: {'url': need(0), ...dst},
        kind: RcKind.asyncJob,
      );
    case 'bisync':
      if (!has(0) || !has(1)) return missing();
      return RcDispatch(
        method: 'sync/bisync',
        params: {'path1': need(0), 'path2': need(1)},
        kind: RcKind.asyncJob,
      );
    case 'check':
      if (!has(0) || !has(1)) return missing();
      return RcDispatch(
        method: 'operations/check',
        params: {'srcFs': need(0), 'dstFs': need(1)},
        kind: RcKind.asyncJob,
        asyncResult: true,
      );
    case 'delete':
    case 'cleanup':
      if (!has(0)) return missing();
      return RcDispatch(
        method: verb == 'delete' ? 'operations/delete' : 'operations/cleanup',
        params: {'fs': need(0)},
        kind: RcKind.asyncJob,
      );
    case 'purge':
      if (!has(0)) return missing();
      final s = split(need(0));
      if (s == null) return missing();
      return RcDispatch(
        method: 'operations/purge',
        params: s,
        kind: RcKind.asyncJob,
      );
    case 'rmdirs':
      if (!has(0)) return missing();
      final s = split(need(0));
      if (s == null) return missing();
      return RcDispatch(
        method: 'operations/rmdirs',
        params: {...s, 'leaveRoot': false},
        kind: RcKind.asyncJob,
      );
    default:
      return RcRefusal(_refuseVerb(verb));
  }
}
