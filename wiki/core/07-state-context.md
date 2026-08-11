---
type: "core"
name: "State & Context"
status: "stable"
dependencies: ["08-core-architecture", "14-performance-standards"]
description: "The Riverpod provider graph: which provider owns which state, where it lives, what mutates it, what it persists, and the lifecycle traps."
---

# 🧩 State & Context

The complete map of Airclone's app state: every provider, its file, its state shape, the controller
methods that mutate it, and where it persists.

**When to read this:** before you add or change any app state — a new setting, a new panel, a new
cached server value — or when you need to find "which provider owns X" without reading
`app/lib/src/` end to end.

---

## 🧭 Conventions (read first)

| Rule | Detail |
| :--- | :--- |
| **Framework** | Riverpod 2 (`flutter_riverpod`) with the modern `Notifier` / `NotifierProvider` API **only**. |
| **Not used** | No `riverpod_generator` / code-gen, no `StateNotifierProvider`, no `ChangeNotifierProvider`, no `AsyncNotifierProvider`. Do not introduce them. |
| **Naming** | Every top-level provider is named `<thing>Provider`. 80 public providers + 1 private (`_transferInFlightProvider` in [ui/paste_action.dart](../../app/lib/src/ui/paste_action.dart)). |
| **Location** | 75 live in [app/lib/src/state/](../../app/lib/src/state/); 5 UI-local ones live beside their widget in `app/lib/src/ui/`. New state belongs in `state/` unless it is purely one widget's chrome. |
| **Root** | The graph is rooted at `engineControllerProvider`. Every server-state provider starts with `ref.read/watch(engineControllerProvider).client` and returns an **empty value when it is null** — never throws, never blocks. |
| **Persisted scalar idiom** | A `Notifier<T>` whose `build()` fires an unawaited `_load()` and returns the default **synchronously**, plus `Future<void> set(T)` that assigns `state` then writes SharedPreferences inside a swallowing `try/catch`. Canonical example: [state/advanced_mode.dart](../../app/lib/src/state/advanced_mode.dart). |
| **`ensureLoaded()`** | Providers whose value is read at *startup decision time* also expose an idempotent `Future<void> ensureLoaded()` caching a single `_loading` future — see [settings_controller.dart](../../app/lib/src/state/settings_controller.dart), [config_password_vault.dart](../../app/lib/src/state/config_password_vault.dart), [biometric_unlock.dart](../../app/lib/src/state/biometric_unlock.dart). Callers making a boot-time branch **must await it** (see Traps). |
| **`autoDispose`** | Used exactly once, deliberately: `recentTransfersProvider`. Everything else is app-lifetime. |

The engine seam itself (`RcloneClient`, transports, restart semantics) is owned by
[08-core-architecture.md](08-core-architecture.md). Concurrency budgets and poller cadence rationale
live in [14-performance-standards.md](14-performance-standards.md). Do not restate either here.

---

## 📇 Provider index

Paths are relative to `app/lib/src/`. Line numbers are the declaration site at time of writing.

### Engine & configuration lifecycle

| Provider | File | Kind → state | Owns / mutated by |
| :--- | :--- | :--- | :--- |
| `engineControllerProvider` | [state/engine_controller.dart:605](../../app/lib/src/state/engine_controller.dart) | `NotifierProvider<EngineController, EngineUi>` | **Root of the graph.** Locates/provisions rclone, gates on config encryption, spawns the engine, exposes `state.client`. Methods: `bootstrap`, `installAndStart`, `unlockAndStart`, `restartEngine`, `switchConfigAndStart`, `switchEngineAndStart`, `updateEngine`, `quiesceForConfigOp`, `reloadWithConfigPassword`. |
| `settingsControllerProvider` | [state/settings_controller.dart:151](../../app/lib/src/state/settings_controller.dart) | `NotifierProvider<SettingsController, SettingsState>` | `themeMode`, `rclonePathOverride`, `configPathOverride`, `engineMode`. `setThemeMode` / `setRclonePath` / `setConfigPathOverride` / `setEngineMode`; `ensureLoaded()`. |
| `engineFlagsProvider` | [state/engine_flags.dart:36](../../app/lib/src/state/engine_flags.dart) | `NotifierProvider<EngineFlags, String>` | Raw extra argv appended to the spawned `rclone rcd`. `set(String)`. |
| `configTransferControllerProvider` | [state/config_transfer_controller.dart:972](../../app/lib/src/state/config_transfer_controller.dart) | `Provider<ConfigTransferController>` | Config import / export / merge / replace / encryption applied **to the config file itself** (the one sanctioned out-of-band writer — see Traps). |
| `configBackupsProvider` | [state/config_backups.dart:167](../../app/lib/src/state/config_backups.dart) | `FutureProvider<ConfigBackups>` | Rolling config backups under `<appSupport>/config-backups`. Fully injectable (dir + clock) for tests. |
| `appVersionProvider` | [state/app_info.dart:11](../../app/lib/src/state/app_info.dart) | `FutureProvider<String>` | Package version string. |
| `updateCheckProvider` | [state/app_info.dart:76](../../app/lib/src/state/app_info.dart) | `FutureProvider<UpdateStatus>` | App update availability. **Sealed** result: `StoreManagedUpdates` (no network call at all) or `ReleaseUpdateInfo` (the GitHub check). Branches on `installSourceProvider` — see [10-external-integrations.md §5.1](10-external-integrations.md). |
| `installSourceProvider` | [state/install_source.dart:295](../../app/lib/src/state/install_source.dart) | `FutureProvider<InstallSource>` | How this copy was installed (MSIX / Play / Amazon / F-Droid / Galaxy / App Store / Flathub / Snap / direct). A store-managed install must never be shown an out-of-store download link. |
| `externalBackupProvider` | [state/external_config_backup.dart:488](../../app/lib/src/state/external_config_backup.dart) | `NotifierProvider<ExternalConfigBackup, ExternalBackupState>` | "Survive uninstall" (Android): the opt-in encrypted copy of the config in shared storage. `enableEncrypted`, `enablePlaintext`, `disable`, `backupNow`, `refreshIfStale`. Self-refreshes off a `ref.listen(remotesProvider)`. |
| `externalBackupVaultProvider` | [state/external_config_backup.dart:193](../../app/lib/src/state/external_config_backup.dart) | `Provider<ExternalBackupPassphraseVault>` | OS-vault slot for the backup passphrase, so the refresh runs unattended. Overridden in tests. |
| `restorableBackupProvider` | [state/external_config_backup.dart:564](../../app/lib/src/state/external_config_backup.dart) | `FutureProvider<FoundBackup?>` | A backup **and** an empty config ⇒ a fresh install after an uninstall; drives the startup restore offer. Watches `allFilesAccessProvider` too — a fresh install has no storage permission at launch. |
| `externalBackupFileProvider` | [state/external_config_backup.dart:543](../../app/lib/src/state/external_config_backup.dart) | `FutureProvider<FoundBackup?>` | Whether a backup FILE exists, regardless of the mode. The two come apart after a reinstall (prefs are wiped, the file is not), and Settings must say so. |

