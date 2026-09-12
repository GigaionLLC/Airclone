# Dual-engine plan: in-process `librclone` alongside spawned `rcd`

**Status:** SHIPPED — all five phases. The desktop in-process engine ships from v0.2.0-beta.1
(`EngineMode` switch in Settings, `librclone` built and bundled by CI on all three desktops); the
iOS engine is statically linked and reached `ready` on a simulator on 2026-08-28, and iOS/MAS
builds have been through App Store review since.
**Pinned rclone:** whatever `RCLONE_VERSION` says in
[`.github/workflows/release.yml`](../../.github/workflows/release.yml) — that is the value that
actually builds the artifact, and it carries a comment explaining each bump. Do not restate it here;
a second copy only goes stale, and this one is security-relevant.
**Owner interface:** [`RcloneClient`](../../app/lib/src/rclone/rclone_client.dart) — the ONE seam.

## Why

*(Written before the work; the present tense below describes the pre-v0.2.0-beta.1 world.)*

The engine was always a **spawned `rclone rcd`** subprocess driven over loopback
HTTP ([`HttpRcloneClient`](../../app/lib/src/rclone/http_rclone_client.dart)) — on
desktop directly, on Android via a bundled `librclone.so` exec'd as a subprocess.
That is still the desktop default; what follows is why a second engine had to exist
beside it.

Two forces need a second engine that runs rclone **in-process** via `dart:ffi`:

1. **Mac App Store / iOS** forbid `fork()`/`exec()` of a bundled binary. Linking
   `librclone` is the *only* legal way to run rclone there (see
   [wiki/core/08-core-architecture.md](../../wiki/core/08-core-architecture.md)).
2. **Desktop option** (user ask): on Windows/macOS/Linux, offer an in-process
   engine as an alternative to the subprocess — no stray `rclone.exe`, one process
   to sign/sandbox, tidier lifecycle. DMG/self-build keeps *both*; MAS ships library-only.

The seam already anticipates this — `rclone_client.dart`'s header says params/results
are "identical JSON shapes whether driven over HTTP … or in-process (mobile,
`librclone`)". librclone's `RcloneRPC(method, input)` **is** the RC API. So above
`RcloneClient.rpc`, nothing changes. This is a transport swap, not a rewrite.

## The librclone C ABI (confirm in spike against v1.74.4 source)

```c
void  RcloneInitialize(void);                 // once, before any RPC
void  RcloneFinalize(void);                   // on shutdown
struct RcloneRPCResult { char* Output; int Status; };
struct RcloneRPCResult RcloneRPC(char* method, char* input);  // input/Output = JSON
void  RcloneFreeString(char* str);            // free .Output
```

`Status` is the HTTP-like code (200 = ok). `Output` is a JSON string that MUST be
freed with `RcloneFreeString`. Struct-return-by-value is supported by Dart FFI
(`Struct` subclass).

**CONFIRMED against v1.74.4 source** (`librclone/librclone.go`, `librclone/ctest/ctest.c`):
- Package is `github.com/rclone/rclone/librclone` (top-level, `package main`, cgo exports).
- Struct is exactly `{ char* Output; int Status; }` — pointer first, `int` (Int32) second.
- **Build:** `go build --buildmode=c-shared -o librclone.dll github.com/rclone/rclone/librclone`
  (also emits `librclone.h`). Depends on `libdl`+`libpthread` (mingw provides both on Windows).
- **`config/setpath`** is a real RC method (`{"path": "..."}`) — use it to point at a
  custom config file *after* Initialize, cleaner than the `RCLONE_CONFIG` env var.
- **Build risk:** the stock package imports `cmd/cmount`/`mount`/`mount2`. On Windows,
  cgofuse loads WinFsp at *runtime* (no build-time WinFsp headers needed) so the
  c-shared build should still link. If it doesn't, fall back to a trimmed `main` that
  imports only `backend/all` + `fs/operations` + `fs/sync` (drop mount) — Airclone's
  FFI engine doesn't need OS mount.

## Naming

`FfiRcloneClient` (matches the mermaid in the architecture wiki). Lives at
`app/lib/src/rclone/ffi_rclone_client.dart`. The low-level binding is a separate
`app/lib/src/rclone/librclone_ffi.dart` (DynamicLibrary + lookups + isolate glue),
so the client stays about lifecycle/semantics and the FFI mechanics are isolated
(and mockable).

