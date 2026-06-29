---
type: "core"
name: "Explorer Design & Direction"
status: "stable"
dependencies: ["05-app-structure", "06-design-system", "08-core-architecture"]
description: "How Airclone's in-app file explorer becomes intuitive, modern, and native-feeling on every platform — principles, layout, view modes, thumbnails/quick-look over rclone, and a phased plan."
---

# 🧭 Explorer Design & Direction

Airclone's hero is the [in-app file explorer](../features/feat-file-browser.md). This doc raises its
bar from *functional* to *premium* — an explorer that feels as intuitive and native as a best-in-class
desktop file manager, while everything it shows lives on rclone remotes.

> Airclone has one structural advantage to lean into: **Flutter renders real platform widgets and
> adaptive chrome.** We don't have to *simulate* native with CSS — we can *be* native (Cupertino on
> iOS, Material on Android, real window chrome + menus on desktop) per OS.

## 🎯 Design Principles

- **P1 — Native by host, not by skin.** Host OS font stack + antialiasing, real platform window chrome,
  real platform context menus, platform-correct keybinds (⌘ on macOS, Ctrl elsewhere).
- **P2 — Instant first paint, progressive richness.** Nothing blocks. A directory shows its first page
  immediately and streams the rest; a file shows its kind-icon instantly, then fades in a thumbnail.
  Never a full-screen spinner for a listing, never a blank box for a thumbnail.
- **P3 — One coherent surface from semantic tokens.** Every color is a named, context-scoped token
  (`surface*`, `sidebar*`, `menu*`, `text*`, `primary*`), never raw hex. Dark-first.
- **P4 — One motion signature.** A single ease-out curve (`cubic-bezier(0.25, 1, 0.5, 1)`, 150–300ms)
  on every transition: panel slides, popovers, path-bar morph, tab changes, thumbnail crossfades.
- **P5 — Deliberate selection & direct manipulation.** Toggle, range-with-anchor, marquee, typeahead;
  a clear visual grammar (accent-tinted selection, merged contiguous rows, inset accent ring on drops).
- **P6 — Preview before commit.** Before any copy/move/delete, show count, total size, conflicts, and
  ETA → Confirm/Cancel — routed through the transfers panel (pairs perfectly with rclone job semantics).
- **P7 — Density is a first-class control.** Grid-size/gap sliders, Folders-First / Show-Size and
  **Thumbnails** toggles, double-click behavior — surfaced live in the top bar.
- **P8 — Discoverability without clutter.** Keybind glyphs in menus/tooltips, a shortcuts sheet, and a
  **priority-overflow top bar** that gracefully collapses controls on narrow / dual-pane layouts.
- **P9 — Virtualize everything, always.** Every view windows its items from day one — the difference
  between trustworthy and broken on a 50k-object bucket.

## 🪟 Layout Redesign

Three-zone chrome (floating blurred top bar → sidebar → content → **inspector**) overlaid on our
dual-pane model.

| Region | Contents |
| :--- | :--- |
| **Top bar** (~48px, floating, blurred) | *Left:* sidebar toggle, back/forward, **morphing PathBar**. *Right:* expandable search, view-mode picker, view-settings (sliders), sort, inspector toggle. Priority-overflow collapses low-priority controls when width is tight. |
| **Sidebar** (~220px, collapsible) | Remotes (each with its backend icon), pinned/favorite paths, recents, a transfers entry. Active item gets accent fill. Remotes are the "devices" analogue. |
| **Main view** | The active view (list / grid / media / columns) for the focused pane — virtualized. Two sit side-by-side in dual-pane. |
| **Inspector** (~284px, toggleable) | Tabbed details for the selection: Overview (large thumb, name/kind, quick-action pills, media card) and More (hashes/MIME, full path, rclone remote/backend metadata). Multi-select + empty states. Reused inside Quick Look. ⌘/Ctrl+I. |
| **Status bar** (~24px) | Item count, selection count + aggregate size, current sort, transfer mini-indicator, free/used where the backend exposes it. |

**Dual-pane coexistence:** the top bar, sidebar, inspector, and status bar are *shared chrome* that
reflect the **active pane**. Each pane keeps its own path history, view mode, sort, scroll, and
selection. A thin active-pane accent indicator makes focus unambiguous; the inactive pane is a
first-class drop target. **Single-pane is a mode** (toggle), not a fallback — default dual-pane on
desktop, single-pane stack on mobile.

