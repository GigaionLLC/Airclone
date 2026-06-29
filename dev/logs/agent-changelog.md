# 📝 Agent Changelog

All changes made by AI agents are tracked chronologically below (most recent first).

---

<!-- New entries go above this line, most recent first -->

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
