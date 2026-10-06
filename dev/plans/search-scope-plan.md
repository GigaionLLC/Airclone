# 📦 Parcel Plan: Search — one box, this folder by default, subfolders one step away

## 📊 State Dashboard
| Metric | Value |
| :--- | :--- |
| **Status** | `BUILT` (branch `feat/search-scope`) — A1-A9 done: analyze clean, all app + package tests pass. Open: A10 real Google TV pass and Web UI smoke; Phase B (multi-select over results) not started. |
| **Version** | `v1.0.0` |
| **Active Persona** | `Architect` |
| **Last Updated** | 2026-10-04 (built) |

Branch: `plan/search-scope-and-player-formats` (plan only). Sister plan, same customer email:
[player-format-support-plan.md](player-format-support-plan.md).

---

## 1️⃣ Phase 1: Expansion & Scoping

* **The ask (customer email, Android TV user, 2026-10-04):**
  > "One thing that could be improved would be the search feature for files, not only on the current
  > folder but the ability to search inside all sub-folders also."

* **What the code says.** Recursive search **already exists** — `operations/list` with
  `recurse: true` in `search_dialog.dart` (removed by this plan). The customer did
  not find it, or did not believe it: the phone/TV header button is labelled `Search this folder` and
  the dialog is titled `Search in <remote>/<folder>`. Meanwhile there are two different tools with two
  different rules — a live **Filter** box (desktop only, current folder, name substring) and a
  **Search dialog** (all shells, recursive, button-press, tokens over name + path). That split is the
  real defect.

* **Jake's direction (2026-10-04):** search defaults to the **current folder**, with an option that is
  *easy and obvious* to extend it to **current + subfolders**. Not a separate dialog.

* **Intent:** One search box per pane, on every shell (desktop, phone, Android TV, Web UI). Typing
  filters the current folder instantly. One visible control — and one row at the end of the results —
  extends the same query to every subfolder, with results shown in the pane.

* **In Scope:**
  - `PaneSearchBox` — one shared widget replacing `_FilterBox` (desktop toolbars) and the phone/TV
    header's search icon + dialog.
  - Scope control `This folder | Subfolders` (text segments, TV-focusable), plus a trailing
    **`Search subfolders for "<q>"`** row in the results (and in the "No matches" state).
  - In-pane subfolder results: each row shows its folder path; open, reveal-in-folder, preview,
    context menu resolved from the row's **full path**.
  - Recursive scan as an **async RC job** (`_async` + `job/status` + `job/stop`): no 30 s timeout,
    real cancel, indeterminate progress (elapsed time + item count when done).
  - Listing **cache** for the (remote, folder) while the query is refined — typing re-filters in
    memory, it never re-lists.
  - Scope resets to `This folder` on navigation (Jake). Esc / system Back closes subfolder results
    before navigating.
  - Crypt honesty: warn when undecryptable names were skipped during the scan.
  - Remove `search_dialog.dart` and its two call paths; update shortcuts, palette, docs.
* **Out of Scope (v1):**
  - **Multi-select and bulk operations across subfolder results** (copy/move/delete many hits at
    once). Single-row actions are in scope; bulk is Phase B below, because it is the stale-path /
    wrong-object risk class the tree view was built against.
  - Content (full-text) search, search history, saved searches, cross-remote ("all remotes") search.
  - A persistent index. The cache lives only as long as the pane stays on that folder.
  - Server-side `_filter` pruning (does not shorten the backend walk; tokens-AND over path is not
    expressible as an rclone filter — see §2 RC notes).

## 2️⃣ Phase 2: Requirements & Context

Line numbers are at `97fd8fb` (v0.22.2); `~` means approximate. Paths relative to `app/lib/src/`.

