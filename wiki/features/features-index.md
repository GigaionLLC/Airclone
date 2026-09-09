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

| Feature | Doc | Platforms | Description |
| :--- | :--- | :--- | :--- |
| ⭐ **File Browser (hero)** | [`feat-file-browser.md`](feat-file-browser.md) | all | **The rebuilt rclone explorer** — multi-remote (tabs + dual-pane), inline config, in-app drag-and-drop onto folders, direct (non-VFS) transfer engine. The primary, performant surface. Also owns the collision preflight, the marked sync source and its dry-run preview, and the undecryptable-name notice. |
| **Remote / config management** | [`feat-config-management.md`](feat-config-management.md) | all | Add/edit/duplicate/delete remotes, the taken-name guard over `config/create`, config import (merge · merge-replacing-collisions · whole-config replace), remove-all-remotes, and the backup ring under all of it. Forms themselves are inline in the File Browser. |
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

> **Shipped surfaces whose own doc is still a seed** are written up in the two pages above rather than
> left undocumented: pinned per-remote **drive letters** and the mount/explorer division of labour are
> [File Browser §7](feat-file-browser.md#7-relationship-to-the-os-mount); **opt-in recent folders**
> (off by default, session-only, cleared when switched off) are
> [File Browser §6](feat-file-browser.md#6-browsing--viewing). When `feat-mount.md` and
> `feat-settings.md` are written, move them and leave a link behind.

## 🔗 Cross-cutting rules every feature must honour

| Before you… | Read |
| :--- | :--- |
| Wire a feature to state | [State & Context](../core/07-state-context.md) |
| Call an rclone RC method or native channel | [External Integrations](../core/10-external-integrations.md) |
| Read file **content**, spawn a process, or change browser-pane listing state | [Performance & Reliability Standards](../core/14-performance-standards.md) |
| Add a field, or an action that can delete/overwrite data | [Validation Standards](../core/11-validation-standards.md) |
