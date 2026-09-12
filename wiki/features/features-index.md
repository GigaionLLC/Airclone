---
type: "index"
name: "Features Index"
status: "seed"
description: "Table of contents for Airclone feature documentation."
---

# 🗺️ Features Index

Entry point for all Airclone feature documentation. Each feature is specified for **desktop** and
**mobile** (or explicitly scoped to one). The prioritized build order lives in the
[Feature Backlog & Roadmap](../../dev/backlog/feature-backlog.md).

## 🧭 Feature docs (written as features are built — the rest are seeds)

**Status is about the feature, not the doc.** A doc name in back-ticks is a page nobody has written;
the status column says whether that is a missing page or a missing feature, because the two used to
look identical here. **Shipped** = in the app today · **partial** = usable but knowingly incomplete
(the gaps are named where the feature is documented) · **not built** = designed only.

| Feature | Doc | Platforms | Status | Description |
| :--- | :--- | :--- | :--- | :--- |
| ⭐ **File Browser (hero)** | [`feat-file-browser.md`](feat-file-browser.md) | all | shipped | **The rebuilt rclone explorer** — multi-remote (tabs + dual-pane), inline config, in-app drag-and-drop onto folders, direct (non-VFS) transfer engine. The primary, performant surface. Also owns the collision preflight, the marked sync source and its dry-run preview, and the undecryptable-name notice. |
| **Remote / config management** | [`feat-config-management.md`](feat-config-management.md) | all | shipped | Add/edit/duplicate/delete remotes, the taken-name guard over `config/create`, config import (merge · merge-replacing-collisions · whole-config replace), remove-all-remotes, native config encryption, the Android copy that survives uninstall, and the backup ring under all of it. Forms themselves are inline in the File Browser. |
| **Backup & restore** | [`feat-backup.md`](feat-backup.md) | desktop · Android | shipped | A folder copied somewhere safe on a schedule: copy-only with versions kept, a per-device destination so two machines cannot merge, retention with a prune that refuses rather than guesses, and a restore that is just the file browser plus the existing conflict preflight. The wizard is on desktop and Android; **camera-roll backup** (below) is the Android-only sibling. |
| Copy / Move / Sync | `feat-sync.md` | all | shipped | One-click transfers; sync direction options; bisync (two-way). Built and in daily use — `ui/transfer_options_dialog.dart`, `ui/bisync_confirm.dart` — but with no page of its own; the transfer engine and its preflights are [File Browser §5](feat-file-browser.md#5-the-transfer-engine-stat-then-dispatch). |
| Transfers & jobs | `feat-transfers-and-jobs.md` | all | shipped | Async job model, queue, progress, bandwidth limits. `state/jobs_controller.dart`, `ui/jobs_panel.dart`, `ui/jobs_dock.dart`; provider contracts in [State & Context](../core/07-state-context.md). |
| **Scheduling & automation** | [`feat-scheduling.md`](feat-scheduling.md) | desktop · Android | partial | Saved tasks on an interval/daily/weekly schedule; in-app ticking everywhere, background runs with the app closed on **Windows** (Task Scheduler: exact triggers for daily/weekly, one shared `--run-due` poller for intervals) and on **Android** (a WorkManager poll — no exact triggers, and a background wake is capped at 8 minutes on Android 12+, 5 hours where the foreground promotion is granted); the mandatory delete cap on a repeating Sync and the circuit breaker that pauses the whole scheduler when one trips. No background execution on macOS or Linux yet. |
| **Camera-roll backup** | in [`feat-scheduling.md` §6](feat-scheduling.md#6-what-this-is-not-yet) and [`feat-backup.md` §2](feat-backup.md#2-where-a-backup-lands) | Android | shipped | `TaskKind.photos`: DCIM by default plus any folders you add, mirrored into `remote:Airclone/Photos/<device>/` on the Android background poll, copy-only, Wi-Fi-only by default, videos on their own toggle. No own doc yet — Settings → Automation → "Back up your photos" (`ui/photo_backup_section.dart`). |
| **Tree view** | [File Browser §6.2](feat-file-browser.md#62-the-tree-view) · [Explorer design § View Modes](../core/20-explorer-design.md#-view-modes) · [plan](../../dev/archive-plans/tree-view-plan.md) | desktop | shipped | The fourth `ViewMode`: an expandable hierarchy in one pane — lazy per-folder listings, several folders open at once, Details columns, keyboard expand/collapse, selection spanning folders, and every operation resolving its path from the **node**, never `state.path`. Not offered on the touch shell. |
| **Command console** | `feat-console.md` · state contracts in [State & Context](../core/07-state-context.md#wizards-console--os-integration), helpers in [Utility Standards](../core/12-utility-standards.md) | all | shipped | A pane kind of its own (`PaneKind.console`) rather than a dialog: type rclone commands, get them translated argv→RC where a safe RC primitive exists, refused with an in-app alternative where one does not, and redacted before anything is displayed. `state/console/`, `ui/console_pane.dart`. No feature page yet. |
| **Archive operations** | [File Browser §6](feat-file-browser.md#6-browsing--viewing) | desktop · Android | shipped | Compress… / Extract here / Extract to… / List contents… over the `rclone archive` CLI, so they appear only where this build may spawn a subprocess. `ui/archive_dialogs.dart`, `state/archive_service.dart`. |
| **Duplicate finder** | [File Browser §6](feat-file-browser.md#6-browsing--viewing) | all | shipped | Same-content copies grouped under a folder, keep one and delete the rest, each targeted by its own unique path. `ui/dedupe_dialog.dart`. |
| **Bandwidth schedule** | `feat-transfers-and-jobs.md` · provider in [State & Context](../core/07-state-context.md) | all | shipped | A persisted timetable of `--bwlimit` windows with a 60 s applier, so overnight transfers can run flat out and daytime ones cannot saturate the link. `state/bw_schedule.dart`, `state/bw_schedule_controller.dart`. |
| **Diagnostics** | [Security §5.1](../core/15-security.md#51-diagnostics--evidence-without-telemetry) | all | shipped | The local, user-driven evidence channel — a bounded ring, redacted **at ingest**, exported only when the user asks. Airclone sends no telemetry, so this is the only way evidence leaves a device. `state/diagnostics.dart`, Settings → Diagnostics. |
| **Android TV** | [dev/android-tv.md](../../dev/android-tv.md) | Android TV | shipped | The same bundle on a television: the touch shell, focus drawn by us because Material renders it invisibly there, D-pad row actions, and no file picker to fall back on. `ui/tv.dart`, `ui/tv_row_actions.dart`. |
| Mount as drive (secondary) | `feat-mount.md` | desktop | shipped | FUSE mounting (WinFsp/macFUSE/FUSE3) — a convenience for other apps; slower than the File Browser for upload/move (VFS). `state/mount_controller.dart`, `ui/mount_panel.dart`; the pinned-letter half is [File Browser §7](feat-file-browser.md#7-relationship-to-the-os-mount). |
| Mobile file-provider | `feat-mobile-fileprovider.md` | mobile | **not built** | Android DocumentsProvider / iOS File Provider exposure. Designed only — there is no `DocumentsProvider` in the Android manifest; [02-product-context](../core/02-product-context.md) owns the status. |
| Serve | `feat-serve.md` | desktop/mobile | shipped | WebDAV/SFTP/HTTP/FTP/NFS/DLNA servers. `state/serve_controller.dart`, `ui/serve_panel.dart`. |
| Preview / viewer | `feat-preview.md` | all | shipped | Inline image/video/audio/PDF/text preview, plus the pop-out gallery. `ui/media_preview.dart`, `ui/preview_dialog.dart`, `ui/media_gallery.dart`. |
| Public links | `feat-public-link.md` | all | shipped | Generate shareable links where the backend supports it (capability-gated). `ui/public_link_dialog.dart`. |
| Encryption (crypt) | `feat-encryption.md` · config-password half in [`feat-config-management.md` §6](feat-config-management.md#6-config-encryption-is-rclones-own-and-it-is-cli-only) | all | shipped | Encrypted remotes (`ui/encrypt_remote_dialog.dart`) and the config password. |
| Settings & themes | `feat-settings.md` | all | shipped | Preferences, light/dark themes, skins. `ui/settings_screen.dart`, `state/skin.dart`. i18n is the part that does not exist yet. |
| Tray & windows | `feat-tray-windows.md` | desktop | **not built** | System tray, auto-launch, window management. Nothing is wired — no tray or launch-at-startup code exists in `app/lib/src`. |
| Onboarding | `feat-onboarding.md` | all | partial | What ships is the pane's first-run empty state when zero remotes are configured (`ui/browser_pane.dart`). The onboarding *experience* expressing the product vision is not built. |

> **A seed row is not a missing feature.** Most of the back-ticked docs above describe things that
> ship today and simply have no page yet; only **Mobile file-provider** and **Tray & windows** are
> unbuilt outright, with **Onboarding** half-there, and the status column is there so the three
> states stop looking alike. Where a shipped
> surface has been written up on a page that *does* exist, the Doc column points at that section
> rather than leaving it undocumented — pinned per-remote **drive letters** are
> [File Browser §7](feat-file-browser.md#7-relationship-to-the-os-mount), and **opt-in recent
> folders** (off by default, session-only, cleared when switched off) are
> [File Browser §6](feat-file-browser.md#6-browsing--viewing). When `feat-mount.md` and
> `feat-settings.md` are written, move them and leave a link behind.

## 🔗 Cross-cutting rules every feature must honour

| Before you… | Read |
| :--- | :--- |
| Wire a feature to state | [State & Context](../core/07-state-context.md) |
| Call an rclone RC method or native channel | [External Integrations](../core/10-external-integrations.md) |
| Read file **content**, spawn a process, or change browser-pane listing state | [Performance & Reliability Standards](../core/14-performance-standards.md) |
| Add a field, or an action that can delete/overwrite data | [Validation Standards](../core/11-validation-standards.md) |
