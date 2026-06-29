---
type: "core"
name: "User Journey & Per-Platform UI Tour"
status: "stable"
dependencies: ["05-app-structure", "06-design-system", "19-enterprise-readiness"]
description: "How Airclone looks and what it does on each platform — Windows, macOS, Linux, Android, iPad, iOS — with text wireframes and a feature matrix."
---

# 🧭 User Journey & Per-Platform UI Tour

One Flutter codebase, two form factors, five operating systems. The **shared core** (design system,
domain models, the `RcloneClient` seam, the in-app explorer) is identical everywhere; only the
**layout shell, navigation model, and OS-integration surface** differ. Wireframes below are sketches,
not final pixels.

> Form-factor split: **desktop** (Win/macOS/Linux) = dual-pane commander; **mobile** (Android/iOS) =
> single-pane touch browser + system-Files integration; **tablet/iPad** = adaptive (single-pane
> portrait, optional dual-pane landscape).

---

## 1. Shared foundation (all platforms)

- The **rebuilt rclone file explorer** is the hero everywhere (browse, drag/drop, multi-select,
  preview, server-side transfers via direct RC — no VFS). See [feat-file-browser](../features/feat-file-browser.md).
- The same **add-remote wizard** (dynamic form from `config/providers` + OAuth), **transfer/job
  model**, **sync directions** (Mirror / Backup-new / Two-way), **design tokens**, light/dark theme,
  and **i18n**.
- Differences are only: window chrome, navigation (sidebar+tabs vs bottom-nav), and how a remote is
  exposed to the OS (FUSE mount vs DocumentsProvider/File Provider).

---

## 2. 🖥️ Desktop — Windows / macOS / Linux

Same **dual-pane commander** (full anatomy + wireframe in [05-app-structure](05-app-structure.md)).
The body is identical across the three desktops; the **chrome and OS integration** differ.

### Windows
```
┌─ ▣ Airclone ─────────────────────────────────────────────  — ▢ ✕ ┐   ← Windows caption buttons
│ [+New Remote] [Copy][Move][Sync][Compare]    [Jobs][Mounts][Sched] ⚙ │
├──────────────┬───────────────────────────────────────────────────────┤
│ REMOTES   +  │  ⊞gdrive ⊞dropbox  +     │   ⊞ s3:backups  +           │
│ ▣ Google Drv │  ⌂ > Work > Q1           │   ⌂ > 2026                   │
│ ▣ S3 backups │  📁 designs/     2d       │   📁 jan/        5 Jan       │
│ 💽 Local C:  │  📄 plan.pdf  2.1MB 3h ═▶ │   📄 plan.pdf  2.1MB today   │
│ 💽 Mapped Z: │  🖼 hero.png  8.4MB 2h    │                             │
├──────────────┴───────────────────────────────────────────────────────┤
│ JOBS [Active] Sched History            ▓▓▓▓▓▓░ 73% 8.4MB/s ETA 0:03    │
│ ⛁ Mounts  ⌨ CLI  ● engine ok    ↑12.4MB/s · 2 jobs        | 5 items   │
└───────────────────────────────────────────────────────────────────────┘
   ▼ system tray (notification area): right-click ▾
     ┌──────────────────────────┐
     │ Airclone — engine ok     │
     │ Mount  gdrive → X:        │
     │ Quick: Sync "Photos"      │
     │ Open · Pause all · Quit   │
     └──────────────────────────┘
```
- **Mount** → drive letter (`X:`) via WinFsp; appears in Explorer "This PC".
- Tray in the notification area; "minimize to tray keeps jobs/mounts running."
- Installers: MSI/winget/choco/scoop; Authenticode-signed.

