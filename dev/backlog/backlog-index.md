---
type: "backlog"
name: "Backlog Index"
status: "stable"
description: "Master queue of all pending, parked, and roadmap features for Airclone."
---

# 📋 Backlog Index

Master queue for all proposed, deferred, or future feature requests and roadmap items. The full,
prioritized roadmap (MoSCoW + theme grouping, desktop vs mobile) lives in the
**[Feature Backlog & Roadmap](feature-backlog.md)**. Individual large items get their own backlog
plan file here when scoped.

## 🚦 Parked / Future Features

| Feature / Task | Plan Link | Status | Description |
| :--- | :--- | :--- | :--- |
| Full prioritized roadmap | [feature-backlog.md](feature-backlog.md) | `ROADMAP` | The cross-app feature matrix and v1→v2 backlog distilled from research. |
| Settings & advanced-config UX | [settings-ux-improvements.md](settings-ux-improvements.md) | `PROPOSED` | 14 prioritized findings (2026-07-09 review): make Mount/Serve discoverable, explain remote options, settings search/reset. |
| Beta quality review | [beta-quality-review.md](beta-quality-review.md) | `PROPOSED` | 16 beta-readiness findings — **P0: one-way sync lacks `--max-delete`/forced dry-run** (top pick for beta.2), silent file-op errors, engine tests. |
| README screenshots | [../plans/readme-screenshots-plan.md](../plans/readme-screenshots-plan.md) | `SHIPPED` | Shot list, README markup, and capture workflow; 9 shots captured + committed 2026-07-09. |
| Phase 3 continuation | [../plans/phase3-continuation-plan.md](../plans/phase3-continuation-plan.md) | `ACTIVE` | Finish bisync/crypt/scheduling: background execution design, crypt reattach/rotation, bisync reliability, engine test harness. |
| Config portability & unlock | [../plans/config-portability-plan.md](../plans/config-portability-plan.md) | `PLANNED` | Config path control, encrypted import/export, desktop→phone QR/LAN handoff, biometric unlock — the serverless profile-sync on-ramp. |
| Store submission automation | [../plans/store-automation-plan.md](../plans/store-automation-plan.md) | `ACTIVE` | Play internal-track lane wired (needs `PLAY_SERVICE_ACCOUNT_JSON`); iOS/TestFlight path documented (gated on iOS app); MAS revised: viable via dual-engine. |
| Dual-engine: librclone backend | [../plans/store-automation-plan.md](../plans/store-automation-plan.md) | `PLANNED` | In-process `LibRcloneClient` (dart:ffi) behind the `RcloneClient` seam — Windows/macOS/Linux ship both engines (subprocess default), MAS/iOS librclone-only; unblocks MAS, zero-download Windows first launch, hard iOS prerequisite. |
| Mobile tabs + adaptive/resizable split | — | `PLANNED` | (1) Mobile **tab strip** (+new-tab) surfacing the pane's existing tab model. (2) **Resizable dual-pane** with a draggable divider (persisted split ratio via a `splitRatioProvider`, clamped so neither pane collapses) — reuse the `_SidebarResizeHandle` drag→clamp→persist pattern (home_screen.dart:1225). **This also fixes DESKTOP**, where the dual-pane is currently a fixed 50/50 (`Expanded`/`Expanded`, home_screen.dart:741/743) — resize lands on both. (3) **Manual orientation control** (side-by-side ⇄ stacked), default adaptive (side-by-side ≥600dp, stacked in portrait), user-overridable; stacked layout uses a vertical drag divider. Top-bar split toggle; drag-between-panes both layouts. Lift desktop `_TabStrip` to shared. Sequence AFTER config batch B (both touch mobile_home.dart). User-confirmed 2026-07-10 (adaptive default + resizable + orientation choice). |
| Pop-out image viewer (desktop) | [../plans/popout-image-viewer-plan.md](../plans/popout-image-viewer-plan.md) | `PLANNED` | Separate resizable OS windows per image w/ independent zoom via `desktop_multi_window` ^0.3.x (official Flutter multiwindow is main-channel-only). ~1–2d, image-only MVP; slots into the existing main(args) branch. Sequence after batch B. |
