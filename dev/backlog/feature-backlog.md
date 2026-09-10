---
type: "backlog"
name: "Feature Backlog & Roadmap"
status: "stable"
description: "Prioritized (MoSCoW) feature roadmap for Airclone, desktop + mobile, v1 → v2."
---

# 📋 Feature Backlog & Roadmap

Prioritized roadmap distilled from competitive + engine research. Tags: `[D]` desktop · `[M]` mobile ·
`[D+M]` both. (The full cross-product feature comparison lives in gitignored
`reference/research/synthesis-feature-matrix.md`.)

> **Status reconciled against the code at v0.7.6 (2026-09-09).** This file had drifted badly — it
> called bisync a "marquee gap" while bisync had shipped with its own confirm dialog, options tab,
> scheduler and task rows, and it listed the skin selector, the crypt wizard, public links, serve,
> bandwidth, compare and keep-replaced as unbuilt. Every item below was re-checked against
> `app/lib`, and each shipped claim now names the file that proves it. **Where a doc and the code
> disagreed, the code won** — see the OS drag-out entry under *Recommended additions* for the
> sharpest case. Items still marked `[ ]` were verified absent, not merely assumed.

---

## 🧭 EXPLORER-NATIVE UX TRACK (ACTIVE) — desktop-first

> **Goal:** make Airclone feel like the host OS's native file manager — Windows Explorer on Windows,
> macOS Finder on macOS, the native paradigm on Linux — with a **switchable skin** (use any look on any
> OS). Default to **easy "native" mode**; expose rclone's power behind an optional **advanced mode**
> (custom flags, queue, stats). This is the live tracking list for the current wave of work. Detailed UX
> research from other rclone GUIs lives gitignored under `reference/`.

### ✅ Shipped (recent alphas)
- [x] Grid / Media-gallery / List views + tabbed **Inspector** + **Quick Look** (Space, ←/→) — a7/a8
- [x] **Local-filesystem browsing** + grouped, collapsible sidebar (**Locations / Disks / Cloud**) — a9/a11
- [x] **Single-pane explorer default** + dual-pane (commander) toggle — a9
- [x] **Auto thumbnails** for images **and** videos; local always on, per-remote disable for bandwidth — a12
- [x] **Editable Locations** — + folder picker, drag-drop a folder to add, remove from sidebar — a11
- [x] **Instant** right-click context menu (no fetch-blocking, no scale-in) — a13
- [x] **Resizable + hideable** sidebar — a13
- [x] **Explorer two-row header** — address row + **command bar** (New · Cut/Copy/Paste · Rename · Delete ·
  **Sort ▾** · **View ▾** with icon-size presets) — a14
- [x] **Advanced transfer dialog** (Copy/Move/Sync · skip rules · compare · Include/Exclude/Filter · cmd
  preview · Dry-run) + **live statistics strip** (`core/stats`) — a15
- [x] **Folder previews** (composite of first images) + **orphaned-engine reap** — a16
- [x] **Tabs per pane** (independent sessions + history; Ctrl+T/W) — a17
- [x] **Video thumbnails fixed** (libmpv headless keyframe) — a18
- [x] **Encrypted preview cache** (AES-256-GCM; PBKDF2/config-pw or remote-name key) + **Clear cache** +
  **memory-only** mode — a19
- [x] **Download-to-chosen-folder** (prompt/remember/always-ask) · **type-to-navigate** · **rich status bar**
  (count · selection size · free/total via `operations/about`) — a20
- [x] **Double-context-menu bug fixed** (onSecondaryTapUp) — a21
- [x] **Easy/Advanced mode** toggle + **Saved transfer tasks** (run/delete) — a22
- [x] **Morphing breadcrumb path bar** (breadcrumbs ⇄ editable) · **resizable Details columns** ·
  **global engine flags** (Apply & restart) — a23
- [x] **Transfer concurrency queue** (limit · Queued state · auto-dispatch) — a24
- [x] **Native window backdrop (opt-in)** — Mica/Acrylic via flutter_acrylic, persisted — a25

### ✅ Shipped in the release line (beta → v0.7.6)

The alpha list above stops at a25; the numbered releases kept shipping. Verified present at v0.7.6:

- [x] **Two-way sync (bisync)** — `ui/bisync_confirm.dart` (the guarded one-time `--resync`),
  `TransferMode.bisync` + the conflict/`maxDeletePercent`/`checkAccess`/`baselineEstablished` fields in
  `state/transfer_options.dart`, the bisync tab in `ui/transfer_options_dialog.dart`, and scheduled
  bisync pairs in `state/scheduler_controller.dart` + `ui/tasks_panel.dart`.
- [x] **Crypt "wrap an existing remote" wizard** — `state/encrypt_remote_controller.dart` +
  `ui/encrypt_remote_dialog.dart`. Holds no secrets (the password is a transient argument, obscured
  server-side by rclone) and verifies with a round-trip canary.
- [x] **Public / share links** (capability-gated) — `ui/public_link_dialog.dart` on
  `operations/publiclink`, reachable from the context menu and the Inspector pills.
- [x] **Serve management** — `state/serve_controller.dart` (`serve/types` ∩ a curated
  http/webdav/ftp/sftp/dlna list) + `ui/serve_panel.dart`, kill-switchable via `state/serve_policy.dart`.
- [x] **Bandwidth limit + timetable** — live `core/bwlimit` in `state/bandwidth_controller.dart`, daily
  windows in `state/bw_schedule.dart` / `bw_schedule_controller.dart`, UI in `ui/bandwidth_control.dart`.
- [x] **Compare two locations** — `FileOps.compare` (`operations/check`) with the match/differ/missing
  buckets in `ui/folder_tools.dart`.
- [x] **Recoverable delete / keep replaced** — `TransferOptions.keepReplaced` emits
  `--suffix .replaced --suffix-keep-extension` (`state/transfer_options.dart`).
- [x] **Dedupe**, **storage breakdown**, **cleanup / empty trash**, **import from URL**, **checksums**,
  **recent activity** — `state/dedupe.dart` + `ui/dedupe_dialog.dart`, `ui/storage_breakdown.dart`,
  `FileOps.cleanup`, `FileOps.copyUrl`, `ui/checksum_dialog.dart`, `ui/recent_activity_panel.dart`.
- [x] **Mounts manager** with VFS cache-mode presets — `state/mount_controller.dart` +
  `ui/mount_panel.dart` / `ui/mount_options_editor.dart`.