* **Relevant Docs Found:**
  - [`docs/guide/browsing.md`](../../docs/guide/browsing.md) §"Filtering, and searching" (~L165-182),
    toolbar mention (~L72), `No matches` (~L437), keyboard table (~L448-485, incl. "None of these fire
    while you are typing in the filter box").
  - [`wiki/features/feat-file-browser.md`](../../wiki/features/feat-file-browser.md) §6 (~L260-270):
    per-pane filter box + "Find is one `operations/list` with `recurse: true`, at most 500 matches".
  - [`wiki/core/10-external-integrations.md`](../../wiki/core/10-external-integrations.md) L214
    (`operations/list` consumers, links `search_dialog.dart#L79`).
  - [`wiki/core/06-design-system.md`](../../wiki/core/06-design-system.md) ~L171 (shortcut list mirrors
    `shortcuts_dialog.dart`).
  - [`dev/android-tv.md`](../android-tv.md) — focus visibility, the text-field trap, the D-pad probe.
  - [`archive-plans/tree-view-plan.md`](../archive-plans/tree-view-plan.md) — the full-path row model
    and the v0.5.0 stale-path invariant this plan reuses.

* **Relevant Code Found:**
  - **Filter box** — `_FilterBox` [`ui/browser_pane.dart`](../../app/lib/src/ui/browser_pane.dart)
    L2869-2938; placed only in the two desktop toolbars (Airclone skin ~L1943-1947, OS skins
    ~L2302-2305). Text sync is one-way and only on "became empty" (L2896-2898) — **latent bug:** switching
    to a tab with a non-empty filter shows an empty box.
  - **Filter state** — `BrowserState.filter` (String) in the per-tab `_Session`,
    [`state/browser_controller.dart`](../../app/lib/src/state/browser_controller.dart): field ~L102,
    `visibleEntries` L190-195 (name substring), `setFilter` L521, cleared in `_navigate` L483 (all
    navigation funnels through `_navigate` L461-490), and in `open`/`clear`.
  - **Tree filter** — `flattenTree(filter:)` [`state/tree_state.dart`](../../app/lib/src/state/tree_state.dart)
    L162-212 (filters only what is loaded). `TreeRow.entry(entry, parentPath, depth)` L90+,
    `parentOf`, `groupByParent`.
  - **Everything that reads "what is displayed"** goes through `visibleEntries` / `flattenTree`:
    `browser_pane.dart` `_body` (L301-560; list/grid/media/tree), `home_screen.dart` L210 (type-ahead),
    L238/L368 (Quick Look / scroll-into-view), L1676 (status bar count), `ui/mobile_home.dart` L616
    (select-all in selection bar), `ui/storage_breakdown.dart` L54, `selectAll` (browser_controller ~L559-585).
  - **Empty state** — `browser_pane.dart` L340-384: `'Empty folder'` vs `'No matches'`; hidden-undecryptable
    banner L556-557.
  - **Search dialog** — `ui/search_dialog.dart` (removed by this plan) (307 lines):
    synchronous `operations.list(fs, basePath, opt: {'recurse': true, 'noModTime': true})` L78-84,
    tokens-AND over `'${name} ${path}'` L86-100, cap 500, sorts only the kept 500. Callers:
    desktop `_openSearch` [`ui/home_screen.dart`](../../app/lib/src/ui/home_screen.dart) L325-361
    (+ `_scrollSelectedIntoView` L365-380, hard-coded 36 px row), palette action L454-462, Ctrl+Shift+F
    L686-691; phone `mobileFolderSearch` [`ui/mobile_action_sheets.dart`](../../app/lib/src/ui/mobile_action_sheets.dart)
    L606-630, called from [`ui/mobile_home.dart`](../../app/lib/src/ui/mobile_home.dart) L565-571 (header
    icon, hidden when `compact`) and `mobile_action_sheets.dart` L242-245 (sheet tile when `compact`).
  - **Phone/TV header** — `_MobilePaneHeader` `mobile_home.dart` L458-~600: back/up · breadcrumb
    (`Expanded`) · search icon · view cycle · ⋯. `compact = maxWidth < 300`. System Back `PopScope`
    ~L86-135 (order: clear selection → leave tab → collapse split → up). TV takes this same shell
    (`home_screen.dart` L650) with a left `TvNavRail`; `TvShell` wraps the app.
  - **TV text fields** — `TvDpadEscape` [`ui/tv.dart`](../../app/lib/src/ui/tv.dart) L375-415 frees
    only UP/DOWN from a TextField; LEFT/RIGHT stay with the caret. Rows: `FileRow`
    [`ui/file_row.dart`](../../app/lib/src/ui/file_row.dart) with `TvRowMenuKey` (RIGHT = row menu) and
    `tvSkippableFocusNode` on its ⋯ button ([`ui/tv_row_actions.dart`](../../app/lib/src/ui/tv_row_actions.dart)).
  - **Async + cancel precedent** — `CompareJob` + `FileOps.compare`
    [`state/file_ops.dart`](../../app/lib/src/state/file_ops.dart) L20-205: `RcOptions(async: true)`,
    take `jobid` (or accept an inline answer), poll `job/status` every 400 ms, `job/stop` on cancel,
    a stopped job reports failure → treat as cancel. `RcJob.status/stop` in
    [`rc_api.dart`](../../packages/airclone_rc/lib/src/rc_api.dart) L440-467.
  - **Timeouts** — every RC call has a 30 s transport timeout (`HttpRcloneClient.requestTimeout`,
    `RemoteRcloneClient.requestTimeout`). A big synchronous recursive list fails **today**.
  - **Stale-result guard precedent** — `_loadTreeFolder` (browser_controller L738-785): per-session
    generation, `superseded()`, commit into the *originating* `_Session` even if it is not the active tab.
  - **Crypt** — `_load` samples `undecryptableNameCount` around the listing and sets
    `hiddenUndecryptable` (~L802-825; `hiddenForBackend` in `state/undecryptable_names.dart` L61). The
    dialog never did — a mis-keyed crypt returns a confident "No matches".
  - **Local remotes** — the dialog lists `remote.fs`; browsing lists `remote.listFs` (adds
    `copy_links=true`). Keep `remote.fs` for the recursive scan deliberately: following symlinks /
    Windows reparse points recursively can loop (see `test/local_reparse_listing_test.dart`).
  - **Web UI** — same Flutter UI compiled for web; `operations/list`, `job/status`, `job/stop` are all
    on the allowlist ([`webui/webui_rc_policy.dart`](../../app/lib/src/webui/webui_rc_policy.dart) L120,
    L151-153); no guard on `recurse`. No policy change needed. Check how `webui_server.dart` annotates
    `onlineOnly` on a recursive list before shipping (per-entry host probe could be slow).
  - **Segmented controls to reuse** — `_ViewSegmented` (browser_pane.dart L1724-1789, private, icon-only,
    28 px — too small/unlabelled for TV), Material `SegmentedButton` (mobile_home.dart L880-889),
    `ChoiceChip` (tasks_panel.dart L1329). Tokens: `Space`, `Radii`, `AircloneTheme.of/tokensOf`.

* **RC notes.** A single async `operations/list recurse` job gives **no partial results and no
  progress counter**; `job/status.output` is `{list: [...]}` like the sync answer. Finished jobs expire
  after `--rc-job-expire-duration` (60 s default) — read the output on the first `finished: true`. The
  alternative (client-side BFS of per-folder lists) gives streaming results but N round-trips and loses
  `ListR` on backends that have it; rejected for v1, noted in §3 Q4.

## 3️⃣ Phase 3: User Clarification

Defaults are chosen so the build is not blocked; Jake can overturn any of them.

* `[x]` Default scope? → **Answer (Jake):** current folder. Subfolders is an easy, obvious option.
* `[x]` Dialog or inline? → **Answer (Jake):** "a different search bar or something more intuitive" —
  inline box with a scope control (this plan).
* `[ ]` **Q1. Should the scope survive navigation?** → **Default:** no — resets to `This folder` on
  every navigation, as Jake asked. (A user who opens a result and comes Back gets `This folder` again;
  the cached listing is kept for 2 minutes so re-choosing `Subfolders` on the same folder is instant.)
* `[ ]` **Q2. Matching rule.** → **Default:** one rule everywhere — case-insensitive, every
  whitespace-separated word must match. In `This folder` it matches the **name**; in `Subfolders` it
  matches **name or folder path** (so `2024 holiday` finds `Photos/2024/holiday.jpg`). Ranking in
  Subfolders: name starts with the query > name contains it > only the path contains it; then folders
  first; then path A-Z.
* `[ ]` **Q3. Start the subfolder scan when the scope is switched, or on Enter?** → **Default:** on
  switch. Choosing `Subfolders` starts the scan immediately (empty box allowed); typing then filters
  live in memory. That is the TV-friendly behaviour — no "now press Search" step.
* `[ ]` **Q4. Is indeterminate progress acceptable?** → **Default:** yes for v1 (`Scanning
  <folder>… 0:07` + Cancel). Streaming partial results needs the BFS approach; revisit only if users
  hit long waits.
* `[ ]` **Q5. Cache size cap.** → **Default:** 250,000 entries; beyond that, keep the first 250k and
  show `Only the first 250,000 items were searched — start from a smaller folder.`

## 4️⃣ Phase 4: Detailed Execution Plan

### 4.A The interaction (all shells)

```
Desktop toolbar / phone+TV header (title area becomes the box while searching)
┌──────────────────────────────────────────────────────────────────┐
│ 🔍 holiday                                              ✕        │
│ [ This folder | Subfolders ]                 3 in this folder    │   ← scope row, BELOW the box (TV: DOWN reaches it)
├──────────────────────────────────────────────────────────────────┤
│ 📁 holiday-2024                                                  │
│ 🎬 holiday-intro.mp4                                             │
│ 🔍 Search subfolders for "holiday"                          →   │   ← trailing row; also shown in "No matches"
└──────────────────────────────────────────────────────────────────┘

Subfolders mode
│ [ This folder | Subfolders● ]      Scanning Movies…  0:07  Cancel │
│ 🎬 holiday-intro.mp4          Movies/2024                12 MB   │   ← parent path line
│ 📁 holiday                    Photos/2023                        │
│ 41 matches in 18,204 items                                       │
```

Rules:
1. **This folder** = today's filter, unchanged in feel: live, per keystroke, all four view modes.
2. **Subfolders** = results list (list layout regardless of view mode — grid/gallery cannot show a
   path; tree view shows the flat result list too). Rows are `FileRow` + a parent-path line.
3. The trailing `Search subfolders for "<q>"` row appears in This-folder mode whenever the box has
   text, as the **last** list item and inside the `No matches` state. Activating it = switch scope.
   In grid/gallery it renders as a full-width footer button.
4. Opening a result: folder → `navigateTo(abs)` (scope resets — Jake's rule); file → preview as from
   the browser (sibling walk = the result's real folder? **No** — v1 previews the single file; the
   prev/next walk stays a browser-folder feature). Row menu adds **Show in folder** (navigate to
   parent + `selectOnly` + scroll into view — the dialog's current behaviour).
5. Close/clear: ✕ in the box clears text and returns to This folder; **Esc** (desktop) and
   **system Back** (phone/TV) close Subfolders results first, then clear the text, then behave as
   before. Navigation of any kind resets scope + text (already true for the filter at `_navigate`).
6. Shortcuts: `Ctrl+F` focuses the box (unchanged contract with `paneFilterFocusProvider`);
   `Ctrl+Shift+F` focuses the box **and** selects Subfolders. Palette action renamed
   `Search here and in subfolders…` → same as Ctrl+Shift+F.
7. Phone/TV header: the search icon stays where it is (tooltip `Search`). Pressing it swaps the
   breadcrumb `Expanded` for the box and shows the scope row as a second header line; Back/✕ swaps
   back. When `compact` (pane < 300 px) the sheet tile does the same thing.
8. Copy (exact strings): hint `Search this folder`; segments `This folder` / `Subfolders`; trailing row
   `Search subfolders for "<q>"`; progress `Scanning <folder>…` + elapsed `m:ss` + `Cancel`;
   done `<n> matches in <N> items`; cap notice per Q5; crypt warning
   `<n> names could not be decrypted — results may be incomplete.`; error = the RC message +
   `Try again`.

### 4.B State (`state/browser_controller.dart`)

* New immutable model, new file `state/pane_search.dart`:

```dart
enum SearchScope { folder, subfolders }
enum SearchScanStatus { idle, scanning, done, error, cancelled }

class SearchHit {            // one recursive result, path already absolute
  const SearchHit({required this.entry, required this.parentPath});
  final RcloneFile entry;    // entry.name is the leaf
  final String parentPath;   // absolute within the remote ('' = root)
  String get absPath => parentPath.isEmpty ? entry.name : '$parentPath/${entry.name}';
}

class PaneSearch {
  const PaneSearch({this.scope = SearchScope.folder, this.status = SearchScanStatus.idle,
      this.basePath, this.scanned = 0, this.truncated = false, this.hiddenNames = 0,
      this.error, this.startedAt});
  // + copyWith. Holds NO list — the cache lives in _Session (mutable, not diffed).
}

/// Pure, unit-tested: tokens-AND + ranking (Q2). Used by both scopes.
List<SearchHit> matchHits(List<SearchHit> all, String query, {int? limit});
bool matchesName(String name, String query);   // This-folder rule
```

* `BrowserState` gains `final PaneSearch search;` (ctor default, field, **copyWith** — remember
  `copyWith` drops `error` unless passed; do not repeat that pattern for `search`). `filter` stays the
  query string for both scopes (one source of truth for the box text).
* `visibleEntries` switches to `matchesName` (tokens-AND) so both scopes share the rule.
* New getter `displayedHits` (Subfolders + done/scanning-with-cache): `matchHits(cache, filter)`.
  Memoise on `(cacheIdentity, filter)` inside the controller, not in the getter, so a rebuild does
  not re-rank 250k entries — store the last ranked result in `_Session`.
* `_Session` gains: `List<SearchHit>? searchCache; String? searchCacheKey; DateTime? searchCacheAt;
  int searchGen = 0; SearchJob? searchJob;` (`SearchJob` = copy of `CompareJob`: attach/cancel,
  idempotent, safe before attach).
* Controller methods:
  - `setSearchScope(SearchScope s)` — folder: cancel job, status idle (keep cache). subfolders: if a
    fresh cache exists for `(remote.fs, path)` (< 2 min) use it, else `_startScan()`.
  - `_startScan()` — `gen = ++ses.searchGen`; cancel previous job; sample
    `undecryptableNameCount` before; `RcApi(client).operations.list(remote.fs, basePath,
    opt: {'recurse': true, 'noModTime': true, 'showHash': false}, options: RcOptions(async: true))`;
    take `jobid` or inline answer; poll `job/status` every 400 ms; on `finished`: if
    `superseded()` drop; map to `SearchHit` (re-prefix `basePath` once, here), apply cap Q5, sample
    counter after → `hiddenNames = hiddenForBackend(remote.type, before, after)`; commit into the
    originating session (pattern `_setTree`). A stopped job's failure = `cancelled`, not `error`.
  - `cancelSearch()` — `job/stop`, status `cancelled`, keep whatever cache existed.
  - `setFilter` unchanged (re-ranking happens off `filter`).
  - Reset: `_navigate` (L483) sets `search: PaneSearch()` and cancels the job; `open`, `clear`,
    `closeTab`, `switchTab` (cancel job of the session going away? **No** for switchTab — the scan
    keeps running and commits to its own session; **yes** for closeTab/clear/open).
  - Invalidate cache on `refresh()` and after any file op that targets a path under `searchCacheKey`'s
    base (FileOps completion hooks already trigger `refresh` of the pane — piggy-back on that).
* `selectAll` (L559-585): in Subfolders mode v1 does nothing (single-selection only — Phase B).
  `selectedEntries` stays empty while results are shown (same "safe failure" as tree mode), so every
  flat-selection operation in `home_screen.dart` / `browser_pane.dart` is inert on results.
* Single-row actions resolve from the hit: build the same `_treeLoc`-style location
  (`parentPath`, `entry`) used by the tree view (`browser_pane.dart` L1361), never `state.path + name`.

### 4.C RC helper (`packages/airclone_rc`)

* No new RC method. Optional typed convenience in `rc_api.dart`: `operations.listAsync(...)` returning
  `AsyncJob` — if added, pin its exact method/params in `packages/airclone_rc/test/rc_api_test.dart`.
  `RcloneClient` gains **no** member (package rule).

### 4.D UI

* **`ui/pane_search_box.dart`** (new, replaces `_FilterBox`): `ConsumerStatefulWidget(index,
  {dense})`. TextField bound to `paneFilterFocusProvider(index)` (keep the `home_filter_test.dart`
  contract). Two-way sync: on `state.filter` change set `_controller.text` when different (fixes the
  tab-switch bug). Debounce 120 ms in Subfolders mode only. Esc handling via `Focus.onKeyEvent`
  (clear → close scope). Under it (or beside it on wide desktop toolbars ≥ 900 px) the scope control.
* **`ui/search_scope_toggle.dart`** (new, shared): two **text** segments built on Material
  `SegmentedButton<SearchScope>` (`showSelectedIcon: false`), sized from `SkinTokens.rowHeight`, 40 dp
  minimum on TV. Real focusables → `TvFocusOverlay` rings them.
* **Desktop toolbars** — swap `_FilterBox` for `PaneSearchBox` at both sites (L1943-1947,
  L2302-2305); widen `_searchWidth` (L1717-1721) when the box has focus or text. Scope control and the
  status line ride in a 28 px strip directly under the toolbar, only while the box has text or scope is
  Subfolders (no permanent chrome).
* **Phone/TV header** — `_MobilePaneHeader`: `searchOpen` local state per pane (or derive from
  `filter.isNotEmpty || scope == subfolders`). When open, replace the breadcrumb `Expanded` with
  `PaneSearchBox(dense)` and add a second 44 dp line with the scope control + status. Back/Up button
  becomes "close search". `PopScope` gets a first step: close search for the active pane.
* **Results body** — in `browser_pane.dart` `_body`: when `scope == subfolders`, render
  `SearchResultsList` (new, `ui/search_results_list.dart`): progress strip (spinner 22 px stroke 2,
  `textMuted` 12) · crypt/cap notices · `ListView.builder` of `FileRow(..., subtitle: parentLabel)` ·
  footer count. `FileRow` gains an optional `subtitle` (one muted line under the name, ellipsised from
  the left so the nearest folder stays visible).
* **Trailing row** — `browser_pane.dart` list branch `itemCount + 1` when filter non-empty and scope
  folder; equivalent footer in grid/gallery/tree; in `nothingToShow` render `No matches` + the row (as
  a focusable `FilledButton.tonal` on TV/touch, a link-style row on desktop).
* **Remove** `ui/search_dialog.dart`, `test/search_dialog_test.dart`, `mobileFolderSearch` and the
  `showSearchDialog` imports (home_screen.dart L58, mobile_action_sheets.dart L24). `_openSearch` becomes
  "focus box + set Subfolders".
* **Status bar** (home_screen L1676): in Subfolders mode show `n matches` instead of `N items`.
* Type-ahead (`_onKey` L180-195) is disabled while Subfolders results are shown.

### 4.E TV specifics (must pass on a real Google TV, not just the AVD)

* The box is **not** a permanent traversal stop: on TV the header shows the search *icon* (as today);
  selecting it opens the box and focuses it (IME opens — expected, the user asked to type). DOWN
  leaves the field (`TvDpadEscape`) and lands on the scope control; DOWN again → first result / the
  trailing row. UP from the first row → scope control → box.
* The trailing row is a normal focusable list item (InkWell) so the natural DOWN path reaches it.
* RIGHT on a result row opens its menu (`TvRowMenuKey`, free via `FileRow`).
* Back: closes Subfolders → clears text → closes the box → then the normal Back chain.
* Verify with `dev/android/tv-dpad-probe.sh` (add a search leg: key events only) and screenshots for
  ring visibility (dev/android-tv.md rule).

### 4.F Test Verification Plan

* `docker compose run --rm flutter flutter analyze` and `... flutter test` (via `tool/flutter.sh`);
  `dart format`. `python tool/check-docs.py`.
* `[ ]` `pane_search_test.dart` (pure): tokens-AND, name vs path matching per scope, ranking order,
  cap/truncation flag, `SearchHit.absPath` at root and nested.
* `[ ]` `browser_search_controller_test.dart` (fake client): async job path (jobid → status polling →
  output), inline-answer path, cancel → `job/stop` sent + status cancelled, superseded result dropped
  after navigation, commit to originating tab after `switchTab`, cache reuse within 2 min, cache
  invalidated by `refresh()`, scope reset on every navigation method, crypt counter → `hiddenNames`.
* `[ ]` `pane_search_box_test.dart` (widget): Ctrl+F focuses (`paneFilterFocusProvider` contract),
  Ctrl+Shift+F focuses + Subfolders, Esc order, text re-syncs on tab switch, trailing row present only
  with text in folder scope and present inside `No matches`.
* `[ ]` `search_results_list_test.dart`: parent-path line, open folder navigates, open file previews
  the right absolute path, "Show in folder" selects + scrolls, select-all inert, no flat selection.
* `[ ]` TV: extend `tv_dpad_test.dart` — DOWN from the box reaches the scope control, then the first
  row / trailing row; Back order via `PopScope`.
* `[ ]` `home_filter_test.dart`, `tree_controller_test.dart` filter cases still pass (rule change to
  tokens-AND must not break single-word cases).
* `[ ]` Manual: large Google Drive folder (> 50k items) — no timeout, Cancel stops the job
  (`job/list` empty afterwards); crypt remote with wrong password shows the warning; Web UI search
  works through the proxy.

## 5️⃣ Phase 5: Product Owner Review
* **Status:** `PENDING` (pre-reviewed by the planner; formal pass at build time)
* **Findings (planner self-check):**
  - ✅ **Vision & Scope** — answers the customer and Jake's direction; removes the two-tools confusion.
  - ⚠️ **Business Logic & Edge Cases** — bulk ops on results deliberately deferred (Phase B); the 250k
    cap and indeterminate progress are honest but visible limits.
  - ✅ **Dependency & Functional Risk** — no new dependency; RC methods already allowlisted for the Web UI.
  - ⚠️ **Completeness & User Intent** — TV IME behaviour can only be confirmed on hardware.
* **Required Fixes:** None yet.

## 6️⃣ Phase 6: Senior Dev Hygiene Review
* **Status:** `PENDING`
* **Findings (planner self-check):**
  - ✅ **DRY Scan** — one matcher (`matchHits`/`matchesName`) for both scopes; one box widget for all shells.
  - ✅ **Abstraction & Architecture** — everything through `RcApi`; `RcloneClient` unchanged.
  - ✅ **State Management & Data Flow** — immutable `PaneSearch` in state, mutable cache + job in `_Session`, generation guard like `_loadTreeFolder`.
  - ✅ **Technical Debt & Deletion** — deletes the dialog + its test; fixes the tab-switch text bug.
  - ✅ **Secret Management** — n/a.
  - ✅ **Data Security** — full-path resolution for row actions; flat selection inert on results.
  - ✅ **Rate Limiting** — one recursive list per (folder, 2 min); job stopped on cancel/navigate.
  - ✅ **Error Handling** — stopped job = cancelled; RC error shown with Try again; crypt warning.
* **Required Fixes:** None yet.

## 7️⃣ Phase 7: Implementation Checklist (Execution)

**Phase A — v1 (this plan):**
- `[x]` A1 `state/pane_search.dart` (models + pure matcher) + tests. → `pane_search_test.dart`; the test caught a `Media//a.txt` path for matches directly in the search root, fixed.
- `[x]` A2 `BrowserState.search`, `_Session` cache/job, `setSearchScope` / `_startScan` / `cancelSearch`, resets + invalidation + tests. → `browser_search_controller_test.dart` (async job, inline answer, cancel + late answer dropped, navigation stops the job, cache reuse, refresh rescans, lands in its own tab, step-out order). Package gained `RcOperations.listAsync` + `parseList` (pinned in `rc_api_test.dart`).
- `[x]` A3 `visibleEntries` → tokens-AND (`matchesName`). Tree filter left on its substring rule (it filters only what is loaded; one-word queries behave the same).
- `[x]` A4 `ui/pane_search_box.dart` (`PaneSearchBox`, `SearchScopeToggle`, `SearchStrip`, `SearchSubfoldersRow`, `SearchResultsList`); `_FilterBox` deleted, both desktop toolbars use the box.
- `[x]` A5 Results body + `FileRow.subtitle`; context menu `Show in folder`, no `Select` on results.
- `[x]` A6 Phone/TV header box, `PopScope` first step, compact sheet tile `Search`. → `mobile_search_test.dart`.
- `[x]` A7 `Ctrl+Shift+F` = focus box + Subfolders; palette `Search here and in subfolders…`; status bar `n matches`; type-ahead off on results; `Esc` steps out after clearing a selection; `shortcuts_dialog.dart`.
- `[x]` A8 Deleted `search_dialog.dart`, `search_dialog_test.dart`, `mobileFolderSearch`.
- `[x]` A9 Docs: browsing.md (§Searching, shortcuts, empty states), feat-file-browser.md §6, 10-external-integrations.md, 06-design-system.md, dev/android-tv.md.
- `[ ]` A10 Real Google TV pass (IME, ring on the switch and the bottom row) and a Web UI smoke through the proxy.

**Deviations from §4 (deliberate):**
- The scope switch and status live in a strip at the top of the **pane body**, not the toolbar: the OS skins hoist their toolbar away from the pane, and the phone/TV header has no room. Same strip on every shell.
- `Search subfolders for "…"` is a **fixed row at the bottom of the pane**, not the last list item: always on screen, and reachable with DOWN however long the list is. Shown in every view mode and under `No matches`.
- `Enter` on a highlighted result does nothing yet (double-click / tap / menu open it).
- Desktop Esc inside the box: results → text → unfocus. The global `Esc` (no field focused) clears a selection first, then steps out of the search.

**Phase B — later, separate go-ahead:** multi-select over results (full-path selection set, like
`tree.selected`), copy/cut/delete/drag from results via `groupByParent`; `selectedTreeRows`-style
resolution that consults the result cache, not `childrenOf`.

## 8️⃣ Phase 8: Verification Dashboard
* **Verification Status:** `AUTOMATED PASS, EMULATOR PASS, HARDWARE PENDING` (2026-10-05)
* **Report:**
  - `[x]` `flutter analyze` clean; full app suite and `airclone_rc` suite pass (counts in the changelog entry).
  - `[x]` Code matches §4 except the deviations listed in Phase 7.
  - `[x]` API 36 Android TV emulator, remote only: box opens focused; This folder count + "No matches";
    the fixed Subfolders row; a 2,741-item scan with ranked results and folder paths; Show in folder;
    Back chain player → results → This folder. Fixed on the way: field not focused on open.
  - `[x]` API 35 phone emulator: same flow by touch. Fixed on the way: results read "long-… Airclo…"
    (name/folder split evenly, empty Modified column) — results now drop Modified, drop size below
    600 px, and give the name its full width first.
  - `[ ]` Real Google TV pass; Web UI smoke.

## 9️⃣ Phase 9: User Verification
* **Status:** `PENDING` — reply to the customer once a build with this is on Play.

## 🔟 Phase 10: Wrap Up & Archival
* **System Context Updates:** `wiki/features/feat-file-browser.md` owns the search model after build;
  record the "results rows carry full paths" rule next to the tree view's.

## ✅ Completion Note
<!-- Added during wrap-up. -->
