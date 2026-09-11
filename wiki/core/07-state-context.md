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
| **Naming** | Every top-level provider is named `<thing>Provider`. 96 public providers + 2 private, both re-entrancy latches: `_transferInFlightProvider` in [ui/paste_action.dart](../../app/lib/src/ui/paste_action.dart) and `_syncInFlightProvider` in [ui/sync_here_action.dart](../../app/lib/src/ui/sync_here_action.dart). |
| **Location** | 91 live in [app/lib/src/state/](../../app/lib/src/state/); the other 5 public ones (plus both private ones) live beside their widget in `app/lib/src/ui/`. New state belongs in `state/` unless it is purely one widget's chrome. |
| **Root** | The graph is rooted at `engineControllerProvider`. Every server-state provider starts with `ref.read/watch(engineControllerProvider).client` and returns an **empty value when it is null** — never throws, never blocks. |
| **Persisted scalar idiom** | A `Notifier<T>` whose `build()` fires an unawaited `_load()` and returns the default **synchronously**, plus `Future<void> set(T)` that assigns `state` then writes SharedPreferences inside a swallowing `try/catch`. Canonical example: [state/advanced_mode.dart](../../app/lib/src/state/advanced_mode.dart). |
| **`ensureLoaded()`** | Providers whose value is read at *startup decision time* also expose an idempotent `Future<void> ensureLoaded()` caching a single `_loading` future — see [settings_controller.dart](../../app/lib/src/state/settings_controller.dart), [config_password_vault.dart](../../app/lib/src/state/config_password_vault.dart), [biometric_unlock.dart](../../app/lib/src/state/biometric_unlock.dart). Callers making a boot-time branch **must await it** (see Traps). |
| **`autoDispose`** | Used exactly twice, deliberately: `recentTransfersProvider` and `androidWorkStatusProvider` (re-asks WorkManager each time the Settings section opens). Everything else is app-lifetime. |

The engine seam itself (`RcloneClient`, transports, restart semantics) is owned by
[08-core-architecture.md](08-core-architecture.md). Concurrency budgets and poller cadence rationale
live in [14-performance-standards.md](14-performance-standards.md). Do not restate either here.

---

## 📇 Provider index

Paths are relative to `app/lib/src/`. Line numbers are the declaration site at time of writing.

### Engine & configuration lifecycle

| Provider | File | Kind → state | Owns / mutated by |
| :--- | :--- | :--- | :--- |
| `engineControllerProvider` | [state/engine_controller.dart:620](../../app/lib/src/state/engine_controller.dart) | `NotifierProvider<EngineController, EngineUi>` | **Root of the graph.** Locates/provisions rclone, gates on config encryption, spawns the engine, exposes `state.client`. Methods: `bootstrap`, `installAndStart`, `unlockAndStart`, `restartEngine`, `switchConfigAndStart`, `switchEngineAndStart`, `updateEngine`, `quiesceForConfigOp`, `reloadWithConfigPassword`. |
| `settingsControllerProvider` | [state/settings_controller.dart:151](../../app/lib/src/state/settings_controller.dart) | `NotifierProvider<SettingsController, SettingsState>` | `themeMode`, `rclonePathOverride`, `configPathOverride`, `engineMode`. `setThemeMode` / `setRclonePath` / `setConfigPathOverride` / `setEngineMode`; `ensureLoaded()`. |
| `engineFlagsProvider` | [state/engine_flags.dart:36](../../app/lib/src/state/engine_flags.dart) | `NotifierProvider<EngineFlags, String>` | Raw extra argv appended to the spawned `rclone rcd`. `set(String)`. |
| `configTransferControllerProvider` | [state/config_transfer_controller.dart:1058](../../app/lib/src/state/config_transfer_controller.dart) | `Provider<ConfigTransferController>` | Config import / export / merge / replace / encryption applied **to the config file itself** (the one sanctioned out-of-band writer — see Traps). Also owns `removeAllRemotes()` — back up, then `config/delete` every section — which refuses outright when the active config cannot be located to back up. |
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
| `browserAProvider` | [state/browser_controller.dart:848](../../app/lib/src/state/browser_controller.dart) | `NotifierProvider<BrowserController, BrowserState>` | Pane 0 (left / top). |
| `browserBProvider` | [state/browser_controller.dart:851](../../app/lib/src/state/browser_controller.dart) | same type | Pane 1 (right / bottom). |
| `activePaneProvider` | [state/browser_controller.dart:857](../../app/lib/src/state/browser_controller.dart) | `StateProvider<int>` | Which pane (0/1) sidebar clicks and cross-pane copies target. |
| `paneFilterFocusProvider` | [state/browser_controller.dart:864](../../app/lib/src/state/browser_controller.dart) | `Provider.family<FocusNode, int>` | App-lifetime `FocusNode` per pane's Ctrl+F box; disposes it in `ref.onDispose`. |
| `pathEditRequestProvider` | [state/browser_controller.dart:873](../../app/lib/src/state/browser_controller.dart) | `StateProvider.family<int, int>` | A monotonic tick bumped by Ctrl+L / Alt+D to pop the address bar into edit mode. |
| `paneScrollProvider` | [state/browser_controller.dart:879](../../app/lib/src/state/browser_controller.dart) | `Provider.family<ScrollController, int>` | App-lifetime `ScrollController` per pane; disposes it in `ref.onDispose`. |
| `viewMemoryProvider` | [state/view_memory.dart:96](../../app/lib/src/state/view_memory.dart) | `NotifierProvider<ViewMemory, Map<String, ViewPref>>` | Per-remote last view mode / sort / density. `remember(name, pref)` (skips a no-change write), `prefFor(name)`. |
| `clipboardControllerProvider` | [state/clipboard_controller.dart:82](../../app/lib/src/state/clipboard_controller.dart) | `NotifierProvider<ClipboardController, ClipboardItems>` | Copy/cut staging shared by both panes. `copy`, `cut`, `clear`. Pure state — the paste integrator performs the transfer. |
| `recentsEnabledProvider` | [state/recent_locations.dart:46](../../app/lib/src/state/recent_locations.dart) | `NotifierProvider<RecentsEnabled, bool>` | Whether visited folders are remembered at all. **Opt-in, default off** — a trail nobody asked for puts remote and folder names on the Home screen. The *choice* is persisted; the trail is not. |
| `recentLocationsProvider` | [state/recent_locations.dart:94](../../app/lib/src/state/recent_locations.dart) | `NotifierProvider<RecentLocations, List<RecentLocation>>` | Session-only MRU, capped at 12. `record(remote, path)` is a **no-op while `recentsEnabledProvider` is off** — nothing is collected and filtered later. A `ref.listen` on that switch clears the list the moment it goes off. |
| `syncSourceProvider` | [state/sync_source.dart:50](../../app/lib/src/state/sync_source.dart) | `NotifierProvider<SyncSourceController, SyncSource>` | The folder a later "Sync to here" syncs **from**. Session-only, and deliberately **not** a third state on the clipboard: `ClipboardItems.isNotEmpty` drives whether Paste appears, and the two gestures are orthogonal. `mark(remote, path)`, `clear()`. The pure `syncTargetRefusal()` beside it refuses an overlapping source/destination pair outright (case-insensitively) rather than warning. |