### Browser panes & navigation

| Provider | File | Kind → state | Owns / mutated by |
| :--- | :--- | :--- | :--- |
| `browserAProvider` | [state/browser_controller.dart:456](../../app/lib/src/state/browser_controller.dart) | `NotifierProvider<BrowserController, BrowserState>` | Pane 0 (left / top). |
| `browserBProvider` | [state/browser_controller.dart:459](../../app/lib/src/state/browser_controller.dart) | same type | Pane 1 (right / bottom). |
| `activePaneProvider` | [state/browser_controller.dart:465](../../app/lib/src/state/browser_controller.dart) | `StateProvider<int>` | Which pane (0/1) sidebar clicks and cross-pane copies target. |
| `paneFilterFocusProvider` | [state/browser_controller.dart:472](../../app/lib/src/state/browser_controller.dart) | `Provider.family<FocusNode, int>` | App-lifetime `FocusNode` per pane's Ctrl+F box; disposes it in `ref.onDispose`. |
| `pathEditRequestProvider` | [state/browser_controller.dart:481](../../app/lib/src/state/browser_controller.dart) | `StateProvider.family<int, int>` | A monotonic tick bumped by Ctrl+L / Alt+D to pop the address bar into edit mode. |
| `paneScrollProvider` | [state/browser_controller.dart:487](../../app/lib/src/state/browser_controller.dart) | `Provider.family<ScrollController, int>` | App-lifetime `ScrollController` per pane; disposes it in `ref.onDispose`. |
| `viewMemoryProvider` | [state/view_memory.dart:96](../../app/lib/src/state/view_memory.dart) | `NotifierProvider<ViewMemory, Map<String, ViewPref>>` | Per-remote last view mode / sort / density. `remember(name, pref)` (skips a no-change write), `prefFor(name)`. |
| `clipboardControllerProvider` | [state/clipboard_controller.dart:82](../../app/lib/src/state/clipboard_controller.dart) | `NotifierProvider<ClipboardController, ClipboardItems>` | Copy/cut staging shared by both panes. `copy`, `cut`, `clear`. Pure state — the paste integrator performs the transfer. |
| `recentLocationsProvider` | [state/recent_locations.dart:39](../../app/lib/src/state/recent_locations.dart) | `NotifierProvider<RecentLocations, List<RecentLocation>>` | Session-only MRU, capped at 12. `record(remote, path)`. |

> `paneProvider(int index)` at [browser_controller.dart:468](../../app/lib/src/state/browser_controller.dart)
> is a plain **top-level function**, not a provider. It returns `browserA`/`browserB` and is the
> canonical way UI code reaches a pane (~112 call sites in `ui/`).

### Layout & shell chrome

