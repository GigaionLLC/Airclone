# 📝 Agent Changelog

All changes made by AI agents are tracked chronologically below (most recent first).

---

<!-- New entries go above this line, most recent first -->

## [2026-06-28] - v0.1.0-alpha.39: skin foundation (Phase D — zero visual change)

**Agent:** Airclone Build (Claude Opus 4.8)
**Files Modified:**
- `ui/theme/tokens.dart`: new `Skin` enum (`airclone` default + `windows`/`macos`/`gnome`) with labels;
  `SkinTokens` (fontFamily/fallback, bodySize, rowHeight, density, selectionRadius) with `.of(skin)` +
  `.lerp`; per-skin instances (airclone = today's values; OS variants are starting points). `AircloneColors`
  gains a real `lerp`. `AircloneTheme` now carries `colors` + `tokens`, with `tokensOf(context)` and a
  proper `copyWith`/`lerp` (the old `lerp` returned `this`).
- `ui/theme/app_theme.dart`: `AppTheme.build(Skin, Brightness)` sets fontFamily/fallback/visualDensity +
  the extension from the skin's tokens; `light()`/`dark()` keep working (Airclone skin).
- New `state/skin.dart`: persisted `skinProvider` (`SkinController`, key `skin`, default `Skin.airclone`).
- `ui/app.dart`: watches `skinProvider`, builds light/dark themes per skin.
- New `test/skin_test.dart`: 5 tests (default reproduces today's look, per-skin token bundles, lerp
  interpolates, provider persistence round-trip, labels).
- pubspec → alpha.39

**Database/API Changes:** None
**Summary:** alpha.39 — the safe scaffolding for optional native skins. The default **Airclone** skin renders
exactly as before (verified: fontFamily 'Segoe UI', rowHeight 36, today's palette), so this is a no-visible-
change release. Next: route `_FileRow`/sidebar/toolbar through `SkinTokens` + add the Settings skin selector
(Phase E), then build out the Explorer/Finder/GNOME looks (Phase F/G, user-verified). analyze (0) /
test (54, +5) / Windows build green.

## [2026-06-28] - v0.1.0-alpha.38: engine-flag preset chips (discoverability Phase C)

**Agent:** Airclone Build (Claude Opus 4.8)
**Files Modified:**
- `state/engine_flags.dart`: pure `hasEngineFlag(raw, flag)` + `toggleEngineFlag(raw, flag)` (handles bare
  `--name` and `--name value` pairs; removes the value with the name; free-text stays source of truth)
- `ui/settings_screen.dart`: `_EngineFlagsSection` shows a `Wrap` of `FilterChip` presets (`--fast-list`,
  `--transfers 8`, `--checkers 16`, `--no-traverse`) above the text field, composing into it
- New `test/engine_flags_test.dart`: 5 tests (tokenize + add/remove bare + value flags + reflect existing)
- pubspec → alpha.38

**Database/API Changes:** None
**Summary:** alpha.38 — Phase C of the discoverability track: common engine flags are now one-tap chips that
compose into the existing free-text field, so users don't need to know rclone's flag syntax. analyze (0) /
test (49, +5) / Windows build green. Discoverability track (A–C) done; next up is the skins track
(Airclone default + optional Explorer/Finder/GNOME).

## [2026-06-28] - v0.1.0-alpha.37: discoverable advanced transfer options (Phase A+B of the discoverability track)

**Agent:** Airclone Build (Claude Opus 4.8) — preceded by a 4-agent audit/research/plan workflow
**Why:** the user couldn't tell how to reach advanced upload/download options. The audit found the whole
tabbed transfer dialog was gated behind Advanced Mode, and some controls didn't name their rclone flag.
**Files Modified:**
- `ui/browser_pane.dart`: the command-bar advanced-transfer button is **ungated** (shown whenever there's a
  selection, not just in Advanced Mode) and relabeled "Transfer with options…"; `_advancedTransfer` now
  **falls back to a destination picker** when there's no second pane, so it works in single-pane mode.
  Removed the now-unused `advanced_mode` import/var.
- `ui/transfer_options_dialog.dart`: compare dropdown shows `--size-only`/`--checksum`; Include/Exclude/Filter
  fields are labelled with their flag (`--include`/`--exclude`/`--filter`) + a tooltip + a glob-pattern hint.
- New `test/transfer_options_dialog_test.dart`: asserts the flag labels + Dry-run/Run buttons render.
- pubspec → alpha.37

**Database/API Changes:** None
**Summary:** alpha.37 — Phase A (teach the flag) + Phase B (ungate the dialog) of the discoverability plan.
The advanced Copy/Move/Sync dialog is reachable for everyone via a command-bar "Transfer with options…"
button (single-pane friendly), and each control names its rclone flag. analyze (0) / test (44, +2) /
Windows build green. Next: Settings reorganization + engine-flag preset chips (Phase C), then the skins track.

## [2026-06-28] - v0.1.0-alpha.36: auto-refresh panes after a transfer completes

**Agent:** Airclone Build (Claude Opus 4.8)
**Why:** user noted a dropped/uploaded file only appeared after a manual refresh — transfers are async rclone
jobs that finish a moment after the drop, and nothing re-listed the folder on completion.
**Files Modified:**
- `ui/home_screen.dart`: `ref.listen(jobsControllerProvider, …)` in the shell — when any job transitions to
  `JobStatus.success` (id wasn't success in the previous snapshot), re-list both panes
  (`browserA/BProvider.refresh()`). Imported `jobs_controller.dart`.

**Database/API Changes:** None
**Summary:** alpha.36 — drops/uploads/pastes now show up on their own. The shell watches the jobs list and
refreshes both panes the moment a transfer job succeeds, so the new file appears without a manual refresh
(~1s after the rclone job actually finishes). analyze (0) / test (42) / Windows build green.

## [2026-06-28] - v0.1.0-alpha.35: restore OS→app upload + drag auto-scroll (post-migration fixes)

**Agent:** Airclone Build (Claude Opus 4.8)
**Why:** user testing of alpha.34 confirmed whole-file drag-out, no scroll-jump, and in-app drag all work,
but found two issues: (1) dragging files FROM Explorer INTO the app stopped uploading (super_native owns
native drops once a DropRegion exists, so `desktop_drop` no longer fired); (2) no auto-scroll while
in-app-dragging, so off-screen folders were unreachable.
**Files Modified:**
- `ui/native_drag.dart` `NativePaneDropRegion`: now also handles **OS-file drops** — `onOsFiles(paths)`
  reads each dropped `Formats.fileUri` via the `DataReader` and returns absolute paths; added **edge
  auto-scroll** (a 60 fps timer scrolls `scrollController` while an in-app drag hovers within 52 px of the
  top/bottom). `onDrop` made optional (locations region is OS-files-only).
- `ui/browser_pane.dart`: pane region gains `onOsFiles` (→ `_uploadLocal`) + `scrollController`
  (→ `paneScrollProvider`); removed the `desktop_drop` `DropTarget` + import.
- `ui/home_screen.dart`: LOCATIONS folder-drop migrated to `NativePaneDropRegion(onOsFiles: …)`; removed
  the `desktop_drop` import.
- `pubspec.yaml`: **removed `desktop_drop`** (fully replaced) → alpha.35.

**Database/API Changes:** None
**Summary:** alpha.35 — OS→app file upload works again (now through the native DropRegion; `desktop_drop`
gone), and in-app dragging auto-scrolls near the list edges to reach off-screen folders. analyze (0) /
test (42) / Windows build green. **Needs user re-test** of upload + auto-scroll (drop behavior isn't
agent-observable).

## [2026-06-28] - v0.1.0-alpha.34: whole-file drag — full migration of in-app DnD to the native engine

**Agent:** Airclone Build (Claude Opus 4.8)
**Why:** the user wanted to drag the WHOLE file (not a grip), and diagnosed that the "view jumps to top on
drag" came from Flutter's `Draggable` (the super_native grip didn't jump). One widget can't run both drag
systems, so the in-app drag/drop is migrated onto `super_drag_and_drop` — the same gesture now serves both
an in-app drop and an OS drag-out, and the scroll-jump goes away.
**Files Modified:**
- New `ui/native_drag.dart`: `NativePaneDraggable` (whole-widget drag → `localData` = PaneDragData JSON +
  `Formats.plainText` marker + `Formats.fileUri` for local files = OS drag-out) and `NativePaneDropRegion`
  (DropRegion accepting only in-app drags via localData; OS-file drops fall through to `desktop_drop`;
  hover highlight).
- `ui/pane_drag.dart`: `PaneDragData.toJson`/`fromJson` (rides as native localData).
- `ui/browser_pane.dart`: list `_FileRow` source + folder drop + pane drop migrated; removed the grip +
  Flutter `Draggable`/feedback; deleted `ui/os_drag_handle.dart`.
- `ui/file_grid.dart`, `ui/media_gallery.dart`: tile sources (+ grid folder drop) migrated; removed feedbacks.
- `ui/home_screen.dart`: sidebar remote tile drop migrated; dropped the now-unused `_RemoteTile.dropHover`.
- New `test/pane_drag_test.dart`: 2 round-trip tests. pubspec → alpha.34.

**Database/API Changes:** None
**Summary:** alpha.34 — the entire file is the drag handle. Grab a row/tile and drop it onto a folder, the
other pane, a sidebar remote (in-app copy) **or** onto the OS (local files copy out) in one gesture; the
list no longer jumps to the top. OS→app uploads unchanged (`desktop_drop`). analyze (0) / test (42, +2) /
Windows build green. **Needs the user to verify the actual drags** (in-app pane/folder/sidebar, OS drag-out,
and that OS-file upload still works) since drag behavior isn't agent-observable.

## [2026-06-28] - v0.1.0-alpha.32: drag a local file out to the OS from a row grip (super_drag_and_drop returns)

**Agent:** Airclone Build (Claude Opus 4.8)
**Why:** the user explicitly chose real OS drag-out after the verifiable reveal/open/copy approach (a30–a31)
wasn't the drag UX they wanted. There is no official Flutter drag-out, so this re-adds the community
`super_drag_and_drop` (+ Rust/cargokit). Implemented on the file ROWS this time (the natural place) via a
NON-conflicting drag handle so the working in-app drag is preserved.

**Files Modified:**
- New `ui/os_drag_handle.dart`: `OsDragHandle` — a `DragItemWidget`/`DraggableWidget` grip providing
  `Formats.fileUri` (copy) for a local OS path; shows a **diagnostic SnackBar when the drag gesture fires**
  (an OS drag is not auto-testable, so this distinguishes "gesture didn't start" from "OS drop failed").
- `ui/browser_pane.dart`: list `_FileRow` now overlays the handle at the left edge via a `Stack`, OUTSIDE
  the in-app `Draggable<PaneDragData>` (local files only).
- `pubspec.yaml`: re-add `super_drag_and_drop: ^0.9.1` (→ alpha.32). `.github/workflows/release.yml`:
  re-add `dtolnay/rust-toolchain` to the 3 desktop jobs.

**Toolchain:** Rust required again for desktop builds (cargokit). Verified analyze (0) / test (40) /
`flutter build windows` green with cargo on PATH.

**Database/API Changes:** None
**Summary:** alpha.32 — drag-out from a left-edge grip on local file rows, kept separate from the in-app
drag gesture. The build + code are verified by the agent; the **drag itself needs the user to confirm on
screen** — the diagnostic toast is there to make that confirmation/iteration efficient. (List view first;
grid/media can follow if it works.)

## [2026-06-28] - v0.1.0-alpha.30: official OS interop (Open/Reveal/Copy-path) replaces native drag-out

**Agent:** Airclone Build (Claude Opus 4.8) — preceded by a 4-agent research+verify workflow
**Why:** the user asked for an OS-interop method that is **verifiable by the agent** + **official** +
**maintainable** cross-platform. A verified research pass confirmed **Flutter has no first-party drag-out**
(its own docs redirect to the community `super_drag_and_drop`, which needs a Rust/cargokit build and whose
drag gesture cannot be verified by an agent that can't see the screen). So we removed it and replaced it
with documented, unit-testable actions.

**Files Modified:**
- New `state/os_integration.dart`: pure `revealCommand(TargetPlatform, absPath)` (Windows
  `explorer.exe /select,<path>` as ONE argv elem; macOS `open -R`; Linux `dbus-send`
  FileManager1.ShowItems) + `revealFallbackCommand` (xdg-open parent dir) + `isSpawnSuccess` (per-OS
  exit-code policy — Windows explorer returns nonzero on success, so ignore it) + `OsIntegration`
  (revealInFileManager / openWithDefaultApp via url_launcher / copyToClipboard) + provider. ProcessRunner +
  launch seams for testing.
- New `test/os_integration_test.dart`: 16 tests (argv per OS, comma-quoting, exit-code policy, Linux
  dbus→xdg-open fallback, Uri.file build + round-trip, clipboard channel).
- `ui/context_menu.dart`: `FileMenuAction.openWith/revealInFolder/copyPath` + `isLocal` gating
  (Open/Show-in-Explorer for local files; Copy path always).
- `ui/browser_pane.dart`: pass `isLocal`, dispatch the 3 actions via `osIntegrationProvider`.
- `ui/inspector_panel.dart`: removed the super_drag_and_drop drag code; added **Open** / **Show in folder** /
  **Copy path** pills for local files (Download still shown for cloud).
- `pubspec.yaml`: removed `super_drag_and_drop` (→ alpha.30). `.github/workflows/release.yml`: removed the
  three `dtolnay/rust-toolchain` steps (no longer needed).

**Toolchain:** desktop builds no longer require Rust — verified `flutter build windows` succeeds with cargo
NOT on PATH. (Rust stays installed locally but is unused; ci.yml unaffected.)

**Database/API Changes:** None
**Summary:** alpha.30 — replaced the unverifiable, Rust-backed native drag-out with the **official,
agent-verifiable trio**: Open (url_launcher), Show in File Explorer/Finder (documented OS commands behind a
pure per-OS argv builder), Copy path (Clipboard) — on local files, via the right-click menu and the Details
pills; Download remains for cloud. analyze (0) / test (39, +16 new) / Windows build green **without Rust**.

## [2026-06-28] - v0.1.0-alpha.29: fix in-app drag self-reupload

**Agent:** Airclone Build (Claude Opus 4.8)
**Files Modified:**
- `ui/browser_pane.dart` `_dropOnto`: early-return when `data.remote == dstRemote && data.parentPath ==
  dstPath` (dropping items back into their current folder); per-file skip when `dstPath == srcPath` or
  `dstPath.startsWith('$srcPath/')` (folder onto itself / into its own subtree)
- `ui/home_screen.dart` `_copyToRemoteRoot`: no-op when dropping a remote's own root items back onto that
  same remote (`data.remote == dst && data.parentPath.isEmpty`)
- pubspec → alpha.29

**Database/API Changes:** None
**Summary:** alpha.29 — fixes the user-reported bug where dragging an already-present file inside a pane and
releasing it re-uploaded the file onto its own location. Same-folder and folder-into-itself drops are now
no-ops across list/grid/media (all route through `_dropOnto`) plus the sidebar remote-root drop. Pure
in-app-drag fix; the separate question of dragging the file *rows* out to the OS (vs the alpha.28 inspector
preview) is unchanged and tracked in the backlog. analyze (0) / test (23) / Windows build green.

## [2026-06-28] - v0.1.0-alpha.28: drag a local file out to the OS

**Agent:** Airclone Build (Claude Opus 4.8)
**Files Modified:**
- `ui/inspector_panel.dart`: the single-file **Details preview** is now an OS drag source for **local**
  files — `_localOsPath()` derives the real on-disk path (local remotes only), `_maybeDraggable()` wraps
  the preview in `DragItemWidget`/`DraggableWidget` providing `Formats.fileUri` (copy); a "Drag out to copy
  elsewhere" hint shows for draggable files. Cloud files are not draggable yet (no local path).
- pubspec: `super_drag_and_drop: ^0.9.1` (its native side, super_native_extensions, builds a **Rust** crate
  via cargokit) → alpha.28
- `.github/workflows/release.yml`: added `dtolnay/rust-toolchain@stable` to the windows/linux/macos build
  jobs so the new native dep compiles in CI (ci.yml is analyze/test only — no native build, unchanged)

**Toolchain:** installed Rust (rustup, stable 1.96, MSVC host) locally so desktop builds + the install/verify
loop keep working. Verified: analyze (0) / test (23) / `flutter build windows` green (Rust crate compiles) /
app **launches** with super_native_extensions initialized.

**Database/API Changes:** None
**Summary:** alpha.28 — first cut of **drag-out to the OS**. Pick a file on a local disk and drag its Details
preview to Explorer/Finder/the desktop to copy it out. Deliberately scoped to the inspector preview (not the
file rows) so it does **not** disturb the working in-app pane-to-pane drag, and to local files (cloud needs
download-on-drop, still deferred). Drag behavior itself needs visual confirmation on the user's screen.

## [2026-06-28] - v0.1.0-alpha.27: clipboard keyboard shortcuts (Ctrl+C/X/V)

**Agent:** Airclone Build (Claude Opus 4.8)
**Files Modified:**
- `ui/home_screen.dart`: `_clipboardStage(cut:)` (Ctrl+C copy / Ctrl+X cut → `clipboardControllerProvider`)
  and `_pasteIntoActive` (Ctrl+V → transfer each staged file into the active pane, move-on-paste for a cut,
  clear after a cut, refresh) + the three CallbackShortcuts bindings; imported `clipboard_controller.dart`
- pubspec → alpha.27

**Database/API Changes:** None
**Summary:** alpha.27 — wired **Ctrl+C / Ctrl+X / Ctrl+V** to the existing shared clipboard (the same staging
used by the right-click Copy/Cut/Paste), finishing the Explorer keyboard map started in a26. A cut pastes as
a move and clears the clipboard. Editable text fields keep handling these keys for normal text editing.
analyze (0) / test (23) / Windows build green.

## [2026-06-28] - v0.1.0-alpha.26: Explorer keyboard shortcuts + per-location view memory

**Agent:** Airclone Build (Claude Opus 4.8)
**Files Modified:**
- `ui/home_screen.dart`: CallbackShortcuts for **F2** (rename selected) · **Delete** (confirm + delete
  selection) · **Enter** (open folder / Quick Look file) · **Ctrl+A** (select all) · **Esc** (clear
  selection); handlers operate on the active pane. (Focused text fields still consume these keys, so the
  filter box is unaffected — same pattern as the existing Space binding.)
- New `state/view_memory.dart`: `ViewPref` (viewMode/sortKey/ascending/gridSize as `.name` strings, JSON
  round-trip) + persisted `viewMemoryProvider` (`ViewMemory.remember`/`prefFor`, no-op on unchanged)
- `state/browser_controller.dart`: `open()` restores a remote's saved `ViewPref` (else keeps the pane's
  current view); `setViewMode`/`setSort`/`setGridSize` now call `_rememberView()`
- New `test/view_memory_test.dart`: 4 tests (round-trip, partial-map defaults, remember/read-back, no-op)
- pubspec → alpha.26

**Database/API Changes:** None
**Summary:** alpha.26 — two "feels like the native file manager" wins. **Keyboard shortcuts** complete the
Explorer key map (F2 / Delete / Enter / Ctrl+A / Esc on the active pane). **Per-location view memory**: each
remote remembers its last view mode, sort, and grid density and restores it on open (persisted). analyze (0)
/ test (23, +4 new) / Windows build green.

## [2026-06-28] - v0.1.0-alpha.25: native window backdrop (Mica/Acrylic, opt-in)

**Agent:** Airclone Build (Claude Opus 4.8) — background agent drafted the state file; integration by main
**Files Modified:**
- New `state/window_backdrop.dart`: `WindowBackdrop` enum (systemDefault/solid/mica/acrylic) + `.label`;
  persisted `windowBackdropProvider`; `initWindowBackdrop()` / `applyWindowBackdrop()` (flutter_acrylic,
  every call try/caught); `loadSavedBackdrop()` for startup
- `main.dart`: async — `initWindowBackdrop()` + `applyWindowBackdrop(loadSavedBackdrop())` before runApp
- `ui/app.dart`: when Mica/Acrylic active, theme `scaffoldBackgroundColor`/`canvasColor` → transparent so
  the OS material reads through
- `ui/settings_screen.dart`: `_BackdropSection` (Window background dropdown) under Appearance
- pubspec: `flutter_acrylic: ^1.1.4`; → alpha.25

**Database/API Changes:** None
**Summary:** alpha.25 — opt-in **native window backdrop**. Settings → Window background offers Mica (Win11)
/ Acrylic / Solid / System default; the choice is applied via flutter_acrylic and persisted, and the app
paints transparently behind the material when active. All native calls are best-effort no-ops where
unsupported, and the default (System default) leaves the standard opaque window — verified the app builds
**and launches** with the new startup init. First cut of the native-chrome track; per-surface translucency
tuning will follow (needs visual iteration). analyze (0) / test (19) / Windows build + launch green.

## [2026-06-28] - v0.1.0-alpha.24: transfer concurrency queue

**Agent:** Airclone Build (Claude Opus 4.8)
**Files Modified:**
- `rclone/models/job.dart`: new `JobStatus.queued`; `isQueued`/`isActive` getters; `isFinished` now means
  strictly terminal (success/failed/canceled)
- `state/jobs_controller.dart`: a `_pending` dispatch queue + `enqueue()`/`_pump()`/`pumpQueue()`; `add()`
  gains a `status` param; `markDone` pumps the next queued job; `stop`/`remove` un-queue; new persisted
  `transferConcurrencyProvider` (`TransferConcurrency`, 0 = unlimited) that re-pumps on raise
- `state/transfer_service.dart`: both `transfer` and `transferAdvancedRaw` now create the job as `queued`
  and hand their dispatch closure to `jobs.enqueue` (gated by the limit) instead of firing immediately
- `ui/jobs_panel.dart`: `Queued` status chip; queued jobs are cancelable; dock header shows `N queued`
- `ui/settings_screen.dart`: advanced `_ConcurrencySection` (Unlimited / 1–8) dropdown
- New `test/transfer_queue_test.dart`: gating, completion-pump, queued-cancel (3 tests)
- pubspec → alpha.24

**Database/API Changes:** None
**Summary:** alpha.24 — an app-level **transfer concurrency queue**. Set Advanced → Concurrent transfers to
a limit and only that many transfers run at once; extras sit **Queued** and dispatch automatically as
running ones finish (or when the limit is raised). Default **Unlimited** keeps the historical fire-all
behavior, so nothing changes unless opted in. Queued jobs show a chip + cancel; the dock counts them.
analyze (0) / test (19, +3 new) / Windows build green.

## [2026-06-28] - v0.1.0-alpha.23: morphing breadcrumb + resizable columns + engine flags

**Agent:** Airclone Build (Claude Opus 4.8) — 3-agent parallel workflow + integration
**Files Modified:**
- `ui/path_bar.dart` (rewrite): morphing address bar — clickable breadcrumb segments (remote chip ›
  folders) with middle-overflow `…` menu; click empty area / pencil to edit as a path TextField (Enter
  navigates, Esc/blur reverts). Public `PathBar` constructor unchanged.
- New `state/engine_flags.dart`: `engineFlagsProvider` (persisted raw string) + `parseEngineFlags()`
  (quote-aware argv tokenizer)
- New resizable columns in `ui/column_header.dart`: `ColumnWidths` + `columnWidthsProvider` (persisted,
  clamped), draggable dividers on the Size/Modified headers; `ColumnHeader` → ConsumerWidget; trailing
  28px slot to align with row action button
- `rclone/http_rclone_client.dart`: `extraArgs` appended to the `rcd` argv (after rc-binding flags)
- `state/engine_controller.dart`: passes `parseEngineFlags(engineFlagsProvider)` into the client; new
  `restartEngine()` (reuses held config password)
- `ui/browser_pane.dart`: `_FileRow` → ConsumerWidget, Size/Modified cells track `columnWidthsProvider`
  (with matching resize-handle gaps + trailing slot)
- `ui/settings_screen.dart`: advanced-only `_EngineFlagsSection` (field + Apply & restart engine);
  dialog wrapped in a height-capped `SingleChildScrollView`
- pubspec → alpha.23

**Database/API Changes:** None
**Summary:** alpha.23 — three Explorer-native features authored in parallel then integrated. The address
bar **morphs** between native-style breadcrumbs and an editable path field. **Details columns resize**
by dragging the header dividers (persisted; rows stay aligned). Power users can pass **global rclone
engine flags** from Settings and apply them with a one-click engine restart. analyze (0) / test (16) /
Windows build green.

## [2026-06-28] - v0.1.0-alpha.22: easy/advanced mode + saved transfer tasks

**Agent:** Airclone Build (Claude Opus 4.8)
**Files Modified:**
- New: `state/advanced_mode.dart` (`advancedModeProvider`, persisted), `state/tasks_controller.dart`
  (`TransferTask` + persisted `tasksProvider`), `ui/tasks_panel.dart` (`showTasksDialog` — list/run/delete +
  "New task" from active→other pane via the advanced dialog + name prompt)
- `state/transfer_options.dart`: `TransferOptions` toJson/fromJson (shipped in alpha.21)
- `state/transfer_service.dart`: extracted `transferAdvancedRaw(srcFs/dstFs/labels/options)`; `transferAdvanced`
  delegates to it (so tasks reuse the same dispatch)
- `ui/browser_pane.dart`: the advanced-transfer command-bar button is gated on advanced mode
- `ui/home_screen.dart`: top-bar **Saved tasks** button (advanced mode only)
- `ui/settings_screen.dart`: **Advanced mode** toggle
- pubspec → alpha.22

**Database/API Changes:** None
**Summary:** alpha.22 — **easy/advanced mode** (default easy hides power-user controls; flip it in Settings)
and **saved transfer tasks**. In advanced mode, the top bar gets a **Saved tasks** panel: "New task" captures
the active pane → other pane as a From/To with full Copy/Move/Sync + filter options, names it, and persists
it; later you **Run** it (one click → tracked job) or delete it. Built on a refactored `transferAdvancedRaw`.
Transfer **queue + scheduler** remain on the backlog (the scheduler needs background execution to be useful).
analyze (0) / test (16) / Windows build green.

## [2026-06-28] - v0.1.0-alpha.20: download-to-folder + type-to-navigate + status bar

**Agent:** Airclone Build (Claude Opus 4.8)
**Files Modified:**
- New: `state/download_settings.dart` — `downloadDirProvider` (persisted default folder),
  `downloadAlwaysPromptProvider`, and `resolveDownloadDir(ref)` (uses the saved default, else a native
  folder picker, remembering the choice); `state/remote_about.dart` — `remoteAboutProvider` (`operations/about`)
- `ui/inspector_panel.dart` + `ui/browser_pane.dart`: Download no longer assumes the OS Downloads folder —
  resolves the destination **once** via `resolveDownloadDir` (prompt/remember), then copies (download-all
  prompts once, not per file); dropped now-unused `dart:io`
- `ui/settings_screen.dart`: **Downloads** section — default folder (Change / Clear) + "Always ask where to save"
- `state/browser_controller.dart`: `selectOnly` + `paneScrollProvider`; `ui/browser_pane.dart` list view uses it
- `ui/home_screen.dart`: **type-to-navigate** (Focus `onKeyEvent` accumulates printable keys, jump-selects +
  scrolls the active pane; skips space + modified combos); **richer status bar** (item count · selection +
  size · free/total space)
- pubspec → alpha.20

**Database/API Changes:** None (uses `operations/about`)
**Summary:** alpha.20 — addresses the Download UX: it now **prompts for the save folder** and remembers it
(Settings → Downloads sets a default + an "always ask" toggle), instead of silently using Downloads.
**Type-to-navigate** jumps to a file as you type its name. The **status bar** now shows the active pane's
item count, selection + size, and the remote's free/total space. analyze (0) / test (16) / Windows build green.

## [2026-06-28] - v0.1.0-alpha.19: encrypted preview cache + clear-cache + memory-only

**Agent:** Airclone Build (Claude Opus 4.8)
**Files Modified:**
- New: `state/cache_crypto.dart` — `CacheCrypto` (AES-256-GCM seal/open, key via PBKDF2-HMAC-SHA256 from
  `cachePassphraseProvider` else a per-remote-name seed; `cryptography` pkg), `cacheMemoryOnlyProvider`
  (persisted), `diskCacheSize()` / `clearDiskCaches()`
- `state/thumbnail_service.dart`: takes `Ref`; `ThumbRequest.cacheSecret`; cache blobs are now `*.bin`
  sealed/opened via `CacheCrypto`; generators downscale only, `load()` handles encrypted read/write;
  memory-only skips disk entirely
- `state/folder_preview.dart`: same — `compose(remoteSecret:)`, encrypted `*.bin`, memory-only
- `state/engine_controller.dart`: sets `cachePassphraseProvider` to the config password on engine start
- `ui/browser_pane.dart` + `ui/inspector_panel.dart` + `ui/folder_thumbnail.dart`: pass `cacheSecret` /
  `remoteSecret` = remote name
- `ui/settings_screen.dart`: **Preview cache** section — size, **Clear cache**, **memory-only** toggle
- pubspec → `cryptography: ^2.7.0`, alpha.19

**Database/API Changes:** None
**Summary:** alpha.19 — the on-disk preview cache is now **encrypted at rest**. When your rclone config is
password-encrypted, the cache key is derived from that password (PBKDF2), so the cached blobs are unreadable
without it. With an unencrypted config it falls back to a per-remote-name key (obfuscation only, by design —
the name isn't secret). Settings gains a **Preview cache** panel: see the size, **clear** it, or flip
**memory-only** to never write previews to disk. All failures degrade safely (wrong key → regenerate).
analyze (0) / test (16) / Windows build green.

## [2026-06-28] - v0.1.0-alpha.18: fix video thumbnails (attach VideoController)

**Agent:** Airclone Build (Claude Opus 4.8)
**Files Modified:** `state/thumbnail_service.dart` — `_captureVideoFrame` now creates a `VideoController`
for the headless `Player`, sets volume 0, plays until `controller.waitUntilFirstFrameRendered`, pauses, then
`screenshot`s. libmpv only renders a frame when a video output is attached, so the previous (controller-less)
capture always returned null and videos fell back to the movie icon.
**Summary:** alpha.18 — mp4/mov/mkv/etc. now show real keyframe thumbnails in grid/media views (images were
already working). Bounded to 4 concurrent + disk-cached as before. analyze (0) green.

## [2026-06-28] - v0.1.0-alpha.17: tabs (multiple locations per pane)

**Agent:** Airclone Build (Claude Opus 4.8)
**Files Modified:**
- `state/browser_controller.dart`: tabs via an internal **`_Session`** list (each = a `BrowserState` + its
  own `history`/`idx`). The controller keeps `Notifier<BrowserState>` and `_emit()`s the active session's
  state with `TabInfo` `tabs` + `activeTab` overlaid — so the 36 existing `paneProvider` call sites are
  unchanged. New ops: `newTab` / `switchTab` / `closeTab`; navigation/history now operate on the active
  session. `BrowserState` gains `tabs`/`activeTab` + `TabInfo`.
- `ui/browser_pane.dart`: `_TabStrip` (shown only when >1 tab — chips switch, ✕ closes, **+** adds); a
  new-tab **+** button in the address row.
- `ui/home_screen.dart`: **Ctrl+T** (new tab) / **Ctrl+W** (close active tab) shortcuts.
- pubspec → alpha.17

**Database/API Changes:** None
**Summary:** alpha.17 — **tabs**. Each pane can hold several tabs, each remembering its own remote, path,
selection, view mode, and **independent back/forward history**. Add a tab with the **+** in the address row
or **Ctrl+T**; a tab strip appears once you have more than one; **Ctrl+W** closes the active tab. The whole
thing rides on an internal session model so the existing browser/UI code didn't have to change. analyze (0)
/ test (16) / Windows build green locally.

## [2026-06-28] - v0.1.0-alpha.16: folder previews + safe orphaned-engine reap (2-agent workflow)

**Agent:** Airclone Build (Claude Opus 4.8) + 2-agent parallel workflow
**Files Modified:**
- New (agent): `ui/folder_thumbnail.dart` (`FolderThumbnail` — lists a folder, composites its first ≤4
  images via the alpha.15 `FolderPreviewService`, falls back to the folder icon; cached)
- Edited (agent): `rclone/http_rclone_client.dart` — records the spawned rcd PID to a temp marker; on next
  `start()` best-effort `Process.killPid` the previously-recorded PID then clears it (targeted reap, never a
  broad name match); clears the marker on `quit()`
- New (me wiring): `ui/file_grid.dart` gains a `folderPreviews` flag → renders `FolderThumbnail` for dir tiles
  when on; `ui/browser_pane.dart` passes `folderPreviews: thumbsOn` to the grid
- pubspec → alpha.16

**Database/API Changes:** None
**Summary:** alpha.16 — **folder previews**: in grid view, a folder shows a composite of its first few images
(2×2) instead of a plain icon when thumbnails are enabled for the remote (local always; cloud opt-in), with a
graceful icon fallback for empty/non-image folders. Also fixes the **orphaned `rclone rcd`** accumulation
safely — only the single PID we recorded is reaped, so the user's unrelated rclone processes are never
touched. Both units authored concurrently by a 2-agent workflow. analyze (0) / test (16) / Windows build green.

## [2026-06-28] - v0.1.0-alpha.15: advanced transfer dialog + live stats (3-agent workflow)

**Agent:** Airclone Build (Claude Opus 4.8) + 3-agent parallel workflow
**Files Modified:**
- New (agents): `state/transfer_options.dart` (TransferMode/CompareMode, `TransferOptions`, `rcloneCmdPreview`,
  `buildRcCall` → `sync/copy|move|sync` + `_config`/`_filter`), `ui/transfer_options_dialog.dart`
  (`showTransferOptionsDialog` — Settings/Filters/rclone-cmd tabs, Dry-run/Run), `state/stats_controller.dart`
  (`statsProvider` 1s `core/stats` poller → `CoreStats`/`TransferItem`), `ui/stats_panel.dart` (`StatsPanel`
  live strip), `state/folder_preview.dart` (`FolderPreviewService` — composites a folder thumbnail from its
  first images; ready, wiring next)
- New (me): `TransferService.transferAdvanced(...)` dispatches `buildRcCall` with `_group`/`_async` + Job tracking
- Refactored: `ui/browser_pane.dart` (command-bar **Advanced transfer** button → dialog → `transferAdvanced`),
  `ui/home_screen.dart` (live `StatsPanel` strip in the transfers dock, shown while transfers are active)
- pubspec → alpha.15

**Database/API Changes:** None (uses `sync/*` + `core/stats` RC)
**Summary:** alpha.15 — the **power-user transfer path**. Select files → **Advanced transfer** (tune icon)
opens a tabbed dialog: Copy/Move/Sync, skip-newer/skip-existing, compare by size/checksum, Include/Exclude/
Filter pattern lists, and a **live `rclone` command preview**, with **Dry run** or **Run**. While transfers
run, a **live stats strip** shows aggregate speed/ETA + per-file progress (`core/stats`). The three feature
units were authored concurrently by a 3-agent workflow, then integrated. analyze (0) / test (16) / Windows
build green locally.

## [2026-06-28] - v0.1.0-alpha.14: Explorer-style command toolbar + view-size presets

**Agent:** Airclone Build (Claude Opus 4.8)
**Files Modified:**
- `ui/browser_pane.dart`: rebuilt `_PaneToolbar` into a two-row header — **address row** (active dot ·
  back/fwd/up/refresh · breadcrumb PathBar · filter · close) and a **command bar** (`_commandRow`): New
  folder · Cut · Copy · Paste · Rename · Delete (selection-aware enable/disable) · **Sort ▾** menu
  (Name/Size/Modified + direction arrow) · **View ▾** menu (Extra-large/Large/Medium/Small icon presets
  → grid `maxCrossAxisExtent`, List, Media gallery, + Thumbnails toggle). Command bar handlers
  (`_clip`/`_paste`/`_rename`/`_delete`) call the existing clipboard/file-ops/transfer providers; horizontal
  scroll prevents overflow in narrow/dual-pane. Removed the old `_ViewControls`/`_ViewSettingsPanel`
  (folded into the View menu).
- pubspec → alpha.14

**Database/API Changes:** None
**Summary:** alpha.14 — the pane header now reads like a native file manager: a top **address row** and a
**command toolbar** beneath it. File verbs (New/Cut/Copy/Paste/Rename/Delete) enable based on the
selection + clipboard; **Sort** and **View** are proper dropdown menus, and **View** exposes the
Windows-style icon-size presets (Extra-large → Small) plus List/Media and the per-remote Thumbnails
toggle. analyze (0) / test (16) / Windows build green locally.

## [2026-06-28] - v0.1.0-alpha.13: instant context menu + resizable/hideable sidebar

**Agent:** Airclone Build (Claude Opus 4.8)
**Files Modified:**
- `ui/context_menu.dart`: replaced Flutter's `showMenu` (300ms scale-in) with a custom near-instant
  `PopupRoute` (`_ContextMenuRoute`) — 60ms fade, no scale, no barrier tint, cursor-anchored + on-screen
  clamped (`_MenuLayout`), themed `_MenuPanel`/`_MenuRow`
- `ui/browser_pane.dart`: `_showFileMenu` no longer `await`s `operations/fsinfo` before showing — reads the
  cached capability via `ref.read(remoteFeaturesProvider(fs)).valueOrNull` (menu opens instantly; the
  "Get public link" item appears once the capability is warmed)
- `ui/home_screen.dart`: `sidebarVisibleProvider` + `sidebarWidthProvider`; top-bar **hide/show sidebar**
  toggle; draggable `_SidebarResizeHandle` (resize cursor, clamp 170–460px)
- `dev/backlog/feature-backlog.md`: new **Explorer-Native UX Track** section consolidating all the
  requested Explorer/Finder-parity work (command toolbar, tabs, view presets, native skins, folder
  previews, advanced transfer dialog, queue/scheduler, statistics) + recommended additions
- pubspec → alpha.13

**Database/API Changes:** None
**Summary:** alpha.13 — two snappiness/ergonomics wins. The **right-click menu is now instant** (the lag
was an fsinfo RC round-trip blocking the menu *plus* the 300ms scale animation — both removed). The
**sidebar resizes** by dragging its divider and **hides** from a top-bar toggle. Also began the master
**Explorer-Native UX backlog** to track the growing set of native-file-manager parity requests. analyze
(0) / test (16) / Windows build green locally.

## [2026-06-28] - v0.1.0-alpha.12: auto-thumbnails for pictures + videos

**Agent:** Airclone Build (Claude Opus 4.8)
**Files Modified:**
- `state/thumbnail_prefs.dart`: flipped semantics from an enabled-set (default off) to a **disabled-set**
  (`thumbnailsDisabledProvider`, default empty = on everywhere) + `thumbnailsOn(remote, disabled)` helper
  (local always on; cloud on unless opted out)
- `state/thumbnail_service.dart`: `ThumbRequest.isVideo`; **video keyframe capture** via media_kit
  (`Player` opened headlessly → wait for first decoded frame → libmpv `screenshot` → downscale → cache),
  refactored shared `_downscaleAndCache`, image/video dispatch behind the existing concurrency gate + dedup
- `ui/file_icon.dart`: `isVideoThumbnailable` + `isThumbnailable` (image OR video)
- `ui/browser_pane.dart`: `thumbReqFor` now uses `thumbnailsOn(...)` + `isThumbnailable` and sets `isVideo`;
  view-settings popover toggle reworked to disable-for-cloud semantics (local shown as always-on)
- `ui/inspector_panel.dart`: big preview uses the same default-on + video path
- pubspec → alpha.12

**Database/API Changes:** None
**Summary:** alpha.12 — thumbnails now **auto-generate for both pictures and videos** instead of being
off-by-default. **Local** folders always render previews (no bandwidth cost); **cloud** remotes are on by
default with a one-tap **disable** in the view-settings popover for metered backends. Video thumbnails grab
a first-frame keyframe through libmpv (media_kit) with no visible player, downscaled and immutably
disk-cached; any failure falls back to the kind icon. analyze (0) / test (16) / Windows build green locally.
(Android stays `continue-on-error` for one more release while the new `file_selector` plugin's APK build is
confirmed.)

## [2026-06-28] - v0.1.0-alpha.11: collapsible/editable sidebar + android build fix

**Agent:** Airclone Build (Claude Opus 4.8)
**Files Modified:**
- `state/local_locations.dart`: split into `drivesProvider` (auto-detected disks) + `userLocationsProvider`
  (`UserLocations` Notifier — persisted, editable, seeded with default user folders; `addFolder`/`remove`,
  JSON-serialized) + `collapsedSectionsProvider` (`CollapsedSections` Notifier — persisted set of collapsed
  section keys); `LocalKind.folder` for custom folders; `LocalLocation` toJson/fromJson
- `ui/home_screen.dart`: rebuilt `_Sidebar` into three collapsible sections (LOCATIONS / DISKS / CLOUD) via
  a new `_SectionHeader` (chevron toggles + persists collapse); Locations are editable — `+` opens a native
  folder picker, an OS folder drag-drop (`desktop_drop` `DropTarget`) adds folders, and each has a "Remove
  from sidebar" action; `_RemoteTile` gains a `deleteLabel`
- pubspec: `desktop_drop` ^0.6.0 → **^0.7.1** (fixes the android APK build — 0.7.x compiles against
  compileSdk 34+, resolving `desktop_drop:checkReleaseAarMetadata`), added `file_selector` ^1.0.0 (folder picker)
- Reverted the alpha.10 root-Gradle `compileSdk` override (errored under AGP 9)

**Database/API Changes:** None
**Summary:** alpha.11 — the sidebar is now a collapsible tree: **Locations**, **Disks**, and **Cloud** each
toggle open/closed via a chevron (state persisted). **Locations** is fully editable — add folders with the
**+** native picker or by **dragging a folder in** from the OS, and remove any via its menu; the set is
persisted and seeded with your standard user folders on first run. Disks are auto-detected; Cloud is your
rclone remotes. Also: the **android release build is fixed** by bumping `desktop_drop` to 0.7.1 (the actual
root cause from the build log — its androidx deps required compileSdk 34+ while the plugin compiled against
33). analyze (0) / test (16) / Windows build green locally.

## [2026-06-28] - v0.1.0-alpha.9: local-filesystem browsing + grouped sidebar + single-pane layout

**Agent:** Airclone Build (Claude Opus 4.8)
**Files Modified:**
- New: `state/local_locations.dart` (`localLocationsProvider` — drives C:..Z: + Home/Desktop/Documents/Downloads/Pictures/Videos/Music, each an openable local `Remote`; cross-platform with `/` root on POSIX)
- Refactored: `ui/home_screen.dart` — grouped sidebar (LOCATIONS + CLOUD sections, `_sectionHeader`/`_localIcon`/`_openOrToggle` helpers), `_RemoteTile` gains a `leadingIcon` override; `singlePaneProvider` (default single-pane); `_WorkArea` renders one wide pane by default (active pane) with the dual-pane commander behind a top-bar toggle; `_TopBar` split/single toggle
- CI: `.github/workflows/release.yml` android job → `continue-on-error: true` (best-effort; never blocks the desktop release or fires a failure email until the android build is fixed)
- pubspec → alpha.9

**Database/API Changes:** None — local browsing reuses rclone's `local` backend through the existing `RcloneClient` (list/copy/preview/thumbnail all work unchanged).
**Summary:** alpha.9 — addresses feedback that the app wasn't explorable like a normal file manager and
didn't *feel* like Spacedrive. The sidebar is now grouped into **Locations** (your drives + standard user
folders, browsable like any explorer) and **Cloud** (rclone remotes). The default layout is a **single
wide explorer** (sidebar · explorer · inspector) — Spacedrive-like — with the **dual-pane commander** kept
behind a one-click top-bar toggle for side-by-side transfers. Local folders are drop targets too (drag in
to copy). analyze (0) / test (16) / Windows build green locally. Android remains a known, separate failure
(now best-effort in CI) pending the actual build log.

## [2026-06-28] - v0.1.0-alpha.8: explorer redesign Phase 2 — inspector, media gallery, quick look

**Agent:** Airclone Build (Claude Opus 4.8) + 3-agent workflow
**Files Modified:**
- New (agents): `ui/inspector_panel.dart` (right-rail details: Overview/More tabs, big thumb/icon, quick-action pills, multi-select + folder/empty states; `inspectorVisibleProvider`), `ui/media_gallery.dart` (date-grouped image/video gallery with pinned day headers + square tiles + video badge), `ui/quick_look.dart` (`showQuickLook` immersive overlay reusing `PreviewContent`, ←/→ nav, Space/Esc close)
- New (me): extracted reusable `PreviewContent` ConsumerWidget out of `preview_dialog.dart`
- Refactored: `state/browser_controller.dart` (ViewMode.media), `ui/browser_pane.dart` (media branch + shared thumbReq/quickLook closures, 3-way list/grid/media segmented control, Quick Look wired to double-click + right-click Preview), `ui/home_screen.dart` (inspector rail in the work area, top-bar Info toggle, Ctrl+I + Space shortcuts), pubspec → alpha.8
- Tests: media-gallery render test (date header) added to `browser_pane_test.dart`

**Database/API Changes:** None (Quick Look + inspector reuse existing object URLs / RC calls)
**Summary:** alpha.8 — Phase 2 of the explorer. A toggleable **Inspector** rail (Info button / **Ctrl+I**)
shows the active pane's selection: large thumbnail/icon, name, kind·size, quick actions (Preview, Download,
Copy link when supported), with Overview/More tabs and multi-select/folder summaries. A third **Media
gallery** view renders images + video as square thumbnail tiles grouped by date under pinned day headers
(video tiles get a play badge). **Quick Look** (**Space**, double-click, or right-click → Preview) opens an
immersive overlay reusing the preview renderers, with **← / →** navigation across the listing and Space/Esc
to close. The preview renderer was extracted into a reusable `PreviewContent`. analyze (0) / test (16) /
Windows build all green locally.

## [2026-06-28] - v0.1.0-alpha.7: explorer redesign Phase 1 — grid view + thumbnails

**Agent:** Airclone Build (Claude Opus 4.8) + 3-agent workflow
**Files Modified:**
- New (agents): `ui/file_icon.dart` (FileKind classifier + icon/tint resolver), `state/thumbnail_service.dart` (disk-cached, concurrency-gated, in-flight-deduped thumbnail loader over rclone object URLs) + `ui/thumbnail_image.dart` (icon→thumb fade widget) + `state/thumbnail_prefs.dart` (per-remote on/off, persisted), `ui/file_grid.dart` (virtualized grid of icon/thumbnail cards)
- New (me): `ui/pane_drag.dart` (extracted shared `PaneDragData` + `joinPath` to break a view↔view cycle)
- Refactored: `state/browser_controller.dart` (ViewMode + gridSize per-pane state + setters, preserved across remotes), `ui/browser_pane.dart` (list/grid switch in `_body`, list-only ColumnHeader, `_ViewControls` toolbar = list/grid toggle + density slider + Thumbnails switch, list rows adopt the shared icon resolver), `ui/home_screen.dart` (import the moved `pane_drag`), pubspec → alpha.7
- Tests: grid-view render test + `file_icon` kind/thumbnailable unit tests

**Database/API Changes:** None (thumbnails reuse the existing `rcd --rc-serve` object URLs)
**Summary:** alpha.7 — the first Spacedrive-grade explorer pass. Each pane can switch to a **grid view**
with a type-aware **icon system** (folders/images/video/audio/pdf/archive/code/docs, tinted from tokens).
**Thumbnails** render lazily over rclone — **off by default** (icons only, zero network beyond the
listing), flipped on **per remote** from the toolbar's view-settings popover for richer scrolling
previews; generated visible-window-only, downscaled to 256px WebP/PNG, immutably disk-cached by
`(remote,path,modTime,size)`, with bounded concurrency + in-flight dedup. Live **grid-density** slider.
Direction captured in `wiki/core/20-explorer-design.md` + `dev/plans/explorer-redesign-plan.md`. Built
via a 3-agent workflow against fixed contracts; analyze/test (15)/Windows build all green locally.

## [2026-06-28] - v0.1.0-alpha.6: video/audio previews + sortable columns

**Agent:** Airclone Build (Claude Opus 4.8) + 2-agent workflow
**Files Modified:**
- New (agents): `ui/media_preview.dart` (media_kit video/audio), `ui/column_header.dart` (SortKey + comparator + header)
- Refactored: `ui/preview_dialog.dart` (video/audio kinds), `state/browser_controller.dart` (sort state + setSort), `ui/browser_pane.dart` (ColumnHeader), `main.dart` (MediaKit.ensureInitialized), pubspec (+media_kit, media_kit_video, media_kit_libs_video)

**Database/API Changes:** None
**Summary:** alpha.6 — **video & audio previews** (libmpv-backed media_kit, streamed via the engine serve URL) and **sortable columns** (click Name/Size/Modified to sort asc/desc, folders always first). Verified media_kit builds on Windows before building the feature. analyze/test/build green locally.

## [2026-06-28] - v0.1.0-alpha.5: previews, editable path bar, right-click menus, keyboard nav

**Agent:** Airclone Build (Claude Opus 4.8) + 3-agent workflow
**Files Modified:**
- New (agents): `ui/preview_dialog.dart` (image/text/markdown/PDF), `ui/path_bar.dart`, `ui/context_menu.dart`, `state/clipboard_controller.dart`
- New (me): `state/remote_features.dart` (fsinfo capability gating); engine `objectRef()` (serve URL) in `rclone_client.dart` + `http_rclone_client.dart`
- Refactored: `state/browser_controller.dart` (history/back-forward, filter, navigateTo, selectAll, filter FocusNode provider), `ui/browser_pane.dart` (path bar, right-click menus, preview, clipboard, filter box, deselect), `ui/home_screen.dart` (keyboard shortcuts, sidebar deselect-toggle), pubspec (+flutter_markdown, pdfrx)

**Database/API Changes:** None
**Summary:** alpha.5 (built locally via the new Flutter+VS toolchain — sub-15s builds, no CI loop): file/photo **previews** (images/text/markdown/PDF streamed via an authenticated engine serve URL), an Explorer-style **editable path bar**, rich **right-click context menus** + copy/cut/paste **clipboard**, **back/forward history** + **filter box** + **keyboard shortcuts** (Alt-nav, Ctrl+F) = REM #9. Plus: deselect a remote (sidebar toggle + close button), and public-link gated by `operations/fsinfo` capabilities. REM #20 (multi-select) and #10 (folders-first) were already done.

## [2026-06-28] - v0.1.0-alpha.4: fix blank-pane StackOverflow

**Agent:** Airclone Build (Claude Opus 4.8)
**Files Modified:** `app/lib/src/ui/browser_pane.dart`, `app/test/browser_pane_test.dart`
**Database/API Changes:** None
**Summary:** Fixed the alpha.3 blank-pane regression — a `DragTarget` builder for folder rows captured the `row` variable *after* it was reassigned to the DragTarget itself, causing infinite self-rendering (`StackOverflowError`, shown as a gray box in release builds). Captured the row content in a separate `base` variable. Added a `BrowserPane` widget test (regression guard) reproducing + verifying the fix in the container.

## [2026-06-28] - v0.1.0-alpha.3: dual-pane, transfers, jobs, file-ops, settings (multi-agent)

**Agent:** Airclone Build (Claude Opus 4.8) + 4-agent workflow
**Files Modified:**
- New (agents): `models/job.dart`, `state/jobs_controller.dart`, `state/transfer_service.dart`, `ui/jobs_panel.dart`, `state/file_ops.dart`, `ui/file_op_dialogs.dart`, `state/settings_controller.dart`, `state/app_info.dart`, `ui/settings_screen.dart`, `ui/destination_picker.dart`
- New (me): `state/bandwidth_controller.dart`, `ui/bandwidth_control.dart`, `ui/browser_pane.dart`
- Refactored: `state/browser_controller.dart` (dual-pane A/B + multi-select), `ui/home_screen.dart` (dual-pane shell, jobs dock, top-bar controls), `ui/app.dart` (theme mode), `pubspec.yaml` (+desktop_drop, package_info_plus, url_launcher, shared_preferences)
- `tool/install-windows.ps1` (upgrade-aware)

**Database/API Changes:** None
**Summary:** alpha.3 — built largely by a 4-agent workflow (jobs/transfer engine, file-ops, settings/update, destination picker) integrated with a hand-written dual-pane shell: dual-pane + multi-select, drag-and-drop transfers (pane↔pane, into folders, OS→app upload, drop-onto-remote), async **jobs panel** (live speed/ETA, cancel), file operations (new folder/rename/delete), **bandwidth limit**, **settings** (theme/rclone-path) + app version + GitHub update check. analyze/test/format green.


**Agent:** Airclone Build (Claude Opus 4.8)
**Files Modified:**
- `app/lib/src/rclone/models/provider.dart` (RcloneProvider/ProviderOption), `rclone_engine.dart` (isConfigEncrypted), `http_rclone_client.dart` (RCLONE_CONFIG_PASS)
- `app/lib/src/state/` (providers_provider, add_remote_controller, engine_controller password gate, browser clear)
- `app/lib/src/ui/add_remote_dialog.dart` (new), `home_screen.dart` (+ button, delete, password gate)
- `app/test/widget_test.dart` (+ provider tests); `tool/run-windows.ps1` (visual smoke-test harness)

**Database/API Changes:** None
**Summary:** alpha.2 — add-remote wizard (provider picker + dynamic form from `config/providers` + interactive `config/create` state-machine for OAuth/multi-step), delete remote (`config/delete`), and **encrypted-config support** (out-of-band detection + password gate → `RCLONE_CONFIG_PASS`, never `--ask-password=false`). analyze/test/format green; reusable Windows screenshot harness added.


**Agent:** Airclone Build (Claude Opus 4.8)
**Files Modified:**
- `app/**` (Flutter project: theme tokens, models, `RcloneClient` + `HttpRcloneClient`, `RcloneEngine`
  provisioner, Riverpod state, UI shell, unit tests)
- `.github/workflows/ci.yml` + `release.yml`, `docker-compose.yml`, `tool/*`
- `wiki/core/04-directory-structure.md`, `dev/backlog/feature-backlog.md` (profile-sync), `.gitignore`

**Database/API Changes:** None
**Summary:** Stood up the build pipeline (local Docker for analyze/test, GitHub Actions windows/macOS/
linux/android runners for binaries) and implemented the v0.1 alpha: a Flutter desktop shell that
provisions/starts the rclone engine (`rcd` over loopback HTTP behind the `RcloneClient` seam) and
browses remotes + local disk via `operations/list`. analyze/test/format all green in-container.


**Agent:** Airclone Docs (Claude Opus 4.8)
**Files Modified:**
- `wiki/core/19-enterprise-readiness.md` (new), `wiki/core/15-security.md` (new)
- `wiki/core/00-system-index.md`, `01-vision-north-star.md`, `02-product-context.md`, `16-glossary-of-terms.md`
- `dev/backlog/feature-backlog.md` (Enterprise track), `dev/plans/cross-platform-architecture-plan.md` (Enterprise track + risks 19–26)
- `README.md`; `reference/research/enterprise-*.md` (gitignored research)

**Database/API Changes:** None
**Summary:** Researched and documented enterprise readiness (MDM/policy deployment, SSO/SCIM/RBAC, secrets/encryption/FIPS, audit→SIEM, DLP governance, supply-chain/SBOM/SLSA, air-gapped, headless/HA, commercial model), reconciled with the privacy-first stance via a customer-owned control plane + opt-in egress, and folded an Enterprise track into the roadmap with open decisions (hybrid open-core, defer management plane, Apache-2.0) flagged for sign-off.

## [2026-06-28] - Sharpen file-explorer-as-hero direction

**Agent:** Airclone Docs (Claude Opus 4.8)
**Files Modified:**
- `wiki/features/feat-file-browser.md` (new hero-feature doc)
- `wiki/core/05-app-structure.md`, `wiki/core/08-core-architecture.md`, `wiki/core/01-vision-north-star.md`
- `wiki/features/features-index.md`, `dev/backlog/feature-backlog.md`

**Database/API Changes:** None
**Summary:** Established the in-app rebuilt rclone file explorer (multi-remote tabs + dual-pane, inline config, target-aware in-app drag-and-drop onto folders, direct server-side/non-VFS transfer engine) as the primary, performant hero surface, with the OS mount repositioned as a secondary convenience whose VFS overhead is called out.

## [2026-06-28] - Bootstrap documentation architecture & deep research

**Agent:** Airclone Bootstrap (Claude Opus 4.8)
**Files Modified:**
- `.gitignore` (ignore `/reference/`)
- `wiki/**`, `dev/**`, `Skills/**` (Vibe-App-Wiki documentation scaffold adopted)
- `AGENT.md`, `HOW-TO.md`, `DESIGN.md`, `README.md`
- `reference/**` (gitignored — competitive research, rclone-engine integration notes, framework decision, mobile-mount strategy)

**Database/API Changes:** None
**Summary:** Initialized the Airclone repository as a modern cross-platform rclone GUI. Adopted a structured documentation methodology, set up a gitignored `reference/` area for external research, ran a deep multi-agent research pass across competing rclone GUIs and the rclone engine, and authored the vision, cross-platform architecture/modernization plan, feature backlog, and design direction.