```
┌──────────────────────────────────────────────────────────────────────────────────────┐
│ ⟨◰⟩ ◀ ▶   ( ☁ s3-prod › invoices › 2026 ▾ )          🔍  ⊞▾  ⚙  ↕Sort  ⓘ            │  top bar (blurred)
├───────────────┬──────────────────────────────────┬──────────────────┬─────────────────┤
│  REMOTES      │  ┃ PANE A (active)                │  PANE B          │  INSPECTOR      │
│  ☁ s3-prod ◀  │  ┃ Name           Size   Modified │  Name      Size  │  ┌───────────┐  │
│  ⬡ b2-backup  │  ┃ 📁 jan            —   Jun 02   │  📁 archive   —  │  │  [ thumb ] │  │
│  🗄 gdrive     │  ┃ 📄 inv-001.pdf 88kB Jun 14 ◀ │  🖼 cover…  1.2MB │  └───────────┘  │
│  🌐 webdav     │  ┃ 🖼 receipt.jpg 1.2MB Jun 15  │  🎞 demo…   44MB │  invoice-001.pdf│
│  PINNED       │  ┃ 🎞 walkthrough  44MB Jun 18  │                  │  PDF · 88 KB    │
│  ★ 2026       │  ┃                              │                  │  ♥  ⤴  ✦        │
│  ⇅ Transfers  │  ┃                              │                  │  [Overview·More]│
├───────────────┴──────────────────────────────────┴──────────────────┴─────────────────┤
│ 6 items · 1 selected · 88 KB · sort: Modified ▾            ⇅ 2 transfers · 41%           │  status bar
└──────────────────────────────────────────────────────────────────────────────────────┘
```

Quick Look (Space) overlays the view as a scale-in modal with prev/next nav + the inspector as a
sidebar; the top bar hides while open.

## 🔲 View Modes

Each view renders an rclone entry `{name, isDir, size, modTime, mimeType?, objectRef}` and requests
thumbnails lazily only for the visible window.

| View | Status | Notes | Priority |
| :--- | :--- | :--- | :--- |
| **List** | ✅ have | Virtualized table (Name/Size/Modified/Type). Refine: adjacent selected rows merge into one rounded block, alternating bg, drop-target affordance. | P0 |
| **Grid / icons** | build | Row-virtualized (column count from width). Card = thumbnail box (icon→thumb crossfade) + centered name pill + optional size. Grid-size/gap sliders, size-scaled corner radius. | **P1 (first)** |
| **Media / gallery** | build | Square-cropped tiles, ~1px gap, fill width; date grouping with sticky floating date header; video duration badge. Reuses grid thumbnails. | P2 |
| **Columns (Miller)** | build | Cascading columns: select a folder → append a column; ←/→ traverse, ↑/↓ within; per-pane column stack. The strongest "native" signal. | P3 |

We deliberately skip disk-usage treemap / "knowledge" views — niche, high effort, not core to a cloud
browser.

## 🖼️ Thumbnails & Quick Look over rclone

The single highest-leverage feature for making *remote feel local*. We already hold an authenticated
[`objectRef`](08-core-architecture.md) and run `rclone rcd`.

> **Default: thumbnails OFF.** To respect metered / per-GET backends (e.g. S3), the grid/media views
> render kind-icons only by default — **zero network beyond the listing**. A prominent one-click
> **Thumbnails** toggle in the top-bar view-settings turns them on for richer, faster scrolling
> previews; the preference is remembered **per remote**. When enabled, generation stays strictly
> visible-window-only and immutably cached, so cost is bounded and a re-scroll is free.

1. **Local thumbnail service** — a tiny loopback HTTP endpoint answering `GET /thumb?ref=…&size=256`;
   Flutter renders thumbnails as cached network images against it.
2. **Generate on demand, visible-window only** — images: ranged read → decode → downscale to WebP
   256/512px; video: one keyframe via ffmpeg; PDF/docs: first page where a renderer exists, else
   icon + extension badge.
3. **Cache immutably, keyed by content identity** — key = `(remote, path, modTime, size)`; write WebP
   to disk; serve `Cache-Control: immutable`. Never regenerate / re-download on an unchanged key.