| Provider | File | Kind → state | Notes |
| :--- | :--- | :--- | :--- |
| `paneSplitRatioProvider` | [state/pane_layout.dart:100](../../app/lib/src/state/pane_layout.dart) | `NotifierProvider<PaneSplitRatio, double>` | Persisted, clamped. |
| `paneSplitOrientationProvider` | [state/pane_layout.dart:144](../../app/lib/src/state/pane_layout.dart) | `NotifierProvider<…, PaneSplitOrientation>` | `adaptive` / `sideBySide` / `stacked`, persisted. |
| `mobileSplitProvider` | [state/pane_layout.dart:152](../../app/lib/src/state/pane_layout.dart) | `StateProvider<bool>` | Phone-only second-pane opt-in; session only. |
| `singlePaneProvider` | [ui/home_screen.dart:64](../../app/lib/src/ui/home_screen.dart) | `StateProvider<bool>` | Desktop single vs dual pane (default `true`). |
| `sidebarVisibleProvider` | [ui/home_screen.dart:67](../../app/lib/src/ui/home_screen.dart) | `StateProvider<bool>` | |
| `sidebarWidthProvider` | [ui/home_screen.dart:70](../../app/lib/src/ui/home_screen.dart) | `StateProvider<double>` | Default 240. |
| `inspectorVisibleProvider` | [ui/inspector_panel.dart:26](../../app/lib/src/ui/inspector_panel.dart) | `StateProvider<bool>` | |
| `columnWidthsProvider` | [ui/column_header.dart:141](../../app/lib/src/ui/column_header.dart) | `NotifierProvider<ColumnWidthsController, ColumnWidths>` | Persisted Size / Modified column widths (clamped on load). |
| `skinProvider` | [state/skin.dart:47](../../app/lib/src/state/skin.dart) | `NotifierProvider<SkinController, Skin>` | Defaults to `Skin.forHost()`; a persisted choice always wins. |
| `windowBackdropProvider` | [state/window_backdrop.dart:99](../../app/lib/src/state/window_backdrop.dart) | `NotifierProvider<…, WindowBackdrop>` | Desktop Mica/Acrylic. `loadSavedBackdrop()` reads the same key **before the provider graph exists**, to apply the effect pre-first-frame. |
| `advancedModeProvider` | [state/advanced_mode.dart:35](../../app/lib/src/state/advanced_mode.dart) | `NotifierProvider<AdvancedMode, bool>` | Gates advanced affordances (Serve/Mount entry points, etc.). |

### Jobs, transfers & stats

| Provider | File | Kind → state | Owns / mutated by |
| :--- | :--- | :--- | :--- |
| `jobsControllerProvider` | [state/jobs_controller.dart:280](../../app/lib/src/state/jobs_controller.dart) | `NotifierProvider<JobsController, List<Job>>` | The **one 1 Hz job poller** + the transfer concurrency queue. `add`, `enqueue`, `update`, `markDone`, `remove`, `clearFinished`, `stop`, `pumpQueue`, `registerCancel`/`unregisterCancel`. |
| `queuePausedProvider` | [state/jobs_controller.dart:298](../../app/lib/src/state/jobs_controller.dart) | `NotifierProvider<QueuePaused, bool>` | Session only — deliberately **not** persisted (a paused queue surviving a restart is a trap). `toggle()`. |
| `transferConcurrencyProvider` | [state/jobs_controller.dart:336](../../app/lib/src/state/jobs_controller.dart) | `NotifierProvider<TransferConcurrency, int>` | `0` = unlimited. Persisted; `set()` re-pumps the queue. |
| `statsProvider` | [state/stats_controller.dart:83](../../app/lib/src/state/stats_controller.dart) | `NotifierProvider<StatsController, CoreStats>` | 1 Hz `core/stats`; keeps the last good snapshot on any failure. |
| `transferServiceProvider` | [state/transfer_service.dart:220](../../app/lib/src/state/transfer_service.dart) | `Provider<TransferService>` | Dispatches transfers with `_async: true` and `_group: 'airclone/<local jobId>'`. |
| `recentTransfersProvider` | [state/recent_activity_controller.dart:10](../../app/lib/src/state/recent_activity_controller.dart) | `FutureProvider.autoDispose<List<TransferredItem>>` | `core/transferred`. The **only** autoDispose provider; the panel refreshes by invalidating it. |
| `transferForegroundServiceProvider` | [state/android_transfer_service.dart:17](../../app/lib/src/state/android_transfer_service.dart) | `Provider<void>` | Side-effect-only: `ref.listen`s jobs and drives the Android `dataSync` foreground service over `MethodChannel('airclone/native')`. No-op off Android. |
| `fileOpsProvider` | [state/file_ops.dart:175](../../app/lib/src/state/file_ops.dart) | `Provider<FileOps>` | Single-shot non-streaming mutations (create / rename / delete). Long transfers belong to jobs. |
| `archiveServiceProvider` | [state/archive_service.dart:214](../../app/lib/src/state/archive_service.dart) | `Provider<ArchiveService>` | `rclone archive create/extract/list` as a **subprocess** (no RC method exists); tracked as `JobType.archive`. |

### Remotes & server-state caches

