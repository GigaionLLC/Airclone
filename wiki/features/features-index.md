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

## 🧭 Planned Features (seed — docs authored as features are built)

| Feature | Doc | Platforms | Description |
| :--- | :--- | :--- | :--- |
| ⭐ **File Browser (hero)** | [`feat-file-browser.md`](feat-file-browser.md) | all | **The rebuilt rclone explorer** — multi-remote (tabs + dual-pane), inline config, in-app drag-and-drop onto folders, direct (non-VFS) transfer engine. The primary, performant surface. |
| Remote / config management | `feat-config-management.md` | all | Add/edit/delete remotes; dynamic forms from `/config/providers`; OAuth. (Surfaced inline in the File Browser.) |
| Copy / Move / Sync | `feat-sync.md` | all | One-click transfers; sync direction options; bisync (two-way). |
| Transfers & jobs | `feat-transfers-and-jobs.md` | all | Async job model, queue, progress, bandwidth limits. |
| Scheduling & automation | `feat-scheduling.md` | all | Scheduled syncs; triggers; background runs. |
| Mount as drive (secondary) | `feat-mount.md` | desktop | FUSE mounting (WinFsp/macFUSE/FUSE3) — a convenience for other apps; slower than the File Browser for upload/move (VFS). |
| Mobile file-provider | `feat-mobile-fileprovider.md` | mobile | Android DocumentsProvider / iOS File Provider exposure. |
| Serve | `feat-serve.md` | desktop/mobile | WebDAV/SFTP/HTTP/FTP/NFS/DLNA servers. |
| Preview / viewer | `feat-preview.md` | all | Inline image/video/audio/PDF/text preview. |
| Public links | `feat-public-link.md` | all | Generate shareable links where the backend supports it. |
| Encryption (crypt) | `feat-encryption.md` | all | Encrypted remotes and config password. |
| Settings & themes | `feat-settings.md` | all | Preferences, light/dark themes, i18n. |
| Tray & windows | `feat-tray-windows.md` | desktop | System tray, auto-launch, window management. |
| Onboarding | `feat-onboarding.md` | all | First-run experience expressing the product vision. |