- [x] **Command console** (fail-closed argv→RC translator) — `state/console/`, `ui/console_pane.dart`.
- [x] **Config portability** — encrypted export/import, offline multi-QR (desktop image decode + phone
  camera), external encrypted backup — `state/config_io.dart`, `state/offline_qr.dart`,
  `state/external_config_backup.dart`.

**v0.7.6 (tagged, built and released — Play production at 10% staged, Store staged, Apple records in
PREPARE_FOR_SUBMISSION):**

- [x] **Transfer conflict preflight on every path.** Five entry points (Download from the toolbar, the
  Inspector and a selection; OS drag-and-drop; pane-to-pane ⇄) used to let rclone replace silently.
  All now funnel through `transferNamesIntoFolder` (`ui/paste_action.dart`) — the one function that
  calls `showCopyConflictDialog` — from `ui/browser_pane.dart`, `ui/home_screen.dart`,
  `ui/inspector_panel.dart` and `ui/selection_actions.dart`. It fails closed when the destination
  cannot be listed. *(Note: this closes the attended half of the Transfer Coordinator plan; the
  unattended half is still open — see the backlog index row.)*
- [x] **`config/create` refuses to overwrite an existing remote** — `existingRemoteNames()` in
  `state/remotes_provider.dart`, checked by both wizards (`state/add_remote_controller.dart`,
  `state/encrypt_remote_controller.dart`), and refusing just as firmly when the list can't be read.
- [x] **Cloud-hydration guard follows crypt/alias/chunker/compress chains** to a local backing root —
  `resolveLocalBackingRoot` / `isLocalBacked` (tri-state) in `state/cloud_placeholder.dart`; dedupe
  consults it instead of gating on `type == 'local'` (`ui/dedupe_dialog.dart`).
- [x] **Undecryptable-name notice** — a crypt remote with a mismatched key returned an empty listing
  and the pane drew a confident "Empty folder" over a full one. `state/undecryptable_names.dart`
  counts rclone's skipped-name notices from the log drain and the pane samples the counter either
  side of its own `operations/list`, so it now says "N items hidden" instead.
- [x] **Sync source flow** — mark a folder, navigate elsewhere, sync into it. `state/sync_source.dart`
  (deliberately separate from the copy/cut clipboard, and session-only) + `ui/sync_here_action.dart`,
  which **refuses overlapping paths and an empty/unreadable source outright**.
- [x] **Sync dry-run preview** on `operations/check` — `state/sync_preview.dart` +
  `ui/sync_preview_dialog.dart`, where the deletions lead and are the only bucket coloured as a warning.
- [x] **Import merge can REPLACE an existing remote** — explicit, backed up first, and reported apart
  from creations (`MergeReport.replaced` in `state/config_transfer_controller.dart`).
- [x] **Remove all remotes** — `ui/remove_all_remotes.dart`; backs up first and refuses if it cannot.
- [x] **Recents are opt-in and session-only** — `state/recent_locations.dart` defaults to off and
  persists only the choice, never the trail.
- [x] **Mounts can pin a drive letter** — `state/mount_letters.dart`, keyed by full fs so two folders
  of one remote can hold different letters.
- [x] Sidebar long-name wrapping; `core/command` children get the engine's own config path pinned;
  `extraFlags` removed from `TransferOptions` (it was preview-only and never emitted — see the note at
  the top of `state/transfer_options.dart`); `ios-release` export no longer passes
  `-allowProvisioningUpdates` except on `signing=automatic`; three stray DEVELOPMENT certificates
  revoked (four load-bearing ones remain).

### 🔜 Layout & chrome
- [x] **Command toolbar** below the address/path bar (New · Cut/Copy/Paste · Rename · Delete · Sort ·
  View · Filter) — Explorer-style two-row header — a14.
- [x] **Tabs** — multiple open locations per pane, each its own path history + view mode + selection — a17.
- [x] **View presets** — Extra-large / Large / Medium / Small icons · List · Media (via View ▾) — a14.
  `ViewMode` is `{list, grid, media, tree}` (`state/browser_controller.dart`) — the **tree** view
  landed in v0.8 (`ui/tree_view.dart`, desktop only) — so **Tiles / Content** are still open. The **Details pane** did ship, as the toggleable right-rail Inspector
  (`inspectorVisibleProvider` in `ui/inspector_panel.dart`, Ctrl+I, with Overview/More tabs); a docked
  **Preview pane** is still open — preview today is a modal (`ui/preview_dialog.dart`) plus Quick Look.
- [x] **Native per-OS look** as default + a **skin selector** — `state/skin.dart` persists the choice and
  defaults to `Skin.forHost()` (Explorer on Windows, Finder on macOS, GNOME on Linux; the brand look on
  mobile). The `Skin` enum and its `SkinTokens` live in `ui/theme/tokens.dart`, and the selector is in
  `ui/settings_screen.dart`. Honest scope: the per-skin tokens are typography/density axes, deliberately
  "starting points, refined when each skin is built out" — not finished per-OS chrome.
- [~] **Native window chrome** — **Mica/Acrylic backdrop shipped (opt-in)** a25
  (`state/window_backdrop.dart`). Still open, and verified absent — the repo has no titlebar code at
  all: tabs-in-titlebar, macOS traffic-light insets/vibrancy, per-surface translucency tuning.

### 🖼️ Previews & icons
- [x] **Folder previews** — folder thumbnail composited from the folder's first few images — a16.
- [x] **Icon/preview sizing** wired to the view presets — a14.
- [ ] PDF / document **first-page thumbnails in the grid** — genuinely open, and the distinction matters:
  a full PDF **viewer** already ships in the preview dialog via `pdfrx` (`ui/preview_dialog.dart`, which
  also renders markdown and text), but `state/thumbnail_service.dart` has no PDF path at all — it
  handles images and video only. This is about extending that pipeline, not adding a renderer.

### ⚙️ Advanced power (optional "advanced mode")
- [x] **Advanced transfer dialog** — Copy/Move/Sync · skip rules · compare · Include/Exclude/Filter tabs ·
  rclone-cmd preview · Dry-run/Run — a15 (gated behind advanced mode a22).