| Provider | File | Kind → state | Backing RC call |
| :--- | :--- | :--- | :--- |
| `remotesProvider` | [state/remotes_provider.dart:10](../../app/lib/src/state/remotes_provider.dart) | `FutureProvider<List<Remote>>` | `config/dump`, plus a synthetic `localHomeRemote()` peer (suppressed on Android). |
| `providersProvider` | [state/providers_provider.dart:8](../../app/lib/src/state/providers_provider.dart) | `FutureProvider<List<RcloneProvider>>` | `config/providers` — powers the dynamic add-remote forms. |
| `remoteAboutProvider` | [state/remote_about.dart:18](../../app/lib/src/state/remote_about.dart) | `FutureProvider.family<RemoteAbout?, String>` | `operations/about`, keyed by fs. |
| `remoteFeaturesProvider` | [state/remote_features.dart:8](../../app/lib/src/state/remote_features.dart) | `FutureProvider.family<Map<String,bool>, String>` | `operations/fsinfo` → `Features`; used to capability-gate UI. |
| `drivesProvider` | [state/local_locations.dart:137](../../app/lib/src/state/local_locations.dart) | `Provider<List<LocalLocation>>` | Auto-detected local disks — synchronous, no engine needed. |
| `userLocationsProvider` | [state/local_locations.dart:249](../../app/lib/src/state/local_locations.dart) | `NotifierProvider<UserLocations, List<LocalLocation>>` | Persisted, seeded with defaults on first run. |
| `collapsedSectionsProvider` | [state/local_locations.dart:293](../../app/lib/src/state/local_locations.dart) | `NotifierProvider<CollapsedSections, Set<String>>` | Persisted sidebar section collapse. |
| `bookmarksProvider` | [state/bookmarks_controller.dart:115](../../app/lib/src/state/bookmarks_controller.dart) | `NotifierProvider<BookmarksController, List<Bookmark>>` | Persisted "Favorites", most-recently-pinned first. |
| `allFilesAccessProvider` | [state/android_native.dart:29](../../app/lib/src/state/android_native.dart) | `FutureProvider<bool>` | Android all-files-access permission state. |

### Mount, serve & policy kill-switches

| Provider | File | Kind → state | Notes |
| :--- | :--- | :--- | :--- |
| `mountControllerProvider` | [state/mount_controller.dart:147](../../app/lib/src/state/mount_controller.dart) | `NotifierProvider<MountController, List<MountInfo>>` | 2 s `mount/listmounts` poll. `mount`, `unmount`, `unmountAll`, `unmountAllForExit`, `refreshCache`. **Nothing is persisted**, so mounts never auto-resurrect. |
| `mountTypesProvider` | [state/mount_controller.dart:12](../../app/lib/src/state/mount_controller.dart) | `FutureProvider<List<String>>` | Empty on Windows ⇒ WinFsp missing. |
| `mountEnabledProvider` | [state/mount_policy.dart:7](../../app/lib/src/state/mount_policy.dart) | `Provider<bool>` (hard-coded `true`) | MDM/enterprise kill-switch seam, meant to be **overridden**, not edited. |
| `serveControllerProvider` | [state/serve_controller.dart:157](../../app/lib/src/state/serve_controller.dart) | `NotifierProvider<ServeController, List<ServeServer>>` | 2 s `serve/list` poll. `start`, `stop`, `panicStopAll`. |
| `serveTypesProvider` | [state/serve_controller.dart:17](../../app/lib/src/state/serve_controller.dart) | `FutureProvider<List<String>>` | Curated set ∩ `serve/types`. |
| `lanIpProvider` | [state/serve_controller.dart:34](../../app/lib/src/state/serve_controller.dart) | `FutureProvider<String?>` | Display only — never used as a bind address. |
| `serveEnabledProvider` | [state/serve_policy.dart:9](../../app/lib/src/state/serve_policy.dart) | `Provider<bool>` (hard-coded `true`) | Same kill-switch pattern. `panicStopAll()` stays callable when disabled. |

Both kill-switches are re-checked **inside** `MountController.mount()` and `ServeController.start()`,
not only in the UI — flipping one to `false` refuses new mounts/servers rather than merely hiding a
button. Overriding either is the enterprise-deployment lever described in
[19-enterprise-readiness.md](19-enterprise-readiness.md).

### Security & secrets

| Provider | File | Kind → state | Notes |
| :--- | :--- | :--- | :--- |
| `cachePassphraseProvider` | [state/cache_crypto.dart:13](../../app/lib/src/state/cache_crypto.dart) | `StateProvider<String?>` | The live rclone config password. Set by `EngineController._startWith`; **never persisted**. |
| `cacheCryptoProvider` | [state/cache_crypto.dart:83](../../app/lib/src/state/cache_crypto.dart) | `Provider<CacheCrypto>` | AES-256-GCM, key via PBKDF2-HMAC-SHA256 (50 000 iterations, fixed app salt `airclone::cache::v1`). Key source = config password when set, else a hash of the remote name (**obfuscation only**). |
| `cacheMemoryOnlyProvider` | [state/cache_crypto.dart:116](../../app/lib/src/state/cache_crypto.dart) | `NotifierProvider<CacheMemoryOnly, bool>` | When `true`, nothing is written to disk. |
| `configPasswordVaultProvider` | [state/config_password_vault.dart:77](../../app/lib/src/state/config_password_vault.dart) | `Provider<ConfigPasswordVault>` | `flutter_secure_storage`, one key: `airclone.configPassword`. `read` / `save` / `clear`. |
| `rememberConfigPasswordProvider` | [state/config_password_vault.dart:128](../../app/lib/src/state/config_password_vault.dart) | `NotifierProvider<RememberConfigPassword, bool>` | Default **off**. Has `ensureLoaded()`. |
| `biometricUnlockProvider` | [state/biometric_unlock.dart:83](../../app/lib/src/state/biometric_unlock.dart) | `Provider<BiometricUnlock>` | `local_auth` wrapper: `available()`, `authenticate()`. |
| `biometricUnlockOptInProvider` | [state/biometric_unlock.dart:151](../../app/lib/src/state/biometric_unlock.dart) | `NotifierProvider<BiometricUnlockOptIn, bool>` | Default **off**. Biometric adds no crypto — it only *releases* the vault secret. |

