# Version History & Policy

This log records the formal releases, deployments, and the 3-level versioning strategy enforced across the **Airclone** project.

## 📌 Versioning Strategy (3-Level System)

All versioning follows the semantic hierarchy configured within the `/Test-and-Deploy` pipeline:

1. **Level 1 (Major)**: User-directed primary versions (e.g., `1.02.003` -> `2.00.000`). Triggered for fundamental architectural updates, paradigm shifts, or major product milestones. Resets both minor and patch levels to double/triple zero padding.
2. **Level 2 (Minor)**: New feature versions (e.g., `1.02.003` -> `1.03.003`). Adds `.01` to Level 2 versioning (allowing up to 99 level 2 versions), while preserving the patch level as-is. Prompted and confirmed when introducing discrete new features, capabilities, or major screen flows.
3. **Level 3 (Patch)**: Automated deployment versions (e.g., `1.02.003` -> `1.02.004`). Adds `.001` to Level 3 versioning (allowing up to 999 level 3 versions), while preserving the minor level as-is. Automatically bumped on every routine code deployment or patch push if no major/minor bump is specified.

---

## 📈 Release Log

| Version | Date | Level | Deployer | Key Release Highlights / Milestones |
|---|---|---|---|---|
| **v0.0.0** | 2026-06-28 | — | bootstrap | Repo initialized; documentation architecture + research scaffold established (pre-code). |
| **v0.1.0-alpha.1** | 2026-06-28 | Minor | CI (windows-latest) | First code: Flutter desktop shell — provisions/starts the rclone engine and browses remotes + local disk. Windows reference build. |
| **v0.1.0-alpha.2** | 2026-06-28 | Patch | CI (windows-latest) | Add-remote wizard (dynamic forms + OAuth state-machine), delete remote, and encrypted-config password gate. |
| **v0.1.0-alpha.3** | 2026-06-28 | Minor | CI (windows-latest) | Dual-pane + drag-drop transfers, jobs panel, file operations, bandwidth limit, settings/theme + update check. Built via a 4-agent workflow. |
| **v0.1.0-alpha.4** | 2026-06-28 | Patch | CI (windows-latest) | Fix blank-pane StackOverflow (folder-row DragTarget closure); BrowserPane regression test. |
| **v0.1.0-alpha.5** | 2026-06-28 | Minor | local + CI | File/photo previews, editable path bar, right-click menus + clipboard, back/forward history + filter + keyboard shortcuts (REM #9), deselect remote, public-link capability gating. First batch built on the local toolchain. |
| **v0.1.0-alpha.6** | 2026-06-28 | Minor | local + CI | Video/audio previews (media_kit) and sortable columns (Name/Size/Modified). |
| **v0.1.0-alpha.7** | 2026-06-28 | Minor | local + CI | Explorer redesign Phase 1: per-pane **grid view** with a type/kind icon system, on-demand **thumbnails** over rclone (off by default, per-remote toggle, disk-cached, visible-window-only), and live grid-density controls. Built via a 3-agent workflow. |
| **v0.1.0-alpha.8** | 2026-06-28 | Minor | local + CI | Explorer redesign Phase 2: tabbed **Inspector** rail (Overview/More, quick actions, Ctrl+I), date-grouped **Media gallery** view (3rd view mode), and immersive **Quick Look** (Space) with ←/→ navigation + reusable `PreviewContent`. Built via a 3-agent workflow. |
| **v0.1.0-alpha.9** | 2026-06-28 | Minor | local + CI | Explorer feel: **local-filesystem browsing** (drives + Home/Desktop/Documents/Downloads/Pictures/Videos/Music via the rclone `local` backend) surfaced in a **grouped sidebar** (Locations / Cloud), and a **single-pane explorer layout by default** with a dual-pane (commander) toggle in the top bar. Android release build set best-effort (`continue-on-error`) pending a real fix. |
| **v0.1.0-alpha.10** | 2026-06-28 | Patch | local + CI | **Android build fix (attempt 1, reverted)**: a root-Gradle `compileSdk` override errored on AGP 9. Superseded by alpha.11's dependency bump. |
| **v0.1.0-alpha.11** | 2026-06-28 | Minor | local + CI | **Collapsible sidebar** (Locations / Disks / Cloud each toggle via a chevron, persisted) and **editable Locations** (native folder picker +, drag-drop a folder to add, remove from sidebar). **Android build fixed** the right way: bump `desktop_drop` 0.6.1 → 0.7.1 (compiles against compileSdk 34+). First all-green release (windows/macOS/linux/android). |
| **v0.1.0-alpha.12** | 2026-06-28 | Minor | local + CI | **Thumbnails auto-generate** for pictures **and videos** by default. Local folders always on; cloud remotes on-by-default with a per-remote disable toggle (bandwidth). Video thumbnails capture a keyframe via libmpv (media_kit) headlessly, cached to disk, with graceful icon fallback. |
| **v0.1.0-alpha.13** | 2026-06-28 | Patch | local + CI | **Instant right-click menu** (custom popup route — no fsinfo fetch blocking, no scale-in animation; capability read from cache) and a **resizable + hideable sidebar** (drag the divider; toggle from the top bar). Kicked off the Explorer-native UX track in the backlog. **Relicensed to GNU AGPLv3** (history squashed to a single AGPLv3 commit). |
| **v0.1.0-alpha.14** | 2026-06-28 | Minor | local + CI | **Explorer-style two-row pane header**: an address row (nav + breadcrumb + filter) and a **command bar** (New · Cut/Copy/Paste · Rename · Delete · **Sort ▾** · **View ▾**). The **View menu** carries icon-size presets (Extra-large/Large/Medium/Small icons · List · Media) + the Thumbnails toggle. |
| **v0.1.0-alpha.15** | 2026-06-28 | Minor | local + CI | **Advanced transfer dialog** (Copy/Move/Sync · skip-newer/existing · compare · Include/Exclude/Filter tabs · live rclone-cmd preview · Dry-run/Run) on the command bar, and a **live statistics strip** (aggregate speed/ETA + per-file progress from `core/stats`) in the transfers dock. Authored via a 3-agent parallel workflow. (Folder-preview compositor landed, wiring next.) |
| **v0.1.0-alpha.16** | 2026-06-28 | Minor | local + CI | **Folder previews** — folders in grid view render a composite thumbnail of their first images (when thumbnails are on). Plus a safe **orphaned-engine reap**: the spawned `rclone rcd` PID is recorded and the previous one is killed on next launch (targeted, never the user's other rclone). Authored via a 2-agent workflow. |