> `paneProvider(int index)` at [browser_controller.dart:860](../../app/lib/src/state/browser_controller.dart)
> is a plain **top-level function**, not a provider. It returns `browserA`/`browserB` and is the
> canonical way UI code reaches a pane (~112 call sites in `ui/`).

### Layout & shell chrome

| Provider | File | Kind → state | Notes |
| :--- | :--- | :--- | :--- |
| `paneSplitRatioProvider` | [state/pane_layout.dart:128](../../app/lib/src/state/pane_layout.dart) | `NotifierProvider<PaneSplitRatio, double>` | Persisted, clamped. |
| `paneSplitOrientationProvider` | [state/pane_layout.dart:216](../../app/lib/src/state/pane_layout.dart) | `NotifierProvider<…, PaneSplitOrientation>` | `adaptive` / `sideBySide` / `stacked`, persisted. |
| `mobileSplitProvider` | [state/pane_layout.dart:224](../../app/lib/src/state/pane_layout.dart) | `StateProvider<bool>` | Phone-only second-pane opt-in; session only. |
| `singlePaneProvider` | [ui/home_screen.dart:67](../../app/lib/src/ui/home_screen.dart) | `StateProvider<bool>` | Desktop single vs dual pane (default `true`). |
| `sidebarVisibleProvider` | [ui/home_screen.dart:70](../../app/lib/src/ui/home_screen.dart) | `StateProvider<bool>` | |
| `sidebarWidthProvider` | [ui/home_screen.dart:73](../../app/lib/src/ui/home_screen.dart) | `StateProvider<double>` | Default 240. |
| `inspectorVisibleProvider` | [ui/inspector_panel.dart:26](../../app/lib/src/ui/inspector_panel.dart) | `StateProvider<bool>` | |
| `columnWidthsProvider` | [ui/column_header.dart:141](../../app/lib/src/ui/column_header.dart) | `NotifierProvider<ColumnWidthsController, ColumnWidths>` | Persisted Size / Modified column widths (clamped on load). |
| `jobsDockHeightProvider` | [state/pane_layout.dart:172](../../app/lib/src/state/pane_layout.dart) | `NotifierProvider<JobsDockHeight, double>` | Height of the bottom Transfers dock, persisted **unclamped by viewport** — the widget re-clamps against the live layout every build via the pure `clampJobsDockHeight`, so a dock dragged tall on a big monitor cannot swallow a small one. |
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
| `fileOpsProvider` | [state/file_ops.dart:282](../../app/lib/src/state/file_ops.dart) | `Provider<FileOps>` | Single-shot non-streaming mutations (create / rename / delete), plus the read-only `compare()` (`operations/check`) and `folderSize()` the sync preview is built on. Long transfers belong to jobs. |
| `archiveServiceProvider` | [state/archive_service.dart:229](../../app/lib/src/state/archive_service.dart) | `Provider<ArchiveService>` | `rclone archive create/extract/list` as a **subprocess** (no RC method exists); tracked as `JobType.archive`. |