Threat model and the full secrets posture live in [15-security.md](15-security.md).

### Thumbnails & previews

| Provider | File | Kind → state | Notes |
| :--- | :--- | :--- | :--- |
| `thumbnailServiceProvider` | [state/thumbnail_service.dart:307](../../app/lib/src/state/thumbnail_service.dart) | `Provider<ThumbnailService>` | Bounded concurrency + in-flight dedup + a session-scoped "undecodable" negative cache. Two gates: a general one and a stricter video-keyframe one, always taken in that order. |
| `thumbnailReloadProvider` | [state/thumbnail_reload.dart:67](../../app/lib/src/state/thumbnail_reload.dart) | `NotifierProvider<…, ThumbnailReloadSignal>` | Carries only a `tick` + `force` epoch — deliberately **not** per-item progress, so tiles wake rarely. `reload()`, `rebuild()`, `prewarm()` (batched). |
| `thumbnailsDisabledProvider` | [state/thumbnail_prefs.dart:59](../../app/lib/src/state/thumbnail_prefs.dart) | `NotifierProvider<ThumbnailPrefs, Set<String>>` | Per-remote **opt-out** keyed by fs — thumbnails are on by default. `toggle(fs)`, `isDisabled(fs)`. |
| `folderPreviewServiceProvider` | [state/folder_preview.dart:223](../../app/lib/src/state/folder_preview.dart) | `Provider<FolderPreviewService>` | Composites a folder's images into a 2×2 card thumbnail, sealed + disk-cached. |

Exact slot counts, timeouts and batch sizes are budgets, not state — they belong to
[14-performance-standards.md](14-performance-standards.md). Content reads must additionally respect
the cloud-hydration guard in [state/cloud_placeholder.dart](../../app/lib/src/state/cloud_placeholder.dart).

### Tasks, scheduler & bandwidth

| Provider | File | Kind → state | Notes |
| :--- | :--- | :--- | :--- |
| `tasksProvider` | [state/tasks_controller.dart:278](../../app/lib/src/state/tasks_controller.dart) | `NotifierProvider<TasksController, List<TransferTask>>` | Persisted saved transfers with stable string ids and a per-task run history capped at 10. `add`, `update`, `remove`, `recordRun`. |
| `schedulerProvider` | [state/scheduler_controller.dart:291](../../app/lib/src/state/scheduler_controller.dart) | `NotifierProvider<SchedulerController, SchedulerStatus>` | 30 s tick, in-memory only. Runs due tasks **while the app is open**; stamps `lastRun` before the async kickoff so a tick can't double-fire; records `skippedWhileUnavailable` when the engine is down. |
| `bandwidthControllerProvider` | [state/bandwidth_controller.dart:53](../../app/lib/src/state/bandwidth_controller.dart) | `NotifierProvider<…, BandwidthState>` | Live `core/bwlimit`. `setLimit(rate)`. |
| `bwScheduleControllerProvider` | [state/bw_schedule_controller.dart:72](../../app/lib/src/state/bw_schedule_controller.dart) | `NotifierProvider<…, BwSchedule>` | Persisted timetable + a 60 s applier. `setEnabled`, `setWindows`. |
| `windowsTaskSchedulerProvider` | [state/windows_task_scheduler.dart:272](../../app/lib/src/state/windows_task_scheduler.dart) | `Provider<WindowsTaskScheduler>` | `schtasks` register / unregister / isRegistered for headless runs. Windows-only; silently no-ops elsewhere. Has a `ProcessRunner` seam for tests. |

### Wizards, console & OS integration

