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

import 'models/provider.dart';
import 'models/rclone_file.dart';
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
      sync = RcSync(client);

  /// The engine underneath. Use it directly for anything not typed here.
  final RcloneClient client;

  final RcCore core;
  final RcConfig config;
  final RcOperations operations;
  final RcJob job;
  final RcSync sync;
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
  }) async {
    final res = await send(
      'operations/list',
      {'fs': fs, 'remote': remote, 'opt': ?opt},
      extra: extra,
      options: options,
    );
    return ((res['list'] as List?) ?? const [])
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
}
