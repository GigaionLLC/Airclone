/// A typed face over rclone's rc API.
///
/// **It is a facade, not an interface.** Everything here ends in
/// [RcloneClient.rpc], which is why adding it breaks nothing: a fake that
/// answers `rpc('operations/list', …)` answers `api.operations.list(…)` too,
/// and `RcloneClient` itself never grows a member. Raw `rpc` stays the escape
/// hatch for everything not covered here, and for anything rclone adds later.
///
/// Every method takes `extra`, merged into its parameters, so moving a call
/// site onto the typed form can never silently drop a parameter it was
/// passing. `options` ([RcOptions]) carries the underscore-prefixed
/// parameters and is merged last.
///
/// The exact method string and parameter map each of these sends is pinned by
/// `test/rc_api_test.dart` — that is what makes migrating a call site
/// provably behaviour-preserving.
library;

import 'models/mount_info.dart';
import 'models/provider.dart';
import 'models/rclone_file.dart';
import 'models/serve_server.dart';
import 'rc_options.dart';
import 'rclone_client.dart';

/// Typed calls, grouped the way rclone groups its rc methods.
///
/// ```dart
/// final api = RcApi(client);
/// final files = await api.operations.list('gdrive:', 'papers');
/// ```
class RcApi {
  RcApi(this.client)
    : core = RcCore(client),
      config = RcConfig(client),
      operations = RcOperations(client),
      job = RcJob(client),
      sync = RcSync(client),
      mount = RcMount(client),
      serve = RcServe(client),
      vfs = RcVfs(client);

  /// The engine underneath. Use it directly for anything not typed here.
  final RcloneClient client;

  final RcCore core;
  final RcConfig config;
  final RcOperations operations;
  final RcJob job;
  final RcSync sync;
  final RcMount mount;
  final RcServe serve;
  final RcVfs vfs;
}

/// Shared plumbing: merge a method's own parameters with `extra` and
/// [RcOptions], in that order, and send.
abstract class _Namespace {
  const _Namespace(this.client);

  final RcloneClient client;

  Future<Map<String, dynamic>> send(
    String method,
    Map<String, dynamic> params, {
    Map<String, dynamic>? extra,
    RcOptions options = RcOptions.none,
  }) {
    final merged = <String, dynamic>{...params, ...?extra};
    return client.rpc(method, options.apply(merged));
  }

  /// The `jobid` an `_async` call returns.
  AsyncJob asJob(Map<String, dynamic> result) {
    final id = (result['jobid'] as num?)?.toInt();
    if (id == null) {
      throw RcloneException('_async', 'the call returned no jobid');
    }
    return AsyncJob(id);
  }
}

/// `core/*` — the engine itself.
class RcCore extends _Namespace {
  const RcCore(super.client);

  /// The running rclone's version, e.g. `v1.74.4`.
  Future<String?> version({Map<String, dynamic>? extra}) async =>
      (await send('core/version', const {}, extra: extra))['version']
          as String?;

  /// Live transfer statistics. [group] narrows them to one stats group.
  Future<Map<String, dynamic>> stats({
    String? group,
    Map<String, dynamic>? extra,
  }) => send('core/stats', {'group': ?group}, extra: extra);

  /// What has finished transferring, per group.
  Future<Map<String, dynamic>> transferred({
    String? group,
    Map<String, dynamic>? extra,
  }) => send('core/transferred', {'group': ?group}, extra: extra);

  /// Reads the bandwidth limit, or sets it when [rate] is given
  /// (rclone's own syntax: `off`, `1M`, `10M:100k`).
  Future<Map<String, dynamic>> bwlimit({
    String? rate,
    Map<String, dynamic>? extra,
  }) => send('core/bwlimit', {'rate': ?rate}, extra: extra);

  /// Ask the engine to exit. The client's own `quit()` is usually what you
  /// want; this is the bare RC method.
  Future<Map<String, dynamic>> quit({Map<String, dynamic>? extra}) =>
      send('core/quit', const {}, extra: extra);

  /// Memory the Go runtime is holding.
  Future<Map<String, dynamic>> memstats({Map<String, dynamic>? extra}) =>
      send('core/memstats', const {}, extra: extra);