- [x] **Transfer queue** (a24) + "**save as task**" (a22) + **scheduler** (a50 — interval/daily/weekly).
  **OS-level background execution shipped on Windows**, contradicting the "app-open-only" note this
  entry used to carry: `app/lib/src/headless/headless_runner.dart` gives the app a headless
  `--run-task <id>` / `--run-due` entrypoint, and `state/windows_task_scheduler.dart` registers it as a
  real Task Scheduler job via `schtasks /Create /XML`, so a schedule fires with the app closed.
  `ui/tasks_panel.dart` gates the offer on `canRunWhileClosed` (`state/scheduling_policy.dart` —
  Windows and Android today) and blocks it when the config is encrypted with no stored password,
  because every fire would otherwise exit 2 silently.
  **Android is built (v0.8 Phase F):** one `PeriodicWorkRequest` (`app/android/.../DueTasksWorker.kt`,
  driven from `state/android_work_registration.dart`) boots a headless Flutter engine and runs the
  same `--run-due` path. It *attempts* WorkManager's `setForeground()` (reusing `TransferService`'s
  notification channel), but — **measured on Android 15, 2026-09-09** — Android 12+ refuses that
  promotion to a periodic wake started in the background (`mAllowStartForeground false`; only
  expedited work and a visible app are exempt). A background wake therefore runs inside the plain
  worker's budget, with the Dart run capped at **8 minutes** so it ends cleanly, and a large first
  backup proceeds in slices, one per wake, resuming where it stopped. The promotion does succeed for
  the one-off the user launches from inside the app. **There is deliberately NO `BOOT_COMPLETED` receiver** —
  an earlier version of this entry called for one, and that was wrong: WorkManager persists its
  requests and re-arms them after a reboot itself; a receiver of ours would be a second wakeup
  source with nothing to add. **Still open:** the macOS (`launchd`) and Linux (`systemd --user`
  timer) equivalents.
- [x] **Run history** — `TaskRunRecord` (time · ok/failed · error · duration · bytes), newest-first and
  capped at 10, persisted with the task in `state/tasks_controller.dart`; `ui/tasks_panel.dart` shows the
  last outcome inline and the last five in a tooltip. **Cron is still open** — `ScheduleKind` is
  `{interval, daily, weekly}` (`state/task_schedule.dart`), with no 5-field parser anywhere.
- [x] **Statistics** strip — live transfer stats (`core/stats`), per-job + aggregate, speeds/ETA — a15.
- [~] **Global settings** — custom rclone **engine flags** shipped a23 (`state/engine_flags.dart`);
  **bandwidth shipped too** — a live global cap via `core/bwlimit` (`state/bandwidth_controller.dart`)
  plus a daily **time-window timetable** (`state/bw_schedule.dart` + `bw_schedule_controller.dart`, UI in
  `ui/bandwidth_control.dart`). Still open: **global** VFS settings (VFS options exist, but per-mount
  only — `ui/mount_options_editor.dart`) and **performance presets** (OS × provider × base).
- [x] **Easy ⇄ Advanced mode** toggle (progressive disclosure) — a22.

### 🔒 Cache & privacy
- [x] **Clear cache** — one-click in Settings (deletes `airclone_thumbs` + `airclone_folderthumbs`); shows
  cache size — a19.
- [x] **Encrypt the on-disk cache at rest** (thumbnails now; file/VFS cache later). AES-256-GCM per blob.
  Key derivation: **PBKDF2 from the rclone config password** when the config is encrypted (so no config
  password ⇒ no remotes ⇒ no cache — coherent). **Fallback when the config is NOT password-encrypted:**
  a random key sealed in the **OS secure store** (Windows DPAPI / macOS Keychain / Linux Secret Service)
  — *stronger than a remote-name hash, which is not secret and gives only obfuscation*. Also offer a
  **memory-only / no-disk-cache** mode for the paranoid.
- [ ] **Bring in-process preview materialization under the same cache/privacy policy** — the v0.5
  object server downloads whole remote objects into general plaintext storage, does not consult
  memory-only mode, and can reuse stale `(fs,path)` entries. See
  [hardening audit H-09](hardening-audit-2026-07-15.md).
  - **Re-verified unchanged at v0.7.6.** In `rclone/librclone_object_server.dart`, `_materialize`
    keys the cache on `sha1(fs + '\0' + remote)` alone — no size, mtime or hash — and returns the
    existing file whenever it is non-empty, so an object edited at the source serves its stale copy
    forever. The bytes land in `cacheDir` as plain files (the encrypted-cache machinery in
    `state/cache_crypto.dart` is not in this path), `stop()` deliberately leaves them for the OS cache
    policy to reclaim, and nothing in the file references memory-only mode. Affects the **in-process
    (librclone) engine only** — iOS and MAS always, desktop when the Engine setting selects it.

### 🐞 Known robustness bugs
- [ ] **Engine process ownership / orphan cleanup** — reopened by the 2026-07-15 audit. a16 reduced
  accumulated orphan processes, but all desktop/headless instances share one raw temp PID marker and
  hard-kill its current numeric PID without validating ownership. Replace it with an ownership-safe
  lease/mutex/IPC design plus OS process containment; test concurrent GUI/headless instances and PID
  reuse. See [hardening audit H-01](hardening-audit-2026-07-15.md).
  - **Partly addressed in v0.5.5 (Windows only):** the *OS process containment* half now exists —
    `rclone/windows_child_job.dart` puts every rclone child in a **kill-on-close Job Object**, so no
    child can outlive its own instance regardless of how that instance dies, and
    `AppLifecycleListener.onExitRequested` stops `rcd` on window close. That makes the PID marker a
    pure fallback on Windows and removes the PID-reuse hazard there. **Still open:** the
    ownership-unsafe shared temp PID marker itself, and the equivalent containment on
    **macOS/Linux** (a process group + `kill(-pgid)`, or `prctl(PR_SET_PDEATHSIG)` on Linux). Landed
    for Microsoft Store policy 10.2.7 — see `dev/windows-signing-and-store.md` §2.
  - **Re-verified unchanged at v0.7.6.** `rclone/http_rclone_client.dart` still writes
    `${Directory.systemTemp.path}/airclone_rcd.pid` — one path for every instance and every user on the
    box — and still `Process.killPid(pid, SIGKILL)`s whatever numeric PID it reads, with no check that
    the process is ours. `WindowsChildJob.adopt` and `ui/app.dart`'s `onExitRequested` are both present
    as described, and there is still **no** POSIX containment anywhere (no process group, no
    `PR_SET_PDEATHSIG`), so macOS and Linux depend entirely on the unsafe marker.
