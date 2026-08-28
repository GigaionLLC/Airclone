import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

/// Low-level `dart:ffi` binding to rclone's C library (`librclone`) plus the
/// worker-isolate plumbing that keeps its (blocking) calls off the UI isolate.
///
/// The C ABI (confirmed against rclone v1.74.4 `librclone/librclone.go`):
/// ```c
/// void  RcloneInitialize(void);
/// void  RcloneFinalize(void);
/// struct RcloneRPCResult { char* Output; int Status; };
/// struct RcloneRPCResult RcloneRPC(char* method, char* input);   // JSON in/out
/// void  RcloneFreeString(char* str);
/// ```
/// `RcloneRPC` speaks the SAME RC protocol as the HTTP daemon — a method string
/// and a JSON body in, a JSON body + HTTP-style status out — so above
/// [FfiRcloneClient] nothing about the app changes. See dev/plans/dual-engine-plan.md.
///
/// Everything FFI (the [DynamicLibrary], the [Pointer]s, the lookups) lives
/// ENTIRELY inside the worker isolate: those handles are not sendable, and
/// `RcloneRPC` blocks on network I/O, which would freeze the UI if run inline.
/// The one long-lived worker opens the lib + resolves symbols ONCE and calls
/// `RcloneInitialize` exactly once; transfers already run as async RC jobs
/// (`_async: true`, polled via `core/stats`), so serializing the short
/// control-plane RPCs through a single worker costs nothing observable.

/// `struct RcloneRPCResult { char* Output; int Status; }`, returned by value.
/// Field names mirror the C struct exactly (hence the lint waiver).
// ignore_for_file: non_constant_identifier_names
final class _RcloneRPCResult extends Struct {
  external Pointer<Utf8> Output;

  @Int32()
  external int Status;
}

typedef _VoidNative = Void Function();
typedef _VoidDart = void Function();
typedef _RpcNative = _RcloneRPCResult Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _RpcDart = _RcloneRPCResult Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _FreeNative = Void Function(Pointer<Utf8>);
typedef _FreeDart = void Function(Pointer<Utf8>);

/// The platform filename of the librclone shared library. Pure (takes the OS
/// name) so it is unit-testable without a real platform.
String librcloneFileName(String operatingSystem) {
  switch (operatingSystem) {
    case 'macos':
      return 'librclone.dylib';
    case 'windows':
      return 'librclone.dll';
    default: // linux (and any other unix)
      return 'librclone.so';
  }
}

/// Whether librclone is STATICALLY linked into the executable on
/// [operatingSystem], instead of loaded from a file beside it.
///
/// Only iOS. Go's `c-shared` build mode is not supported there at all, so the
/// iOS build emits a `c-archive` that the Xcode target `-force_load`s into the
/// app binary: there is no `.dylib` to find and no path to resolve, and the
/// symbols are already in the process. A missing library is therefore a LINK
/// error at build time rather than anything a running app could detect.
///
/// Pure (takes the OS name) so it is testable without a device.
bool librcloneIsStaticallyLinked(String operatingSystem) =>
    operatingSystem == 'ios';

/// Best-effort absolute path to the bundled librclone.
///
/// - **Windows/Linux:** beside the executable (Windows would also find a bare
///   name via the default DLL search path, but Linux does NOT search the app dir,
///   so resolve absolutely for both). CMake installs it into that dir.
/// - **macOS:** under `Contents/Frameworks/` (sibling of `Contents/MacOS/`, where
///   the exe lives). That is where signed dylibs belong — the release codesign
///   pass already walks Frameworks, so the bundled lib is signed with the app and
///   passes notarization; a loose dylib in `MacOS/` would be unsigned and rejected.
String defaultLibrclonePath() {
  // Statically linked: there is no file, and the empty string is the sentinel
  // that makes the worker use DynamicLibrary.process() instead of open().
  if (librcloneIsStaticallyLinked(Platform.operatingSystem)) return '';
  final name = librcloneFileName(Platform.operatingSystem);
  final exe = File(Platform.resolvedExecutable);
  if (Platform.isMacOS) {
    final contents = exe.parent.parent.path; // Airclone.app/Contents
    return '$contents/Frameworks/$name';
  }
  return '${exe.parent.path}${Platform.pathSeparator}$name';
}

/// Whether the in-process engine can be loaded in this build.
///
/// Replaces a bare `File(defaultLibrclonePath()).existsSync()`, which reports
/// FALSE on iOS - where the engine is always present, just not as a file.
bool librcloneLibraryAvailable() =>
    librcloneIsStaticallyLinked(Platform.operatingSystem) ||
    File(defaultLibrclonePath()).existsSync();

