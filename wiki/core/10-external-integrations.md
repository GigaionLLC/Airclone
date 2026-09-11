---
type: "core"
name: "External Integrations"
status: "stable"
dependencies: ["08-core-architecture", "14-performance-standards"]
description: "Every seam between Airclone and the outside world: the RcloneClient engine abstraction, the full rclone RC method catalogue, the platform channels, bundled native code, and the OS integration surfaces."
---

# 🔌 External Integrations

The complete map of everything Airclone talks to outside its own Dart code — the rclone engine, the
platform channels, the bundled native libraries, and the operating system.

**When to read this:** you are about to call a new rclone RC method, add a native/platform-channel
call, bundle another native library, or touch mount / serve / drag-and-drop / open-in-another-app /
background execution.

Airclone has **exactly four** outward seams. Nothing else in the app reaches outside the process.

| # | Seam | Owner | Section |
| :--- | :--- | :--- | :--- |
| 1 | **`RcloneClient`** — the one engine abstraction (JSON RC in/out + a byte reference) | [`rclone/`](../../app/lib/src/rclone/) | [§1](#1--rcloneclient--the-one-engine-seam) · [§2](#2--rc-method-catalogue) |
| 2 | **Platform channels** — three app-defined MethodChannel names: `airclone/native`, `airclone/work`, `airclone/work_bg` | [`NativeChannel.kt`](../../app/android/app/src/main/kotlin/app/airclone/airclone/NativeChannel.kt) · [`WorkChannel.kt`](../../app/android/app/src/main/kotlin/app/airclone/airclone/WorkChannel.kt) · [`DueTasksWorker.kt`](../../app/android/app/src/main/kotlin/app/airclone/airclone/DueTasksWorker.kt) (Android) · [`SecurityScopedBookmarks.swift`](../../app/macos/Runner/SecurityScopedBookmarks.swift) (Mac App Store) | [§3](#3--platform-channels) |
| 3 | **Bundled native code** — rclone, librclone, libmpv, PDFium, a Rust crate | CI + build scripts | [§4](#4--bundled-native-code) |
| 4 | **OS integration** — mount, serve, drag, hand-off, credential vault, biometrics, background execution | [`state/`](../../app/lib/src/state/) + plugins | [§5](#5--os-integration-surfaces) |

The *decision* behind seam 1 (why two implementations, why one interface) lives in
[08-core-architecture.md](08-core-architecture.md) §3. This document is the *reference*: what exists
today, verified against the source.

---

## 1. 🔀 `RcloneClient` — the one engine seam

[`rclone_client.dart`](../../app/lib/src/rclone/rclone_client.dart) declares an
`abstract interface class` with **six members**. Everything above it is transport-agnostic Dart.

| Member | Contract |
| :--- | :--- |
| `rpc(String method, [Map params])` | The core RPC. Returns the decoded JSON map on 2xx; throws `RcloneException` otherwise. |
| `start()` | Bring the engine up and prove it answers `core/version`. |
| `quit()` | Tear it down. |
| `restart()` | First-class op — rclone has **no** `core/restart`. Both clients implement it as `quit()` + `start()`. |
| `status()` | Non-throwing `EngineStatus(state, version, message)` snapshot. |
| `objectRef(String fs, String remote)` | An **`ObjectRef(url, headers)`** — an authenticated URL + header pair for an object's raw bytes (previews, thumbnails, media, external hand-off). |

Supporting types in the same file: `ObjectRef`, `enum EngineState {stopped, starting, running, error}`,
`EngineStatus`, `RcloneException(method, message, {statusCode})`.

`objectRef` is the **whole** byte path — there is no streaming read on the interface. Its consumers are
[`preview_dialog.dart`](../../app/lib/src/ui/preview_dialog.dart),
[`quick_look.dart`](../../app/lib/src/ui/quick_look.dart),
[`inspector_panel.dart`](../../app/lib/src/ui/inspector_panel.dart),
[`folder_thumbnail.dart`](../../app/lib/src/ui/folder_thumbnail.dart),
[`browser_pane.dart`](../../app/lib/src/ui/browser_pane.dart) and
[`open_external_action.dart`](../../app/lib/src/ui/open_external_action.dart), none of which knows which
engine is live.

### 1.1 The two implementations

There is no third variant. **Android runs the same `HttpRcloneClient` as desktop.**

| | `HttpRcloneClient` | `FfiRcloneClient` |
| :--- | :--- | :--- |
| File | [`http_rclone_client.dart`](../../app/lib/src/rclone/http_rclone_client.dart) | [`ffi_rclone_client.dart`](../../app/lib/src/rclone/ffi_rclone_client.dart) |
| Mechanism | Spawns the `rclone` **executable** as `rcd`; POSTs JSON over loopback HTTP | `dart:ffi` → `librclone`'s C ABI, in-process |
| Used on | Windows · macOS · Linux (default) · **Android** | Desktop when selected/only option; the only legal path for iOS / Mac App Store |
| Transport detail | `POST http://127.0.0.1:<free port>/<method>`, Basic auth, 30 s timeout, **one automatic retry on a connection-level failure — read-only methods only** (§6) | `RcloneRPC(method, inputJson) → (Output, Status)` on a worker isolate |
| Error mapping | non-2xx → `RcloneException` carrying rclone's `error` field | `mapRpcResult()` — pure, unit-tested, produces the **identical** shape |
| Byte path | rcd's built-in `--rc-serve` file server at `/[<fs>]/<percent-encoded remote>` | `LibrcloneObjectServer` (§1.4) |
| Extra capability | `commandStream()` — `core/command` with `returnType: STREAM` | none (see [§6](#6--gotchas)) |

**`rcd` spawn argv** ([`http_rclone_client.dart#L259`](../../app/lib/src/rclone/http_rclone_client.dart#L259)):

```
rclone rcd <user extraArgs…> --rc-addr 127.0.0.1:<free port> --rc-user airclone
           --rc-pass <24 random bytes, base64url> --rc-serve
           --rc-job-expire-duration 24h [--config <path>]
```

- User-supplied engine flags go **first, on purpose**: pflag lets the *last* occurrence win, so the
  loopback bind and per-session credentials always override anything pasted into the engine-flags
  setting.
- `RCLONE_CONFIG_PASS` travels via **env only**, never argv.
- Orphan containment: `WindowsChildJob.adopt(pid)` on spawn, plus a PID marker at
  `<systemTemp>/airclone_rcd.pid` reaped on the next launch (skipped on Android).
- **Both** `stdout` and `stderr` are drained unconditionally, on every build — that is a pipe-deadlock
  fix, not a logging feature ([14-performance-standards.md §6](14-performance-standards.md)).
  **Retention is the separate decision:** debug prints every line, while a release build keeps only
  rclone's own `ERROR`/`CRITICAL` lines (at `-vv`/`--dump` rclone echoes request headers carrying the
  rc credentials), minus the `operations/about` + `operations/fsinfo` capability probes, de-duplicated
  and capped at 100 a session, into the diagnostics ring. `isEngineFailureLine` is a pure top-level
  function so that rule is unit-testable on its own. One line type is inspected **before** either
  filter, on every build: rclone's `Skipping undecryptable file name` / `Skipping undecryptable dir
  name` NOTICE (it words objects and directories separately), which is a `crypt` key mismatch and the
  only evidence a listing came back short (§6). It is counted every time and
  written to the diagnostics ring once per session — one broken folder emits a notice per entry, and
  repeating that would spend the ring's whole budget restating a fact the first line already made.

**librclone C ABI**, confirmed in-tree against rclone v1.74.4's `librclone/librclone.go`
([`librclone_ffi.dart#L12`](../../app/lib/src/rclone/librclone_ffi.dart#L12)):
`RcloneInitialize()`, `RcloneFinalize()`, `RcloneRPC(char*, char*) → {char* Output; int Status;}`,
`RcloneFreeString(char*)`. **All FFI lives inside one long-lived worker isolate** — `DynamicLibrary`
and `Pointer` are not sendable, and `RcloneRPC` blocks on network I/O.

### 1.2 Which client runs, per platform

`EngineController._resolveEngineMode` ([`engine_controller.dart#L161`](../../app/lib/src/state/engine_controller.dart#L161))
feeds the pure, unit-tested `resolveEngineMode()` in
[`engine_mode.dart`](../../app/lib/src/state/engine_mode.dart#L39).

| Input | Value today |
| :--- | :--- |
| `Platform.isAndroid` | **Short-circuits to `EngineMode.binary` before the setting is read** — engine choice is desktop-only. |
| `subprocessAllowed` | `subprocessAllowedHere` from [`build_flavor.dart`](../../app/lib/src/state/build_flavor.dart) — **false** in a Mac App Store build (`flutter build macos --dart-define=AIRCLONE_MAS=true`) and on iOS, true everywhere else. `kMacAppStoreBuild` is a `bool.fromEnvironment` compile-time constant, so the spawn path is const-folded and tree-shaken **out of** a store binary rather than merely unused in it. |
| `libraryAvailable` | `File(defaultLibrclonePath()).existsSync()` |
| `binaryAvailable` | `RcloneEngine.findExisting() != null` |

Resolution rules: `!subprocessAllowed` → always `inProcess`; an explicit `inProcess` is honoured when
the library exists, else falls back to `binary`; `auto` prefers the binary but picks the library when
no binary exists and one is bundled.

The same flag drives two more features from
[`native_actions_policy.dart`](../../app/lib/src/state/native_actions_policy.dart): **reveal in file
manager** and **archive create/extract/list**, both of which spawn a process, are hidden rather than
left to fail — a dead action is a store rejection. Deliberately **not** gated: *open with the default
app* (`url_launcher` / NSWorkspace, not a spawn, and sandbox-legal for a file the user granted) and
*copy path*.

`kMacAppStoreBuild` gates two further surfaces **directly**, not through `subprocessAllowedHere`, so
they are easy to miss when auditing what a store build still offers:
[`mountEnabledProvider`](../../app/lib/src/state/mount_policy.dart) and
[`serveEnabledProvider`](../../app/lib/src/state/serve_policy.dart) are both `!kMacAppStoreBuild`. A
Mac App Store build therefore offers neither Mount (FUSE is impossible under the App Sandbox) nor
Serve (the entitlement set omits `com.apple.security.network.server`) — hidden at the one provider
every entry point already checks, rather than failing at runtime.

### 1.3 Locating and provisioning the binary

`RcloneEngine.findExisting()` ([`rclone_engine.dart#L31`](../../app/lib/src/rclone/rclone_engine.dart#L31)) —
first hit wins:

1. explicit settings override,
2. **Android** → `bundledAndroidBinary()` and nothing else,
3. the app-managed engine dir (`<applicationSupport>/engine/rclone[.exe]`),
4. a binary bundled beside the executable (`bundledDesktopBinary()` — every desktop build ships one),
5. `rclone` on `PATH` (`where` / `which`).

Managed is checked **before** bundled deliberately, so a user-initiated engine update wins on the next
launch.

| Concern | Behaviour |
| :--- | :--- |
| **Store-managed gate** | `isStoreManaged()` calls kernel32 `GetCurrentPackageFullName` with a null name buffer: `APPMODEL_ERROR_NO_PACKAGE` (15700) ⇒ unpackaged, anything else ⇒ MSIX. Needed because the MSIX repackages the **identical** compiled exe (`msix:create --build-windows false`), so nothing at compile time tells them apart. `downloadLatestToStaging()` throws for a Store build and for Android. A future sandboxed macOS App Store build must add its own check here before shipping. |
| **Download is fail-closed** | Resolves `downloads.rclone.org/version.txt`, fetches `rclone-<ver>-<os>-<arch>.zip`, and refuses to install if the official `SHA256SUMS` cannot be fetched, parsed for that zip name, or matched — a `StateError`, never an unverified engine. |
| **Swap is recoverable** | Downloads land in a `.new` staging file; `installStaged` renames the current binary to `<managed>.old` (undone by `rollbackEngine`), with a 10×200 ms rename retry because Windows briefly holds a handle on a just-exited process's image. |
| **Minimum version** | `minRcloneVersion = '1.73.5'`, enforced fail-closed — an unparseable version does **not** meet the minimum. |

### 1.4 `LibrcloneObjectServer` — the in-process byte bridge

librclone has no HTTP server and `RcloneRPC` returns JSON only, so `FfiRcloneClient` starts a tiny
loopback `HttpServer` on port 0 with a per-session Bearer token
([`librclone_object_server.dart`](../../app/lib/src/rclone/librclone_object_server.dart)).

`GET /obj?fs=…&remote=…` materialises the object into `previewCacheDir` via `operations/copyfile`
run with `_async: true` (a large download must never block the engine worker isolate), polls
`job/status` every 150 ms up to a 10-minute deadline, renames `<sha1>.part` → `<sha1>`, and streams it
back with single-range `Range:` / 206 `Content-Range` support and a best-effort `Content-Type`.
In-flight materialisations are deduped by cache key.

Because the URL + `Authorization` header shape matches the rcd file server exactly, **every preview
widget works unchanged**. With no `previewCacheDir`, `objectRef` throws `UnsupportedError` and
previews go dark while browse and transfer keep working.

---

## 2. 📚 RC method catalogue

**50 distinct RC methods** are called across the app. Five (marked 🖥️) are reachable *only* through
the console's fail-closed argv→RC translator
([`console_rc_translate.dart`](../../app/lib/src/state/console/console_rc_translate.dart)) and have no
button anywhere in the UI.

Shared conventions: `_async: true` + `_group: 'airclone/<local job id>'` for anything the jobs panel
tracks; `_config` / `_filter` blocks for per-call global options and filters; `opt: {…}` for
per-method options.

### `config/*`

| Method | What it is used for | Call sites |
| :--- | :--- | :--- |
| `config/dump` | Every configured remote (sidebar list); source of a scoped export; **and the duplicate-name probe every `config/create` caller must run first** (`existingRemoteNames`) | [`remotes_provider.dart#L22`](../../app/lib/src/state/remotes_provider.dart#L22), `#L36` · [`config_transfer_controller.dart#L495`](../../app/lib/src/state/config_transfer_controller.dart#L495) |
| `config/providers` | The backend catalogue that drives the provider picker + dynamic forms | [`providers_provider.dart#L11`](../../app/lib/src/state/providers_provider.dart#L11) |
| `config/create` | Add a remote; answer an interactive question (when not editing); import merge and replace; create a `crypt` remote; duplicate a remote. **It silently REPLACES a section of the same name** — see §6 — so the add-remote and encrypt wizards refuse a taken name first, and import has to make replacing an explicit choice | [`add_remote_controller.dart#L139`](../../app/lib/src/state/add_remote_controller.dart#L139), `#L232` · [`config_transfer_controller.dart#L165`](../../app/lib/src/state/config_transfer_controller.dart#L165), `#L264` · [`encrypt_remote_controller.dart#L94`](../../app/lib/src/state/encrypt_remote_controller.dart#L94) · [`home_screen.dart#L1550`](../../app/lib/src/ui/home_screen.dart#L1550) |
| `config/update` | Save an edit; answer an interactive question **during** an edit (never `config/create`, which would recreate) | [`add_remote_controller.dart#L215`](../../app/lib/src/state/add_remote_controller.dart#L215), `#L232` |
| `config/get` | Prefill the edit form (password fields blanked — an obscured token is never surfaced); read a remote for duplication | [`add_remote_controller.dart#L177`](../../app/lib/src/state/add_remote_controller.dart#L177) · [`home_screen.dart#L1544`](../../app/lib/src/ui/home_screen.dart#L1544) |
| `config/delete` | Remove a remote; prune remotes absent from an incoming config during a replace; **remove every remote at once** (Settings → Remove all remotes), which backs the config up first and refuses if it cannot | [`home_screen.dart#L1526`](../../app/lib/src/ui/home_screen.dart#L1526) · [`mobile_action_sheets.dart#L583`](../../app/lib/src/ui/mobile_action_sheets.dart#L583) · [`config_transfer_controller.dart#L216`](../../app/lib/src/state/config_transfer_controller.dart#L216) (remove all), `#L292` (replace prune) |
| `config/paths` | Probe for the config file location — for the in-process engine's encryption gate, and for `engineConfigPath()`, which pins the engine's own config onto every re-exec'd child (§6) | [`engine_controller.dart#L528`](../../app/lib/src/state/engine_controller.dart#L528) · [`http_rclone_client.dart#L427`](../../app/lib/src/rclone/http_rclone_client.dart#L427) |
| `config/setpath` | Point librclone at an explicit config **after** `RcloneInitialize` | [`librclone_ffi.dart#L324`](../../app/lib/src/rclone/librclone_ffi.dart#L324) |
| `config/listremotes` 🖥️ | console `listremotes` | [`console_rc_translate.dart#L302`](../../app/lib/src/state/console/console_rc_translate.dart#L302) |

### `operations/*`

| Method | What it is used for | Call sites |
| :--- | :--- | :--- |
| `operations/list` | The browser listing **and**, separately, each folder a tree-view node expands (`_loadTreeFolder` — the one listing path that does *not* sample the undecryptable-name counter, see §6); destination picker; folder-thumbnail probe; paste/drop collision probe; search (`recurse`); dedupe scan **and** its local cloud-placeholder pre-probe; crypt round-trip canary; connection-test fallback when About is unsupported; console `ls`/`lsf`/`lsl`/`lsjson`/`lsd` | [`browser_controller.dart#L811`](../../app/lib/src/state/browser_controller.dart#L811) (`_load`), [`#L759`](../../app/lib/src/state/browser_controller.dart#L759) (`_loadTreeFolder`) · [`destination_picker.dart#L120`](../../app/lib/src/ui/destination_picker.dart#L120) · [`folder_thumbnail.dart#L57`](../../app/lib/src/ui/folder_thumbnail.dart#L57) · [`paste_action.dart#L107`](../../app/lib/src/ui/paste_action.dart#L107) · [`search_dialog.dart#L79`](../../app/lib/src/ui/search_dialog.dart#L79) · [`dedupe_dialog.dart#L103`](../../app/lib/src/ui/dedupe_dialog.dart#L103), `#L133`, `#L192` · [`encrypt_remote_controller.dart#L242`](../../app/lib/src/state/encrypt_remote_controller.dart#L242) · [`connection_test_dialog.dart#L38`](../../app/lib/src/ui/connection_test_dialog.dart#L38) |
| `operations/stat` | File-vs-dir probe before dispatch; per-file checksums via `opt: {showHash: true, hashTypes: …}` | [`transfer_service.dart#L57`](../../app/lib/src/state/transfer_service.dart#L57) · [`console_controller.dart#L284`](../../app/lib/src/state/console/console_controller.dart#L284) · [`checksum_dialog.dart#L29`](../../app/lib/src/ui/checksum_dialog.dart#L29) |
| `operations/about` | Remote quota/usage; connection test; console `about` | [`remote_about.dart#L25`](../../app/lib/src/state/remote_about.dart#L25) · [`connection_test_dialog.dart#L24`](../../app/lib/src/ui/connection_test_dialog.dart#L24) |
| `operations/fsinfo` | The backend `Features` map, used to capability-gate UI (e.g. `PublicLink`) | [`remote_features.dart#L13`](../../app/lib/src/state/remote_features.dart#L13) |
| `operations/mkdir` | New folder; crypt probe dir; console `mkdir` | [`file_ops.dart#L84`](../../app/lib/src/state/file_ops.dart#L84) · [`encrypt_remote_controller.dart#L169`](../../app/lib/src/state/encrypt_remote_controller.dart#L169) |
| `operations/rmdir` | Crypt probe cleanup; console `rmdir` | [`encrypt_remote_controller.dart#L228`](../../app/lib/src/state/encrypt_remote_controller.dart#L228) |
| `operations/purge` | Delete a **directory** (recursive); console `purge` | [`file_ops.dart#L113`](../../app/lib/src/state/file_ops.dart#L113) |
| `operations/deletefile` | Delete a **file**; dedupe delete; console `deletefile` | [`file_ops.dart#L115`](../../app/lib/src/state/file_ops.dart#L115) · [`dedupe_dialog.dart#L290`](../../app/lib/src/ui/dedupe_dialog.dart#L290) |
| `operations/movefile` | Rename in place (src/dst fs equal); single-**file** move | [`file_ops.dart#L96`](../../app/lib/src/state/file_ops.dart#L96) · [`transfer_service.dart#L79`](../../app/lib/src/state/transfer_service.dart#L79) |
| `operations/copyfile` | Single-**file** copy; the librclone preview bridge's materialisation | [`transfer_service.dart#L79`](../../app/lib/src/state/transfer_service.dart#L79) · [`librclone_object_server.dart#L132`](../../app/lib/src/rclone/librclone_object_server.dart#L132) |
| `operations/copyurl` | Stream a URL straight into a remote (`autoFilename`) — no local round-trip | [`file_ops.dart#L165`](../../app/lib/src/state/file_ops.dart#L165) |
| `operations/check` | Compare two paths, returning match / missing-on-src / missing-on-dst / differ / error buckets. **This is what the sync dry-run preview is built on** (`missingOnSrc` is exactly what a one-way Sync would delete) — it runs under the same `_config`/`_filter` the transfer will use, because `--size-only`/`--checksum` change what counts as "differs" | [`file_ops.dart#L135`](../../app/lib/src/state/file_ops.dart#L135) · [`folder_tools.dart#L75`](../../app/lib/src/ui/folder_tools.dart#L75) (the "Compare with other pane" tool) · [`sync_preview.dart`](../../app/lib/src/state/sync_preview.dart) · [`sync_here_action.dart`](../../app/lib/src/ui/sync_here_action.dart) |
| `operations/size` | Folder file count + total bytes; also the empty-source refusal in front of a marked-source sync | [`file_ops.dart#L155`](../../app/lib/src/state/file_ops.dart#L155) |
| `operations/cleanup` | Empty backend trash / abort incomplete uploads | [`file_ops.dart#L178`](../../app/lib/src/state/file_ops.dart#L178) |
| `operations/publiclink` | Create a share link; **revoke is the same method with `unlink: true`**; console `link` | [`public_link_dialog.dart#L61`](../../app/lib/src/ui/public_link_dialog.dart#L61), `#L91` |
| `operations/hashsum` 🖥️ | console `md5sum` / `sha1sum` / `hashsum` | [`console_rc_translate.dart#L370`](../../app/lib/src/state/console/console_rc_translate.dart#L370), `#L378` |
| `operations/delete` 🖥️ | console `delete` | [`console_rc_translate.dart#L449`](../../app/lib/src/state/console/console_rc_translate.dart#L449) |
| `operations/rmdirs` 🖥️ | console `rmdirs` | [`console_rc_translate.dart#L467`](../../app/lib/src/state/console/console_rc_translate.dart#L467) |

`operations/uploadfile` is **never called** — it needs a multipart HTTP request. Uploads go through
the `local` backend via `sync/copy` / `operations/copyfile`.

**The destination picker only reaches the engine on its second step.** Its first step — choosing
*where* to browse — is sourced from `remotesProvider` **plus** `drivesProvider` and
`userLocationsProvider`: the same LOCATIONS / DISKS / CLOUD sections as the sidebar, and the two local
ones need no engine at all. It used to list remotes alone, which meant a local disk was impossible to pick as a
destination: "Copy to…" could not reach the drive sitting two inches away in the sidebar. Only
descending into a folder calls `operations/list`, and only that step can report "Engine not ready".
[`destination_picker.dart`](../../app/lib/src/ui/destination_picker.dart).

### `sync/*`, `job/*`, `core/*`

| Method | What it is used for | Call sites |
| :--- | :--- | :--- |
| `sync/copy` · `sync/move` | Directory transfers (the dir branch of stat-then-dispatch); console `copy`/`move`, and the dir fallback for `copyto`/`moveto` | [`transfer_service.dart#L71`](../../app/lib/src/state/transfer_service.dart#L71) · [`console_controller.dart#L294`](../../app/lib/src/state/console/console_controller.dart#L294) |
| `sync/sync` 🖥️ | console `sync` | [`console_rc_translate.dart#L390`](../../app/lib/src/state/console/console_rc_translate.dart#L390) |
| `sync/bisync` | Two-way sync (`maxDelete` here is a **percent**, default 50); console `bisync` | [`transfer_options.dart#L490`](../../app/lib/src/state/transfer_options.dart#L490) |
| `job/status` | Transfer completion polling; scheduler supervision; reading a console read-verb's `output` when its async job settles; the preview bridge's copy wait | [`jobs_controller.dart#L259`](../../app/lib/src/state/jobs_controller.dart#L259) · [`scheduler_controller.dart#L377`](../../app/lib/src/state/scheduler_controller.dart#L377) · [`console_controller.dart#L376`](../../app/lib/src/state/console/console_controller.dart#L376) |
| `job/stop` | Jobs-panel Stop and console Stop (one convergence point) | [`jobs_controller.dart#L203`](../../app/lib/src/state/jobs_controller.dart#L203) · [`console_controller.dart#L349`](../../app/lib/src/state/console/console_controller.dart#L349) |
| `core/stats` | The 1 Hz global stats poller; per-job progress scoped by `group` | [`stats_controller.dart#L57`](../../app/lib/src/state/stats_controller.dart#L57) · [`jobs_controller.dart#L235`](../../app/lib/src/state/jobs_controller.dart#L235) |
| `core/version` | Readiness handshake and `status()` on **both** clients; console `version` | [`http_rclone_client.dart#L442`](../../app/lib/src/rclone/http_rclone_client.dart#L442), `#L621` · [`ffi_rclone_client.dart#L59`](../../app/lib/src/rclone/ffi_rclone_client.dart#L59) |
| `core/transferred` | The Recent Activity panel — and **nothing else**: it is a capped ring, not a log (§6) | [`recent_activity_controller.dart#L14`](../../app/lib/src/state/recent_activity_controller.dart#L14) |
| `core/bwlimit` | Read and set the global bandwidth limit | [`bandwidth_controller.dart#L32`](../../app/lib/src/state/bandwidth_controller.dart#L32), `#L45` |
| `core/quit` | Orderly rcd shutdown before `kill()` | [`http_rclone_client.dart#L590`](../../app/lib/src/rclone/http_rclone_client.dart#L590) |
| `core/command` | HTTP-engine-only console streaming (`returnType: STREAM`) | [`http_rclone_client.dart#L560`](../../app/lib/src/rclone/http_rclone_client.dart#L560) |

### `mount/*`, `serve/*`, `vfs/*`

| Method | What it is used for | Call sites |
| :--- | :--- | :--- |
| `mount/types` | Which mount implementations the engine supports. **Empty on Windows means WinFsp is not installed** — the UI then guides the user to it | [`mount_controller.dart#L18`](../../app/lib/src/state/mount_controller.dart#L18) |
| `mount/listmounts` | Source of truth for active mounts, polled every 2 s; nothing is persisted, so mounts never auto-resurrect | [`mount_controller.dart#L43`](../../app/lib/src/state/mount_controller.dart#L43) · [`app.dart#L150`](../../app/lib/src/ui/app.dart#L150) |
| `mount/mount` | Mount `fs` at a mount point (`*` = auto-assign a drive letter — and because that means "whichever letter is free", a mount point can be **pinned per fs** in [`mount_letters.dart`](../../app/lib/src/state/mount_letters.dart) so a remote lands on the same one every time). The whole `vfsOpt` / `mountOpt` payload comes from [`MountOptions`](../../app/lib/src/rclone/models/mount_options.dart) — cache mode **`full`** by default, plus cache size and age, read chunk size + growth limit, dir-cache time, fast-fingerprint, attr-timeout, and Windows-only network mode; `MountController` has no option knowledge of its own. Still never sets a shared cache dir (rclone picks a per-mount one). Keys are rclone's **Go field names**, and an unrecognised one is silently dropped — the rule and the verification method are [14 §6](14-performance-standards.md) | [`mount_controller.dart#L73`](../../app/lib/src/state/mount_controller.dart#L73) · [`mount_defaults.dart`](../../app/lib/src/state/mount_defaults.dart) |
| `mount/unmount` · `mount/unmountall` | Unmount one / all. `unmountAllForExit()` runs **before** the engine stops — rclone serves every mount from the `rcd` process, so stopping the engine first strands the mount point | [`mount_controller.dart#L117`](../../app/lib/src/state/mount_controller.dart#L117), `#L128`, `#L151` |
| `vfs/refresh` | Freshen a mount's directory cache without remounting | [`mount_controller.dart#L100`](../../app/lib/src/state/mount_controller.dart#L100) |
| `serve/types` | Engine-supported protocols, intersected with the curated set `http, webdav, ftp, sftp, dlna` | [`serve_controller.dart#L21`](../../app/lib/src/state/serve_controller.dart#L21) |
| `serve/list` | Source of truth for running servers, polled every 2 s | [`serve_controller.dart#L69`](../../app/lib/src/state/serve_controller.dart#L69) |
| `serve/start` | Start a server. **Whitelisted params only** (`type, fs, addr, user, pass, read_only, vfs_cache_mode`) — never the rc creds, `_config`, or the config password. Security is enforced in `start()` itself, not the UI: policy kill-switch, loopback default (`127.0.0.1:<port>` unless LAN), mandatory auth for exposed auth-capable protocols, and an explicit DLNA acknowledgement | [`serve_controller.dart#L128`](../../app/lib/src/state/serve_controller.dart#L128) |
| `serve/stop` · `serve/stopall` | Stop one / kill-switch tear-down of all | [`serve_controller.dart#L139`](../../app/lib/src/state/serve_controller.dart#L139), `#L151` |

---

## 3. 📱 Platform channels

**Three** app-defined channel names. Two of them are the Android background-execution seam, and both
serve a Flutter engine that has no Activity behind it.

| Channel | Direction | Native handler | Dart side |
| :--- | :--- | :--- | :--- |
| `airclone/native` | Dart → native facts and actions | [`NativeChannel.kt`](../../app/android/app/src/main/kotlin/app/airclone/airclone/NativeChannel.kt) (Android) · [`SecurityScopedBookmarks.swift`](../../app/macos/Runner/SecurityScopedBookmarks.swift) (Mac App Store) | [§3.1](#31-android--nativechannelkt) · [§3.2](#32-macos--securityscopedbookmarksswift) |
| `airclone/work` | Dart → WorkManager: `registerCallback` · `enqueuePeriodic` · `cancelPeriodic` · `runOnce` · `status` | [`WorkChannel.kt`](../../app/android/app/src/main/kotlin/app/airclone/airclone/WorkChannel.kt) | [`android_work_channel.dart`](../../app/lib/src/state/android_work_channel.dart) ([§3.3](#33-android-background-execution)) |
| `airclone/work_bg` | The headless worker's engine → Dart: `start` · `log` · `done` | [`DueTasksWorker.kt`](../../app/android/app/src/main/kotlin/app/airclone/airclone/DueTasksWorker.kt) | [`android_work_entrypoint.dart`](../../app/lib/src/state/android_work_entrypoint.dart) ([§3.3](#33-android-background-execution)) |

The two `airclone/native` method sets are disjoint, and every Dart caller is `Platform`-guarded, so
one name safely serves Android and macOS. There is no iOS, Windows or Linux handler.

### 3.1 Android — `NativeChannel.kt`

Registered on the **application** context, not the Activity. It used to live in
`MainActivity.configureFlutterEngine`, which meant it existed only on an engine some Activity had
created — and a WorkManager worker runs a second Flutter engine with no Activity at all, unable to ask
even for `nativeLibraryDir`, without which the rclone engine cannot start.
[`MainActivity.kt`](../../app/android/app/src/main/kotlin/app/airclone/airclone/MainActivity.kt) is now
27 lines that register the handler against `applicationContext` and lend themselves to the few calls
that genuinely need an Activity (permission prompts, choosers), which degrade rather than crash when
there is none. **A method added to an Activity-scoped channel would be missing from every background
run** — add it here.

| Method | Returns / does | Dart caller |
| :--- | :--- | :--- |
| `nativeLibraryDir` | `applicationInfo.nativeLibraryDir` — where the engine executable was extracted | [`rclone_engine.dart#L113`](../../app/lib/src/rclone/rclone_engine.dart#L113) |
| `externalStorageDir` | `Environment.getExternalStorageDirectory()` — the shared-storage root shown in the browser | [`android_native.dart#L18`](../../app/lib/src/state/android_native.dart#L18) |
| `hasAllFilesAccess` | R+: `Environment.isExternalStorageManager()`; pre-R: the legacy READ permission | [`android_native.dart#L32`](../../app/lib/src/state/android_native.dart#L32) |
| `requestAllFilesAccess` | Opens the per-app All-Files-Access settings screen, falling back to the list screen (both launches guarded — some OEM builds ship neither) | [`android_native.dart#L44`](../../app/lib/src/state/android_native.dart#L44) |
| `openExternal` | Wraps a staged file in a `FileProvider` `content://` URI and fires an `ACTION_VIEW` or `ACTION_SEND` chooser with `FLAG_GRANT_READ_URI_PERMISSION` on **both** the intent and the chooser. Returns error code `not_shareable` when the path is outside every `file_paths.xml` root | [`open_external.dart#L149`](../../app/lib/src/state/open_external.dart#L149) |
| `installerPackage` | The package that installed us (`com.android.vending` for Play, null for a sideload), via `getInstallSourceInfo` on R+ | [`install_source.dart`](../../app/lib/src/state/install_source.dart) |
| `deviceName` | `Settings.Global.DEVICE_NAME` — what the phone calls itself over Bluetooth/Wi-Fi Direct — falling back to make + model. Names the per-device folder a camera-roll backup writes into (`deviceFolderName` in [`task_kind.dart`](../../app/lib/src/state/task_kind.dart)). Off Android `Platform.localHostname` stands in, and any failure yields the placeholder `Android` rather than throwing inside a setup flow | [`photo_backup.dart#L243`](../../app/lib/src/state/photo_backup.dart#L243) (`photoBackupDeviceName()`) |
| `videoThumbnail` | PNG bytes of a keyframe, via `MediaMetadataRetriever` on a single background thread (never the platform thread — decoding blocks). Tries ~10% in, then 1 s, then 0, and prefers the first frame that isn't one flat shade | [`android_native.dart`](../../app/lib/src/state/android_native.dart) → [`thumbnail_service.dart`](../../app/lib/src/state/thumbnail_service.dart) |
| `startTransferService` | Starts **or updates** the `dataSync` foreground service notification (same call does both) | [`android_transfer_service.dart#L55`](../../app/lib/src/state/android_transfer_service.dart#L55) |
| `stopTransferService` | Stops it | [`android_transfer_service.dart#L36`](../../app/lib/src/state/android_transfer_service.dart#L36) |
| `requestNotificationPermission` | Tiramisu+ `POST_NOTIFICATIONS` request | [`android_transfer_service.dart#L50`](../../app/lib/src/state/android_transfer_service.dart#L50) |
| `isTelevision` | Whether this is a TV. Two independent signals, because neither is reliable alone: `UI_MODE_TYPE_TELEVISION` (what the platform reports at runtime, and what emulators set) **or** `FEATURE_LEANBACK` (what Play filters on, and what some manufacturer boxes report instead) | [`android_native.dart#L24`](../../app/lib/src/state/android_native.dart#L24) — called from `initAndroidIsTelevision()` in [`main.dart`](../../app/lib/main.dart) **before `runApp`**, because the shell is chosen inside a synchronous `build()`. A channel failure leaves it `false`, i.e. the touch shell: degraded, not broken |

Native-side notes worth knowing before you touch this file:

- A raw `file://` URI would throw `FileUriExposedException` — `openExternal` **must** go through
  `FileProvider`, authority `${applicationId}.fileprovider`.
- **Android's media stack enforces the cleartext policy — even on loopback.** The engine serves
  object bytes over plain `http://127.0.0.1:<port>`, and `MediaHTTPConnection` (behind
  `MediaMetadataRetriever`) simply refuses to fetch that without an explicit exemption: the
  extractor then fails with `Unable to instantiate an extractor` and every video tile stays empty.
  [`res/xml/network_security_config.xml`](../../app/android/app/src/main/res/xml/network_security_config.xml)
  permits cleartext for `127.0.0.1` and `localhost` **only**; everything else keeps the platform
  default. Dart's own sockets are not subject to this policy, which is why the browser, previews and
  transfers all worked while thumbnails did not.
- The provider's whitelist is deliberately narrow:
  [`res/xml/file_paths.xml`](../../app/android/app/src/main/res/xml/file_paths.xml) exposes the
  staging dir (`<cache-path name="airclone_open" path="airclone_open/" />`) **and** primary shared
  storage (`<external-path name="shared_storage" path="." />`, where a LOCAL remote's files live).
  Nothing in the app's own private storage — `rclone.conf` above all — is reachable, and because the
  provider is `exported=false` only a URI we explicitly mint, for the one file the user picked, is
  ever readable.
  - Shared storage was added in v0.6.2. Without it, "Open in another app" on a local file failed
    with `Failed to find configured root that contains /storage/emulated/0/DCIM/Camera/…` — the
    local-remote path skips staging by design (it must, for a 40 GB video), so the real OS path
    reached `getUriForFile` and matched no root.
  - A path outside **both** roots (an SD card or USB volume) still cannot be minted. Kotlin catches
    that `IllegalArgumentException` and returns `not_shareable`; `handOffToOs` then copies the file
    into the staging dir and retries, so removable volumes work at the cost of one local copy.
- `startForegroundService` is wrapped in a `try/catch`: Android 12+ forbids starting a foreground
  service from the background, so a transfer kicked off while backgrounded runs without the
  keep-alive instead of crashing.

### 3.2 macOS — `SecurityScopedBookmarks.swift`

Only the **sandboxed Mac App Store** build needs these; the DMG runs unsandboxed and can read a path
forever, so `bookmarksRequired` is `Platform.isMacOS && kMacAppStoreBuild` and every function is a
safe no-op elsewhere. Dart side:
[`mac_bookmarks.dart`](../../app/lib/src/state/mac_bookmarks.dart).

| Method | Returns / does |
| :--- | :--- |
| `grantFolder` | Runs the `NSOpenPanel` natively and returns the picked path **plus** base64 bookmark data. It cannot be `file_selector`: that returns a bare `String`, so the `NSURL` carrying the sandbox extension never reaches Dart and the grant dies with the process. |
| `resolveBookmark` | Turns stored bookmark data back into a usable URL, reporting `isStale` — macOS asking for it to be re-created and re-persisted. Still works right now, so it is not an error; ignoring it is how a saved Location quietly stops working after an OS update. |
| `startAccess` · `stopAccess` | Begin / end access. **Must run on the same native `NSURL` instance**, which is why the Swift side caches by bookmark string rather than re-resolving — stopping on an equal-looking URL silently fails to release, and the OS ceiling on simultaneously-held resources is real (low thousands). Grants are therefore held per Location, never per file. |

### 3.3 Android background execution — `airclone/work` + `airclone/work_bg`

Two channels, one round trip: the app enqueues work, then the OS wakes a **second Flutter engine** in
the same process and that engine calls back. See [feat-scheduling.md](../features/feat-scheduling.md)
for what the schedule means; this is only the seam.

| Channel | Method | Does |
| :--- | :--- | :--- |
| `airclone/work` | `registerCallback` | Persists the raw callback handle of `androidWorkEntrypoint` natively — a worker booting a fresh engine has nothing else to go on. The entrypoint must be `@pragma('vm:entry-point')` or AOT tree-shakes it and the handle resolves to nothing. |
| | `enqueuePeriodic` | One `PeriodicWorkRequest` under the unique name `airclone.run-due`, `ExistingPeriodicWorkPolicy.UPDATE` so re-saving a task does not push the next run out by a whole period. Returns the interval actually in force — WorkManager's 15-minute floor is applied natively so Dart reads back the real value. |
| | `cancelPeriodic` · `runOnce` | Cancel by name; enqueue an unconstrained one-shot (`KEEP`, so a double-tap does not queue two). |
| | `status` | Whether a live request exists, its WorkManager state and next run, plus the stamp the last run left (time, headless exit code, summary). Read off the platform thread — the WorkManager database blocks. |
| `airclone/work_bg` | `start` | The worker hands the engine its argv: `--run-due --timeout-minutes N`, the same contract `schtasks` uses. |
| | `log` | One line into logcat under the tag `AircloneWork`. |
| | `done` | Exit code + summary; the worker finishes and destroys the engine. The isolate must **never** call `exit()` — that would end the whole process, foreground Activity included. |

Three things make the worker work at all, each of them a constraint rather than a preference:

- **`airclone/native` is registered on the worker's engine too** — the rclone engine cannot come up
  without `nativeLibraryDir`, and that is the whole reason §3.1's handler is Application-scoped.
- **`setForeground()`, not `startForegroundService`.** Android 12+ forbids starting a foreground
  service from the background, and a worker *is* the background; WorkManager's own promotion is one of
  the sanctioned routes. Promoted, the run is capped at 5 h (inside Android 15's ~6 h/day `dataSync`
  budget); refused, at 8 min, because a plain worker is stopped at ~10. A run cut short is not lost —
  the next wake resumes, since `copy` skips what is already at the destination.
- **It yields to a visible app.** The in-app scheduler ticks every 30 s while an Activity is on screen
  and runs due tasks itself; running here as well would spawn a second rclone engine and race it over
  the same `SharedPreferences`.
  [`AircloneApplication.kt`](../../app/android/app/src/main/kotlin/app/airclone/airclone/AircloneApplication.kt)
  counts started Activities, and the worker simply returns when the count is non-zero.

`airclone/work` is registered by the Activity only
([`MainActivity.kt`](../../app/android/app/src/main/kotlin/app/airclone/airclone/MainActivity.kt)):
enqueueing is something the app does, never something a worker does to itself.

Everything else that crosses into native code does so through a **pub plugin's own** channel
(`path_provider`, `flutter_secure_storage`, `local_auth`, `url_launcher`, `package_info_plus`,
`shared_preferences`, `file_selector`, `mobile_scanner`, `desktop_multi_window`, `media_kit`,
`pdfrx`, `super_drag_and_drop`, `flutter_acrylic`) — not through a channel of Airclone's own.

---

## 4. 📦 Bundled native code

| Artifact | Why it is there | Built / sourced by |
| :--- | :--- | :--- |
| **`rclone` / `rclone.exe`** (desktop, beside the app exe) | The engine `HttpRcloneClient` spawns. Bundling it means first run never downloads. | CI downloads + SHA256-verifies the pinned release and copies it into the Release dir before packaging, so the signing step signs it too ([`release.yml`](../../.github/workflows/release.yml)) |
| **`librclone.dll` / `.so` / `.dylib`** | The in-process engine for `FfiRcloneClient`. Windows/Linux: beside the executable. macOS: `Contents/Frameworks/` — where signed dylibs belong, so the codesign pass covers it and notarization passes. | [`dev/desktop/build-librclone.ps1`](../../dev/desktop/build-librclone.ps1) / [`.sh`](../../dev/desktop/build-librclone.sh), run in an isolated CI job and handed to each platform build as an artifact |
| **rclone-as-jniLib** (Android) | The rclone **executable**, shipped as a per-ABI native library named `librclone.so`. The installer extracts it to `nativeLibraryDir` — the one location Android still permits `exec()` from under W^X (targetSdk 29+). | [`dev/android/build-rclone.ps1`](../../dev/android/build-rclone.ps1) |
| **libmpv** (via `media_kit` + `media_kit_libs_video`) | Video/audio preview everywhere; video thumbnail keyframes on every platform **except Android**, where it decodes into a Surface and its `screenshot` has no CPU-readable frame to return (Android uses `MediaMetadataRetriever` instead — see §3). Linux tarballs expect a system `libmpv`. | pub package |
| **PDFium** (via `pdfrx`) | In-app PDF preview. | pub package |
| **A Rust crate** (via cargokit, for `super_drag_and_drop` / `super_native_extensions`) | Real OS drag payloads in and out. Desktop **and** Android builds therefore need a Rust toolchain on `PATH`. | pub package, compiled at build time |
| **MSVC runtime** (`msvcp140.dll`, `vcruntime140.dll`, `vcruntime140_1.dll`) | App-local so the build is self-contained. Microsoft Store certification failed on 2026-07-29 under policy 10.2.4.1 for the undisclosed dependency, and a clean device cannot start the app without them. CI **hard-gates** on their presence in the artifact. | `windows/CMakeLists.txt` via `InstallRequiredSystemLibraries`, verified in [`release.yml`](../../.github/workflows/release.yml) |

**The rclone version is pinned once**, as `RCLONE_VERSION` in
[`release.yml`](../../.github/workflows/release.yml) — the value bundled on Windows, built into
librclone, and built as the Android jniLib. [`ci.yml`](../../.github/workflows/ci.yml) greps that line
and warns when any of the three build scripts drift from it, or when the pin falls behind the latest
upstream release (rclone ships security fixes in patch releases).

Release/packaging mechanics — signing, notarization, Store submission — belong to
[dev/README.md](../../dev/README.md), not here.

> ⚠️ CI lesson worth repeating: `continue-on-error` on the bundling step masked a missing `rclone.exe`
> for three releases. **Verify by artifact, never by the green check.**

---

## 5. 🖥️ OS integration surfaces

| Surface | Mechanism | Where |
| :--- | :--- | :--- |
| **Mount** (remote as a drive/folder) | `mount/*` + `vfs/refresh` against the spawned `rcd`. Needs a FUSE provider: WinFsp / macFUSE / FUSE3. `mount/types` empty ⇒ not installed. **Off in a Mac App Store build** (§1.2). | [`mount_controller.dart`](../../app/lib/src/state/mount_controller.dart) |
| **Serve** (expose a remote over a protocol) | `serve/*`. Loopback by default; LAN binds all interfaces and forces credentials on auth-capable protocols. **Off in a Mac App Store build** (§1.2). | [`serve_controller.dart`](../../app/lib/src/state/serve_controller.dart) |
| **Drag in / out** | `super_drag_and_drop`. Once any `DropRegion` exists, `super_native_extensions` owns native drops app-wide, so `NativePaneDropRegion` wraps every drop target. | [`native_drag.dart`](../../app/lib/src/ui/native_drag.dart) |
| **Open in another app** | Bytes are **staged**: streamed from `objectRef` into the app cache under `airclone_open/`, written `.part`-first and renamed, pruned on a 12 h TTL. Android → `content://` chooser via the channel; desktop → `file:` URL via `url_launcher`. A `local` remote skips staging entirely. | [`open_external.dart`](../../app/lib/src/state/open_external.dart) |
| **Reveal in file manager** (local files) | Documented OS commands, no plugin: Windows `explorer.exe /select,<path>` (backslashes mandatory; exit code is meaningless so success = "it launched"); macOS `open -R`; Linux `org.freedesktop.FileManager1.ShowItems` over `dbus-send`, falling back to `xdg-open` on the parent dir. Argv is always a list — never a shell string. | [`os_integration.dart`](../../app/lib/src/state/os_integration.dart) |
| **Credential vault** | `flutter_secure_storage` (Windows DPAPI/Credential Manager · macOS Keychain · Linux Secret Service) behind one key, `airclone.configPassword`. **Opt-in, default off**; a vault failure degrades to the manual password gate, never a crash. | [`config_password_vault.dart`](../../app/lib/src/state/config_password_vault.dart) |
| **Biometrics** | `local_auth`. Adds **no** crypto — the OS keystore already holds the password; a successful prompt merely *releases* it instead of showing the typing gate. Never hard-blocks startup. | [`biometric_unlock.dart`](../../app/lib/src/state/biometric_unlock.dart) |
| **Android foreground service** | `dataSync` service declared in the manifest, driven by the channel, holding the app **and its engine child** alive while transfers run. | [`TransferService.kt`](../../app/android/app/src/main/kotlin/app/airclone/airclone/TransferService.kt) |
| **Windows background execution** | `schtasks /Create /XML … /F` registers *this exe's own* `--run-due` / `--run-task` invocation (`/F` doubles as the update on an edited schedule); `/Delete … /F` removes one and `/Query /FO CSV /NH` lists them — there is no "query one folder" form. The definition must be in the Task Scheduler **v1.2 namespace** and is written **UTF-16** to a temp file, because `schtasks /XML` reads a file and not stdin. | [`windows_task_scheduler.dart`](../../app/lib/src/state/windows_task_scheduler.dart) |
| **Android background execution** | One WorkManager periodic request under the unique name `airclone.run-due`, driven over `airclone/work`; the worker boots a second Flutter engine and talks back over `airclone/work_bg` (§3.3). Needs three manifest/Gradle pieces: `android:name=".AircloneApplication"`, a `tools:node="merge"` `foregroundServiceType` on `androidx.work.impl.foreground.SystemForegroundService` (Android 14+ wants the type on *that* service, not only ours), and `androidx.work:work-runtime-ktx`. | [`android_work_channel.dart`](../../app/lib/src/state/android_work_channel.dart) · [`AndroidManifest.xml`](../../app/android/app/src/main/AndroidManifest.xml) |
| **Camera** | `mobile_scanner`, for scanning an Offline-QR config. Permission requested in-flow on first open, never at launch; `uses-feature` declared optional so camera-less devices can still install. | [`AndroidManifest.xml`](../../app/android/app/src/main/AndroidManifest.xml) |
| **Extra desktop windows** | `desktop_multi_window` — pop-out image viewers, each its own `FlutterEngine` in the same process. Desktop only; every call is `Platform`-guarded. | [`popout_image_app.dart`](../../app/lib/src/ui/popout_image_app.dart) |
| **Update channel** | Detects how this copy was installed and routes "Check for updates" to the owning store — MSIX via `GetCurrentPackageFullName`/`…FamilyName`, Android via `installerPackage`, macOS via a `_MASReceipt` in the bundle, Linux via `FLATPAK_ID`/`SNAP`. See §5.1. | [`install_source.dart`](../../app/lib/src/state/install_source.dart) |

Both background-execution rows land on the **same** Dart entrypoint —
[`headless_runner.dart`](../../app/lib/src/headless/headless_runner.dart), which boots the engine, runs
the due tasks with no UI, and exits 0 / 1 / 2. The flag strings and those exit codes are the contract
the OS registrations depend on. On Windows,
[`windows/runner/main.cpp`](../../app/windows/runner/main.cpp) mirrors the Dart-side
`isHeadlessInvocation` scan so a background run never spawns a console window. The app window is still
created — its message loop is what services the platform-channel replies the headless isolate awaits —
but is never `Show()`n, because the entrypoint returns before `runApp` and no first frame is ever
produced, and the frame callback is what would have shown it. A headless run spawns its
**own** `rcd` on its own free loopback port, so it coexists with a running GUI instance — at the cost of
a known last-writer-wins race on the `SharedPreferences` run stamps.

### 5.1 Update channel — a store install must never see a download link

Airclone ships the *same binary* through several channels, so nothing at compile time tells a Store
MSIX from the Inno installer, or a Play install from a sideloaded APK.
[`install_source.dart`](../../app/lib/src/state/install_source.dart) resolves it at runtime, and
[`app_info.dart`](../../app/lib/src/state/app_info.dart) branches on the answer:

- **store-managed** → `StoreManagedUpdates`. **No GitHub request is made at all**, and the only
  affordance offered is the store's own page.
- **direct download** → `ReleaseUpdateInfo`. The GitHub release check runs exactly as before, which
  is what an installer/zip/dmg/tarball/sideload user installed the app for.

`UpdateStatus` is a **sealed** class so the settings switch is exhaustive: a build cannot silently
fall through to rendering "Open release".

> ⚠️ This is a certification requirement, not a preference. **Microsoft Store policy 10.2.5**
> ("Installing and Updating Store Apps") failed Airclone **v0.6.0** on 2026-08-10 for exactly this:
> "Check for updates" offered an **Open release** button that led to the GitHub releases page.
> Google Play and the App Store enforce the same rule. Never add an out-of-store download link
> behind a code path a store build can reach.

### Three features have no RC method and run as real subprocesses

They re-exec the rclone **binary**, so they are unavailable in in-process mode:

| Feature | Why no RC | Where |
| :--- | :--- | :--- |
| Archive create / extract / list | `rclone archive` has no RC method | [`archive_service.dart`](../../app/lib/src/state/archive_service.dart) |
| Config encryption set / remove / change | Interactive password prompts on stdin; run with the engine quiesced so nothing races the atomic rewrite | [`config_transfer_controller.dart`](../../app/lib/src/state/config_transfer_controller.dart) |
| Console commands (HTTP engine) | `core/command` re-execs a fresh rclone; on the in-process engine the console falls back to the RC translator instead | [`http_rclone_client.dart`](../../app/lib/src/rclone/http_rclone_client.dart) |

Every one of these adopts its child into `WindowsChildJob` so no rclone process can outlive the app
and hold `rclone.exe` open in the install directory (a clean-uninstall requirement).

---

## 6. ⚠️ Gotchas

RC-API traps that have actually cost this project time. Check this table before debugging a new RC call.

| Trap | What happens | The rule |
| :--- | :--- | :--- |
| **`parameters` is mandatory on `config/create` / `config/update` — including `continue` steps** | HTTP 400 `Didn't find key "parameters" in input`. Answering *any* provider question failed. Cost a Microsoft Store certification cycle. | Always send the key; send it **empty** on a continue step — the opening call already persisted the values, and re-sending them without `obscure` would write a password back in the clear. [`add_remote_controller.dart#L232`](../../app/lib/src/state/add_remote_controller.dart#L232) |
| **`config/create` on an existing name REPLACES it** | Exit 0, no warning, nothing in the response to distinguish it from a create. On a `crypt` remote that is data loss with no error: the files stay put, the new key cannot decrypt their names, rclone skips them, and the pane renders "Empty folder". A real user hit exactly this. | Every caller reads `existingRemoteNames(client)` from [`remotes_provider.dart`](../../app/lib/src/state/remotes_provider.dart) first and **fails closed** when the config cannot be read — an unreadable config is not a free name. Import's Replace mode is the one path that may overwrite, and only as an explicit per-import choice. |
| **`vfs/refresh` param typing** | The handler hard-asserts string params and rejects a JSON bool; a present-but-empty `fs` is looked up literally (`no VFS found with name ''`). | `recursive` must be the **string** `'true'`; omit `fs` entirely rather than passing `''`. [`mount_controller.dart#L100`](../../app/lib/src/state/mount_controller.dart#L100) |
| **`core/stats` group keying** | Local job ids start at 0 and rclone jobids at 1, so a jobid-keyed group never matches and progress silently reads zero. | Scope per-job stats by the `_group` you dispatched with (`airclone/<local job id>`), never the rclone `jobid`. `job/status` correctly takes the jobid. [`jobs_controller.dart#L235`](../../app/lib/src/state/jobs_controller.dart#L235) |
| **`core/command` needs the live response writer** | With `_async` it returns a jobid but the writer dies, so output vanishes. librclone rejects it outright (a `NeedsRequest` method). | HTTP engine only, plain synchronous streamed request, `returnType: STREAM`, **no** rpc timeout. Cancelling the stream subscription closes the request, which kills the child — that is the console's Stop. In-process mode uses the fail-closed argv→RC translator instead. |
| **`operations/uploadfile` needs multipart HTTP** | Unusable from both clients. | Upload through the `local` backend: `sync/copy` for directories, `operations/copyfile` for a file. |
| **`config/get` hangs on a locked encrypted config**, and `--ask-password=false` crashes rclone | The RC server freezes on stdin before you can ask it anything. | Detect encryption **out-of-band** by reading the config file header for `Encrypted rclone configuration File`, then gate startup on the password. [`rclone_engine.dart#L138`](../../app/lib/src/rclone/rclone_engine.dart#L138) |
| **No `core/restart`** | Only `core/quit` exists. | `restart()` is a first-class client op: quit + start (subprocess), Finalize + Initialize (in-process). |
| **`operations/stat` reports "not found" as a 2xx with `item: null`** | A null check that assumes an exception silently treats a deleted file as an error-free empty result. | Test `item is! Map` explicitly. [`checksum_dialog.dart#L29`](../../app/lib/src/ui/checksum_dialog.dart#L29) |
| **User engine flags can shadow the rc security flags** | pflag lets the *last* occurrence of a repeated flag win. | Put user `extraArgs` **first** in the `rcd` argv so `--rc-addr`/`--rc-user`/`--rc-pass` always override. [`http_rclone_client.dart#L259`](../../app/lib/src/rclone/http_rclone_client.dart#L259) |
| **Re-exec'd children do not inherit `--config`** | `core/command` and the archive subprocess spawn a *fresh* rclone. It inherits the environment but not the flag, and rclone treats a config it cannot open as an **empty** one — silently — so every remote answers `didn't find section in config file` while the sidebar, served by the parent, still lists them. On Android it resolves an empty `$HOME/.config/rclone/rclone.conf`; on desktop any divergence in default resolution does the same. | Two layers. Android also passes `RCLONE_CONFIG` in the engine's `extraEnv` (precedence is flag > env > default, so the parent is unaffected) [`engine_controller.dart#L224`](../../app/lib/src/state/engine_controller.dart#L224); and every console dispatch pins the engine's own path onto the child argv via `withConfigArg` + `HttpRcloneClient.engineConfigPath()` (the spawn override, else `config/paths`) — a `--config` the **user** typed still wins. [`console_command.dart`](../../app/lib/src/state/console/console_command.dart) |
| **`core/transferred` is a capped ring, not a log** | ~100 entries per group, in completion order, not configurable. A 300-file dry run returns 104 entries — all `what: "deleting"`, with the transfers evicted. Querying an unknown group also CREATES it, and the group filter is exact-match, not prefix. | Never build a "what changed" list on it. `operations/check` is uncapped and sorted, and its `missingOnSrc` is exactly what a sync would delete; async, `job/status.output` carries the whole result object (a `sync/sync` job's `output` is always `{}`). [`sync_preview.dart`](../../app/lib/src/state/sync_preview.dart) |
| **A `crypt` remote with the wrong key returns a SHORT listing, not an error** | `operations/list` answers 200 with the entries whose names decrypted and silently omits the rest; six directories arrive as `{"list":[]}` and the pane renders a confident "Empty folder". The only evidence is rclone's `NOTICE: …: Skipping undecryptable file name:` — or `… dir name:`, which is the spelling behind the *wholly* empty pane, since rclone words objects and directories separately — on the engine's own log. | The stdout/stderr drain counts both spellings ([`undecryptable_names.dart`](../../app/lib/src/state/undecryptable_names.dart)) and `BrowserController._load` samples the counter either side of its request, so a short listing says "N items hidden". Two limits: it rides on the log drain, so it is **`HttpRcloneClient` only** — the in-process engine emits no such stream — and only `_load` samples it, not a tree-view expansion (§2). |
| **A dropped keep-alive socket looks like a failed call** | `ClientException: Connection closed before full header was received` — the socket died before the response started, so the request most likely never ran. On the 1 Hz stats poll it self-heals; on a call the *user* made it surfaces as a failed listing or a failed copy. | `sendWithConnectionRetry` retries exactly once, gated on `isRetryableRcMethod`'s read-only allowlist; a `TimeoutException` is never retried (the engine took that request and is already struggling). **Adding a mutating method to `_readOnlyRcMethods` is a data-loss bug** — a doubled `operations/copyfile` is far worse than an error the caller can see. Both are pure top-level functions, so the rule is unit-testable on its own. [`http_rclone_client.dart#L92`](../../app/lib/src/rclone/http_rclone_client.dart#L92) |
| **`--rc-job-expire-duration 24h`** | An expired job's `job/status` no longer carries its `output`. | Treat a settle-time `job/status` read as best-effort; the terminal summary must not depend on it. |
| **Windows env vars and Go** | A CRT `_putenv` only touches the calling CRT's snapshot, which Go never reads — so `RCLONE_CONFIG_PASS` silently would not reach librclone. | Set it via kernel32 `SetEnvironmentVariableW` (POSIX: libc `setenv`/`unsetenv`), before `RcloneInitialize`, then clear it. [`librclone_ffi.dart#L354`](../../app/lib/src/rclone/librclone_ffi.dart#L354) |
| **`RcloneRPC` blocks** | Called inline it freezes the UI isolate; and `DynamicLibrary`/`Pointer` are not sendable across isolates. | All FFI stays inside the single worker isolate; the main isolate only exchanges plain messages. |
| **Revoking a public link is not a separate method** | There is no `operations/unlink`. | `operations/publiclink` with `unlink: true`. |

Reliability invariants that constrain *how often* you may call these methods — the single shared
poller, transfer concurrency, thumbnail budgets, the listing-race guard — live in
[14-performance-standards.md](14-performance-standards.md).

---

## Related

- [08-core-architecture.md](08-core-architecture.md) — **why** there is one `RcloneClient` seam and two implementations; the layered architecture; mount vs in-app explorer.
- [07-state-context.md](07-state-context.md) — the Riverpod providers and controllers that own the RC calls tabulated above.
- [14-performance-standards.md](14-performance-standards.md) — concurrency budgets, the one shared poller, and the reliability invariants around these calls.
- [11-validation-standards.md](11-validation-standards.md) — how `RcloneException` and provider-form input are validated and surfaced to the user.
- [15-security.md](15-security.md) — rc credentials, config encryption, the credential vault, and the serve/mount exposure policy.
- [16-glossary-of-terms.md](16-glossary-of-terms.md) — remote, backend, fs, mount, bisync, VFS.
- [dev/README.md](../../dev/README.md) — building, signing, and releasing the native bits described in §4.
- [00-system-index.md](00-system-index.md) — the master router.