- [ ] **Scheduled Tasks survive uninstall (Windows)** — `state/windows_task_scheduler.dart` registers
  tasks as `Airclone\<id>`, which Windows stores as real files under
  `C:\Windows\System32\Tasks\Airclone\`. Uninstalling removes neither them nor that folder, so any
  schedule the user created is left behind pointing at a deleted `airclone.exe` and fails forever.
  Residual state of exactly the kind Store policy **10.2.7** targets — the 2026-07-29 report did not
  cite it (a reviewer who never creates a schedule cannot hit it), so it was deliberately left out of
  the v0.5.5 fix rather than churn a release in flight. Fix: an `[UninstallRun]` entry running
  `schtasks /Delete /TN "Airclone\*" /F` (tolerate a non-zero exit — the folder may not exist), and
  drop the now-empty Task Scheduler folder, which needs `ITaskService` COM since `schtasks` cannot
  remove folders.
  - **Still open at v0.7.6, and now higher-stakes.** Re-verified: `taskName(id)` is still
    `'Airclone\\$id'` and `app/windows/installer/airclone.iss` still has **no** `[UninstallRun]` and no
    `schtasks` call — its uninstall work is `[UninstallDelete]` plus a `CurUninstallStepChanged` sweep
    of `{app}` and the user-data dirs. The stakes rose because OS-level background scheduling is no
    longer hypothetical: `ui/tasks_panel.dart` now offers "run while closed" on Windows, so ordinary
    use creates exactly the registrations an uninstall leaves behind. Deleting a task in-app *does*
    unregister it (`windowsTaskSchedulerProvider.unregister`), so only the uninstall path is unclean.

### 💡 Recommended additions (proposed)
- [x] **Type-to-navigate** (typeahead) — a20; **keyboard map** F2 · Del · Enter · Ctrl+A · Esc — a26.
  **Ctrl+C/X/V are wired**, contrary to the parenthetical this entry used to carry: the Ctrl branch of
  `_onKey` in `ui/home_screen.dart` maps `keyC`/`keyX` to `_clipboardStage(cut:)` and `keyV` to
  `_pasteIntoActive()`, guarded by `textEditingHasFocus()` so a text field keeps its own copy/paste.
- [x] **Morphing breadcrumb path bar** (breadcrumbs ⇄ editable type-to-go) — a23.
- [x] **OS interop for local files** — a30. Right-click + Details pills: **Open with default app**
  (url_launcher), **Show in File Explorer/Finder** (documented OS commands via a pure, unit-tested per-OS
  argv builder in `state/os_integration.dart`), **Copy path** (Clipboard). `state/open_external.dart`
  stages a remote object first, so "Open in another app" works off a remote too — on every platform but
  iOS (see the backlog index for why iOS needs Swift, not a flag flip).
- [x] **True OS drag-out — shipped after all.** This entry previously claimed drag-out had been *removed*
  and the Rust toolchain *dropped*, and that Flutter's only option "can't be agent-verified". The code
  disagrees, so the code wins: `super_drag_and_drop: ^0.9.1` is a live dependency in `app/pubspec.yaml`,
  and `NativePaneDraggable` in `ui/native_drag.dart` puts a real `Formats.fileUri` on the drag for local
  files — so **one** gesture drops in-app (into a folder/pane) *or* onto Explorer/Finder/the desktop.
  Two consequences worth keeping visible: its `super_native_extensions` half builds a Rust crate via
  cargokit, so **desktop builds need a Rust toolchain on PATH** (CI installs it), and the same file's
  `NativePaneDropRegion` handles OS→app drops, which is why there is no `desktop_drop` dependency.
  Cloud→OS still goes through Download (drag-out carries local files only).
- [x] **Resizable + sortable columns** in Details view — sortable since a6, resizable a23.
- [x] **Status bar** — item count + selection size + free/used space (`operations/about`) — a20.
- [x] **Per-remote view memory** (remember view mode + sort + density per remote, restored on open) — a26.
  (Per-*tab* state is already inherent — each tab is its own session.)

---

## 🟥 MUST — v1 foundation

Status verified against `app/lib` at v0.7.6. **✅ = built and in the shipping app · ◐ = partly built
(the gap is named) · ⬜ = verified absent.**

**Engine & architecture**
- ✅ `[D+M]` Single `RcloneClient` abstraction: `rpc(method, params) → json`, two transports
  (`rclone/http_rclone_client.dart` → `rcd`; `rclone/ffi_rclone_client.dart` → librclone). Which one
  runs is `resolveEngineMode` (`state/engine_mode.dart`), which folds in platform constraints.
- ◐ `[D]` Spawn `rclone rcd` loopback-only, random port + `--rc-user`/`--rc-pass` per session — done
  (`http_rclone_client.dart`, `--rc-addr` on `InternetAddress.loopbackIPv4:0`). The "prefer unix
  socket / named pipe" half is **not** built; the transport is loopback TCP with per-session creds.
- ◐ `[M]` Per-arch native engine in CI, pinned rclone tag — done, but **not in the shape written
  here**: Android ships the rclone **binary** as a jniLib (`app/android/app/src/main/jniLibs/`,
  arm64-v8a · armeabi-v7a · x86_64) and runs it as a subprocess; iOS links a static
  `librclone.a` (device + simulator, wired in `Runner.xcodeproj`), not an `xcframework`, and there is
  no `librclone.aar` in the tree. Left as an item only because the wording still misleads.
- ✅ `[D]` Auto-provision rclone binary: download, SHA256-verify (against the official `SHA256SUMS`,
  fail-closed), min-version, PATH fallback — `rclone/rclone_engine.dart`.
- ✅ `[D+M]` Engine **restart** as a first-class operation — `state/engine_controller.dart`.
- ✅ `[D+M]` Async job engine: `_async` + `_group`, single shared poller, raised
  `--rc-job-expire-duration` (`http_rclone_client.dart`).
- ✅ `[D+M]` Detect config encryption from the file header rather than an RC call (a locked config
  hangs `config/get`), never `--ask-password=false`, `RCLONE_CONFIG_PASS` env-only —
  `rclone/rclone_engine.dart` + `http_rclone_client.dart`.

**Remote / config**
- ✅ `[D+M]` Dynamic remote forms from cached `config/providers` — `rclone/models/provider.dart` parses
  `Examples`/`Exclusive`/`IsPassword`/`Sensitive`/`Provider`; `state/providers_provider.dart` caches.
- ✅ `[D+M]` Interactive config state machine (`opt.nonInteractive` + continue/state/result) —
  `state/add_remote_controller.dart`; covers OAuth and team drives.
- ✅ `[D+M]` Full remote CRUD incl. **atomic edit** (`config/get` → `config/update` MERGE, never a
  `config/create` recreate) and **Duplicate remote…** in the sidebar menu (`ui/home_screen.dart`).
  Since v0.7.6, create also refuses a name that is already taken.
- ✅ `[D+M]` Capability-gating from `operations/fsinfo` — `state/remote_features.dart`.

**Browser & transfer**
- ✅ `[D]` **Rebuilt rclone file explorer = hero surface.** Dual-pane on `operations/list` with tabs
  per pane, inline add/edit remote; `[M]` single-pane phone shell (`ui/mobile_home.dart`).
- ✅ `[D+M]` Multi-select.
- ◐ `[D]` **In-app, target-aware drag-and-drop** incl. real OS in *and* out payloads —
  `ui/native_drag.dart` (`NativePaneDraggable` / `NativePaneDropRegion`) + `ui/pane_drag.dart`.
  **Gap:** the original requirement was "default copy, modifier move/sync"; the modifier half is
  not built. `native_drag.dart:35` declares `allowedOperations: () => const [DropOperation.copy]`
  and every drop handler treats a drop as a copy.
- ✅ `[D+M]` Stat-then-dispatch copy/move/sync; **server-side** `operations/copyfile`/`movefile` within
  one remote, streamed `sync/copy` cross-remote — `state/file_ops.dart`,
  `state/clipboard_controller.dart`, `state/transfer_service.dart`.
- ◐ `[D+M]` Dry-run + `--max-delete` guard. The **guard** is built (`TransferOptions.maxDeleteFiles`
  for one-way sync, `maxDeletePercent` for bisync). Dry run is **not mandatory** — it is an opt-in
  checkbox (`TransferOptions.dryRun`, default false), and the destructive-sync confirm only *advises*
  running one. The one flow that forces a preview first is "Sync to here"
  (`ui/sync_here_action.dart` → `buildSyncPreview` → `ui/sync_preview_dialog.dart`). Making that
  preview mandatory on every sync/move is the remaining work.
- ◐ `[D+M]` Transfer panel: live speed/ETA/per-file + aggregate and cancel via `job/stop` are built
  (`ui/jobs_dock.dart`, `ui/jobs_panel.dart`, `ui/stats_panel.dart`), and history exists separately as
  `ui/recent_activity_panel.dart` on `core/transferred`. **Not built:** search over that history.

**Mobile storage**
- ⬜ `[M]` Android `DocumentsProvider` — verified absent (no `DOCUMENTS_PROVIDER` intent filter, no
  provider class). Remotes do **not** appear in the system Files app.
- ⬜ `[M]` iOS File Provider extension — verified absent (no extension target in `app/ios/`).
- ✅ `[M]` Foreground service **is built** — `TransferService.kt` with
  `android:foregroundServiceType="dataSync"`, which holds the process (and the engine child) alive
  during a transfer. **WorkManager scheduling is built too** (v0.8 Phase F, `DueTasksWorker.kt`):
  a periodic `--run-due` wake with Wi-Fi-only / charging constraints as settings, plus the
  camera-roll photo backup on top of it (`state/photo_backup.dart`). Boot-resume needs no code of
  ours — WorkManager re-arms its own requests after a reboot, and a `BOOT_COMPLETED` receiver (which
  this entry used to ask for) would be redundant. Not requested on purpose:
  `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (Play policy).