## Seam mapping (HTTP → FFI)

| `RcloneClient` member | `HttpRcloneClient` (today) | `FfiRcloneClient` (new) |
|---|---|---|
| `rpc(method, params)` | POST JSON to `http://127.0.0.1:<port>/<method>` | `RcloneRPC(method, jsonEncode(params))` on a worker isolate; map `Status/2 != 100` → `RcloneException` |
| `start()` | free port, spawn `rcd`, await `core/version` | set env (config path/pass) via FFI `setenv`, `RcloneInitialize`, await `core/version` |
| `quit()` | `core/quit` + kill process | `RcloneFinalize` (+ stop the objectRef bridge) |
| `restart()` | quit + start | quit + start |
| `status()` | `core/version` or stopped | `core/version` or stopped |
| `objectRef(fs, remote)` | loopback URL to rcd `--rc-serve` + Basic auth | **loopback URL to a Dart-side bridge server** (below) |
| `onDied` | fires if subprocess exits unexpectedly | never fires (in-process = as alive as the app); field kept, unused |

**Interface change:** move `onDied` onto `RcloneClient` (currently set on the
concrete `HttpRcloneClient` in `engine_controller._startWith`) so `EngineController`
can hold either impl as `RcloneClient`.

## The hard part: `objectRef` under FFI

Preview/media widgets fetch bytes with `Image.network(url, headers)` /
range-GET. The HTTP engine points them at rcd's `--rc-serve` file server. librclone
has **no HTTP server** and `RcloneRPC` returns JSON only — no byte streaming.

**Bridge:** `FfiRcloneClient` runs a tiny Dart `HttpServer` bound to loopback with a
per-session token (same auth shape as rcd), so `objectRef` returns the *same* URL +
`Authorization` header shape and every preview widget works unchanged.

Per request `GET /[fs]/<encoded path>`:
1. Resolve a temp cache file for (fs, path). If absent, `operations/copyfile`
   (src `fs`/`remote` → dst local temp fs/name) via `rpc` to materialize bytes once.
2. Serve the temp file with **Range** support (so video/audio seeking works, and
   `Image.network` gets a normal 200). Cache keyed by fs+path (+ size/modtime);
   subsequent requests / paging hit the cached file. LRU/size-cap cleanup.

Tradeoff: cloud previews pay a one-time full fetch before first paint (local backend
= a fast file copy). Acceptable for images/text; media seeks are served from the
cached file after the first fetch. Documented limitation; a future streaming path
(gomobile serve, or a librclone serve RC method if one ever lands) can replace it.

## Config path + password (no subprocess env)

`HttpRcloneClient` passes `--config` as argv and `RCLONE_CONFIG_PASS` as child env.
In-process there is no child. rclone honors process env vars:
- `RCLONE_CONFIG` → the config file path (replaces `--config`).
- `RCLONE_CONFIG_PASS` → the encryption password.

**Config path:** call the `config/setpath` RC method (`{"path": "<file>"}`) after
Initialize — a first-class RC method (seen in `ctest.c`), no env needed.
**Config password:** set `RCLONE_CONFIG_PASS` via FFI `setenv`/`_putenv_s` (Dart's
`Platform.environment` is read-only) **before** `RcloneInitialize` (Initialize loads
config), then wipe it. This mirrors the existing encryption gate in `EngineController`
1:1 (same detection, same password flow) — only the delivery differs.

## Concurrency / threading

`RcloneRPC` is synchronous and can block on network I/O — calling it on the UI
isolate would freeze the app. Every `rpc()` runs off-isolate.

- **v1:** `Isolate.run` per RPC. The native lib is already mapped in-process, so
  re-`DynamicLibrary.open(<name>)` inside the fresh isolate returns a handle to the
  *same* loaded module + shared Go runtime; `RcloneRPC` runs on that isolate's thread
  so concurrent RPCs (browse while a transfer runs) don't serialize. `RcloneInitialize`
  runs exactly once in `start()` (its effect is process-global, visible to all isolates).
- **Later (if spawn overhead shows):** a fixed worker-isolate pool over a
  `ReceivePort`. Note only; don't build it first.

Go handles multi-thread entry (cgo thread binding); Dart isolates here are just OS
threads into one Go runtime.

## Engine mode switch