/// Thrown for a catastrophic FFI/worker failure (symbol missing, isolate died) —
/// distinct from an rclone-reported non-2xx status, which surfaces via the normal
/// result path so [FfiRcloneClient] can map it to an `RcloneException`.
class LibrcloneFfiException implements Exception {
  LibrcloneFfiException(this.message);
  final String message;
  @override
  String toString() => 'LibrcloneFfiException: $message';
}

/// Owns the librclone worker isolate and exposes an async, main-isolate-safe RPC.
///
/// Lifecycle: [start] (spawn + Initialize + optional `config/setpath`), any number
/// of [rpc] calls, then [stop] (Finalize + tear down). One instance == one engine.
class LibrcloneEngine {
  Isolate? _isolate;
  SendPort? _commands;
  ReceivePort? _fromWorker;
  bool _started = false;
  int _nextId = 0;

  final _pending = <int, Completer<(int, String)>>{};
  Completer<String?>? _initReply; // error string, or null on success
  Completer<void>? _stopReply;

  bool get isStarted => _started;

  /// Spawn the worker, open [libPath], set the config password env (if any),
  /// `RcloneInitialize`, and — when [configPath] is set — point rclone at it via
  /// the `config/setpath` RC method. Throws [LibrcloneFfiException] if the worker
  /// cannot initialize (missing lib/symbols, bad config path).
  Future<void> start({
    required String libPath,
    String? configPath,
    String? configPass,
  }) async {
    if (_started) return;
    final fromWorker = ReceivePort();
    _fromWorker = fromWorker;
    final ready = Completer<SendPort>();
    _initReply = Completer<String?>();

    fromWorker.listen((msg) {
      if (msg is SendPort) {
        if (!ready.isCompleted) ready.complete(msg);
        return;
      }
      final list = msg as List;
      switch (list[0] as String) {
        case 'inited':
          if (!(_initReply?.isCompleted ?? true)) {
            _initReply!.complete(list[1] as String?);
          }
        case 'result':
          _pending.remove(list[1] as int)?.complete((
            list[2] as int,
            list[3] as String,
          ));
        case 'rpcerr':
          _pending
              .remove(list[1] as int)
              ?.completeError(LibrcloneFfiException(list[2] as String));
        case 'stopped':
          if (!(_stopReply?.isCompleted ?? true)) _stopReply!.complete();
      }
    });

    _isolate = await Isolate.spawn(
      _workerEntry,
      fromWorker.sendPort,
      onError: fromWorker.sendPort,
      errorsAreFatal: true,
    );
    _commands = await ready.future;
    _commands!.send(['init', libPath, configPath, configPass]);
    final err = await _initReply!.future;
    if (err != null) {
      await stop();
      throw LibrcloneFfiException(err);
    }
    _started = true;
  }

  /// One RPC. Returns `(httpStatus, jsonOutput)`; the caller maps non-2xx to an
  /// error. Throws [LibrcloneFfiException] on an FFI/worker-level failure.
  Future<(int, String)> rpc(String method, String input) {
    final cmds = _commands;
    if (!_started || cmds == null) {
      return Future.error(LibrcloneFfiException('engine not started'));
    }
    final id = _nextId++;
    final completer = Completer<(int, String)>();
    _pending[id] = completer;
    cmds.send(['rpc', id, method, input]);
    return completer.future;
  }

  /// `RcloneFinalize` + tear down the worker. Idempotent. Pending RPCs error out.
  Future<void> stop() async {
    final cmds = _commands;
    if (cmds != null) {
      _stopReply = Completer<void>();
      cmds.send(const ['stop']);
      try {
        await _stopReply!.future.timeout(const Duration(seconds: 5));
      } catch (_) {
        /* fall through to hard kill */
      }
    }
    _isolate?.kill(priority: Isolate.immediate);
    _fromWorker?.close();
    _isolate = null;
    _commands = null;
    _fromWorker = null;
    _started = false;
    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.completeError(LibrcloneFfiException('engine stopped'));
      }
    }
    _pending.clear();
  }
}

// ---------------------------------------------------------------------------
// Worker isolate — the ONLY place that touches FFI. Runs in its own isolate so
// the blocking RcloneRPC never stalls the UI, and so the native handles (which
// are not sendable) stay isolate-local.
// ---------------------------------------------------------------------------

void _workerEntry(SendPort toMain) {
  final commands = ReceivePort();
  toMain.send(commands.sendPort);
  _Bindings? bindings;

  commands.listen((msg) {
    final list = msg as List;
    switch (list[0] as String) {
      case 'init':
        try {
          bindings = _Bindings.load(
            list[1] as String, // libPath
            list[2] as String?, // configPath
            list[3] as String?, // configPass
          );
          toMain.send(const ['inited', null]);
        } catch (e) {
          toMain.send(['inited', '$e']);
        }
      case 'rpc':
        final id = list[1] as int;
        final b = bindings;
        if (b == null) {
          toMain.send(['rpcerr', id, 'engine not initialized']);
          return;
        }
        try {
          final (status, output) = b.rpc(list[2] as String, list[3] as String);
          toMain.send(['result', id, status, output]);
        } catch (e) {
          toMain.send(['rpcerr', id, '$e']);
        }
      case 'stop':
        try {
          bindings?.finalize();
        } catch (_) {
          /* best effort */
        }
        bindings = null;
        toMain.send(const ['stopped']);
        commands.close();
    }
  });
}