### macOS
```
┌●●●───────────────────── Airclone ─────────────────────────────────────┐   ← traffic lights
│ menu bar: Airclone  File  Edit  Go  Transfer  Mount  Window  Help      │
│ [+New Remote] [Copy][Move][Sync][Compare]    [Jobs][Mounts][Sched] ⚙ │
├──────────────┬───────────────────────────────────────────────────────┤
│ REMOTES   +  │  ⊞gdrive ⊞dropbox  +     │   ⊞ s3:backups  +           │
│ ▣ Google Drv │  (identical dual-pane body as Windows)                 │
│ 💽 Macintosh │                                                         │
├──────────────┴───────────────────────────────────────────────────────┤
│ ⛁ Mounts  ⌨ CLI  ● engine ok    ↑12.4MB/s · 2 jobs        | 5 items   │
└───────────────────────────────────────────────────────────────────────┘
   ▲ macOS menu-bar extra (status item) mirrors the tray menu
```
- **Mount** → `/Volumes/<name>` via macFUSE / FUSE-T; shows in Finder sidebar.
- Native **menu bar** + a menu-bar status item; traffic-light window controls.
- Distribution: DMG / Homebrew cask; **Developer-ID signed + notarized** (no Gatekeeper scare).

### Linux
```
┌─ Airclone ───────────────────────────────────────────────  ☰  — ▢ ✕ ┐   ← CSD / theme-dependent
│ [+New Remote] [Copy][Move][Sync][Compare]    [Jobs][Mounts][Sched] ⚙ │
├──────────────┬───────────────────────────────────────────────────────┤
│ REMOTES   +  │  (identical dual-pane body)                            │
│ ▣ Google Drv │                                                         │
│ 💽 / (root)  │                                                         │
│ 💽 /mnt/usb  │                                                         │
├──────────────┴───────────────────────────────────────────────────────┤
│ ⛁ Mounts  ⌨ CLI  ● engine ok    ↑12.4MB/s · 2 jobs        | 5 items   │
└───────────────────────────────────────────────────────────────────────┘
   ▼ AppIndicator/StatusNotifier tray (GNOME needs an extension)
```
- **Mount** → `~/mnt/...` or `/mnt/...` via FUSE3; appears in Nautilus/Dolphin.
- Honors system GTK/Qt theme; tray via StatusNotifierItem.
- Distribution: AppImage / deb / rpm / Flathub / AUR.

### Desktop dialogs (shared, OS-themed)
```
  Sync job dialog                          Mount dialog
┌──────── New Sync Job ─────────┐        ┌──────── Mount remote ────────┐
│ name [ Nightly-Photos____ ]   │        │ Remote  [ gdrive ▾ ] /        │
│ SRC [Local C ▾]/Photos        │        │ Mount at [ X:  ▾ ]            │
│ DST [onedrive ▾]/Photos       │        │ Cache mode ( writes ▾ )       │
│ ( ) Mirror →  ⚠ deletes       │        │ Cache dir [ SSD…/cache ]      │
│ (•) Backup new only           │        │ [ ] read-only  [✓] auto-mount │
│ ( ) Two-way ⇄ (pairing)       │        │ ⚠ WinFsp not found — [Install]│
│ ▸ Filters ▸ Tuning ▸ Bw       │        │            [Cancel] [ Mount ] │
│ [🔍 Dry-run][Save][ Run ▶ ]   │        └──────────────────────────────┘
└───────────────────────────────┘
```

### Desktop feature set
Dual-pane + **tabs** (many remotes open), drag/drop onto folders + drag-out, multi-select, inline
remote config/OAuth, copy/move/**sync**/**bisync**, dry-run + color compare, transfer queue with
live speed/ETA + bandwidth slider, **mount manager** (VFS options + FUSE auto-install),
**serve** (WebDAV/SFTP/HTTP/FTP/DLNA), scheduler (cron + watch-folder), public links, crypt wizard,
tray + auto-launch, headless/remote-`rcd` profiles (v2).

---

## 3. 📱 Android

Single-pane, touch-first, 4-tab bottom nav. Headline = remotes appear in the **system Files app** via
a `DocumentsProvider` (the "Show in Files" toggle).