### Remotes & server-state caches

| Provider | File | Kind → state | Backing RC call |
| :--- | :--- | :--- | :--- |
| `remotesProvider` | [state/remotes_provider.dart:31](../../app/lib/src/state/remotes_provider.dart) | `FutureProvider<List<Remote>>` | `config/dump`, plus a synthetic `localHomeRemote()` peer (suppressed on Android). Also publishes every remote's resolved local backing root to the hydration guard (`setRemoteBackingRoots`, [14 §1](14-performance-standards.md)). The same file exports `existingRemoteNames(client)` — **every `config/create` caller must consult it and fail closed**, because `config/create` on an existing name silently REPLACES that remote. |
| `providersProvider` | [state/providers_provider.dart:8](../../app/lib/src/state/providers_provider.dart) | `FutureProvider<List<RcloneProvider>>` | `config/providers` — powers the dynamic add-remote forms. |
| `remoteAboutProvider` | [state/remote_about.dart:18](../../app/lib/src/state/remote_about.dart) | `FutureProvider.family<RemoteAbout?, String>` | `operations/about`, keyed by fs. |
| `remoteFeaturesProvider` | [state/remote_features.dart:8](../../app/lib/src/state/remote_features.dart) | `FutureProvider.family<Map<String,bool>, String>` | `operations/fsinfo` → `Features`; used to capability-gate UI. |
| `drivesProvider` | [state/local_locations.dart:224](../../app/lib/src/state/local_locations.dart) | `Provider<List<LocalLocation>>` | Auto-detected local disks — synchronous, no engine needed. |
| `userLocationsProvider` | [state/local_locations.dart:374](../../app/lib/src/state/local_locations.dart) | `NotifierProvider<UserLocations, List<LocalLocation>>` | Persisted, seeded with defaults on first run. |
| `collapsedSectionsProvider` | [state/local_locations.dart:418](../../app/lib/src/state/local_locations.dart) | `NotifierProvider<CollapsedSections, Set<String>>` | Persisted sidebar section collapse. |
| `bookmarksProvider` | [state/bookmarks_controller.dart:115](../../app/lib/src/state/bookmarks_controller.dart) | `NotifierProvider<BookmarksController, List<Bookmark>>` | Persisted "Favorites", most-recently-pinned first. |
| `allFilesAccessProvider` | [state/android_native.dart:49](../../app/lib/src/state/android_native.dart) | `FutureProvider<bool>` | Android all-files-access permission state. |

### Mount, serve & policy kill-switches