**App shell**
- ⬜ `[D]` System tray + pinned quick actions — verified absent.
- ✅ `[D]` Desktop mount as a secondary convenience: `mount/types` detection, VFS options panel with
  cache-mode presets, drive-letter pinning — `state/mount_controller.dart`,
  `ui/mount_options_editor.dart`, `state/mount_letters.dart`. Hidden entirely in the MAS build
  (`state/mount_policy.dart`), where FUSE is impossible under the App Sandbox.
- ✅ `[D+M]` Themes (light/dark/system) on a real design system — `ui/theme/tokens.dart`
  (`ThemeMode` in `state/settings_controller.dart`), now with per-OS skins on top.
- ◐ `[D+M]` First-run onboarding — there is a zero-remotes empty state that prompts to add the first
  remote (`ui/browser_pane.dart`, shown only once the list has *loaded* empty, never mid-load), and
  OAuth works through the interactive config machine. A **guided** first-run wizard is not built.
- ◐ `[D+M]` i18n-first — **not built**: no `intl`/`flutter_localizations` dependency, no `l10n`
  directory, strings are literals. The automated test suite for engine lifecycle + RC does exist
  (`app/test/`).

## 🟧 SHOULD — v1.x / early v2

Same markers as MUST. **Most of this section shipped** — it was the single biggest source of drift.

- ✅ `[D+M]` Bisync as a "sync pair" object: guided one-time `--resync` behind an explicit confirm
  (`ui/bisync_confirm.dart`), conflict-strategy dropdowns and the `--max-delete` percentage surfaced
  (`ui/transfer_options_dialog.dart`), `baselineEstablished` flipping exactly once on the first
  successful non-dry-run resync, and scheduled pairs refusing to fire before that baseline exists.
- ◐ `[D+M]` Crypt "wrap an existing remote" wizard — shipped (`state/encrypt_remote_controller.dart`,
  `ui/encrypt_remote_dialog.dart`) with a post-create round-trip **canary** that proves names encrypt
  and decrypt end-to-end. The **live filename-transform preview** while typing is not built.
- ◐ `[D+M]` Filter builder — include/exclude/filter rule lists are first-class on every transfer
  (`TransferOptions.includes` / `excludes` / `filters`, reused across copy/move/sync/bisync/check, with
  their own tab in `ui/transfer_options_dialog.dart`). Not built: **size/age/depth** chips and a **live
  match preview**.