  // `core/command` is deliberately NOT here. It runs an arbitrary rclone
  // command line, its output shape depends on `returnType`, and the caller
  // that needs it (a command console) needs the streaming form and its own
  // policy about what may be run at all. A typed wrapper would only make it
  // look ordinary. Use `client.rpc` — or `HttpRcloneClient.commandStream`.
}

/// `config/*` — the remotes rclone knows about.
///
/// Everything here reads or writes the user's rclone config file. Nothing in
/// it is redacted for you: `dump` returns secrets in clear, because that is
/// what the method does.
class RcConfig extends _Namespace {
  const RcConfig(super.client);

  /// The configured remote names, without their trailing colons.
  Future<List<String>> listRemotes({Map<String, dynamic>? extra}) async {
    final res = await send('config/listremotes', const {}, extra: extra);
    return ((res['remotes'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList(growable: false);
  }

  /// The whole config, remote by remote. **Contains credentials.**
  Future<Map<String, dynamic>> dump({Map<String, dynamic>? extra}) =>
      send('config/dump', const {}, extra: extra);

  /// One remote's settings. **Contains credentials.**
  Future<Map<String, dynamic>> get(
    String name, {
    Map<String, dynamic>? extra,
  }) => send('config/get', {'name': name}, extra: extra);

  /// Where rclone is reading its config from.
  Future<Map<String, dynamic>> paths({Map<String, dynamic>? extra}) =>
      send('config/paths', const {}, extra: extra);

  /// Every backend rclone can create, with its options.
  Future<List<RcloneProvider>> providers({Map<String, dynamic>? extra}) async {
    final res = await send('config/providers', const {}, extra: extra);
    return ((res['providers'] as List?) ?? const [])
        .map((e) => RcloneProvider.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Creates a remote.
  ///
  /// [parameters] must also be passed on every CONTINUE step, not just the
  /// first: rclone answers a provider question with a 400 when it is absent,
  /// which is how a Microsoft Store certification failure once happened. Pass
  /// `opt` (e.g. `{'nonInteractive': true}`) through [extra].
  Future<Map<String, dynamic>> create({
    required String name,
    required String type,
    Map<String, Object?> parameters = const {},
    Map<String, dynamic>? extra,
  }) => send('config/create', {
    'name': name,
    'type': type,
    'parameters': parameters,
  }, extra: extra);

  /// Updates an existing remote. The [parameters] rule above applies here too.
  Future<Map<String, dynamic>> update({
    required String name,
    Map<String, Object?> parameters = const {},
    Map<String, dynamic>? extra,
  }) => send('config/update', {
    'name': name,
    'parameters': parameters,
  }, extra: extra);

  /// Deletes a remote from the config.
  Future<Map<String, dynamic>> delete(
    String name, {
    Map<String, dynamic>? extra,
  }) => send('config/delete', {'name': name}, extra: extra);
}

/// `operations/*` — one call, one object or one directory.
class RcOperations extends _Namespace {
  const RcOperations(super.client);

  /// Lists `fs:remote`.
  ///
  /// [opt] is rclone's own listing options map (`recurse`, `dirsOnly`,
  /// `showHash`, `metadata`, …), passed through untouched.
  Future<List<RcloneFile>> list(
    String fs,
    String remote, {
    Map<String, Object?>? opt,
    Map<String, dynamic>? extra,
    RcOptions options = RcOptions.none,
  }) async =>
      await listOrNull(fs, remote, opt: opt, extra: extra, options: options) ??
      const <RcloneFile>[];

  /// Lists `fs:remote`, or **null when the answer carried no listing at all**.
  ///
  /// [list] cannot tell those two apart - it reports both as empty - and for
  /// some callers that difference is the entire answer. Anything that decides
  /// "this directory is empty, so it is safe to delete / overwrite / prune"
  /// wants this method, because an empty listing is also what you get when a
  /// crypt remote's second password is wrong: rclone skips every name it
  /// cannot decrypt and still exits 0. "I read nothing" and "I could not read"
  /// must not look the same to code that then writes.
  Future<List<RcloneFile>?> listOrNull(
    String fs,
    String remote, {
    Map<String, Object?>? opt,
    Map<String, dynamic>? extra,
    RcOptions options = RcOptions.none,
  }) async {
    final res = await send(
      'operations/list',
      {'fs': fs, 'remote': remote, 'opt': ?opt},
      extra: extra,
      options: options,
    );
    final raw = res['list'];
    if (raw is! List) return null;
    return raw
        .map((e) => RcloneFile.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// One object's metadata, or null when it does not exist.
  Future<RcloneFile?> stat(
    String fs,
    String remote, {
    Map<String, dynamic>? extra,
  }) async {
    final res = await send('operations/stat', {
      'fs': fs,
      'remote': remote,
    }, extra: extra);
    final item = res['item'];
    return item == null
        ? null
        : RcloneFile.fromJson(item as Map<String, dynamic>);
  }

  /// Creates a directory.
  Future<Map<String, dynamic>> mkdir(
    String fs,
    String remote, {
    Map<String, dynamic>? extra,
  }) => send('operations/mkdir', {'fs': fs, 'remote': remote}, extra: extra);

  /// Removes an EMPTY directory.
  Future<Map<String, dynamic>> rmdir(
    String fs,
    String remote, {
    Map<String, dynamic>? extra,
  }) => send('operations/rmdir', {'fs': fs, 'remote': remote}, extra: extra);

  /// Removes a directory AND EVERYTHING IN IT.
  Future<Map<String, dynamic>> purge(
    String fs,
    String remote, {
    Map<String, dynamic>? extra,
    RcOptions options = RcOptions.none,
  }) => send(
    'operations/purge',
    {'fs': fs, 'remote': remote},
    extra: extra,
    options: options,
  );

  /// Deletes one file.
  Future<Map<String, dynamic>> deleteFile(
    String fs,
    String remote, {
    Map<String, dynamic>? extra,
  }) =>
      send('operations/deletefile', {'fs': fs, 'remote': remote}, extra: extra);

  /// Copies one file between filesystems, keeping the source.
  Future<Map<String, dynamic>> copyFile({
    required String srcFs,
    required String srcRemote,
    required String dstFs,
    required String dstRemote,
    Map<String, dynamic>? extra,
    RcOptions options = RcOptions.none,
  }) => send(
    'operations/copyfile',
    {
      'srcFs': srcFs,
      'srcRemote': srcRemote,
      'dstFs': dstFs,
      'dstRemote': dstRemote,
    },
    extra: extra,
    options: options,
  );

  /// Moves one file between filesystems.
  Future<Map<String, dynamic>> moveFile({
    required String srcFs,
    required String srcRemote,
    required String dstFs,
    required String dstRemote,
    Map<String, dynamic>? extra,
    RcOptions options = RcOptions.none,
  }) => send(
    'operations/movefile',
    {
      'srcFs': srcFs,
      'srcRemote': srcRemote,
      'dstFs': dstFs,
      'dstRemote': dstRemote,
    },
    extra: extra,
    options: options,
  );

  /// Quota and usage, for backends that report it. Many do not, and say so
  /// with an error rather than zeroes.
  Future<Map<String, dynamic>> about(
    String fs, {
    Map<String, dynamic>? extra,
  }) => send('operations/about', {'fs': fs}, extra: extra);

  /// What a backend can do — hashes, server-side copy, and the rest.
  Future<Map<String, dynamic>> fsInfo(
    String fs, {
    Map<String, dynamic>? extra,
  }) => send('operations/fsinfo', {'fs': fs}, extra: extra);

  /// Total size and object count below `fs`.
  Future<Map<String, dynamic>> size(String fs, {Map<String, dynamic>? extra}) =>
      send('operations/size', {'fs': fs}, extra: extra);

  /// A public link to an object, on backends that can mint one.
  Future<Map<String, dynamic>> publicLink(
    String fs,
    String remote, {
    Map<String, dynamic>? extra,
  }) =>
      send('operations/publiclink', {'fs': fs, 'remote': remote}, extra: extra);

  /// Compares two filesystems.
  ///
  /// The five bucket flags ask rclone to RETURN the per-bucket file lists, not
  /// merely count them, and default to on because a caller that wanted counts
  /// only would read `core/stats`. [download] compares by streaming bytes,
  /// which is the only honest answer when the two backends share no hash.
  ///
  /// Pass `options: RcOptions(async: true)` for anything but a tiny tree; the
  /// result is then an [AsyncJob] id to poll, and the buckets arrive in
  /// `job/status`'s `output`.
  Future<Map<String, dynamic>> check({
    required String srcFs,
    required String dstFs,
    bool download = false,
    bool match = true,
    bool missingOnSrc = true,
    bool missingOnDst = true,
    bool differ = true,
    bool error = true,
    Map<String, dynamic>? extra,
    RcOptions options = RcOptions.none,
  }) => send(
    'operations/check',
    {
      'srcFs': srcFs,
      'dstFs': dstFs,
      'download': download,
      'match': match,
      'missingOnSrc': missingOnSrc,
      'missingOnDst': missingOnDst,
      'differ': differ,
      'error': error,
    },
    extra: extra,
    options: options,
  );

  /// Copies the contents of a URL into `fs:remote`.
  ///
  /// With [autoFilename], `remote` is the DESTINATION DIRECTORY and rclone
  /// takes the file name from the URL; without it, `remote` is the full
  /// destination path including the name.
  Future<Map<String, dynamic>> copyUrl({
    required String fs,
    required String remote,
    required String url,
    bool autoFilename = false,
    Map<String, dynamic>? extra,
    RcOptions options = RcOptions.none,
  }) => send(
    'operations/copyurl',
    {
      'fs': fs,
      'remote': remote,
      'url': url,
      if (autoFilename) 'autoFilename': true,
    },
    extra: extra,
    options: options,
  );

  /// Empties the backend's trash, where it has one. Irreversible.
  Future<Map<String, dynamic>> cleanup(
    String fs, {
    Map<String, dynamic>? extra,
    RcOptions options = RcOptions.none,
  }) => send('operations/cleanup', {'fs': fs}, extra: extra, options: options);

  /// **Deletes every file under `fs`**, honouring `_filter` if one is set.
  /// [purge] removes a directory; this removes contents. Both are final.
  Future<Map<String, dynamic>> delete(
    String fs, {
    Map<String, dynamic>? extra,
    RcOptions options = RcOptions.none,
  }) => send('operations/delete', {'fs': fs}, extra: extra, options: options);
}

/// `job/*` — the background jobs `_async` calls create.
class RcJob extends _Namespace {
  const RcJob(super.client);

  /// Where a job has got to. `finished`, `success`, `error`, `output`.
  Future<Map<String, dynamic>> status(
    int jobid, {
    Map<String, dynamic>? extra,
  }) => send('job/status', {'jobid': jobid}, extra: extra);

  /// Asks a running job to stop.
  Future<Map<String, dynamic>> stop(int jobid, {Map<String, dynamic>? extra}) =>
      send('job/stop', {'jobid': jobid}, extra: extra);

  /// Stops every job in a stats group — the group an `_group` parameter put
  /// them in.
  Future<Map<String, dynamic>> stopGroup(
    String group, {
    Map<String, dynamic>? extra,
  }) => send('job/stopgroup', {'group': group}, extra: extra);

  /// The ids the engine currently knows about.
  Future<List<int>> list({Map<String, dynamic>? extra}) async {
    final res = await send('job/list', const {}, extra: extra);
    return ((res['jobids'] as List?) ?? const [])
        .map((e) => (e as num).toInt())
        .toList(growable: false);
  }
}

/// `sync/*` — whole-directory work, which is almost always asynchronous.
///
/// These default to `_async`, unlike everything else here: a sync of any size
/// outlives an HTTP request, and the engine's own answer to that is a job id.
/// Pass `options: RcOptions()` to wait instead.
class RcSync extends _Namespace {
  const RcSync(super.client);

  /// Copies `srcFs` into `dstFs`, leaving anything extra at the destination
  /// alone.
  Future<AsyncJob> copy({
    required String srcFs,
    required String dstFs,
    Map<String, dynamic>? extra,
    RcOptions options = const RcOptions(async: true),
  }) async => asJob(
    await send(
      'sync/copy',
      {'srcFs': srcFs, 'dstFs': dstFs},
      extra: extra,
      options: options,
    ),
  );

  /// Moves `srcFs` into `dstFs`.
  Future<AsyncJob> move({
    required String srcFs,
    required String dstFs,
    Map<String, dynamic>? extra,
    RcOptions options = const RcOptions(async: true),
  }) async => asJob(
    await send(
      'sync/move',
      {'srcFs': srcFs, 'dstFs': dstFs},
      extra: extra,
      options: options,
    ),
  );

  /// Makes `dstFs` identical to `srcFs`. **This deletes at the destination.**
  Future<AsyncJob> sync({
    required String srcFs,
    required String dstFs,
    Map<String, dynamic>? extra,
    RcOptions options = const RcOptions(async: true),
  }) async => asJob(
    await send(
      'sync/sync',
      {'srcFs': srcFs, 'dstFs': dstFs},
      extra: extra,
      options: options,
    ),
  );

  /// Two-way sync. Note the parameter names: `path1`/`path2`, not src/dst,
  /// because neither side is the source. A first run needs
  /// `extra: {'resync': true}` - without it rclone refuses to guess which
  /// side is right.
  Future<AsyncJob> bisync({
    required String path1,
    required String path2,
    Map<String, dynamic>? extra,
    RcOptions options = const RcOptions(async: true),
  }) async => asJob(
    await send(
      'sync/bisync',
      {'path1': path1, 'path2': path2},
      extra: extra,
      options: options,
    ),
  );
}

/// `mount/*` - mounting a remote as a drive or folder on the host.
///
/// Every one of these acts on the MACHINE THE ENGINE RUNS ON, which is not
/// necessarily the machine that called: an engine reached over the network
/// mounts a drive there, not here.
class RcMount extends _Namespace {
  const RcMount(super.client);

  /// Mounts `fs` at [mountPoint].
  ///
  /// [vfsOpt] and [mountOpt] keys are rclone's **Go field names**
  /// (`CacheMode`, `DirCacheTime`, `AttrTimeout`, ...), not its command-line
  /// flags, and durations and sizes go over as strings (`"24h"`, `"32Mi"`)
  /// which rclone parses itself. `CacheMode` is the exception: an int.
  Future<Map<String, dynamic>> mount({
    required String fs,
    required String mountPoint,
    Map<String, Object?>? vfsOpt,
    Map<String, Object?>? mountOpt,
    Map<String, dynamic>? extra,
  }) => send('mount/mount', {
    'fs': fs,
    'mountPoint': mountPoint,
    'vfsOpt': ?vfsOpt,
    'mountOpt': ?mountOpt,
  }, extra: extra);

  /// Unmounts one mount point.
  Future<Map<String, dynamic>> unmount(
    String mountPoint, {
    Map<String, dynamic>? extra,
  }) => send('mount/unmount', {'mountPoint': mountPoint}, extra: extra);

  /// Unmounts everything this engine mounted. Safe to call when there is
  /// nothing mounted, which is why it is the sane thing to run at shutdown.
  Future<Map<String, dynamic>> unmountAll({Map<String, dynamic>? extra}) =>
      send('mount/unmountall', const {}, extra: extra);

  /// What is mounted right now.
  Future<List<MountInfo>> listMounts({Map<String, dynamic>? extra}) async {
    final res = await send('mount/listmounts', const {}, extra: extra);
    final list = res['mountPoints'];
    return list is List
        ? [for (final e in list) MountInfo.fromList(e)]
        : const <MountInfo>[];
  }

  /// The mount implementations this build supports (`mount`, `cmount`,
  /// `nfsmount`). An empty list means this rclone cannot mount at all.
  Future<List<String>> types({Map<String, dynamic>? extra}) async {
    final res = await send('mount/types', const {}, extra: extra);
    return (res['mountTypes'] as List?)?.whereType<String>().toList(
          growable: false,
        ) ??
        const <String>[];
  }
}

/// `serve/*` - exposing a remote over a network protocol.
class RcServe extends _Namespace {
  const RcServe(super.client);

  /// Starts a server of [type] (`http`, `webdav`, `ftp`, `sftp`, `dlna`, ...)
  /// over `fs`, listening on [addr].
  ///
  /// The option names are rclone's own snake_case wire names, which is why
  /// they are spelled out here rather than left to the caller: `read_only`,
  /// `vfs_cache_mode`. **`user`/`pass` are ignored by protocols that cannot
  /// authenticate** (DLNA and NFS), so a server started without them is
  /// reachable by anyone who can reach [addr]; that is a decision for the host
  /// app to put in front of its user, not something this can fix.
  Future<Map<String, dynamic>> start({
    required String type,
    required String fs,
    required String addr,
    String? user,
    String? pass,
    bool readOnly = false,
    String? vfsCacheMode,
    Map<String, dynamic>? extra,
  }) => send('serve/start', {
    'type': type,
    'fs': fs,
    'addr': addr,
    'user': ?user,
    'pass': ?pass,
    if (readOnly) 'read_only': true,
    'vfs_cache_mode': ?vfsCacheMode,
  }, extra: extra);

  /// Stops one server by the id `start` returned.
  Future<Map<String, dynamic>> stop(String id, {Map<String, dynamic>? extra}) =>
      send('serve/stop', {'id': id}, extra: extra);

  /// Stops every server this engine started.
  Future<Map<String, dynamic>> stopAll({Map<String, dynamic>? extra}) =>
      send('serve/stopall', const {}, extra: extra);

  /// The servers running right now.
  Future<List<ServeServer>> list({Map<String, dynamic>? extra}) async {
    final res = await send('serve/list', const {}, extra: extra);
    final list = res['list'];
    return list is List
        ? [
            for (final e in list)
              if (e is Map) ServeServer.fromList(e.cast<String, dynamic>()),
          ]
        : const <ServeServer>[];
  }

  /// The protocols this build can serve.
  Future<List<String>> types({Map<String, dynamic>? extra}) async {
    final res = await send('serve/types', const {}, extra: extra);
    return (res['types'] as List?)?.whereType<String>().toList(
          growable: false,
        ) ??
        const <String>[];
  }
}

/// `vfs/*` - the cache that sits under a mount or a server.
class RcVfs extends _Namespace {
  const RcVfs(super.client);

  /// Re-reads directories the VFS has cached, so a change made elsewhere
  /// becomes visible inside a mount without waiting for `--dir-cache-time`.
  ///
  /// [recursive] travels as the STRING `'true'`, because that is what this
  /// method's parameters are - rclone parses them as flags - and it is the
  /// form Airclone has shipped since mounts existed. A refresh of a large tree
  /// can take a while, so pass `options: RcOptions(async: true)`.
  Future<Map<String, dynamic>> refresh({
    String? fs,
    String? dir,
    bool recursive = false,
    Map<String, dynamic>? extra,
    RcOptions options = RcOptions.none,
  }) => send(
    'vfs/refresh',
    {'fs': ?fs, 'dir': ?dir, if (recursive) 'recursive': 'true'},
    extra: extra,
    options: options,
  );

  /// Drops a directory or file from the cache instead of re-reading it.
  /// Everything is forgotten when nothing is named.
  Future<Map<String, dynamic>> forget({
    String? fs,
    String? dir,
    String? file,
    Map<String, dynamic>? extra,
  }) =>
      send('vfs/forget', {'fs': ?fs, 'dir': ?dir, 'file': ?file}, extra: extra);

  /// The active VFSes, by the `fs` each was created for. More than one means
  /// a later call must say which it means.
  Future<List<String>> list({Map<String, dynamic>? extra}) async {
    final res = await send('vfs/list', const {}, extra: extra);
    return (res['vfses'] as List?)?.whereType<String>().toList(
          growable: false,
        ) ??
        const <String>[];
  }

  /// Cache size, item counts and in-flight uploads.
  Future<Map<String, dynamic>> stats({
    String? fs,
    Map<String, dynamic>? extra,
  }) => send('vfs/stats', {'fs': ?fs}, extra: extra);
}