4. **Progressive UI** — kind-icon instant; thumbnail fades in on decode (~100ms); a persistent
   `(ref,size)` load cache so scrolling back never re-flashes; size-appropriate variant selection to
   limit cloud bandwidth.

**Quick Look (Space)** reuses our existing preview renderers (image/text/md/pdf/video/audio), streams
bytes via byte-range (`rclone serve http` / RC) so media is seekable without a full download, with
←/→ navigation across the listing and the inspector embedded as a sidebar.

> **Feasibility:** lazy windowed generation + immutable cache + ranged reads is fast and cheap even on
> slow backends. Video keyframes / PDF rendering are heavier — gate behind tool availability, low
> concurrency, and always fall back to icon + extension badge. Backends with per-GET cost (S3) ⇒
> strict visible-window-only generation + aggressive caching.

## 🖥️ Native Feel per Platform

- **macOS:** hidden title + native traffic-lights (reserve their inset), optional sidebar/window
  vibrancy, ~10px rounded floating window.
- **Windows 11:** immersive dark titlebar via DWM; force caption color; Mica-like translucency where
  available; native confirm dialogs.
- **Linux:** standard decorations, respect GTK theme.
- **Fonts:** host system stack, antialiased — matching the OS font is itself a core native win.
- **Context menus & keybinds:** one declarative `items[]` model (icon, label, keybind glyph, `danger`,
  `condition`, separators, submenus) → native menus on desktop, sheets on mobile; a platform-aware
  registry auto-swaps ⌘↔Ctrl and surfaces glyphs.
- **Mobile:** touch explorer — single-pane navigation stack, List + Grid + **Media gallery** hero,
  glass header, swipe-back, long-press sheets, pinch-zoom Quick Look, relative dates; same tokens,
  icons, thumbnail service, and selection model.

## ✨ Polish that Closes the Gap

Thumbnails (icon-first crossfade + persistent cache + DPI/size-aware variants + size-scaled radius);
selection grammar (accent fill + merged contiguous rows); drop targets (inset accent ring + tint);
**morphing PathBar** (collapsed → breadcrumbs → editable type-to-navigate, leading remote icon);
floating blurred top bar with content fading under it; Phosphor-style icons (fill-when-active) + a
kind→extension→generic resolver + first-class backend icons for our 70+ remotes; micro-interactions
(`active:scale-95`, spring-in popovers, animated toggles, name-only inline rename); per-view empty/
loading copy; a full platform-aware keyboard map with glyphs surfaced everywhere.

## 🚫 What We Deliberately Don't Copy

A virtual/content-addressed filesystem, a library/onboarding-before-browse, P2P/sync fabric, a tags
database, treemap/AI-sidecar views, and a server-side SQL/event-bus cache. Airclone's source of truth
is **rclone remotes browsed directly** — we copy the *explorer polish and interaction model*, not a
distributed-data platform. Favorites/pins are lightweight local prefs; "feels instant" comes from
sort-on-receipt + short-TTL listing cache + **optimistic in-memory edits on action success**.

## 🗺️ Phased Plan

Full detail in [dev/plans/explorer-redesign-plan.md](../../dev/plans/explorer-redesign-plan.md).

- **Phase 0 — Foundation:** semantic token theme (ThemeExtensions), system fonts, one motion signature,
  virtualization audit + **incremental/streamed listing** + per-`(remote,path,sort)` listing cache,
  list-view refinements.
- **Phase 1 — Grid + Thumbnails (highest impact):** grid view + the local thumbnail service +
  icon→thumb crossfade + live density controls.
- **Phase 2 — Inspector + Media view + Quick Look.**
- **Phase 3 — Navigation & power-user:** morphing PathBar, Finder-grade selection, keyboard map,
  top-bar priority-overflow, per-pane state model.
- **Phase 4 — Columns + native chrome + transactional transfers.**
- **Phase 5 — Mobile touch explorer.**

**Riskiest unknowns:** rclone listing latency at scale (Phase 0), thumbnail cost over remotes
(Phase 1), per-backend byte-range/seek support (Phase 2), native chrome via platform channels
(Phase 4).

---

**Related:** [App Structure](05-app-structure.md) · [Design System](06-design-system.md) ·
[File Browser](../features/feat-file-browser.md) · [Core Architecture](08-core-architecture.md)