- ✅ `[D+M]` Live bandwidth cap (`core/bwlimit`, `state/bandwidth_controller.dart`) + a daily
  time-window editor (`state/bw_schedule.dart`, `ui/bandwidth_control.dart`). Asymmetric up/down rates
  are not offered (rclone's live RC takes one rate).
- ✅ `[D]` Serve management (HTTP/WebDAV/FTP/SFTP/DLNA) via `serve/start` — `state/serve_controller.dart`
  offers only the curated list ∩ what `serve/types` reports, and `state/serve_policy.dart` is the
  kill-switch every entry point already honours.
- ⬜ `[M]` Serve-WebDAV escape hatch for media players — verified absent: serve is reachable from the
  desktop shell only (`ui/home_screen.dart`), never from `ui/mobile_home.dart` or the mobile sheets.
- ⬜ `[D]` Performance presets system (OS × provider × base), editable — verified absent. The only
  "presets" in the tree are icon sizes, bandwidth rates and engine-flag chips. Note that per-transfer
  performance controls *did* ship (see build-queue item 6).
- ✅ `[D+M]` Public/share links, capability-gated — `ui/public_link_dialog.dart` on
  `operations/publiclink`, gated by `state/remote_features.dart`.
- ✅ `[D+M]` Code/markdown viewer; richer preview — `ui/preview_dialog.dart` covers image · text ·
  markdown (`flutter_markdown`) · PDF (`pdfrx`) · video/audio (`media_kit`), with a size cap so a stray
  multi-megabyte log cannot freeze the UI.
- ⬜ `[M]` Media-picker visibility (Android Photo Picker/MediaStore, iOS FP domain) — verified absent.
- ◐ `[M]` Per-remote **thumbnail** toggle shipped (`state/thumbnail_prefs.dart` — an opt-out set keyed
  by `fs`, on by default, surfaced in the View menu). Per-remote **VFS-cache** toggle is not built:
  VFS options are per-*mount*, not per-remote.
- ◐ `[D+M]` **Cross-device profile sync.** The *manual* half shipped: encrypted config export/import
  (`state/config_io.dart`); an offline multi-QR handoff where the desktop renders and animates the
  pages and the phone camera accumulates chunks (`state/offline_qr.dart`,
  `ui/offline_qr_dialog.dart`, `ui/scan_from_desktop_sheet.dart`) — import is **phone-camera only**,
  the earlier desktop image-decode path having been dropped, and since the 2026-07 rework the phone
  mints a one-time unlock code that is typed on the computer, so a screen-grab of the QR alone cannot
  open it; and an opt-in encrypted external backup that survives uninstall
  (`state/external_config_backup.dart`). **Still open:** the *automatic* half —
  an E2E-encrypted blob stored on one of the user's own remotes, versioned for conflicts, opt-in and
  per-remote selectable. LAN P2P (mDNS) was tried and **removed** in favour of the offline QR. A
  self-hosted server stays an optional org/fleet target, never required.

## 🟨 COULD — v2
- ◐ `[D+M]` Scheduling: **interval/daily/weekly shipped a50** (in-app scheduler + missed-slot catch-up),
  **run history shipped** (`TaskRunRecord`, ten per task, `state/tasks_controller.dart`), and
  **OS-level background execution shipped on Windows** (`headless/headless_runner.dart` +
  `state/windows_task_scheduler.dart`). Still open: **cron** (5-field, prose-rendered) and the
  **macOS/Linux/Android** background equivalents.
- ⬜ `[D]` Real-time FS watcher with net-change debounce — verified absent (no directory watching
  anywhere; listings refresh on navigate, on demand, and via mobile pull-to-refresh).
- ⬜ `[D+M]` Dynamic-path macros (`$(date)`, `$(hostname)` — resolved internally, no shell) — verified
  absent.
- ⬜ `[D+M]` Multi-backend / remote-`rcd` profiles (manage a NAS/remote rclone from one UI) — verified
  absent. The engine seam would take it (any reachable `rcd` is just another transport), but nothing
  today configures a non-local endpoint.
- ◐ `[D]` **Folder compare shipped** — `FileOps.compare` on `operations/check`, with match/differ/missing
  buckets in `ui/folder_tools.dart`, plus the sync preview (`ui/sync_preview_dialog.dart`) that leads
  with deletions. Still open: a true colour diff view, and **1:N multi-destination** (verified absent —
  every transfer is one source to one destination).
- ⬜ `[D+M]` **Reusable filter profiles** — verified absent. Filter rules persist inside a *saved task*
  (`TransferOptions` round-trips them), but there is no named, reusable profile store.
- ⬜ `[D+M]` **Alert channels beyond toast** (webhook → email/Telegram/MQTT) — verified absent. The
  local evidence channel is `state/diagnostics.dart`, which redacts at ingest and never egresses.
- ◐ `[D]` Clean headless/server mode with SSE + Basic-auth + TLS — **not built**. What exists is a
  headless *task runner*, not a server: `app/lib/src/headless/headless_runner.dart` handles
  `--run-task <id>` / `--run-due` and exits. No listener, no web UI, no auth surface.
- ⬜ `[M]` Media auto-backup — verified absent. ✅ `[D+M]` **Recoverable delete shipped** as
  `TransferOptions.keepReplaced` (`--suffix .replaced --suffix-keep-extension`, chosen because it is
  robust across cloud *and* local with no path math); a backend-trash tier and `_config.BackupDir` to a
  separate versions folder are the remaining forms.

## 🛠️ RC-GROUNDED BUILD QUEUE — engine capability mining (2026-06-29)

> Distilled from a deep-dive feature-mining pass (rclone core/backends/RC-API/serve-mount + competitive scan).
> Every item is confirmed reachable through the existing `RcloneClient.rpc()` seam (pure RC pass-through, so
> anything on rclone.org/rc is callable). Ordered by value ÷ effort. Mechanisms are exact so a build can start
> from here. (Generic capability framing only — research notes live gitignored under `reference/`.)
>
> **Thirteen of these sixteen are now built.** Statuses below were re-checked against `app/lib` at v0.7.6;
> the mechanism text is kept so the remaining three can still be started from here.

1. ✅ **Recoverable transfers — "Keep replaced files"** `[D+M]`. Shipped as `TransferOptions.keepReplaced`
   (`state/transfer_options.dart`), emitting `--suffix .replaced --suffix-keep-extension` — robust across
   cloud + local, no path math. Still optional later: `_config.BackupDir` to a separate versions folder.
2. ✅ **Verify / compare two locations** `[D]`. Shipped as `FileOps.compare` on
   `operations/check {srcFs,dstFs,oneWay}` with the match/differ/missing buckets in `ui/folder_tools.dart`
   (active pane vs. the other pane). Per-file checksums ship too, though via
   `operations/stat {opt:{showHash:true}}` rather than `operations/hashsum` —
   `ui/checksum_dialog.dart`, which restricts LOCAL files to md5/sha1/sha256 because the local backend
   *computes* every requested type and unrestricted it blows the RPC timeout on a large file.
3. ✅ **Two-way sync (bisync)** `[D+M]` — **shipped; this was the "marquee gap" line that made this whole
   doc untrustworthy.** `TransferMode.bisync` with `resyncMode`, `conflictResolve`, `conflictLoser`,
   `conflictSuffix`, `maxDeletePercent` and `checkAccess` (`state/transfer_options.dart`); the guarded
   one-time resync in `ui/bisync_confirm.dart`; `baselineEstablished` flipping exactly once on the first
   successful non-dry-run resync, with the scheduler refusing to fire before it does.
4. ◐ **Structured filter / include-exclude builder** `[D+M]`. Include/exclude/filter rule lists are
   first-class and reused across copy/move/sync/bisync/check, with their own tab in
   `ui/transfer_options_dialog.dart`. Remaining: `MinSize/MaxSize/MinAge/MaxAge` + depth as chips, and a
   live match preview.
5. ◐ **Empty trash / reclaim space** `[D+M]`. `operations/cleanup {fs}` shipped as `FileOps.cleanup`
   (`ui/folder_tools.dart`). Two gaps against the mechanism as written: it is **not** pre-gated on fsinfo
   `Features.CleanUp` — it runs and surfaces an honest error when the backend lacks it — and
   `operations/rmdirs` is reachable only through the command console, never as a UI action.
6. ◐ **Advanced performance & safety controls** `[D]`. Shipped in `TransferOptions`: `Transfers`,
   `Checkers`, `Order` (`--order-by`), `IgnoreExisting` (skipExisting), `UpdateOlder` (skipNewer),
   `Immutable`, `TrackRenames`. Verified absent: `MaxTransfer`+`CutoffMode`, `MaxDuration`, `NoTraverse`,
   `FastList`.
7. ✅ **Encrypt-a-remote (crypt) wizard** `[D+M]`. `state/encrypt_remote_controller.dart` +
   `ui/encrypt_remote_dialog.dart`. Security shape held: the password is a transient argument, never a
   provider field, obscured server-side by rclone's `opt.obscure` (so we never call `core/obscure`
   ourselves), and never persisted or logged. Verification is a round-trip canary rather than cryptcheck.
