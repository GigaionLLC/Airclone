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

**When to read this:** you are about to design or scope UI work and need what the target platform's
shell, OS-integration surface and capability level actually are — or a proposal assumes a capability
(tray, dual-pane, drag-out, background sync, FUSE mount) that one of the five platforms does not have.

> Form-factor split: **desktop** (Win/macOS/Linux) = dual-pane commander; **mobile** (Android/iOS) =
> single-pane touch browser; **tablet/iPad** = adaptive (the desktop shell from 700px wide);
> **television** (Android TV / Google TV) = the mobile shell plus a D-pad side rail and a focus ring
> we draw ourselves (§3.1).

---

## 1. Shared foundation (all platforms)

- The **rebuilt rclone file explorer** is the hero everywhere (browse, drag/drop, multi-select,
  preview, server-side transfers via direct RC — no VFS). See [feat-file-browser](../features/feat-file-browser.md).
- The same **add-remote wizard** (dynamic form from `config/providers` + OAuth), **transfer/job
  model**, **sync directions** (Mirror / Backup-new / Two-way), **design tokens**, light/dark theme,
  and **i18n**.
- Differences are only: window chrome, navigation (sidebar+tabs vs bottom-nav vs D-pad rail), and how
  a remote is exposed to the OS — a FUSE mount on desktop, and on mobile the planned
  `DocumentsProvider` / File Provider bridge, which is **not built yet** (see
  [02-product-context](02-product-context.md), which owns that status).

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
│ DST [onedrive ▾]/Photos       │        │ Cache mode ( full ▾ )         │
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

Single-pane, touch-first, bottom-nav shell. The intended headline is that remotes appear in the
**system Files app** via a `DocumentsProvider` — the "Show in Files" toggle sketched below. **That
bridge is designed, not built:** there is no `DocumentsProvider` in `app/android/`, and the
toggle does not ship. What *does* ship on Android today is the in-app explorer, background transfers
as a foreground service, and hand-off to another app through a `FileProvider` `content://` URI.
[02-product-context](02-product-context.md) owns that status; do not re-state it as shipped here.

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
- **Show in Files** (planned) would register the remote as a SAF root (no FUSE/root needed) so other
  apps' open/save pickers could use it. Not implemented.
- Transfers run as foreground-service jobs with a progress notification; scheduled sync via
  WorkManager (best-effort, honest framing).
- Long-press → multi-select action bar (Copy/Move/Download/Share link/Delete); FAB upload.
- Distribution: Play Store + APK (F-Droid-friendly).

### 3.1 📺 Android TV / Google TV

The **same APK and the same phone shell**, wrapped in affordances that arm only when Android reports a
television. `MainActivity.isTelevision()` answers on two independent signals — `UI_MODE_TYPE_TELEVISION`
(what the platform reports at runtime, and what emulators set) or `FEATURE_LEANBACK` (what Play
filters on, and what some manufacturer boxes report instead) — and
[`android_native.dart`](../../app/lib/src/state/android_native.dart) resolves it **once before
`runApp`**, defaulting to `false` until the channel answers — so a channel that fails to answer
degrades a TV to the touch shell rather than giving a phone the TV one.

```
┌──────────────────────────────────────────────────────────────┐  ← 48×27dp overscan inset
│ ▤   │  ‹ gdrive › Work › Q1                                  │     (TVs crop the picture by an
│Files│  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓     │      amount no app can query)
│ ⇅   │  ┃ 📁 designs/                            2d      ┃ ←──┼── the focus ring WE draw
│Trans│  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛     │
│ ⚙   │    📄 plan.pdf                     2.1MB  3h            │
│ Set │    🖼 hero.png                     8.4MB  2h            │
└──────────────────────────────────────────────────────────────┘
   ↑ side rail, not a bottom bar
```

Three things differ from the phone, and each exists because a remote has no pointer: the **rail is on
the side** (from a bottom bar, reaching it means pressing DOWN through every row of the file list
first), the **focus ring is drawn by Airclone** rather than by Material, and **focus is seeded and
kept escapable** so a dialog or a text field can never trap it. The shell that installs all three,
and the incident behind each, is [05-app-structure.md](05-app-structure.md) § *Television*.

Distribution is the same bundle; `leanback` is declared `required="false"` so the phone build stays
installable. Operational detail — how to test with a D-pad, and what a TV image does not have — is in
[`dev/android-tv.md`](../../dev/android-tv.md).

---

## 4. 📱 iOS / iPadOS