| Provider | File | Kind → state | Notes |
| :--- | :--- | :--- | :--- |
| `mountControllerProvider` | [state/mount_controller.dart:155](../../app/lib/src/state/mount_controller.dart) | `NotifierProvider<MountController, List<MountInfo>>` | 2 s `mount/listmounts` poll. `mount`, `unmount`, `unmountAll`, `unmountAllForExit`, `refreshCache`. **Nothing is persisted**, so mounts never auto-resurrect. |
| `mountTypesProvider` | [state/mount_controller.dart:14](../../app/lib/src/state/mount_controller.dart) | `FutureProvider<List<String>>` | Empty on Windows ⇒ WinFsp missing. |
| `mountDefaultsProvider` | [state/mount_defaults.dart:68](../../app/lib/src/state/mount_defaults.dart) | `NotifierProvider<MountDefaults, MountOptions>` | The [`MountOptions`](../../app/lib/src/rclone/models/mount_options.dart) a **new** mount starts from — edited in Settings, and copied transiently by the mount dialog for one mount. Two levels only: a per-mount tweak never redefines the default, and a changed default never reaches a running mount (rclone fixes a VFS's options at mount time). Persisted as one JSON string so a new option needs no migration. |
| `mountLettersProvider` | [state/mount_letters.dart:75](../../app/lib/src/state/mount_letters.dart) | `NotifierProvider<MountLetters, Map<String, String>>` | Which mount point each **fs** (`gdrive:` or `gdrive:work`, not the remote name) was last pinned to, so a remote lands on the same letter every time instead of taking whatever `*` picks. Persisted as one JSON blob, so a new key needs no migration. `remember(fs, point)` treats `*` as the *absence* of a pin and forgets instead, which is what makes the checkbox symmetric; `forget(fs)`. The pin is written **after** the mount succeeds and records the point rclone actually used — with Auto selected that is the assigned letter, which is exactly the "put it back where it was" case worth remembering. |
| `mountEnabledProvider` | [state/mount_policy.dart:15](../../app/lib/src/state/mount_policy.dart) | `Provider<bool>` = `!kMacAppStoreBuild` | MDM/enterprise kill-switch seam, meant to be **overridden**, not edited. Not a constant `true`: FUSE is impossible under the App Sandbox, so a Mac App Store build resolves it to `false` and every existing entry point already hides. |
| `serveControllerProvider` | [state/serve_controller.dart:157](../../app/lib/src/state/serve_controller.dart) | `NotifierProvider<ServeController, List<ServeServer>>` | 2 s `serve/list` poll. `start`, `stop`, `panicStopAll`. |
| `serveTypesProvider` | [state/serve_controller.dart:17](../../app/lib/src/state/serve_controller.dart) | `FutureProvider<List<String>>` | Curated set ∩ `serve/types`. |
| `lanIpProvider` | [state/serve_controller.dart:34](../../app/lib/src/state/serve_controller.dart) | `FutureProvider<String?>` | Display only — never used as a bind address. |
| `serveEnabledProvider` | [state/serve_policy.dart:17](../../app/lib/src/state/serve_policy.dart) | `Provider<bool>` = `!kMacAppStoreBuild` | Same kill-switch pattern, and likewise not a constant — the MAS entitlement set omits `com.apple.security.network.server`. `panicStopAll()` stays callable when disabled. |
| `revealEnabledProvider` | [state/native_actions_policy.dart:31](../../app/lib/src/state/native_actions_policy.dart) | `Provider<bool>` | "Reveal in file manager". **Computed**, not hard-coded: `subprocessAllowedHere`, because every implementation (`open -R`, `explorer.exe /select,`, `dbus-send`) is a spawned process. Still an override seam. |
| `archiveEnabledProvider` | [state/native_actions_policy.dart:46](../../app/lib/src/state/native_actions_policy.dart) | `Provider<bool>` | Archive create / extract / list, likewise `subprocessAllowedHere` — rclone exposes no RC method for archives, so `ArchiveService` shells out. Unlike mount, no future entitlement fixes this; it needs an RC method upstream. |

All four kill-switches — `mountEnabled`, `serveEnabled`, `revealEnabled`, `archiveEnabled` — are
re-checked **inside** the operation: `MountController.mount()`, `ServeController.start()`,
[`os_integration.dart`](../../app/lib/src/state/os_integration.dart) and
[`archive_service.dart`](../../app/lib/src/state/archive_service.dart) each carry a belt-and-braces
check behind the menu item that already hides. Flipping one to `false` therefore *refuses* the action
rather than merely hiding a button. Overriding mount/serve is the enterprise-deployment lever
described in [19-enterprise-readiness.md](19-enterprise-readiness.md).

Two neighbouring actions are deliberately **not** gated, and the policy file says so: **open with the
default app** goes through `url_launcher` (NSWorkspace on macOS), not a spawn, and the sandbox permits
handing off a file the user granted; **copy path** is pure clipboard. Gating either would remove a
feature that works.

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
| `thumbnailServiceProvider` | [state/thumbnail_service.dart:428](../../app/lib/src/state/thumbnail_service.dart) | `Provider<ThumbnailService>` | Bounded concurrency + in-flight dedup + a session-scoped "undecodable" negative cache. Two gates: a general one and a stricter video-keyframe one, always taken in that order. |
| `thumbnailReloadProvider` | [state/thumbnail_reload.dart:67](../../app/lib/src/state/thumbnail_reload.dart) | `NotifierProvider<…, ThumbnailReloadSignal>` | Carries only a `tick` + `force` epoch — deliberately **not** per-item progress, so tiles wake rarely. `reload()`, `rebuild()`, `prewarm()` (batched). |
| `thumbnailsDisabledProvider` | [state/thumbnail_prefs.dart:59](../../app/lib/src/state/thumbnail_prefs.dart) | `NotifierProvider<ThumbnailPrefs, Set<String>>` | Per-remote **opt-out** keyed by fs — thumbnails are on by default. `toggle(fs)`, `isDisabled(fs)`. |
| `folderPreviewServiceProvider` | [state/folder_preview.dart:223](../../app/lib/src/state/folder_preview.dart) | `Provider<FolderPreviewService>` | Composites a folder's images into a 2×2 card thumbnail, sealed + disk-cached. |
| `repeatPlaybackProvider` | [state/media_prefs.dart:47](../../app/lib/src/state/media_prefs.dart) | `NotifierProvider<RepeatPlayback, bool>` | Whether a previewed video/audio file restarts at the end. Persisted, app-wide (a "how I like my player to behave" choice), default **off**. Applied *after* `Player.open` and re-applied mid-playback from a `ref.listen` — see [14 §4](14-performance-standards.md). |

Exact slot counts, timeouts and batch sizes are budgets, not state — they belong to
[14-performance-standards.md](14-performance-standards.md). Content reads must additionally respect
the cloud-hydration guard in [state/cloud_placeholder.dart](../../app/lib/src/state/cloud_placeholder.dart).

### Tasks, scheduler & bandwidth

| Provider | File | Kind → state | Notes |
| :--- | :--- | :--- | :--- |
| `tasksProvider` | [state/tasks_controller.dart:341](../../app/lib/src/state/tasks_controller.dart) | `NotifierProvider<TasksController, List<TransferTask>>` | Persisted saved tasks — `TaskKind.transfer` / `backup` / `photos` share one model, one scheduler and one run history — with stable string ids, a `runWhileClosed` background opt-in, and a per-task run history capped at 10. `add`, `update`, `remove`, `recordRun`, `replaceAll` (one write for a change spanning tasks). Its hydration gate is `await ref.read(tasksProvider.notifier).ready`, **not** the `ensureLoaded()` idiom above: anything acting on the *whole* set must wait, because the empty list `build()` returns reads as "nothing is scheduled" and would unregister everything. |
| `schedulerProvider` | [state/scheduler_controller.dart:394](../../app/lib/src/state/scheduler_controller.dart) | `NotifierProvider<SchedulerController, SchedulerStatus>` | 30 s tick; `SchedulerStatus` itself is in-memory only. Runs due tasks **while the app is open**; stamps `lastRun` before the async kickoff so a tick can't double-fire; records `skippedWhileUnavailable` when the engine is down. Every tick returns immediately while `schedulerPausedProvider` is tripped, and a `TaskKind.transfer` run goes through `withScheduledDeleteCap` (a backup through `backupOptions`). `build()` also fires `reconcileRegistrations(seed: true)` once — the launch-time OS reconcile — which is why HomeScreen must force-read it. |
| `schedulerPausedProvider` | [state/scheduler_pause.dart:110](../../app/lib/src/state/scheduler_pause.dart) | `NotifierProvider<SchedulerPaused, SchedulerPause?>` | The circuit breaker: **global, not per-task**, because the causes of a run blowing its delete cap are environmental. Persisted (`scheduler_paused`) — a pause that forgets itself on restart is not a pause. `pause()` keeps the FIRST reason; `resume()` is only ever a user action, with no auto-resume and no timeout. |
| `pollCadenceProvider` | [state/poll_cadence.dart:51](../../app/lib/src/state/poll_cadence.dart) | `NotifierProvider<PollCadence, int>` | How often the shared background job wakes to run whatever is due. Persisted, because the OS registration built from it outlives the process; clamped by `clampPollMinutes` on the way in *and* out. Bounds lateness for interval schedules only — an exact daily trigger is unaffected. |
| `backupRetentionProvider` | [state/backup_retention.dart:180](../../app/lib/src/state/backup_retention.dart) | `NotifierProvider<BackupRetention, int>` | How many days a replaced version is kept before a prune may remove it (persisted, default 30, clamped). `0` keeps nothing beyond the current file; there is deliberately no "forever". |
| `backupPrunerProvider` | [state/backup_prune.dart:167](../../app/lib/src/state/backup_prune.dart) | `Provider<BackupPruner>` | Lists a backup folder recursively and deletes old versions — **dry run by default**, so the UI previews with the code that will run. Refuses outright above `kMaxPrunePerPass` (500) rather than deleting the first 500: a pass that large is more likely a bug than a backlog. *What* to delete is decided by the pure `prunableVersionsRecursive`, not here. |
| `bandwidthControllerProvider` | [state/bandwidth_controller.dart:53](../../app/lib/src/state/bandwidth_controller.dart) | `NotifierProvider<…, BandwidthState>` | Live `core/bwlimit`. `setLimit(rate)`. |
| `bwScheduleControllerProvider` | [state/bw_schedule_controller.dart:72](../../app/lib/src/state/bw_schedule_controller.dart) | `NotifierProvider<…, BwSchedule>` | Persisted timetable + a 60 s applier. `setEnabled`, `setWindows`. |
| `windowsTaskSchedulerProvider` | [state/windows_task_scheduler.dart:490](../../app/lib/src/state/windows_task_scheduler.dart) | `Provider<WindowsTaskScheduler>` | `schtasks` `register` / `unregister` / `isRegistered` / `listRegistered` / `reconcile` for headless runs. Windows-only; silently no-ops elsewhere. Has a `ProcessRunner` seam for tests. What each schedule gets is decided by `registrationShapeFor` in [state/registration_policy.dart](../../app/lib/src/state/registration_policy.dart): its own exact trigger `Airclone\<task id>` for daily/weekly, membership of the one shared `Run due tasks` job (`--run-due`, cadence from `pollCadenceProvider`) for interval, and `unsupported` where the platform has no background execution at all. |

### Android background execution

Android's half of the shared poller above: one `PeriodicWorkRequest` under one fixed name, which
wakes a second Flutter engine to run whatever is due (see *Three entry points build the graph*).
Every provider here is a safe no-op off Android and none of them throws — background scheduling
failing must never take the Settings screen down with it.

| Provider | File | Kind → state | Notes |
| :--- | :--- | :--- | :--- |
| `androidWorkProvider` | [state/android_work_channel.dart:149](../../app/lib/src/state/android_work_channel.dart) | `Provider<AndroidWork>` | The `MethodChannel('airclone/work')` wrapper over WorkManager: enqueue/cancel the periodic request, `runOnce()`, `status()`. |
| `androidWorkStatusProvider` | [state/android_work_channel.dart:154](../../app/lib/src/state/android_work_channel.dart) | `FutureProvider.autoDispose<AndroidWorkStatus>` | What WorkManager currently holds plus the stamp the last wake left behind (next/last run, headless exit code, summary). `autoDispose` so the Settings section re-asks on every open instead of showing the answer from last time. |
| `androidWorkSettingsProvider` | [state/android_work_settings.dart:77](../../app/lib/src/state/android_work_settings.dart) | `NotifierProvider<AndroidWorkSettings, AndroidWorkConstraints>` | The conditions Android must meet before it wakes us: `unmetered` (default **on** — the headline background task on a phone is a camera-roll backup, and a 40 GB roll on cellular is a bill) and `charging`. Per-device, not per-task, because WorkManager applies them to the single shared wake. Persisted. |
| `androidWorkReconcilerProvider` | [state/android_work_registration.dart:111](../../app/lib/src/state/android_work_registration.dart) | `Provider<void>` | Side-effect-only, force-read once at launch. Stores the Dart entrypoint's callback handle first (a wake before that has nothing to run), awaits `tasksProvider.notifier.ready`, then keeps the periodic request in step with the saved tasks and the constraints. A plan equal to the last one applied is skipped, so the `lastRun`/history writes every scheduled run makes do not each touch WorkManager. |

### Wizards, console & OS integration

| Provider | File | Kind → state | Notes |
| :--- | :--- | :--- | :--- |
| `addRemoteControllerProvider` | [state/add_remote_controller.dart:290](../../app/lib/src/state/add_remote_controller.dart) | `NotifierProvider<AddRemoteController, AddRemoteState>` | The `config/create`+`config/update` interactive/OAuth state machine (`AddPhase`). Refuses a name already in the config (via `existingRemoteNames`) before creating, and fails closed when the config cannot be read. |
| `encryptRemoteControllerProvider` | [state/encrypt_remote_controller.dart:255](../../app/lib/src/state/encrypt_remote_controller.dart) | `NotifierProvider<…, EncryptRemoteState>` | Wrap-an-existing-remote-in-`crypt` wizard (`EncryptPhase`). Same name guard — recreating a `crypt` remote with a different password or salt orphans everything already stored under it. |
| `consoleControllerProvider` | [state/console/console_controller.dart:571](../../app/lib/src/state/console/console_controller.dart) | `NotifierProvider.family<ConsoleController, ConsoleState, String>` | Keyed by a stable console id minted per console tab. **Not autoDispose** — `BrowserController.closeTab` must `stop()` + `invalidate()` it (see Traps). |
| `osIntegrationProvider` | [state/os_integration.dart:142](../../app/lib/src/state/os_integration.dart) | `Provider<OsIntegration>` | Reveal-in-file-manager, open-with-default-app (`url_launcher`), copy path. |
| `downloadDirProvider` | [state/download_settings.dart:39](../../app/lib/src/state/download_settings.dart) | `NotifierProvider<DownloadDir, String?>` | Remembered download folder; clearing removes the key. |
| `downloadAlwaysPromptProvider` | [state/download_settings.dart:73](../../app/lib/src/state/download_settings.dart) | `NotifierProvider<DownloadAlwaysPrompt, bool>` | |
| `diagnosticsProvider` | [state/diagnostics.dart:189](../../app/lib/src/state/diagnostics.dart) | `NotifierProvider<DiagnosticsLog, List<DiagEntry>>` | The local, no-telemetry problem log (Settings → Diagnostics). Bounded ring; **redaction runs at ingest** inside `record()`. `logDiagnostic()` is the `Ref`-free sink for the error hooks in [ui/app.dart](../../app/lib/src/ui/app.dart). See [15-security.md §5.1](15-security.md). |

### Pure modules in `state/` (no provider)

These are provider-free, unit-testable logic used by the controllers above. Prefer adding logic here
over inside a `Notifier` — the test suite reaches these directly:
[archive_command.dart](../../app/lib/src/state/archive_command.dart) ·
[backup_restore.dart](../../app/lib/src/state/backup_restore.dart) (`remote:path` split → open a backup folder in a pane; there is no restore engine) ·
[backup_task.dart](../../app/lib/src/state/backup_task.dart) (where a backup lands: `Airclone/Backups` / `Airclone/Photos` + the per-device folder) ·
[build_flavor.dart](../../app/lib/src/state/build_flavor.dart) (`kMacAppStoreBuild` — a compile-time constant, unlike `install_source.dart`) ·
[bw_schedule.dart](../../app/lib/src/state/bw_schedule.dart) ·
[cloud_placeholder.dart](../../app/lib/src/state/cloud_placeholder.dart) ·
[config_encryption.dart](../../app/lib/src/state/config_encryption.dart) ·
[config_io.dart](../../app/lib/src/state/config_io.dart) ·
[dedupe.dart](../../app/lib/src/state/dedupe.dart) ·
[diagnostics.dart](../../app/lib/src/state/diagnostics.dart) (redaction + report rendering) ·
[engine_mode.dart](../../app/lib/src/state/engine_mode.dart) ·
[external_config_backup.dart](../../app/lib/src/state/external_config_backup.dart) (paths + mode mapping) ·
[install_source.dart](../../app/lib/src/state/install_source.dart) (installer-id → channel + store links) ·
[mac_bookmarks.dart](../../app/lib/src/state/mac_bookmarks.dart) (security-scoped bookmarks; a no-op everywhere but a sandboxed macOS build) ·
[name_conflict.dart](../../app/lib/src/state/name_conflict.dart) ·
[offline_qr.dart](../../app/lib/src/state/offline_qr.dart) ·
[open_external.dart](../../app/lib/src/state/open_external.dart) ·
[photo_backup.dart](../../app/lib/src/state/photo_backup.dart) (camera-roll folders → ordered rclone filter rules) ·
[registration_policy.dart](../../app/lib/src/state/registration_policy.dart) (exact trigger vs shared poller, poll-cadence clamp, reconcile plan) ·
[remote_summary.dart](../../app/lib/src/state/remote_summary.dart) ·
[scheduler_registration.dart](../../app/lib/src/state/scheduler_registration.dart) (`seedRunWhileClosed` + `reconcileRegistrations`) ·
[scheduling_policy.dart](../../app/lib/src/state/scheduling_policy.dart) (what "run on a schedule" means per platform, in one place) ·
[sync_preview.dart](../../app/lib/src/state/sync_preview.dart) (buckets → "what a transfer would do") ·
[task_kind.dart](../../app/lib/src/state/task_kind.dart) (`backupOptions` / `isBackupShaped` — the three constraints that make a task a backup) ·
[task_schedule.dart](../../app/lib/src/state/task_schedule.dart) ·
[tree_state.dart](../../app/lib/src/state/tree_state.dart) (the tree view's forest + row flattening; nothing in it reads `state.path`) ·
[undecryptable_names.dart](../../app/lib/src/state/undecryptable_names.dart) (a session counter, not a provider) ·
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
| `remote`, `path` | Current location. `null` remote = nothing open (**or** a console tab — check `activeIsConsole`). In `ViewMode.tree` this is the folder the tree is *rooted* at, not the folder any given row lives in. |
| `entries`, `loading`, `error` | The listing from `operations/list`. In the tree it is the top level only; deeper levels live in `tree`. |
| `selected` (`Set<String>`), `filter` | Multi-selection by name; live client-side Ctrl+F filter. |
| `sortKey`, `ascending`, `viewMode`, `gridSize` | Per-pane view; persisted per remote via `viewMemoryProvider`. `viewMode == tree` is coerced back to `list` on a touch-primary device (`_allowedHere`), so "tree" always means the tree is what is showing. |
| `tree` | The tree view's forest ([state/tree_state.dart](../../app/lib/src/state/tree_state.dart)): one cached listing per expanded folder, keyed by full path relative to the remote root, plus that view's own expansion, in-flight/error sets, multi-selection and cursor. Expansion is **session-only** (a tree that reopened forty folders at launch would issue forty listings); the cache survives navigation and a view-mode switch, and is cleared when the remote changes. |
| `tabs`, `activeTab` | Overlaid tab metadata (see above). |
| `hiddenUndecryptable` | How many entries rclone silently dropped from this listing because a `crypt` remote could not decrypt their names. Sampled either side of the request from the counter in [state/undecryptable_names.dart](../../app/lib/src/state/undecryptable_names.dart); a listing that came back short renders "N items hidden" instead of "Empty folder". |
| derived | `segments`, `visibleEntries`, `selectedEntries`, `isSelected(name)`, `activeIsConsole`; and for the tree `hasSelection`, `selectionCount`, `childrenOf(folder)`, `isTreeSelected(path)`, `selectedTreeRows`. |

**`selectedEntries` is empty in tree mode, always.** Every consumer of it builds a target as
`state.path + entry.name`, which is right for one flat folder and wrong for a row three levels down —
Delete would purge `root/name` instead of `A/B/C/name`. A tree selection therefore never surfaces
there; it lives in `tree.selected` as full paths and the only correct source for a tree operation is
`selectedTreeRows`, whose rows each carry their own `parentPath`. Use `hasSelection` /
`selectionCount` for "is anything selected", since those answer for whichever view is showing.

Mutators: `newTab` / `newConsoleTab` / `switchTab` / `closeTab`; `open(remote)`, `enterDir`,
`goToSegment`, `up`, `navigateTo`, `back`, `forward`, `refresh`, `clear`; `setFilter`,
`toggleSelect`, `clearSelection`, `selectOnly`, `selectAll`; `setViewMode`, `setGridSize`, `setSort`;
and for the tree `expandNode`, `collapseNode`, `toggleExpand`, `reloadTreeFolder`, `toggleTreeSelect`,
`selectTreeOnly`, `setTreeCursor`.

Explorer-level design intent for these panes lives in [20-explorer-design.md](20-explorer-design.md).

---

## 💾 Persistence map

Three backing stores, plus rclone's own config which this layer does **not** own.

### SharedPreferences (37 keys)

| Key | Provider | Encoding |
| :--- | :--- | :--- |
| `advanced_mode` | `advancedModeProvider` | bool |
| `android_work_unmetered`, `android_work_charging` | `androidWorkSettingsProvider` | bool — unmetered defaults **on** |
| `backup_retention_days` | `backupRetentionProvider` | int — days, clamped on load |
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
| `jobs_dock_height` | `jobsDockHeightProvider` | double — stored unclamped; the widget clamps against the live layout |
| `media_repeat` | `repeatPlaybackProvider` | bool |
| `mount_letters_v1` | `mountLettersProvider` | JSON string — fs → mount point |
| `mount_options_defaults` | `mountDefaultsProvider` | JSON string — tolerant decode; a wrong type, a removed key **or an unknown cache mode** falls back to the shipped default rather than throwing |
| `pane_split_ratio` | `paneSplitRatioProvider` | double |
| `pane_split_orientation` | `paneSplitOrientationProvider` | enum name |
| `rclonePath` | `settingsControllerProvider` | string |
| `recents_enabled` | `recentsEnabledProvider` | bool — the opt-in switch only; the trail itself is never persisted |
| `remember_config_password` | `rememberConfigPasswordProvider` | bool |
| `scheduler_paused` | `schedulerPausedProvider` | JSON string — the tripped circuit breaker, persisted so a restart does not quietly resume it |
| `scheduler_poll_minutes` | `pollCadenceProvider` | int — clamped, because the OS registration built from it outlives the process |
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
`bwScheduleControllerProvider`, `bookmarksProvider`, `transferForegroundServiceProvider`,
`androidWorkReconcilerProvider` (Android: keeps WorkManager's periodic wake in step with the saved
tasks and the Wi-Fi/charging settings; a no-op elsewhere) and
`externalBackupProvider.notifier.ensureLoaded()` — alongside
`engineControllerProvider.notifier.bootstrap()`. **Add any new self-driving provider to that list.**

### Three entry points build the graph

| Entry point | Container | Notes |
| :--- | :--- | :--- |
| GUI | `runApp(const ProviderScope(...))` in [app/lib/main.dart](../../app/lib/main.dart) | The scope is never disposed at process exit — see Traps. |
| Headless (`--run-task` / `--run-due`) | a bare `ProviderContainer()` in [src/headless/headless_runner.dart](../../app/lib/src/headless/headless_runner.dart) | No widget tree, no `runApp`. It force-reads the prefs-backed providers it depends on, uses `SharedPreferences.getInstance()` as a hydration sync-point, quits the engine explicitly, then **does** `container.dispose()`. |
| Android WorkManager wake | `androidWorkEntrypoint()` in [state/android_work_entrypoint.dart](../../app/lib/src/state/android_work_entrypoint.dart) → its own `ProviderContainer()` via `runHeadlessInProcess` | A `vm:entry-point` function running as the root of a **second Flutter engine inside the app's own process**, with no Activity and no widget tree. Same `--run-due` contract as the OS schedulers, and it disposes its container — but it must **never** call `exit()`, which is exactly why `runHeadlessInProcess` exists beside `runHeadless`: ending the process would take the foreground Activity with it. |

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
   The **tree** is the same trap under the opposite constraint: it holds many listings at once and is
   deliberately not cleared on navigate, so it carries its own per-folder form of the guard
   (`_Session.treeSeq` / `treeGen` — one counter for the whole session, so a cleared map can never
   hand a stale response a number that matches again) and a hard rule to go with it: a tree row's path
   is built from `TreeRow.parentPath` and **never** from `state.path`. Nothing in
   [state/tree_state.dart](../../app/lib/src/state/tree_state.dart) reads `state.path`; keep it that
   way.
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
   overriding `mountEnabledProvider` / `serveEnabledProvider`, never by editing their bodies — both
   already resolve to `!kMacAppStoreBuild`, so an edit there silently re-enables a feature the App
   Sandbox cannot deliver.
   `revealEnabledProvider` and `archiveEnabledProvider` are the same seam but *computed* from
   `subprocessAllowedHere` — override those too rather than changing the capability predicate, which
   a store build depends on.
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
