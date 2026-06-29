---
type: "core"
name: "Product Context"
status: "stable"
dependencies: ["01-vision-north-star"]
description: "Personas, domain workflows, competitive landscape, and product roadmap."
---

# 🧭 Product Context

## 👤 Personas

| Persona | Who | Core need | Where Airclone wins |
| :--- | :--- | :--- | :--- |
| **The Switcher** | Non-technical user with files across Drive/Dropbox/OneDrive | Move/organize files between clouds without a terminal | One window, drag-to-transfer, OAuth wizard — no `rclone.conf` editing |
| **The Power User** | Developer/sysadmin already on rclone CLI | A faster surface for everyday browse/move + visible jobs and mounts | RC daemon (structured jobs/stats), dual-pane, mount manager, presets — same config as their CLI |
| **The Mobile-First** | Phone-centric user | Their cloud available in the phone's Files app and other apps | "Show in Files" toggle → `DocumentsProvider`/File Provider; background sync |
| **The Backup-Keeper** | Anyone running scheduled backups | Reliable, safe, scheduled sync with no surprises | Dry-run + compare, `--max-delete` guard, named scheduled jobs, run history |
| **The Self-Hoster** *(v2)* | NAS/VPS owner | Drive remotes from a server / from their phone | Clean headless server mode + remote-`rcd` profile from the desktop/mobile UI |
| **The Enterprise Admin / IT** | Sysadmin / security team deploying to a fleet | Mass-deploy, lock down, audit, and integrate with org identity/secrets — **without the tool phoning home** | MDM/policy manageability (ADMX/Intune/Jamf/Android-MC/AppConfig), enforced kill-switches in the engine seam, OS-keychain/Vault secrets, local hash-chained audit + opt-in SIEM export, signed/SBOM'd builds, optional **self-hosted** control plane. See [Enterprise Readiness](19-enterprise-readiness.md). |

## 🔁 Core Domain Workflows

1. **Add a remote** → provider grid → dynamic form from `config/providers` → OAuth/interactive
   state machine → remote appears in the sidebar/home.
2. **Browse** → navigate any remote or local disk with the same rows/gestures; preview inline.
3. **Transfer** → drag between panes (desktop) or multi-select → action bar (mobile) → async job in
   the always-on transfer panel.
4. **Sync** → choose direction (Mirror / Backup-new / Two-way) → dry-run preview → run now or save as
   a scheduled job.
5. **Make local** → mount as a drive (desktop) or flip "Show in Files" (mobile).

## 🗺️ Competitive Landscape (categories)

- **The rclone CLI** — the engine; terminal-only. Airclone *is* rclone with a GUI.
- **Older desktop GUIs** — typically spawn a process per command and look dated; no mobile. Airclone
  uses the long-lived RC surface and a modern design system, and ships mobile.
- **Single-vendor web consoles** — per-provider; can't cross provider boundaries. Airclone is
  provider-agnostic and cross-storage.
- **Commercial mount/sync clients** — often paywall automation/scale and are desktop-only or
  single-vendor. Airclone is free, open-source, and keeps manual power free.

> Detailed, named competitive analysis is kept out of the committed repo — see gitignored
> `reference/research/` for the full breakdowns.

## 📈 Roadmap

The prioritized, MoSCoW-tagged roadmap is the
**[Feature Backlog & Roadmap](../../dev/backlog/feature-backlog.md)**; the build sequence (Phase 0
spike → desktop MVP → mobile → advanced) is the
**[Cross-Platform Plan](../../dev/plans/cross-platform-architecture-plan.md)**.

---

**Related:** [Vision & North Star](01-vision-north-star.md) · [User Journey](03-user-journey.md) ·
[Core Architecture](08-core-architecture.md)