Same mobile model. OS integration is designed around a **File Provider extension** (remotes appearing
in the **Files** app) — **that extension does not exist yet**: `app/ios/` holds only `Runner` and
`RunnerTests`, no extension target. iPad gets the desktop shell from 700px wide, so a landscape dual
pane comes for free.

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
- **Show in Files** (planned) would publish an `NSFileProviderDomain` so remotes appear in Files and
  in any app's document picker. Design constraints already known and worth keeping: ~20 MB extension
  memory (stream to disk), whole-file up/down (no live mount), range playback via an in-app server.
- Background sync = BGTaskScheduler (opportunistic/best-effort).
- Distribution: App Store; ABM/VPP for managed fleets.

---

## 5. 🏢 Enterprise overlay (how managed devices would differ)

**Designed, not built** — this section is the target shape, kept because it is what the kill-switch
seams in the code are shaped for. When IT manages the device, policy from the OS/MDM plane changes the
UI: forced settings render
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

✅ full · ➖ adapted/limited · ❌ not applicable · ⏳ planned, not built

| Capability | Windows | macOS | Linux | Android | iOS/iPad |
| :--- | :--: | :--: | :--: | :--: | :--: |
| In-app explorer (browse/preview/transfer) | ✅ | ✅ | ✅ | ✅ | ✅ |
| Dual-pane + tabs | ✅ | ✅ | ✅ | ❌ (single) | ➖ (iPad landscape) |
| Drag-drop onto folders / drag-out | ✅ | ✅ | ✅ | ➖ (long-press) | ➖ (Files drag) |
| Add/config remotes + OAuth | ✅ | ✅ | ✅ | ✅ | ✅ |
| Copy/Move/Sync/Bisync + dry-run | ✅ | ✅ | ✅ | ✅ | ✅ |
| Appears in OS file explorer | ✅ FUSE drive | ✅ FUSE volume | ✅ FUSE | ⏳ DocumentsProvider | ⏳ File Provider |
| Live mount perf for upload/move | ➖ VFS | ➖ VFS | ➖ VFS | ➖ on-demand | ➖ whole-file |
| Serve (WebDAV/SFTP/HTTP/DLNA) | ✅ | ✅ | ✅ | ➖ (in-app) | ➖ (in-app) |
| System tray / menu-bar | ✅ | ✅ | ➖ (ext) | ❌ | ❌ |
| Background sync | ✅ daemon | ✅ daemon | ✅ daemon | ➖ WorkManager | ➖ BGTask (best-effort) |
| Scheduler + watch-folder | ✅ | ✅ | ✅ | ➖ scheduled | ➖ scheduled |
| MDM/policy managed | ⏳ ADMX/Intune | ⏳ profiles/Jamf | ⏳ /etc/repo | ⏳ managed config | ⏳ AppConfig |
| Engine | spawn `rcd` | spawn `rcd` | spawn `rcd` | spawn `rcd` (bundled jniLib) | in-proc librclone |

Android runs the **same `HttpRcloneClient` as desktop** — the rclone executable ships as a per-ABI
native library and is spawned as `rcd` on loopback. Only iOS and the Mac App Store build are
in-process. That is a summary of the `Engine` row: the rule itself, the short-circuit that makes it
non-negotiable, and the reasoning are owned by [08-core-architecture.md](08-core-architecture.md) §3.
[10-external-integrations.md](10-external-integrations.md) §1.1–§1.2 carries the two client
implementations and the per-platform resolution; §1.3 and §4 carry how the binary is located and
what native code ships in the bundle.

**MDM is ⏳ on every platform**, and the §5 overlay above is the design for it. What exists today is
the seam it will be enforced through — the four kill-switch providers in
[07-state-context.md](07-state-context.md), each re-checked inside the controller — not a reader for
any OS's managed configuration. Nothing in `app/` parses ADMX, a configuration profile, Android
restrictions or AppConfig.

**Android TV** is the Android column with the shell from §3.1: no tray, no dual pane, and mount and
serve stay where they are on Android. The one capability a television removes outright is the system
file picker — `ACTION_OPEN_DOCUMENT` resolves to a framework stub with no UI, so any flow that asks
the OS for a file needs an in-app path on TV.

---

## 🔗 Related

- [05-app-structure.md](05-app-structure.md) — the shell, navigation and layout anatomy these wireframes sketch.
- [20-explorer-design.md](20-explorer-design.md) — the explorer that is the hero of every platform tour above.
- [../features/feat-file-browser.md](../features/feat-file-browser.md) — the browser spec behind the shared explorer behaviour.
- [../features/features-index.md](../features/features-index.md) — per-capability specs, to check what a matrix cell is actually backed by.
- [06-design-system.md](06-design-system.md) — the tokens, typography and components the per-platform chrome is built from.
- [02-product-context.md](02-product-context.md) — which persona each platform tour is written for.
- [19-enterprise-readiness.md](19-enterprise-readiness.md) — the managed-device overlay in §5, in full.
- [00-system-index.md](00-system-index.md) — master router.