```
 Remotes (home)            Files (browser)          In Android system Files
┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────────┐
│ Airclone        ⚙   │  │ ‹ gdrive › Work › Q1 │  │  Files            ⋮     │
│ Your remotes        │  │ ⌂ Work  Q1         🔎│  │ ☰  Recent   Images  …   │
│ ┌─────────────────┐ │  │ 📁 designs/      2d ›│  │  ───────────────────    │
│ │ ▣ Google Drive ●│ │  │ 📁 contracts/    1w ›│  │  Other storage          │
│ │ ▓▓▓▓▓▓░ 64% used│ │  │ 📄 plan.pdf 2.1MB  ⋯ │  │  ▸ ☁ Airclone           │   ← provided by Airclone
│ │ ☁ In Files      │ │  │ 🖼 hero.png 8.4MB  ⋯ │  │     ▸ Google Drive       │
│ │ Show in Files ●○│ │  │                      │  │     ▸ S3 backups         │
│ └─────────────────┘ │  │   (long-press =      │  │  ▸ 💽 Internal storage   │
│ ┌─────────────────┐ │  │    multi-select)     │  └─────────────────────────┘
│ │ ▣ S3 backups   ●│ │  │                  (+) │   Any app's file picker can
│ │ Not in files    │ │  │                      │   now open/save into a remote.
│ │ Show in Files ○○│ │  ├──────────────────────┤
│ └─────────────────┘ │  │ ▤   📁   ⇅    ⚙      │   ▼ background-sync notification
│                 (+) │  │Rem  File Tran  Set   │   ┌───────────────────────────┐
├─────────────────────┤  └──────────────────────┘   │ ⬆ Airclone — backing up    │
│ ▤   📁   ⇅    ⚙     │                              │ Photos → onedrive  62%     │
│Rem  File Tran  Set  │                              │ ▓▓▓▓▓▓░░  124/200 · 2.1MB/s│
└─────────────────────┘                              └───────────────────────────┘
```
- **Show in Files** registers the remote as a SAF root (no FUSE/root needed); other apps' open/save
  pickers can use it.
- Transfers run as foreground-service jobs with a progress notification; scheduled sync via
  WorkManager (best-effort, honest framing).
- Long-press → multi-select action bar (Copy/Move/Download/Share link/Delete); FAB upload.
- Distribution: Play Store + APK (F-Droid-friendly).

---

## 4. 📱 iOS / iPadOS

Same mobile model; OS integration via a **File Provider extension** (remotes appear in the **Files**
app). iPad can show an optional dual-pane in landscape.

```
 iOS — Remotes              In iOS Files app            iPad landscape (adaptive dual-pane)
┌─────────────────────┐  ┌─────────────────────┐  ┌───────────────────────────────────────────┐
│ Airclone        ⚙   │  │  ‹ Browse           │  │ Airclone   [Copy][Move][Sync]   [Jobs] ⚙  │
│ Your remotes        │  │  Locations          │  ├───────────┬───────────────┬───────────────┤
│ ┌─────────────────┐ │  │  ▸ iCloud Drive     │  │ REMOTES   │ ⊞ gdrive      │ ⊞ s3:backups  │
│ │ ▣ iCloud-S3   ● │ │  │  ▸ On My iPhone     │  │ ▣ Drive   │ 📁 designs/   │ 📁 jan/        │
│ │ ▓▓▓░ 31% used   │ │  │  ▸ ☁ Airclone   ←───┼──│ ▣ S3      │ 📄 plan.pdf ═▶│ 📄 plan.pdf    │
│ │ Show in Files ●○│ │  │      ▸ iCloud-S3    │  │ 💽 On iPad│ 🖼 hero.png   │               │
│ └─────────────────┘ │  │      ▸ Drive        │  ├───────────┴───────────────┴───────────────┤
│                 (+) │  └─────────────────────┘  │ JOBS  ▸ Copy hero.png  ▓▓▓▓░ 73%  ETA 0:03 │
├─────────────────────┤   Provided by Airclone's  │ ● engine ok            ↑ 8.4MB/s · 1 job   │
│ ▤   📁   ⇅    ⚙     │   File Provider extension. └───────────────────────────────────────────┘
│Rem  File Tran  Set  │   Drag-drop between apps     Pencil/keyboard + drag-drop on iPad;
└─────────────────────┘   works via Files.            Stage Manager multi-window aware.
```
- **Show in Files** publishes an `NSFileProviderDomain`; remotes appear in Files + any app's document
  picker. Constraints: ~20 MB extension memory (stream to disk), whole-file up/down (no live mount);
  range playback via an in-app server.