8. ✅ **Bandwidth schedule (timetable)** `[D+M]`. `state/bw_schedule.dart` + `bw_schedule_controller.dart`
   re-issue `core/bwlimit` at slot boundaries, exactly as the mechanism note predicted; UI in
   `ui/bandwidth_control.dart`.
9. ◐ **Import from URL + browser uploads** `[D+M]`. `operations/copyurl` shipped as `FileOps.copyUrl`
   (`ui/folder_tools.dart`). `operations/uploadfile` is unused anywhere — uploads go through the
   drag-and-drop/paste path instead.
10. ✅ **Edit / duplicate a remote** `[D+M]`. `config/get` + `config/update` (a MERGE, so omitted keys keep
    their value) in `state/add_remote_controller.dart`; "Edit remote…" and "Duplicate remote…" both sit in
    the sidebar's per-remote menu (`ui/home_screen.dart`).
11. ◐ **Storage analysis (folder sizes)** `[D]`. `operations/size` shipped as `FileOps.folderSize` with a
    breakdown view in `ui/storage_breakdown.dart`. The local `core/du`/`core/disks` additions and a treemap
    are not built.
12. ✅ **Find & resolve duplicates** `[D]` — **and deliberately NOT via `core/command`.** Built client-side
    instead: `state/dedupe.dart` derives a content signature from an `operations/list` requested with
    `showHash:true` and resolves per group with `operations/deletefile`. A file whose backend exposed **no**
    hash is never a candidate — identity is never guessed from size alone. `ui/dedupe_dialog.dart` also
    consults the cloud-hydration guard before reading content.
13. ⬜ **Storage-tier / archive class** `[D]` — verified absent; `operations/settier`/`settierfile` appear
    nowhere. Gate on fsinfo `Features.SetTier`; the tier list is **backend-specific** (enumerate per
    backend — no universal list).
14. ✅ **Serve a remote on the LAN** `[D]`. `state/serve_controller.dart` offers only the curated
    http/webdav/ftp/sftp/dlna list ∩ what `serve/types` reports, so we never offer a type the binary lacks;
    `ui/serve_panel.dart` is the UI and `state/serve_policy.dart` the enterprise kill-switch.
15. ✅ **Mounts manager (over RC)** `[D]`. `mount/mount|listmounts|unmount|types` in
    `state/mount_controller.dart` (listmounts polled as the source of truth), VFS cache-mode presets in
    `ui/mount_options_editor.dart`, drive-letter pinning in `state/mount_letters.dart`, policy gate in
    `state/mount_policy.dart`.
16. ✅ **Transfer history / recent activity** `[D+M]`. `core/transferred` in
    `state/recent_activity_controller.dart` + `ui/recent_activity_panel.dart`, read-only and `autoDispose`
    so there is no permanent poller.

**Cross-cutting:** keep every long action `_async` (drops into the existing Jobs panel); use `core/obscure`
for any password we hand to `config/create`. **Security invariants to preserve:** loopback-only `rcd` +
per-session `--rc-user`/`--rc-pass`; `RCLONE_CONFIG_PASS` env-only (never logged/persisted); `core/command`
and `options/set` must use a GUI-built allow-list (never free-form user input) — that's the surface of the
published rclone RC CVEs; pin rclone ≥ 1.73.5.

## ⬜ WON'T (v1)
- `[M]` FUSE mount on mobile (needs root — steer to SAF/File Provider; document the rooted path only).
- `[D+M]` Team/multi-user sharing, RBAC, cloud account sync.
- `[D]` Xvfb-wrapped headless (architectural dead-end — defer to a clean server binary). Unaffected by
  `headless/headless_runner.dart`, which is a one-shot task runner with no display and no listener.
- ~~`[M]` `core/command` on mobile~~ — **overtaken by the architecture.** This assumed mobile always
  means librclone, but **Android ships the rclone binary as a jniLib and runs it as a subprocess**, so
  `core/command` works there and the command console is a real Android feature
  (`activeIsConsole` gating in `ui/mobile_home.dart`). The gotcha that comes with it: a `core/command`
  child re-execs a *fresh* rclone that does not inherit the parent `rcd`'s `--config`, so Android must
  pin `RCLONE_CONFIG` in the engine's extra env or the child reads an empty config with none of the
  user's remotes. The restriction still stands wherever librclone *is* the engine (iOS, MAS).
  `operations/uploadfile` is unused on every platform — uploads go through `copyfile`/`sync/copy`.
- `[D]` Bundling rclone's own web-GUI — Airclone ships its own UI.

---

## 🏢 ENTERPRISE TRACK (parallel to the phases)

Full design in [wiki/core/19-enterprise-readiness.md](../../wiki/core/19-enterprise-readiness.md).
Principle: **never phone home; never SSO-tax security.** Tags: `v1-ent` = first enterprise-ready
release · `later` = post-design-partner.