New setting `engineMode`:
- `binary` — spawned `rcd` (`HttpRcloneClient`). Today's behavior; desktop default.
- `library` — in-process (`FfiRcloneClient`). Forced on iOS/MAS.
- `auto` — resolve per platform (binary where a subprocess is allowed, else library).

Pure resolver `resolveEngineMode({platform, isMacAppStore, setting}) → {binary|library}`
(unit-tested, no I/O). `EngineController._startWith` branches on it to construct the
right client; everything downstream reads `state.client` as before. Desktop Settings
exposes the choice; iOS/MAS show it forced+explained (binary greyed out).

## Native build matrix

| Platform | Artifact | Toolchain | Notes |
|---|---|---|---|
| Windows | `librclone.dll` | cgo + mingw-w64 (WinLibs UCRT) | `GOOS=windows GOARCH=amd64 CGO_ENABLED=1 -buildmode=c-shared` |
| macOS | `librclone.dylib` (universal) | cgo + clang | build arm64 + amd64, `lipo -create`; sign for MAS |
| Linux | `librclone.so` | cgo + gcc | `-buildmode=c-shared` |
| iOS | `rclone.xcframework` | `gomobile bind -target=ios` | **different path** (static framework, App-Store legal); later phase |
| Android | (already a subprocess `librclone.so`) | existing `dev/android/build-rclone.ps1` | FFI swap optional, not in scope now |

Build script `dev/desktop/build-librclone.ps1` (+ `.sh`) mirrors the Android script's
dummy-module/`go get`/env-snapshot pattern, targeting the librclone package as
`c-shared`. Bundling: place the lib beside the executable (Windows: next to
`airclone.exe` via CMake `install`; macOS: `Frameworks/`; Linux: `lib/`), resolved by
`DynamicLibrary.open('<name>')`.

## Phasing

- **Phase 0 — SPIKE ✅ DONE (2026-07-11):** portable mingw (WinLibs UCRT gcc 16.1
  at `<user home>\tools\mingw64`) → built `librclone.dll` (66.8 MB, 26s) from
  v1.74.4 via the `<user home>\.airclone-librclone-desktop` work module → Dart
  FFI round-trip **works**: all 4 exports resolve, struct-return-by-value marshals,
  `core/version`→200 (`v1.74.4-DEV`), `config/listremotes`→200 (read the real config),
  `RcloneFreeString`+`RcloneFinalize` clean. Spike files under
  `scratchpad/spike/` (build script `scratchpad/build-librclone-dll.ps1`).
  **Caveat:** module build reports `v1.74.4-DEV` — production builds MUST stamp
  `-ldflags "-X github.com/rclone/rclone/fs.Version=v1.74.4"` so `meetsMinRclone`
  accepts it. Runtime dll deps (`libwinpthread-1.dll` etc.) must be co-located or
  static-linked (`-extldflags "-static"`) for bundling.
- **Phase 1 — `FfiRcloneClient` core:** `librclone_ffi.dart` binding + isolate glue;
  `rpc/start/quit/status` (no objectRef yet — previews disabled on FFI). Behind a
  hidden flag. Reuse the full test suite by pointing it at the FFI client on a
  lib-present machine.
- **Phase 2 — objectRef bridge:** loopback file server + copyfile-to-temp + Range +
  cache. Previews/media work on FFI.
- **Phase 3 — mode switch + wiring ✅ DONE (99ebf2f):** `EngineMode`
  {auto,binary,inProcess} + pure `resolveEngineMode`; persisted setting; desktop
  Settings "Engine" segmented control; `EngineController` resolves the mode and
  builds the right client, with the encryption gate working binary-free (probe the
  library's `config/paths`). `onDied` kept OFF the interface (set only on
  HttpRcloneClient) so the 17 test fakes stay valid. Live UI click-through smoke
  still owed (machine-lock).