- Background sync = BGTaskScheduler (opportunistic/best-effort).
- Distribution: App Store; ABM/VPP for managed fleets.

---

## 5. 🏢 Enterprise overlay (how managed devices differ)

When IT manages the device, policy from the OS/MDM plane changes the UI: forced settings render
**locked** (greyed with a small "Managed by your organization" badge), disabled features disappear or
refuse with a clear reason, and pre-provisioned remotes appear already configured. Examples:
```
 Settings (managed)                         Blocked action (enforced in the seam)
┌──────── Settings ─────────────┐          ┌─────────────────────────────────────┐
│ Theme            [ System ▾ ] │          │  ⚠ Public links are disabled by your │
│ 🔒 Encrypt config   [ON]  🏢  │          │     organization's policy.           │
│ 🔒 Allowed backends s3,sftp 🏢│          │  This action was blocked and logged. │
│ 🔒 Public links   [OFF]   🏢  │          │                          [  OK  ]    │
│ 🔒 Auto-update    [OFF]   🏢  │          └─────────────────────────────────────┘
│    🏢 = managed by your org   │
└───────────────────────────────┘
```
SSO sign-in (if the org enables it) uses the system browser; on-device audit is visible to the user;
nothing phones home. Full design: [19-enterprise-readiness](19-enterprise-readiness.md).

---

## 6. Per-Platform Feature Matrix

✅ full · ➖ adapted/limited · ❌ not applicable

| Capability | Windows | macOS | Linux | Android | iOS/iPad |
| :--- | :--: | :--: | :--: | :--: | :--: |
| In-app explorer (browse/preview/transfer) | ✅ | ✅ | ✅ | ✅ | ✅ |
| Dual-pane + tabs | ✅ | ✅ | ✅ | ❌ (single) | ➖ (iPad landscape) |
| Drag-drop onto folders / drag-out | ✅ | ✅ | ✅ | ➖ (long-press) | ➖ (Files drag) |
| Add/config remotes + OAuth | ✅ | ✅ | ✅ | ✅ | ✅ |
| Copy/Move/Sync/Bisync + dry-run | ✅ | ✅ | ✅ | ✅ | ✅ |
| Appears in OS file explorer | ✅ FUSE drive | ✅ FUSE volume | ✅ FUSE | ✅ DocumentsProvider | ✅ File Provider |
| Live mount perf for upload/move | ➖ VFS | ➖ VFS | ➖ VFS | ➖ on-demand | ➖ whole-file |
| Serve (WebDAV/SFTP/HTTP/DLNA) | ✅ | ✅ | ✅ | ➖ (in-app) | ➖ (in-app) |
| System tray / menu-bar | ✅ | ✅ | ➖ (ext) | ❌ | ❌ |
| Background sync | ✅ daemon | ✅ daemon | ✅ daemon | ➖ WorkManager | ➖ BGTask (best-effort) |
| Scheduler + watch-folder | ✅ | ✅ | ✅ | ➖ scheduled | ➖ scheduled |
| MDM/policy managed | ✅ ADMX/Intune | ✅ profiles/Jamf | ✅ /etc/repo | ✅ managed config | ✅ AppConfig |
| Engine | spawn `rcd` | spawn `rcd` | spawn `rcd` | in-proc librclone | in-proc librclone |

---

**Related:** [App Structure & Layouts](05-app-structure.md) · [File Browser](../features/feat-file-browser.md) ·
[Design System](06-design-system.md) · [Enterprise Readiness](19-enterprise-readiness.md)