| Provider | File | Kind → state | Notes |
| :--- | :--- | :--- | :--- |
| `addRemoteControllerProvider` | [state/add_remote_controller.dart:265](../../app/lib/src/state/add_remote_controller.dart) | `NotifierProvider<AddRemoteController, AddRemoteState>` | The `config/create`+`config/update` interactive/OAuth state machine (`AddPhase`). |
| `encryptRemoteControllerProvider` | [state/encrypt_remote_controller.dart:230](../../app/lib/src/state/encrypt_remote_controller.dart) | `NotifierProvider<…, EncryptRemoteState>` | Wrap-an-existing-remote-in-`crypt` wizard (`EncryptPhase`). |
| `consoleControllerProvider` | [state/console/console_controller.dart:578](../../app/lib/src/state/console/console_controller.dart) | `NotifierProvider.family<ConsoleController, ConsoleState, String>` | Keyed by a stable console id minted per console tab. **Not autoDispose** — `BrowserController.closeTab` must `stop()` + `invalidate()` it (see Traps). |
| `osIntegrationProvider` | [state/os_integration.dart:136](../../app/lib/src/state/os_integration.dart) | `Provider<OsIntegration>` | Reveal-in-file-manager, open-with-default-app (`url_launcher`), copy path. |
| `downloadDirProvider` | [state/download_settings.dart:39](../../app/lib/src/state/download_settings.dart) | `NotifierProvider<DownloadDir, String?>` | Remembered download folder; clearing removes the key. |
| `downloadAlwaysPromptProvider` | [state/download_settings.dart:73](../../app/lib/src/state/download_settings.dart) | `NotifierProvider<DownloadAlwaysPrompt, bool>` | |
| `diagnosticsProvider` | [state/diagnostics.dart:189](../../app/lib/src/state/diagnostics.dart) | `NotifierProvider<DiagnosticsLog, List<DiagEntry>>` | The local, no-telemetry problem log (Settings → Diagnostics). Bounded ring; **redaction runs at ingest** inside `record()`. `logDiagnostic()` is the `Ref`-free sink for the error hooks in [ui/app.dart](../../app/lib/src/ui/app.dart). See [15-security.md §5.1](15-security.md). |

### Pure modules in `state/` (no provider)

These are provider-free, unit-testable logic used by the controllers above. Prefer adding logic here
over inside a `Notifier` — the test suite reaches these directly:
[archive_command.dart](../../app/lib/src/state/archive_command.dart) ·
[bw_schedule.dart](../../app/lib/src/state/bw_schedule.dart) ·
[cloud_placeholder.dart](../../app/lib/src/state/cloud_placeholder.dart) ·
[config_encryption.dart](../../app/lib/src/state/config_encryption.dart) ·
[config_io.dart](../../app/lib/src/state/config_io.dart) ·
[dedupe.dart](../../app/lib/src/state/dedupe.dart) ·
[diagnostics.dart](../../app/lib/src/state/diagnostics.dart) (redaction + report rendering) ·
[engine_mode.dart](../../app/lib/src/state/engine_mode.dart) ·
[external_config_backup.dart](../../app/lib/src/state/external_config_backup.dart) (paths + mode mapping) ·
[install_source.dart](../../app/lib/src/state/install_source.dart) (installer-id → channel + store links) ·
[name_conflict.dart](../../app/lib/src/state/name_conflict.dart) ·
[offline_qr.dart](../../app/lib/src/state/offline_qr.dart) ·
[open_external.dart](../../app/lib/src/state/open_external.dart) ·
[remote_summary.dart](../../app/lib/src/state/remote_summary.dart) ·
[task_schedule.dart](../../app/lib/src/state/task_schedule.dart) ·
[transfer_options.dart](../../app/lib/src/state/transfer_options.dart) ·
plus the console helpers in [state/console/](../../app/lib/src/state/console/).

---

## 🗂️ Pane state in detail

`BrowserController` is the one genuinely non-trivial state shape, so it gets its own section.

- A controller holds a **private `List<_Session>`** of tabs. Each `_Session` carries its own
  `BrowserState`, its own back/forward `history` + `idx`, a `PaneKind` (`browser` or `console`), and
  a `consoleId`.
- The public `state` is an **overlay**: the active session's `BrowserState`, `copyWith`-ed to carry
  `tabs` (a `List<TabInfo>`) and `activeTab`. Call sites and the tab strip therefore see one coherent
  snapshot; they never reach into a session.

| `BrowserState` field | Meaning |
| :--- | :--- |
| `remote`, `path` | Current location. `null` remote = nothing open (**or** a console tab — check `activeIsConsole`). |
| `entries`, `loading`, `error` | The listing from `operations/list`. |
| `selected` (`Set<String>`), `filter` | Multi-selection by name; live client-side Ctrl+F filter. |
| `sortKey`, `ascending`, `viewMode`, `gridSize` | Per-pane view; persisted per remote via `viewMemoryProvider`. |
| `tabs`, `activeTab` | Overlaid tab metadata (see above). |
| derived | `segments`, `visibleEntries`, `selectedEntries`, `isSelected(name)`, `activeIsConsole`. |

Mutators: `newTab` / `newConsoleTab` / `switchTab` / `closeTab`; `open(remote)`, `enterDir`,
`goToSegment`, `up`, `navigateTo`, `back`, `forward`, `refresh`, `clear`; `setFilter`,
`toggleSelect`, `clearSelection`, `selectOnly`, `selectAll`; `setViewMode`, `setGridSize`, `setSort`.

Explorer-level design intent for these panes lives in [20-explorer-design.md](20-explorer-design.md).

---

## 💾 Persistence map

Three backing stores, plus rclone's own config which this layer does **not** own.

### SharedPreferences (27 keys)

