---
type: "core"
name: "Performance & Reliability Standards"
status: "stable"
dependencies: ["08-core-architecture", "07-state-context", "10-external-integrations"]
description: "The concurrency budgets, content-read guards, and lifecycle invariants that broke real releases when violated — each with the failure it prevents and how to check you have not broken it."
---

# ⚡ Performance & Reliability Standards

The load-bearing performance and reliability invariants in Airclone: what they are, which incident
produced them, where they are enforced in code, and how to verify a change still honours them.

**When to read this:** before you add or change anything that reads a file's bytes, spawns a
process, drives libmpv, fetches thumbnails, mutates browser-pane listing state, or replaces the
rclone binary. Also read it when a review flags "this could hang / download too much / show the
wrong folder".

> ### 🛑 If you are adding a feature that reads file CONTENT, read this first
>
> "Content" means anything that fetches a file's **bytes** — thumbnails, previews, checksums,
> content-hash scans, media playback, uploads of a local file. Listing and stat are free; content is
> not. Before the first byte is fetched you must:
>
> 1. Call `wouldHydrateOnRead(remote, pathWithinRemote)` and skip the file when it returns true —
>    see [§1](#1-content-reads-the-cloud-hydration-guard). A missed call silently downloads
>    multi-GB cloud placeholders.
> 2. Bound the size (§1.2) and the concurrency (§2) — no unbounded `Future.wait` over a folder.
> 3. Make the failure observable (§4) — an unobserved async failure reads to the user as a hang.
>
> New content-read call sites must be added to the guard list in §1.1.

---

## 1. Content reads: the cloud-hydration guard

On Windows (Cloud Files API — Proton Drive, OneDrive, iCloud, Dropbox, Google Drive) a synced file
can be an online-only **placeholder**: listing and stat are free, reading its content forces the OS
to download the whole file. Airclone browses local paths that may sit inside such a sync root.

### 1.1 Consult the guard before touching bytes

**RULE — Never read a file's content without first calling `wouldHydrateOnRead(remote, pathWithinRemote)`; treat a `true` result as "skip this file" or "ask the user first".**

- **Why:** a thumbnail grid, a checksum dialog or a dedupe scan over a sync root would otherwise
  trigger unexpected multi-GB downloads with no user action and no visible cause.
- **Enforced in:** [cloud_placeholder.dart](../../app/lib/src/state/cloud_placeholder.dart) —
  `localAbsolutePath()` resolves the entry to an absolute path (null for any non-`local` backend),
  then `isOnlineOnlyPlaceholder()` probes `GetFileAttributesW` for
  `FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS | RECALL_ON_OPEN | OFFLINE`.
- **Check:** the guard is deliberately **fail-open** — Windows-only, and it returns `false` on any
  error, on other platforms, and for an unresolvable path. A false positive costs one thumbnail; a
  false negative costs a silent multi-GB download, so it acts only on a definitive yes. Do not
  "improve" it into a fail-closed check. Behaviour is covered by
  [cloud_placeholder_test.dart](../../app/test/cloud_placeholder_test.dart).

**The complete consult list today.** Adding a content-read path means adding a row here and a call
there:

| # | Call site | What it does on a hit |
| :--- | :--- | :--- |
| 1 | `buildThumbRequest` — [browser_pane.dart:75](../../app/lib/src/ui/browser_pane.dart) | Returns null; the tile shows the kind icon. |
| 2 | Folder cover composition — [folder_thumbnail.dart:75](../../app/lib/src/ui/folder_thumbnail.dart) | Filters the file out (a cover would hydrate up to 4 files *per folder*). |
| 3 | Inspector preview box — [inspector_panel.dart:256](../../app/lib/src/ui/inspector_panel.dart) | Falls back to the kind icon. |
| 4 | Checksum dialog — [checksum_dialog.dart:102](../../app/lib/src/ui/checksum_dialog.dart) | Sets `_needsConsent` in `initState` instead of fetching on open. |
| 5 | Dedupe scan — [dedupe_dialog.dart:103](../../app/lib/src/ui/dedupe_dialog.dart) | Metadata-only recursive list first, then a consent dialog naming file count + total bytes before the content-hash pass. |

**RULE — For a BULK content read, probe with a metadata-only listing first, then ask for consent with the count and total size.**

- **Why:** a per-file skip is right for a thumbnail (silent, cheap fallback) but wrong for a scan the
  user explicitly started — silently skipping half the folder produces wrong dedupe results.
- **Enforced in:** [dedupe_dialog.dart](../../app/lib/src/ui/dedupe_dialog.dart) — a
  `showHash: false` list (never hydrates) counts online-only files and bytes, then `_confirmHydrate`
  gates the `showHash: true` pass.
- **Check:** the probe list must not set `showHash`; cancelling must leave the status text saying
  nothing was downloaded.

### 1.2 Bound image originals by size

**RULE — Cap IMAGE originals fetched for a thumbnail at `kMaxPreviewImageBytes` (128 MiB); do not size-gate videos.**

- **Why:** a cross-platform net for absurd originals on backends where the placeholder probe does not
  apply. Videos stream a keyframe rather than a full read, so they rely on the placeholder check
  instead — size-gating them would drop legitimate previews.
- **Enforced in:** [file_icon.dart:143](../../app/lib/src/ui/file_icon.dart) (the constant),
  [browser_pane.dart:78](../../app/lib/src/ui/browser_pane.dart),
  [folder_thumbnail.dart:74](../../app/lib/src/ui/folder_thumbnail.dart).

**RULE — Build thumbnail requests through `buildThumbRequest`, not by constructing a `ThumbRequest` inline.**

- **Why:** the helper is the single place that applies *both* the placeholder guard and the size cap,
  and it derives the identical URL + cache key used by the per-tile builder and the whole-folder
  pre-warm — divergence there silently doubles the cache.
- **Enforced in:** [browser_pane.dart](../../app/lib/src/ui/browser_pane.dart) — list, grid and
  gallery tiles all funnel through `thumbReqFor` → `buildThumbRequest`.
- **Known gap:** `_preview` in [inspector_panel.dart](../../app/lib/src/ui/inspector_panel.dart)
  builds its own `ThumbRequest` (size 512). It checks the placeholder guard, `thumbnailsOn`,
  `isThumbnailable` and a non-null client, but has **no** `kMaxPreviewImageBytes` check. Route it
  through the helper if you touch that code.

---

## 2. Thumbnail concurrency and caching

Budgets live in [thumbnail_service.dart](../../app/lib/src/state/thumbnail_service.dart):

| Budget | Value | Applies to |
| :--- | :--- | :--- |
| `_maxConcurrent` | 4 | General gate — images **and** videos |
| `_maxConcurrentVideo` | iOS 1 / Android 2 / desktop 2 | Video keyframe captures only |
| `_videoFirstFrameTimeout` | mobile 30 s / desktop 12 s | `waitUntilFirstFrameRendered` (libmpv) — and the whole native call on Android |
| `screenshot()` timeout | 6 s | Keyframe grab after the first frame |
| Image HTTP GET timeout | 20 s | `_fetchAndDecodeImage` |
| Pre-warm batch | 16 | [thumbnail_reload.dart](../../app/lib/src/state/thumbnail_reload.dart) `_batch` |
| Tile retry | 4 attempts, backoff 400 ms / 1.2 s / 3 s (last repeats) | [thumbnail_image.dart](../../app/lib/src/ui/thumbnail_image.dart) |

`_isMobile` is `Platform.isAndroid || Platform.isIOS`.

### 2.1 Two gates, video first

**RULE — A video capture acquires the VIDEO gate before the general gate and releases in mirror order; images never take the video gate.**

- **Why:** each video keyframe spins a whole libmpv `Player` that streams and decodes real media.
  Several at once starve the player the user is actually watching — the recorded cause of unreliable
  cloud video previews on Android. The fixed ordering (plus images never taking the video gate) is
  what makes the two-gate scheme deadlock-free.
- **Enforced in:** `_generateAndCache` in
  [thumbnail_service.dart](../../app/lib/src/state/thumbnail_service.dart) —
  `if (req.isVideo) await _acquireVideo(); await _acquire();` with `_release(); if (req.isVideo)
  _releaseVideo();` inside a `finally`.
- **Check:** any new acquire must keep video-before-general, and every release must sit in a
  `finally` (a throw between the two gates otherwise leaks a permit and wedges all thumbnails).

### 2.2 Do not collapse the mobile/desktop split

**RULE — Keep the platform-split video budgets (`_maxConcurrentVideo`, `_videoFirstFrameTimeout`) as separate mobile/desktop values.**

- **Why:** on a phone the bytes come from a cloud backend over a phone connection, and a capture that
  times out costs the same work again on the next scroll — so mobile gets a *longer* budget and
  *fewer* parallel captures, not the same numbers as desktop.
- **Exception, and why it is one:** Android allows 2 concurrent captures because it does not use
  libmpv for them (see §2.2.1) — the starvation the mobile cap exists to prevent is a libmpv
  `Player` competing with the player the user is watching, and there is no such `Player` here.
- **Check:** a single hardcoded constant for either value is a regression, regardless of which value
  it is.

### 2.2.1 Android captures keyframes natively, not with libmpv

**RULE — On Android, a video thumbnail comes from the `videoThumbnail` platform channel (`MediaMetadataRetriever`); libmpv is used everywhere else.**

- **Why:** libmpv on Android decodes into a Surface, so its `screenshot` command has no CPU-readable
  frame to hand back — captures returned nothing (or, on the emulator, a black frame that got cached
  and looked permanently broken). The platform grabber decodes straight to a Bitmap, applies the
  track's rotation, and costs ~0.2–2 s per file instead of spinning a whole player.
- **Also required:** the engine's object URL is cleartext loopback, which Android's media stack
  refuses without `network_security_config.xml` — see
  [external integrations §3](10-external-integrations.md#3--platform-channels). Without that
  exemption the capture fails silently, no exception reaches Dart, and the tile just stays empty.
- **Enforced in:** `_captureVideoFrame` in
  [thumbnail_service.dart](../../app/lib/src/state/thumbnail_service.dart) dispatches on
  `Platform.isAndroid`.
- **Check:** verifying this on the **emulator** is only meaningful for the native path. The emulator
  cannot render video through libmpv at all (`eglCreateContext` → `EGL_BAD_ATTRIBUTE`), so a libmpv
  capture there proves nothing.

### 2.2.2 A frame with no picture in it is not a thumbnail

**RULE — A capture whose pixels are all one shade (`isFlatRgba`) is treated as a failure: never returned, never cached.**

- **Why:** a black rectangle in the grid is indistinguishable from a broken app, and once written to
  the encrypted disk cache it stays that way until a forced rebuild. Videos legitimately open on
  black (fade-in, slate, camera warm-up), and a failed decode produces a flat frame too.
- **Enforced in:** `isFlatRgba` (pure, unit-tested in
  [video_thumbnail_blank_test.dart](../../app/test/video_thumbnail_blank_test.dart)); the libmpv path
  seeks ~10% in and grabs once more before giving up, and the Android side picks between candidate
  timestamps with the same threshold in `MainActivity.kt`.
- **Check:** the test is *uniformity*, not darkness — a night shot with detail must survive. Keep the
  Kotlin and Dart thresholds (`kBlankLumaRange` / `BLANK_LUMA_RANGE`, 12) in step.

### 2.3 A fetch that decodes to nothing is permanent

**RULE — When bytes download fine but will not decode, record the cache key in `_undecodable`; only a forced rebuild clears it.**

- **Why:** without it the 4-attempt retry loop and every scroll re-mount re-download a multi-MB
  original that will never render (e.g. HEIC/SVG that pass `isThumbnailable` but Flutter's image
  codec rejects). This is a permanent failure, not a transient one.
- **Enforced in:** `_fetchAndDecodeImage` sets it when `_downscale` returns null; `_captureVideoFrame`
  sets it when the captured frame has no picture in it (§2.2.2); `load()` checks it first and
  `force: true` removes it.
- **Check:** the mark means "we got the bytes and there is nothing to show". A video capture that
  *fails* — a timeout, a dead engine, a slow remote — must stay retryable and must not be marked.
  Keep it session-scoped (an in-memory `Set`); persisting it would strand files a codec update later
  fixes.

### 2.4 Dedup in flight; key the cache on identity + size

**RULE — Share one future per `cacheKey` while a generation is in flight, and remove the entry in a `finally`.**

- **Why:** a grid scroll fires many identical requests; without dedup each one re-downloads.
- **Enforced in:** `_inFlight` in
  [thumbnail_service.dart](../../app/lib/src/state/thumbnail_service.dart).
- **Check:** the key is `sha1('fs|path|modTime|size|px')` (`thumbCacheKey`), so any change to
  mod-time or size invalidates the cached thumb automatically — do not drop components from it.
  Cache blobs are AES-GCM sealed via `CacheCrypto`; with `cacheMemoryOnlyProvider` on, both the
  cache read and the cache write are skipped and nothing touches disk.

### 2.5 Pre-warm in bounded batches

**RULE — Warm a folder's thumbnails in batches of `_batch` (16); never a single `Future.wait` over the whole listing.**

- **Why:** two independent failure modes. (a) A whole-folder `Future.wait` pins every decoded
  thumbnail in RAM simultaneously — the results are unused here, only the disk-cache side effect is
  wanted — risking an OOM on a large photo folder. (b) The service's semaphore gates *generation*,
  not cache reads/decrypts, so an unbounded fan-out escapes the gate entirely.
- **Enforced in:** `prewarm` in
  [thumbnail_reload.dart](../../app/lib/src/state/thumbnail_reload.dart).
- **Check:** batching must `await` each batch before starting the next, so each thumbnail's bytes are
  freed as it completes.

### 2.6 The reload signal carries an epoch, nothing else

**RULE — `ThumbnailReloadSignal` carries only `tick` + `force`; tiles `ref.listen` it, never `ref.watch`.**

- **Why:** a per-completion progress counter on this provider would fan thousands of no-op
  notifications across every mounted tile. Reload epochs are rare, and listening avoids rebuilding
  every tile on unrelated notifier churn.
- **Enforced in:** [thumbnail_reload.dart](../../app/lib/src/state/thumbnail_reload.dart) and
  [thumbnail_image.dart](../../app/lib/src/ui/thumbnail_image.dart).
- **Check:** `reload()` is soft (re-attempts only tiles still showing a placeholder); `rebuild()`
  sets `force` (bypass **and** overwrite the disk cache). Covered by
  [thumbnail_reload_test.dart](../../app/test/thumbnail_reload_test.dart).

### 2.7 Guard every async write-back

**RULE — Before any `setState` after an await in a recycled widget, check both `mounted` and a generation token captured at the start of the attempt.**

- **Why:** grid/gallery tiles are recycled onto different files, and a reload can supersede an
  in-flight attempt. Without the token a stale fetch writes the *wrong image* into a tile that has
  moved on.
- **Enforced in:** `_ThumbnailImageState._start` bumps `_gen` and returns early whenever
  `!mounted || gen != _gen` — including after the backoff delay. `didUpdateWidget` drops stale bytes
  and refetches when the recycled tile's `cacheKey` changes.
- **Check:** each `await` in such a method must be followed by the guard, not just the first one.

---

## 3. The browser listing race

Pane operations build paths as `state.path + entry`, so a **stale entry list produces preview 404s
and copy "object not found"**. That is the downstream bug this section exists to prevent.

### 3.1 Navigation clears; refresh does not

**RULE — `_navigate` clears `entries` (and selection + filter) as it starts loading; `refresh()` deliberately keeps the current list on screen.**

- **Why:** clearing on navigate means the pane shows a spinner rather than the *previous* folder's
  list while the new listing lands. Not clearing on refresh means a same-folder reload (including
  pull-to-refresh) does not blank the content.
- **Enforced in:** `_navigate` / `refresh` in
  [browser_controller.dart](../../app/lib/src/state/browser_controller.dart).

### 3.2 Bail on superseded responses

**RULE — Snapshot `remote` + `path` before the RPC, and after EVERY await re-check them and commit nothing if navigation moved on.**

- **Why:** loads overlap — fast folder clicks, pull-to-refresh, the jobs-done auto-refresh, and slow
  cloud lists racing thumbnail traffic on the one engine. Whichever RPC returns last would otherwise
  win, clobbering the current folder with a stale or empty response and flashing "Empty folder".
- **Enforced in:** `_load` in
  [browser_controller.dart](../../app/lib/src/state/browser_controller.dart) —
  `bool superseded() => state.remote != remote || state.path != path;`, checked on **both** the
  success and the catch path.
- **Check:** a new early-return or a new await inside `_load` needs its own `superseded()` check. The
  catch path matters as much as the success path — a stale error would also clobber the pane.

### 3.3 Gate the full-screen spinner on "nothing to show"

**RULE — Derive `initialLoad = state.loading && state.visibleEntries.isEmpty` and gate the full-screen spinner on that, never on raw `loading`.**

- **Why:** gating on `loading` blanks the listing during a pull-to-refresh, which unmounts the
  `RefreshIndicator`'s own inline spinner mid-gesture.
- **Enforced in:** [browser_pane.dart](../../app/lib/src/ui/browser_pane.dart) — the same flag also
  decides the wrap: `isTouchPrimary && !initialLoad ? RefreshIndicator(...) : content`.

---

## 4. Async media failures must be surfaced

libmpv reports almost nothing by throwing. Anything unobserved reaches the user as a black rectangle
that never plays — indistinguishable from a hang. Nearly all of
[media_preview.dart](../../app/lib/src/ui/media_preview.dart) exists for this.

**RULE — Always `await` `Player.open` inside try/catch; never fire it unawaited.**

- **Why:** `open()` rejects **asynchronously**, so a bare call leaves the failure unobserved.
- **Check:** grep for an unawaited `player.open(` in any new media path.

**RULE — For video, the success signal is a rendered FRAME (`waitUntilFirstFrameRendered`); only for audio is `stream.playing` the signal.**

- **Why:** libmpv reports playing while its video output never comes up — the Android emulator does
  exactly this (`eglCreateContext` fails with `EGL_BAD_ATTRIBUTE` and every frame is dropped).
  Trusting `playing` there cancels the watchdog and hands the user the black rectangle.
- **Check:** the buffering listener sets `_loading = buffering || !_started`. The `|| !_started` is
  load-bearing: libmpv stops "buffering" as soon as it has demuxed enough, well before — and
  sometimes instead of — a frame reaching the screen.

**RULE — Arm a start watchdog (`_startTimeout`, 45 s) that fires only when `mounted && _error == null && !_started`, and stop treating `PlayerStream.error` as fatal once `_started` is set.**

- **Why:** the watchdog exists to kill the *infinite* black screen, not to be strict — cloud objects
  come through the local engine and can genuinely take a while. After playback is up, libmpv also
  reports non-fatal problems on the error stream; tearing a playing video down for one would be a
  worse bug than the one this class fixes.
- **Check:** all four observation paths (awaited `open()`, `stream.error`, `stream.buffering`, the
  watchdog) must land on the same error card, which always offers Retry and — when the host supplies
  `onOpenExternally` — a hand-off to another app.

**RULE — Increment `_generation` in `_teardown()` before disposing, and ignore any callback whose token is stale; `_retry()` awaits `_teardown()` before `_start()`.**

- **Why:** a `waitUntilFirstFrameRendered` future that resolves *after* Retry swapped the player out
  would otherwise clear the NEW attempt's loading/watchdog state. Awaiting teardown also guarantees
  two libmpv instances never overlap.
- **Check:** the first-frame `.catchError((_) {})` is swallowed on purpose — the watchdog is what
  surfaces a frame that never arrives. Do not "fix" it into an error path.

**RULE — Repeat is libmpv's playlist mode (`PlaylistMode.single`), applied AFTER `open()` and re-applied when the preference changes mid-playback.**

- **Why:** the preview opens exactly one `Media`, so `single` (loop the current file) is the mode that
  matches the button; `loop` would mean the same thing today and something different the moment a
  playlist exists. Applying it after `open()` keeps it off the path that decides whether playback
  starts — a failure to set repeat must never be able to fail a file.
- **Enforced in:** `_applyRepeat` in
  [media_preview.dart](../../app/lib/src/ui/media_preview.dart), called once after `open()` and again
  from a `ref.listen` on [`repeatPlaybackProvider`](../../app/lib/src/state/media_prefs.dart).
- **Check:** the call is unawaited-with-`catchError` on purpose. Toggling must affect the *playing*
  file, not just the next one — verify by watching `stream.position` wrap instead of
  `stream.completed` firing.

Off-screen thumbnail players obey the same reasoning from the other direction — see §2.1.

---

## 5. Engine binary lifecycle: stage, then swap

**RULE — Download and SHA-256-verify into a `.new` STAGING file BEFORE stopping anything; only then quit the engine, swap, and restart.**

- **Why:** on Windows the running engine holds its own executable open, so an in-place write fails
  with "used by another process" — exactly what made in-app engine update *always* fail once an
  engine had been downloaded. Staging first also means a failed download costs nothing: the working
  engine is still up and untouched.
- **Enforced in:** `downloadLatestToStaging()` in
  [rclone_engine.dart](../../app/lib/src/rclone/rclone_engine.dart) writes
  `rclone.exe.new` / `rclone.new` beside the managed engine and never touches the managed path;
  `EngineController.updateEngine` in
  [engine_controller.dart](../../app/lib/src/state/engine_controller.dart) sequences
  stage → `quit()` → `installStaged` → restart.

**RULE — Keep the previous binary as `<managed>.old`, roll it back and restart if the new engine will not come up, and only then discard it.**

- **Why:** a bad rclone release must not leave Airclone permanently broken. A failed *swap* likewise
  restarts the old engine rather than leaving the user with nothing running.
- **Enforced in:** `swapEngineBinary` / `restoreEngineBackup` / `discardEngineBackup` in
  [rclone_engine.dart](../../app/lib/src/rclone/rclone_engine.dart); the post-update
  `state.isReady` check in `updateEngine` triggers `rollbackEngine()` + restart and rethrows, so
  Settings cannot report "Engine updated." while the engine is down.
- **Check:** [engine_binary_swap_test.dart](../../app/test/engine_binary_swap_test.dart) covers
  install, stale `.old` replacement, a missing staged file, rollback, and swap-then-rollback
  round-tripping to the original bytes.

**RULE — Verification is fail-closed: no checksum, no install.**

- **Why:** an engine we cannot verify is a supply-chain hole. Any failure to fetch *or* parse the
  official `SHA256SUMS`, a missing entry for the zip, or a mismatch throws with an actionable
  message instead of trusting the bytes.
- **Related gates in the same method:** Android has no downloadable engine (it must ship in the APK),
  and the packaged Microsoft Store build refuses to download executable code — the signal is
  `isStoreManaged()`, not the presence of a bundled binary. See
  [dev/README.md](../../dev/README.md) for the packaging side.

---

## 6. Spawned-process lifetime

**RULE — Every `Process.start` of rclone must be followed by `WindowsChildJob.adopt(proc.pid)`.**

- **Why:** Windows does not kill child processes when their parent dies. A disorderly exit (crash,
  Task Manager "End task", a killed debug session) leaves the daemon running forever — and the orphan
  holds an open handle on `rclone.exe` **inside the install directory**, so the uninstaller cannot
  delete it. **Microsoft Store certification failed the product for exactly this on 2026-07-29
  (policy 10.2.7, clean removal).**
- **Enforced in:** [windows_child_job.dart](../../app/lib/src/rclone/windows_child_job.dart) — one
  process-wide unnamed Job Object with `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`, whose handle is held
  open for the process lifetime on purpose. Current call sites:
  [http_rclone_client.dart:149](../../app/lib/src/rclone/http_rclone_client.dart),
  [archive_service.dart](../../app/lib/src/state/archive_service.dart) (two),
  [config_transfer_controller.dart](../../app/lib/src/state/config_transfer_controller.dart) (two).
- **Check:** `grep -rn "Process.start" app/lib` — every rclone spawn should have an `adopt` within a
  few lines. The class is best-effort by design (every failure swallowed and latched), so callers
  must never branch on the result.

**RULE — Keep the PID-marker reap as the second line of defence, and keep it single-PID.**

- **Why:** the Job Object only helps a process that is still alive to hold it; the marker lets the
  *next* launch kill a leftover from a force-killed prior run. It records only the one PID we
  spawned — never a broad process-name match, which would kill the user's own rclone processes.
- **Enforced in:** `_markerFile` / `_reapPreviousRcd` in
  [http_rclone_client.dart](../../app/lib/src/rclone/http_rclone_client.dart), called at the top of
  `start()`. Skipped on Android, where `systemTemp` is not app-writable and the OS kills the process
  group anyway.

**RULE — Use `Process.start` (not `Process.run`) wherever a timeout must be able to kill the child, and cap unbounded child output.**

- **Why:** `Process.run` gives you nothing to kill, so a timeout orphans a child still holding the
  config and its connections. Separately, a pathological archive listing (millions of entries) would
  buffer hundreds of MB and freeze text layout.
- **Enforced in:** [archive_service.dart](../../app/lib/src/state/archive_service.dart) —
  `_listCap = 5000` lines retained, with a truncation note.

---

## 7. Polling and dispatch budgets

| Mechanism | Budget | Where |
| :--- | :--- | :--- |
| Job progress | ONE periodic poller at 1 Hz for *all* running jobs — never one timer per job | [jobs_controller.dart](../../app/lib/src/state/jobs_controller.dart) |
| Engine stats | One 1 Hz `core/stats` poll; keeps the last good snapshot on any error | [stats_controller.dart](../../app/lib/src/state/stats_controller.dart) |
| Transfer dispatch | `transferConcurrencyProvider` slots; `0` = unlimited (default), persisted | [jobs_controller.dart](../../app/lib/src/state/jobs_controller.dart) |
| `rcd` readiness | 15 s deadline in `_awaitReady` | [http_rclone_client.dart](../../app/lib/src/rclone/http_rclone_client.dart) |

**RULE — Wrap every RC call inside a periodic poller in try/catch, and cancel the timer in `ref.onDispose`.**

- **Why:** an uncaught error inside a `Timer.periodic` callback tears progress reporting down for the
  rest of the session; a leaked timer keeps polling a disposed provider.

**RULE — Console (`JobType.command`) and archive (`JobType.archive`) jobs must NOT consume a transfer slot.**

- **Why:** they run as their own subprocess/stream jobs — a read-only `ls` or a user-initiated
  compress must not stall queued copies.
- **Enforced in:** `_runningCount` in
  [jobs_controller.dart](../../app/lib/src/state/jobs_controller.dart); `_pump` claims the slot
  before the async dispatch so the count stays accurate.

---

## 8. Known gaps

Recorded so they are not mistaken for intent:

| Gap | Detail |
| :--- | :--- |
| Inspector preview bypasses `buildThumbRequest` | Gets the hydration guard, but not the 128 MiB image cap — see §1.2. |
| `prewarmFolderThumbnails` is not gated on `thumbnailsOn` | The whole-folder pre-warm in [browser_pane.dart](../../app/lib/src/ui/browser_pane.dart) builds requests directly, so it warms thumbnails for a remote whose per-remote thumbnail opt-out is off. Plausibly intentional for an explicit user action — **intent unverified**. |

---

## Related

- [00-system-index.md](00-system-index.md) — master router.
- [08-core-architecture.md](08-core-architecture.md) — the `RcloneClient` seam, engine-per-platform,
  and why engine restart is a first-class operation.
- [07-state-context.md](07-state-context.md) — the providers and controllers these rules constrain.
- [10-external-integrations.md](10-external-integrations.md) — the RC surface, FFI and OS
  integrations these budgets are spent on.
- [11-validation-standards.md](11-validation-standards.md) — how the failures above are surfaced to
  the user.
- [12-utility-standards.md](12-utility-standards.md) — the shared formatters used in the size/consent
  messages.
- [15-security.md](15-security.md) — fail-closed artifact verification and engine hardening.
- [18-knowledge-capture.md](18-knowledge-capture.md) — where a new incident-driven invariant gets
  recorded before it lands here.
- [dev/README.md](../../dev/README.md) — release, store and platform operations.