- **Phase 4 — build+bundle ✅ (Windows verified locally; mac/linux CI-only):**
  - `dev/desktop/build-librclone.ps1` (Windows) — self-contained (`-extldflags -static`
    folds the mingw runtime in; verified: only KERNEL32 + UCRT deps) + version-stamped
    (`-X fs.Version=v1.74.4`; verified reports clean `v1.74.4`). Loads with mingw OFF PATH.
  - `dev/desktop/build-librclone.sh` (macOS universal dylib via lipo / Linux .so).
  - Bundling: Windows `windows/CMakeLists.txt` + Linux `linux/CMakeLists.txt` install
    the lib NEXT TO the exe (verified on Windows: `librclone.dll` sits beside
    `airclone.exe` after `flutter build windows`). macOS copies the dylib into
    `Contents/Frameworks/` in CI after the app build, before codesign (so the
    inside-out codesign pass seals it → notarization-safe); `defaultLibrclonePath`
    resolves `Contents/Frameworks/librclone.dylib` on macOS, `<exeDir>/lib…` elsewhere.
  - CI: `release.yml` builds librclone before each `flutter build` (setup-go +
    egor-tensin/setup-mingw on Windows). `ci.yml` pin-staleness check extended to the
    new scripts. **Verified in CI since:** `release.yml` runs a dedicated `librclone`
    matrix job (windows/macos/ubuntu) on every tagged release, isolated from the
    Flutter build so a stray gcc can't hijack Windows' MSVC toolchain, uploading with
    `if-no-files-found: error`; the platform jobs declare `needs: librclone`. A leg
    that fails means that platform ships binary-engine-only, by design.
  - Artifacts gitignored (`app/{windows,macos,linux}/librclone/`).
- **Phase 5 — iOS/MAS ✅ DONE (2026-08-28; iOS and MAS have both been through App Store review
  since).** `gomobile bind` was the wrong guess — upstream's gomobile binding is Android-only. What
  actually works, recorded in [`dev/ios/build-librclone-ios.sh`](../../dev/ios/build-librclone-ios.sh)
  and [`.github/workflows/librclone-ios.yml`](../../.github/workflows/librclone-ios.yml):
  - **`-buildmode=c-archive`, one slice at a time.** `c-shared` is not supported on iOS, so the
    engine links statically into the app binary and Dart resolves it with
    `DynamicLibrary.process()`, never `open()`.
  - **A trimmed wrapper package** ([`dev/ios/librclone_ios.go`](../../dev/ios/librclone_ios.go))
    importing only `backend/all`, `fs/operations` and `fs/sync`. Stock `librclone` is unusable here
    because `cmd/mount2` is real on `ios/amd64`; `fs/sync` is not optional (it is what `sync/copy`
    and `sync/move` need). `storj.io/common` needs a module `replace` — its `go:linkname` into the
    runtime breaks the c-archive relink.
  - **Dead-strip roots are mandatory.** The Xcode target links with `-force_load` plus
    `-Wl,-u,_RcloneInitialize|_RcloneFinalize|_RcloneRPC|_RcloneFreeString`; without them the linker
    drops an engine nothing statically references. Go does not apply its own `//go:cgo_ldflag`
    directives for c-archive either, so the target must link CoreFoundation, Security and libresolv
    by hand.
  - **The simulator archive must be fat (arm64 + x86_64).** `flutter build ios --simulator` always
    emits both, and `-force_load` of an archive missing an architecture is only a *warning* — the
    slice silently contains no engine. Give each target its own `GOCACHE` for the same class of
    reason (golang/go#57442 poisons a shared one with device-tagged artifacts).
  - MAS entitlements and signing are not covered here; they live in
    [`apple-appstore-plan.md`](../plans/apple-appstore-plan.md).

## Unit-testable vs integration-only

- **Unit (no native lib):** `resolveEngineMode`, objectRef URL builder, the
  RPC-status→exception mapping (extract a pure `mapRpcResult(status, output)` helper),
  the bridge's path-encode/auth-token logic.
- **Integration (native lib present):** the FFI round-trip, `start/quit`, a real
  `objectRef` fetch. Gated so CI without the lib skips them.

## Open questions the spike was run to answer

Historical, and all three are answered in the shipped code. Phase 0 settled the first two directly:
all four exports resolve and struct-return-by-value marshals, so no cgo shim was needed. The third
split in two — the config *path* is set with the `config/setpath` RC method
(`librclone_ffi.dart`), while the config *password* does need a process env write, so
`_setProcessEnv` resolves `setenv`/`_putenv_s` through `DynamicLibrary.process()` and carries the
CRT-snapshot caveat in its own comment.

- Exact librclone package import path + `RcloneRPCResult` field order (inspect module).
- Does Dart FFI struct-return-by-value work cleanly for `{char*, int}` here, or do we
  need a wrapper export returning via out-params? (Fallback: a tiny cgo shim.)
- `setenv` availability on Windows (`_putenv_s` in msvcrt/ucrt) via `DynamicLibrary.process()`.
