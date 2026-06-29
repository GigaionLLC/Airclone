# 📦 Parcel Plan: Explorer Redesign (premium, native-feeling)

## 📊 State Dashboard
| Metric | Value |
| :--- | :--- |
| **Status** | `IN PROGRESS` (Phase 1 → alpha.7, Phase 2 → alpha.8) |
| **Version** | `v1.0.0` |
| **Active Persona** | `Architect` |
| **Last Updated** | 2026-06-28 |

---

## 1️⃣ Phase 1: Expansion & Scoping
* **Intent:** Raise Airclone's in-app explorer from *functional* to *premium* — an intuitive, modern,
  native-feeling file explorer over rclone remotes, on every platform. Design captured in
  [wiki/core/20-explorer-design.md](../../wiki/core/20-explorer-design.md).
* **In Scope:** semantic-token theme, view modes (grid/media/columns), inspector panel, thumbnails +
  Quick Look over rclone, morphing PathBar, Finder-grade selection, native window chrome, per-pane
  state, transactional transfers, mobile touch explorer.
* **Out of Scope:** virtual/content-addressed filesystem, a media library / forced onboarding, P2P /
  sync fabric, tags database, treemap/AI-sidecar views, server-side SQL/event-bus cache. (See
  *What We Deliberately Don't Copy* in the design doc.)

## 2️⃣ Phase 2: Requirements & Context
* **Relevant Docs:**
  - `wiki/core/20-explorer-design.md` → the design source of truth for this plan.
  - `wiki/core/06-design-system.md` → tokens/typography this extends.
  - `wiki/core/08-core-architecture.md` → `RcloneClient`, `objectRef`, RC API the thumbnail/preview
    services build on.
  - `wiki/core/14-performance-standards.md` → virtualization/lazy-loading budgets.
* **Relevant Code:**
  - `app/lib/src/ui/browser_pane.dart` → the list view to refine + host new view modes.
  - `app/lib/src/state/browser_controller.dart` → per-pane state; extend with view mode + listing cache.
  - `app/lib/src/ui/column_header.dart` → existing sort model reused by all views.
  - `app/lib/src/rclone/http_rclone_client.dart` → `objectRef` / rcd port reused by the thumbnail service.
  - `app/lib/src/ui/preview_dialog.dart` + `media_preview.dart` → renderers reused by Quick Look.

## 3️⃣ Phase 3: User Clarification
* **Open Questions:**
  - `[x]` Confirm build order starts at **Phase 1 (Grid + Thumbnails)** as the first shippable jump.
    -> **Answer:** Yes — start at Phase 1 (Phase 0 groundwork folded in), ship as `v0.1.0-alpha.7`.
  - `[x]` Default behavior for on-demand thumbnails? -> **Answer:** **OFF by default** (icons only, zero
    network beyond listing), with an easy one-click top-bar **Thumbnails** toggle to turn them on for
    faster scrolling previews. Preference remembered per remote.

## 4️⃣ Phase 4: Detailed Execution Plan (phased)

### Phase 0 — Foundation (quick, unblocks everything)
* Semantic token theme as Flutter `ThemeExtension`s (`surface*`, `sidebar*`, `menu*`, `text*`,
  `primary*`, opacity helpers). Dark-first.
* System fonts + antialiasing; one motion signature (shared curve/duration constants).
* **Virtualization audit** — every view uses `*.builder`/slivers with overscan; stress at 20k+ entries.
* **Incremental/streamed listing** (`operations/list` async + poll, render first page immediately) +
  per-`(remote,path,sort)` listing cache (short TTL).
* List-view refinements: adjacent-selected-row merge, click-to-sort polish, alternating bg, drop-target
  affordance.

### Phase 1 — Grid + Thumbnails (highest visual impact) ⭐ first ship
* Grid view (row-virtualized; column count from width).
* **Local thumbnail service** on the rcd loopback: `GET /thumb?ref=…&size=256`; lazy + visible-window
  generation; immutable disk cache keyed `(remote,path,modTime,size)`; served via `CachedNetworkImage`.
  Images first (ranged read → decode → WebP 256/512); video keyframe + PDF first-page gated behind tool
  availability with icon+extension fallback. **OFF by default** — grid renders kind-icons with zero
  network beyond the listing; a one-click top-bar **Thumbnails** toggle (remembered per remote) enables
  generation for faster scrolling previews.
* Icon-first → thumbnail crossfade with a persistent `(ref,size)` load cache; backend + kind/extension
  icon resolver.
* Live density controls (grid-size/gap sliders, Folders-First / Show-Size) in the top bar.

### Phase 2 — Inspector + Media view + Quick Look
* Tabbed Inspector (Overview / More) with media card, quick-action pills, rclone remote/backend
  metadata, multi-select + empty states; reused inside Quick Look.
* Media/gallery view (square tiles, date grouping, sticky date header, duration badges) — reuses Phase 1
  thumbnails.
* Quick Look on **Space** (scale-in overlay, ←/→ nav, embedded inspector, byte-range streaming from
  rclone for media).

### Phase 3 — Navigation & power-user
* Morphing PathBar (collapsed → breadcrumbs → editable type-to-navigate, leading remote icon).
* Finder-grade selection (toggle/range-with-anchor, marquee, typeahead) + full platform-aware keyboard
  map + glyphs / shortcuts sheet.
* Top-bar priority-overflow (essential for dual-pane width).
* Per-pane state model (history/scroll/selection/view per pane) + active-pane indicator + single-pane
  toggle.

### Phase 4 — Columns + native chrome + transactions
* Columns (Miller) view (per-pane column stack, keyboard traversal).
* Native window chrome per platform (macOS traffic-light insets + vibrancy; Windows DWM dark
  titlebar/caption + Mica) via `window_manager`/`bitsdojo_window` + small platform channels.
* Preview-before-commit transfer sheet (count/size/conflicts/ETA → Confirm/Cancel) through the existing
  transfers panel; optimistic in-memory edits on action success.
* One declarative context-menu model → native menus desktop, sheets mobile.

### Phase 5 — Mobile touch explorer
* Single-pane navigation stack, Cupertino/Material adaptivity, Media gallery hero, long-press sheets,
  swipe-back, pinch-zoom Quick Look, relative dates — reusing tokens, thumbnail service, icon system,
  selection model.

* **Test Verification Plan:** `tool/flutter.ps1 test` (or Docker `flutter test`) per phase; add widget
  tests for each new view (grid/media/columns), the thumbnail cache key, and Quick Look navigation;
  keep the existing `browser_pane_test.dart` regression green.

### Riskiest unknowns (watch list)
1. rclone listing latency at scale → incremental streamed listing + caching (Phase 0).
2. Thumbnail generation cost over remotes (video keyframes, per-GET cost) → windowed lazy gen +
   immutable cache + graceful fallback (Phase 1).
3. Per-backend byte-range/seek support for preview streaming → detect capability, fall back to
   fetch-on-open (Phase 2).
4. Native chrome via platform channels (macOS vibrancy/toolbar, Windows DWM) → isolated to Phase 4 so
   it never blocks high-impact view/thumbnail work.

## 5️⃣ Phase 5: Product Owner Review
* **Status:** `PENDING`

## 6️⃣ Phase 6: Senior Dev Hygiene Review
* **Status:** `PENDING`

## 7️⃣ Phase 7: Implementation Checklist (Execution)
- `[~]` Phase 0 — Foundation (grid virtualization + per-pane view state landed; token/motion/streamed-listing groundwork still pending)
- `[x]` Phase 1 — Grid + Thumbnails (alpha.7: grid view, icon system, per-remote disk-cached thumbnails, density slider)
- `[x]` Phase 2 — Inspector + Media + Quick Look (alpha.8: inspector rail + Ctrl+I, media gallery view, Quick Look on Space with ←/→ nav)
- `[ ]` Phase 3 — Navigation & power-user
- `[ ]` Phase 4 — Columns + native chrome + transactions
- `[ ]` Phase 5 — Mobile touch explorer

## 8️⃣ Phase 8: Verification Dashboard
* **Verification Status:** `PENDING`

## 9️⃣ Phase 9: User Verification
* **Status:** `PENDING`

## 🔟 Phase 10: Wrap Up & Archival
* **System Context Updates:** fold final token names, thumbnail-service contract, and view-mode state
  shape back into `06-design-system.md`, `08-core-architecture.md`, and `07-state-context.md`.

## ✅ Completion Note
<!-- Added during wrap-up. -->