| Key | Provider | Encoding |
| :--- | :--- | :--- |
| `advanced_mode` | `advancedModeProvider` | bool |
| `biometric_unlock` | `biometricUnlockOptInProvider` | bool |
| `bookmarks` | `bookmarksProvider` | JSON string |
| `bw_schedule` | `bwScheduleControllerProvider` | JSON string |
| `cache_memory_only` | `cacheMemoryOnlyProvider` | bool |
| `col_w_size`, `col_w_modified` | `columnWidthsProvider` | double |
| `collapsed_sidebar_sections` | `collapsedSectionsProvider` | JSON string |
| `configPath` | `settingsControllerProvider` | string; **removed** when cleared |
| `download_dir` | `downloadDirProvider` | string |
| `download_always_prompt` | `downloadAlwaysPromptProvider` | bool |
| `engineMode` | `settingsControllerProvider` | enum name |
| `engine_flags` | `engineFlagsProvider` | string |
| `external_backup_mode` | `externalBackupProvider` | enum name (`off`/`encrypted`/`plaintext`) |
| `external_backup_digest` | `externalBackupProvider` | string — SHA-256 of the last config written, so an unchanged config is not re-sealed |
| `pane_split_ratio` | `paneSplitRatioProvider` | double |
| `pane_split_orientation` | `paneSplitOrientationProvider` | enum name |
| `rclonePath` | `settingsControllerProvider` | string |
| `remember_config_password` | `rememberConfigPasswordProvider` | bool |
| `skin` | `skinProvider` | enum name |
| `themeMode` | `settingsControllerProvider` | enum name |
| `thumb_disabled` | `thumbnailsDisabledProvider` | JSON string (list of fs) |
| `transfer_concurrency` | `transferConcurrencyProvider` | int |
| `transfer_tasks` | `tasksProvider` | JSON string |
| `user_locations` | `userLocationsProvider` | JSON string |
| `view_memory_v1` | `viewMemoryProvider` | JSON string |
| `window_backdrop` | `windowBackdropProvider` | enum name |

Every read and write is wrapped in a swallowing `try/catch`: a preferences failure degrades to the
default, it never surfaces as an error. Enum values persist by `.name` and resolve with an
`orElse` fallback, so an unknown/renamed value silently reverts to the default rather than throwing.

### Secure storage

Two `flutter_secure_storage` keys, both opt-in and both cleared when their feature is turned off:

| Key | Owner | Written when |
| :--- | :--- | :--- |
| `airclone.configPassword` | `ConfigPasswordVault` | An interactive unlock (or an encryption change) **and** `rememberConfigPasswordProvider` is on. |
| `airclone.externalBackupPassphrase` | `ExternalBackupPassphraseVault` | "Survive uninstall" is enabled with a passphrase, so the backup can refresh unattended. Destroyed with the app on uninstall — a restore then requires typing it, which is the intended behaviour. |

### Encrypted disk caches

| Cache | Location | Sealed by |
| :--- | :--- | :--- |
| Thumbnails | `<appCache>/airclone_thumbs/` (falls back to the temp dir) | `CacheCrypto` (AES-256-GCM) |
| Folder previews | `<appCache>/airclone_folderthumbs/` | `CacheCrypto` |
| Config backups | `<appSupport>/config-backups` | not encrypted — a copy of the config file as-is |

`cacheMemoryOnlyProvider == true` suppresses the disk writes entirely. A wrong-key or corrupt blob
decrypts to `null` and the caller regenerates; a seal failure just skips the write.

### `rclone.conf`

Owned by the engine and mutated through `config/*` RC calls — see
[10-external-integrations.md](10-external-integrations.md). The **single sanctioned exception** is
`ConfigTransferController`, which reads/writes the config file directly for import, replace, restore
and encryption changes. It resolves the active file via its own `_activeConfigFile()` and requires
`EngineController.quiesceForConfigOp()` first (see Traps).

---

## ⏱️ Timers, arming & lifecycle

Six app-lifetime timers exist. Every one is created in `build()` and cancelled in `ref.onDispose`.

| Provider | Interval | Work |
| :--- | :--- | :--- |
| `jobsControllerProvider` | 1 s | `core/stats` (per job group) + `job/status` for every running job |
| `statsProvider` | 1 s | global `core/stats` |
| `mountControllerProvider` | 2 s | `mount/listmounts` |
| `serveControllerProvider` | 2 s | `serve/list` |
| `schedulerProvider` | 30 s | run due tasks |
| `bwScheduleControllerProvider` | 60 s | apply the bandwidth timetable |

Riverpod providers are **lazy**: a timer-owning provider nobody watches never arms. The shell
force-reads the ones with no natural watcher from a post-frame callback in
[ui/home_screen.dart](../../app/lib/src/ui/home_screen.dart) — `schedulerProvider`,
`bwScheduleControllerProvider`, `bookmarksProvider`, `transferForegroundServiceProvider` — alongside
`engineControllerProvider.notifier.bootstrap()`. **Add any new self-driving provider to that list.**

### Two entry points build the graph

| Entry point | Container | Notes |
| :--- | :--- | :--- |
| GUI | `runApp(const ProviderScope(...))` in [app/lib/main.dart](../../app/lib/main.dart) | The scope is never disposed at process exit — see Traps. |
| Headless (`--run-task` / `--run-due`) | a bare `ProviderContainer()` in [src/headless/headless_runner.dart](../../app/lib/src/headless/headless_runner.dart) | No widget tree, no `runApp`. It force-reads the prefs-backed providers it depends on, uses `SharedPreferences.getInstance()` as a hydration sync-point, quits the engine explicitly, then **does** `container.dispose()`. |

---

## 🪤 Traps