/// Resolved librclone function pointers + the marshalling around them. Lives only
/// inside the worker isolate.
class _Bindings {
  _Bindings._(this._init, this._finalize, this._rpc, this._free);

  final _VoidDart _init;
  final _VoidDart _finalize;
  final _RpcDart _rpc;
  final _FreeDart _free;

  static _Bindings load(
    String libPath,
    String? configPath,
    String? configPass,
  ) {
    // An empty path means the archive is linked into this executable (iOS).
    // `process()` searches the whole loaded image, `open('')` would fail.
    final lib = libPath.isEmpty
        ? DynamicLibrary.process()
        : DynamicLibrary.open(libPath);
    final init = lib.lookupFunction<_VoidNative, _VoidDart>('RcloneInitialize');
    final finalize = lib.lookupFunction<_VoidNative, _VoidDart>(
      'RcloneFinalize',
    );
    final rpc = lib.lookupFunction<_RpcNative, _RpcDart>('RcloneRPC');
    final free = lib.lookupFunction<_FreeNative, _FreeDart>('RcloneFreeString');
    final b = _Bindings._(init, finalize, rpc, free);

    // The encryption password must be visible to rclone's config load, which
    // happens during/after Initialize. Set it on the LIVE process environment
    // (Go reads it via GetEnvironmentVariableW / getenv, not a CRT snapshot)
    // BEFORE Initialize, then it can be cleared.
    if (configPass != null && configPass.isNotEmpty) {
      _setProcessEnv('RCLONE_CONFIG_PASS', configPass);
    }
    b._init();
    if (configPass != null && configPass.isNotEmpty) {
      _setProcessEnv('RCLONE_CONFIG_PASS', '');
    }

    // Point rclone at a specific config file via the first-class RC method
    // (cleaner than an env var; runs after Initialize, before any config read).
    if (configPath != null && configPath.isNotEmpty) {
      final (status, output) = b.rpc(
        'config/setpath',
        jsonEncode({'path': configPath}),
      );
      if (status ~/ 100 != 2) {
        throw LibrcloneFfiException('config/setpath failed [$status]: $output');
      }
    }
    return b;
  }

  (int, String) rpc(String method, String input) {
    final m = method.toNativeUtf8();
    final i = input.toNativeUtf8();
    try {
      final r = _rpc(m, i);
      final status = r.Status;
      final out = r.Output == nullptr ? '' : r.Output.toDartString();
      if (r.Output != nullptr) _free(r.Output);
      return (status, out);
    } finally {
      malloc.free(m);
      malloc.free(i);
    }
  }

  void finalize() => _finalize();
}

/// Sets a process environment variable that rclone (Go) will read. Go's
/// `os.Getenv` reads the LIVE environment block on every platform, so on Windows
/// we must use kernel32 `SetEnvironmentVariableW` (a CRT `_putenv` would only
/// touch the calling CRT's snapshot); on POSIX libc `setenv` is process-wide.
void _setProcessEnv(String name, String value) {
  if (Platform.isWindows) {
    final k32 = DynamicLibrary.open('kernel32.dll');
    final setEnv = k32
        .lookupFunction<
          Int32 Function(Pointer<Utf16>, Pointer<Utf16>),
          int Function(Pointer<Utf16>, Pointer<Utf16>)
        >('SetEnvironmentVariableW');
    final n = name.toNativeUtf16();
    final v = value.toNativeUtf16();
    try {
      setEnv(n, v);
    } finally {
      malloc.free(n);
      malloc.free(v);
    }
  } else {
    final libc = DynamicLibrary.process();
    if (value.isEmpty) {
      final unsetenv = libc
          .lookupFunction<
            Int32 Function(Pointer<Utf8>),
            int Function(Pointer<Utf8>)
          >('unsetenv');
      final n = name.toNativeUtf8();
      try {
        unsetenv(n);
      } finally {
        malloc.free(n);
      }
      return;
    }
    final setenv = libc
        .lookupFunction<
          Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int32),
          int Function(Pointer<Utf8>, Pointer<Utf8>, int)
        >('setenv');
    final n = name.toNativeUtf8();
    final v = value.toNativeUtf8();
    try {
      setenv(n, v, 1);
    } finally {
      malloc.free(n);
      malloc.free(v);
    }
  }
}