> **Status at v0.7.6: this whole track is still unbuilt, with two partial exceptions.** There is no
> `PolicyService`, no `policy.schema.yaml`, no `isForced`, and no audit event bus anywhere in `app/lib`.
> What *does* exist is (a) three hand-written kill-switch providers the seam already honours —
> `state/mount_policy.dart`, `state/serve_policy.dart`, `state/native_actions_policy.dart` — which are
> the right shape for a policy engine to feed later but are currently driven by build flavour, not by
> any admin channel; and (b) most of the **supply-chain** row, which shipped for the stores rather than
> for enterprise: Windows Azure Artifact Signing, macOS Developer ID sign + notarize, and a
> fail-closed SHA256 verification of the downloaded rclone against the official `SHA256SUMS`
> (`rclone/rclone_engine.dart`). SBOM, SLSA attestations, OpenVEX and `security.txt` are not built.

**Early (build alongside Phase 1–2)**
- `v1-ent` `[D+M]` **Policy Engine**: one `policy.schema.yaml` → codegen for ADMX/Intune, macOS
  `.mobileconfig`, Linux `/etc/airclone/policy.json`, Android `app_restrictions.xml`, iOS AppConfig;
  `PolicyService` with `isForced`; **kill-switches enforced in the `RcloneClient` seam** (disable
  public links/serve/mount/config-edit/add-remotes/update-check; backend allow/deny).
- `v1-ent` `[D+M]` **Audit event bus** → local append-only, **hash-chained** JSON log (default sink).
- `v1-ent` `[D+M]` **Secrets provider interface** (`SecretStore`): OS keychain first; Vault/KMS via
  external refs + `--password-command`; never plaintext in `rclone.conf`.
- `v1-ent` `[D+M]` **Opt-in SIEM export** (syslog RFC 5424 / CEF / LEEF / OTLP) + drop-in OTel
  Collector config; default empty (zero egress).
- `v1-ent` `[D+M]` **DLP policy keys**: `allowed_remote_pairs`, `block_public_links`,
  `require_encrypted_destination`, `read_only_remotes`, `data_residency`.
- `v1-ent` `[D]` **Harden `rcd`**: loopback/unix-socket, per-session creds, TLS ≥ 1.2, never
  `--rc-no-auth` on TCP.
- `v1-ent` `[all]` **Supply chain**: sign+notarize+staple incl. bundled rclone; pinned+verified rclone
  (**fail-closed**); disable `selfupdate` by policy; CycloneDX SBOM + scanning; SLSA L3 attestations;
  OpenVEX; `security.txt` + CVD/CVE process.
- `v1-ent` `[all]` **Air-gapped**: offline install; `AIRCLONE_RCLONE_PATH` + internal mirror spec;
  self-hosted/static update manifest.

**Later (post-design-partner)**
- `later` `[D+M]` **SSO**: OIDC Auth-Code + PKCE (desktop loopback / mobile AppAuth); Device Grant for
  headless; relying party to Entra/Okta/Ping/Google/Keycloak. **Free, never paywalled.**
- `later` `[server]` **Self-hosted control plane** (`airclone-server`): admin console + fleet + RBAC +
  SCIM 2.0 + signed-policy-bundle distribution + audit aggregation; clients enroll only via
  admin-supplied `controlPlaneUrl`. **Paid (self-host).**
- `later` `[server]` **Headless/HA**: single binary supervising `rcd` + served web UI; Helm + systemd;
  durable job store; **active/passive only** (rclone is single-writer per state dir); declarative
  GitOps apply; `/metrics` + `/healthz` + Grafana/alerts.
- `later` `[D]` **FIPS build** (force TLS ≥ 1.2; label `crypt` non-FIPS); SOC 2 for the control plane;
  LTS line; commercial MSA/indemnification.

> **Open decisions (need sign-off):** (1) commercial model — recommended **hybrid open-core**
> (free OSS client incl. all security; paid self-hosted control plane); (2) **defer** the management
> plane until a design partner commits. **License decided: GNU AGPLv3** (2026-06-28). See
> [19-enterprise-readiness.md §4](../../wiki/core/19-enterprise-readiness.md).

## ⌨️ REM wishlist parity (user-requested)

From the user's own REM feature requests:
- ✅ **Multi-select** files/folders for bulk copy/move/delete (REM #20) — *done in Airclone*.
- ✅ **Folders shown first** in listings (REM #10) — *done in Airclone*.
- ✅ **Keyboard shortcuts + navigation** (REM #9): back/forward **history** (Alt+← / Alt+→), up (Alt+↑),
  **filter box** via **Ctrl+F** — *done a5*; plus tabs (Ctrl+T/W a17) + type-to-navigate (a20).

## 🏆 Differentiators — Airclone's edge

Positioning, not a status list — so each line is marked for what is **true today** vs. still **aimed at**,
because a differentiator that isn't built yet is a plan, and reading it as a fact is how this file drifted.

1. **True cross-platform incl. mobile, one codebase** (Flutter) — desktop + Android/iOS with a shared
   `RcloneClient`. **True today** (v0.7.6 ships on Play, the Microsoft Store, and both Apple stores).
2. **Best-in-class mobile "appears in system Files"** — SAF-grade `DocumentsProvider` + iOS File
   Provider, plus media-picker visibility. **Aimed at, not built** — all three are verified absent.
   What ships today is per-file hand-off out of Airclone (`state/open_external.dart`), not remotes
   mounted into the system Files app.
3. **In-process librclone, hybrid by design** — no RC port to secure where a subprocess is illegal;
   desktop keeps the swappable binary for crash isolation + independent upgrades. **True today**, with
   one correction to the old phrasing: it is not "no subprocess on mobile" — **iOS/MAS** run
   in-process (`resolveEngineMode` forces it), while **Android runs the bundled binary as a
   subprocess**.
4. **Modern UX with progressive disclosure** — a real design system, an Easy ⇄ Advanced toggle, and
   per-OS skins. **True today.**
5. **Safety-first transfers** — `--max-delete` guard, compare-before-sync, recoverable delete, and a
   conflict prompt on every path that can overwrite. **True today**, except that dry-run is **opt-in,
   not mandatory** — the forced preview exists only on "Sync to here". Say "safety-first", not
   "mandatory dry-run", until that changes.
6. **Open-source + privacy headline** — local-only, no telemetry. **True today**, and load-bearing:
   `state/diagnostics.dart` redacts at ingest and there is no egress path at all.
7. **Engineering rigor** — automated tests for the engine lifecycle + RC integration (102 test files in
   `app/test/`), restart as a first-class tested op, structured OAuth. **True today** — except **i18n,
   which does not exist**; drop "from day one" until there is a `l10n` directory.
8. **Free where it matters** — all manual power (dual-pane, drag-drop, mount, compare, dry-run) free;
   the premium story is mobile + cleaner UX, not gating basics. **True today.**
