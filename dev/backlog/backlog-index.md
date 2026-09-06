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
| Reliability and product hardening audit | [hardening-audit-2026-07-15.md](hardening-audit-2026-07-15.md) | `PROPOSED` | 18 prioritized, evidence-linked candidates from the v0.5 audit: P0 process/job safety, transfer invariants, config transactions, and release signing; P1/P2 runtime, mobile, trust, and test work. |
| Settings & advanced-config UX | [settings-ux-improvements.md](settings-ux-improvements.md) | `PROPOSED` | 14 prioritized findings (2026-07-09 review): make Mount/Serve discoverable, explain remote options, settings search/reset. |
| Beta quality review | [beta-quality-review.md](beta-quality-review.md) | `HISTORICAL` | Original beta-readiness findings; several shipped partially. Retained for context, with current evidence and remaining gaps reconciled in the 2026-07-15 hardening audit. |
| Transfer Coordinator (audit H-03/H-02) | [../plans/transfer-coordinator-plan.md](../plans/transfer-coordinator-plan.md) | `PROPOSED` | One safety policy at the execution boundary: `showCopyConflictDialog` has exactly ONE caller, so nine other transfer entry points can silently overwrite. Preflight fails closed, intent enforced in the rclone request (not a racy cached listing), unattended runs skip-by-default + require persisted approval, and the cancel-before-dispatch race closes in the same path. |
| README screenshots | [../archive-plans/readme-screenshots-plan.md](../archive-plans/readme-screenshots-plan.md) | `SHIPPED` | Shot list, README markup, and capture workflow; 9 shots captured + committed 2026-07-09. |
| Phase 3 continuation | [../plans/phase3-continuation-plan.md](../plans/phase3-continuation-plan.md) | `ACTIVE` | Finish bisync/crypt/scheduling: background execution design, crypt reattach/rotation, bisync reliability, engine test harness. |
| Config portability & unlock | [../archive-plans/config-portability-plan.md](../archive-plans/config-portability-plan.md) | `SHIPPED` | Config path control, encrypted import/export, device-to-device handoff, biometric unlock — all in v0.2.0-beta.1. The LAN half of the handoff was later removed in favour of the offline QR (v0.4.0); QR import is phone-camera only since v0.5.0. |
| Store submission automation | [../plans/store-automation-plan.md](../plans/store-automation-plan.md) | `SUPERSEDED` | Original 2026-07-09 research. All three lanes are live and have been used: every tag publishes to Play **open testing** (`release.yml`) with production a manual promote; iOS and Mac App Store builds are archived, signed and submitted from CI; Microsoft is staged by machine and **submitted by a human in Partner Center** — never committed through the API. The as-built accounts of each live in the per-store docs, not here. |
| Dual-engine: librclone backend | [../archive-plans/dual-engine-plan.md](../archive-plans/dual-engine-plan.md) | `SHIPPED` | In-process `FfiRcloneClient` (dart:ffi) behind the `RcloneClient` seam. Desktop ships both engines with an **Engine** switch in Settings (v0.2.0-beta.1, `librclone` built per-OS by `release.yml`); iOS links it statically and reached `ready` on a simulator 2026-08-28, which is what unblocked both Apple stores. |
| Mobile tabs + adaptive/resizable split | — | `SHIPPED` | All three parts landed. (1) The shared `ui/tab_strip.dart` `PaneTabStrip` renders touch-sized in the phone shell (`mobile_home.dart`, `touch: true`) and on desktop. (2) The dual-pane divider drags on both, persisted through `paneSplitRatioProvider` (`state/pane_layout.dart`) and clamped in `ui/pane_split.dart` — which also fixed desktop's fixed 50/50. (3) Orientation is a real choice: `PaneSplitOrientation {adaptive, sideBySide, stacked}`, adaptive resolving on width. |
| iOS "Open in another app" (Swift) | — | `PLANNED` | Android, Windows, macOS and Linux all ship the per-file hand-off (`state/open_external.dart` stages the object, then Android uses a FileProvider `content://` + ACTION_VIEW/ACTION_SEND chooser and desktop uses `launchUrl(Uri.file())`). **iOS is deliberately excluded** from `canOpenExternally`, so the menu item is hidden rather than shown-and-failing. iOS needs a real Swift implementation, not a flag flip: there is no ACTION_VIEW equivalent, so it wants a `UIActivityViewController` share sheet (or `UIDocumentInteractionController` for "open in"), presented from the root view controller, behind a `airclone/native` method channel mirroring `MainActivity.kt`'s `openExternal`. **Unblocked:** iOS ships and runs the in-process engine, and `ios-verify.yml` installs, launches and screenshots the app on a simulator, so this is now testable. |
| Pop-out image viewer (desktop) | [../archive-plans/popout-image-viewer-plan.md](../archive-plans/popout-image-viewer-plan.md) | `SHIPPED` | Separate resizable OS windows per image w/ independent zoom via `desktop_multi_window` ^0.3.x; image-only MVP in v0.2.0-beta.1 (`ui/popout_image_app.dart`). Video/PDF pop-outs still deferred — they would need those plugins registered in the sub-engine. |