1. **The desktop `ProviderScope` is never disposed at process exit**, so
   `EngineController.build`'s `ref.onDispose(() => state.client?.quit())` never fires on a window
   close — on Windows the child `rcd` outlives its parent and holds a handle inside the install
   directory. [ui/app.dart](../../app/lib/src/ui/app.dart) compensates with an
   `AppLifecycleListener(onExitRequested:)` that unmounts (bounded, best-effort) and *then* quits the
   engine. **Never rely on `ref.onDispose` for process-exit cleanup.**
2. **`build()` returns defaults synchronously; the disk value lands a microtask later.** Any
   *start-time decision* on a persisted value must `await ensureLoaded()` first — this is exactly why
   `EngineController._platformSetup` awaits `settingsControllerProvider.notifier.ensureLoaded()`
   before reading `configPathOverride` (otherwise a cold boot spawns against the *default* config).
   The same applies to `rememberConfigPasswordProvider` and `biometricUnlockOptInProvider`.
3. **`consoleControllerProvider` is a non-autoDispose family keyed by a monotonic id.** Dropping a
   console tab without `ref.read(p.notifier).stop()` + `ref.invalidate(p)` leaks the subscription and
   its scrollback for the app's lifetime and orphans a running command. `BrowserController.closeTab`
   already does this; anything else that discards a console id must too.
4. **A stale entry list breaks path building.** Pane operations build paths as
   `state.path + entry.name`, so a listing left over from the previous folder yields 404s and
   "object not found". `_navigate` clears `entries` before loading and `_load` bails when
   `remote`/`path` changed under it (`superseded()`). `refresh()` deliberately does *not* clear, so a
   same-folder reload keeps its list on screen. Preserve both behaviours.
5. **A console tab has `remote == null`.** Any "is this pane showing content?" check must accept
   `BrowserState.activeIsConsole` too, or the phone shell bounces a console back to the locations
   list.
6. **The job stats group is the LOCAL job id, not rclone's `jobid`.** Transfers dispatch with
   `_group: 'airclone/<local id>'`; local ids start at 0 and rclone jobids at 1, so polling
   `core/stats` with an rclone jobid silently reports zero progress. `job/status` correctly takes the
   rclone jobid. Regression-guarded by
   [app/test/jobs_group_test.dart](../../app/test/jobs_group_test.dart).
7. **Never write the config file while the engine is up.** rclone's own OAuth token auto-save is a
   second writer and will race an atomic rename. Call `quiesceForConfigOp()`, do the file work, then
   `reloadWithConfigPassword(...)`.
8. **`restartEngine()` vs `switchConfigAndStart()` are not interchangeable.** The first reuses the
   held password against the *same* file; the second clears the held password and re-runs the
   encryption gate against the *new* config. Using the wrong one leaves a stale password bound to the
   cache or spawns against an encrypted config without ever reaching the gate.
9. **Kill-switch providers are override seams, not constants.** Change deployment behaviour by
   overriding `mountEnabledProvider` / `serveEnabledProvider`, never by editing the `true` literal.
10. **`Provider.family` instances that create disposables must dispose them.**
    `paneFilterFocusProvider` and `paneScrollProvider` both register `ref.onDispose`. Follow that
    pattern for any new family that mints a `FocusNode`, `ScrollController`, or subscription.

---

## 🧪 Testing state

The suite drives providers directly — no widget tree required. The standard shape:

```dart
final c = ProviderContainer(
  overrides: [engineControllerProvider.overrideWith(() => _FakeEngine(spyClient))],
);
addTearDown(c.dispose);
```

`_FakeEngine extends EngineController` and overrides only `build()` to return an
`EngineUi(phase: EnginePhase.ready, client: <fake RcloneClient>)`; the fake client switches on the RC
method string and returns canned JSON. Because every server-state provider reads the client off
`engineControllerProvider`, that single override fakes the whole engine. See
[app/test/jobs_group_test.dart](../../app/test/jobs_group_test.dart) as the reference, and
`pane_layout_test.dart`, `recent_locations_test.dart`, `bookmarks_test.dart` for prefs-backed
notifiers.

---

## 🔗 Related

- [08-core-architecture.md](08-core-architecture.md) — the `RcloneClient` seam, per-platform engines, restart semantics.
- [10-external-integrations.md](10-external-integrations.md) — the RC method surface these providers call, MethodChannels, FFI.
- [14-performance-standards.md](14-performance-standards.md) — poller cadence, concurrency budgets, reliability invariants.
- [15-security.md](15-security.md) — threat model behind `cache_crypto`, the vault, and biometric release.
- [11-validation-standards.md](11-validation-standards.md) — how wizard/console input is validated before it reaches a controller.
- [12-utility-standards.md](12-utility-standards.md) — shared formatters used to render `CoreStats` and `Job`.
- [05-app-structure.md](05-app-structure.md) · [20-explorer-design.md](20-explorer-design.md) — the shell and explorer these providers back.
- [../database/database-index.md](../database/database-index.md) — persistence overview.
- [16-glossary-of-terms.md](16-glossary-of-terms.md) — remote, fs, job group, VFS.
- [00-system-index.md](00-system-index.md) — master router.
