---
type: "plan"
name: "README Screenshots Plan"
status: "planned"
description: "Shot list, README markup, and capture workflow for adding screenshots to the README."
---

# 📸 README Screenshots Plan

Goal: make the README *show* the product. 8 shots max, each tied to a headline feature; hero at the
top, gallery after the feature bullets, phone shots in their own subsection. Assets live in
`docs/screenshots/` (committed, optimized PNGs, relative paths so forks render).

## Shot list

| File (`docs/screenshots/`) | View | Platform | Caption |
|---|---|---|---|
| `explorer-hero.png` (+`-dark`) | Dual-pane commander, sidebar of remote cards; Drive-style remote left, S3-style right, folder mid-drag | Windows, light+dark | One file manager for every cloud — drag a folder from Drive to S3 and it copies, cloud-to-cloud |
| `transfer-running.png` | Jobs dock expanded: live copy ~70%, speed + ETA, one queued job | Windows | Every transfer is a live, observable job |
| `sync-dry-run.png` | Transfer-options dialog: Mirror / Backup-new / Two-way + prominent Dry run | Windows | Safe sync — dry-run preview before anything destructive |
| `mount-manager.png` | Mount dialog + Explorer window behind showing the mounted drive letter | Windows | Mount any remote as a real drive |
| `serve-share.png` | Serve manager: WebDAV server running, copyable URL, LAN toggle | Windows | Serve any remote over HTTP/WebDAV/FTP/SFTP/DLNA *(drop first if trimming to 6)* |
| `native-skins.png` | Settings: theme segmented control + Skin dropdown (Airclone/Explorer/Finder/GNOME) | Windows | Native-feel skins + full light/dark |
| `android-browser.png` | Phone Files tab: remotes list → touch browser one level deep | Phone AVD, portrait | The same app on your phone |
| `android-transfers.png` | Phone Transfers tab, live upload + pulled-down system notification | Phone AVD, portrait | Background transfers with a live notification |

## README markup

- **Hero** (right under the tagline, before "What is Airclone?"): `<picture>` with a
  `prefers-color-scheme: dark` source → tracks the reader's GitHub theme. Only the hero gets a dark
  variant (doubling every asset isn't worth it).
- **Gallery**: a `### A tour` section right after the feature bullets — 2-column HTML `<table>`
  (renders reliably on GitHub; captions via `<sub>`). **No `<details>`** for the primary gallery
  (readers don't expand it); reserve `<details>` for overflow extras (palette, add-remote, inspector).
- **Phone shots**: own `### On your phone` row, side-by-side, `width="270"` attribute per `<img>`
  (GitHub strips CSS but honors width) so portrait shots don't tower.
- `alt` text on every image.

## Capture workflow

**Principle:** consistency comes from seeded demo data + one fixed window size, not from a script.

1. **Demo data** — throwaway `rclone.conf` with `type=local`/`type=alias` remotes *named* like clouds
   ("Google Drive", "S3 backups", "OneDrive") pointing at staged folders (designs/, contracts/,
   plan.pdf, budget.xlsx, jan/, feb/ — varied sizes, back-dated mtimes). No real credentials ever on
   screen. Point the app/`RCLONE_CONFIG` at it.
2. **Desktop (this Windows 11 machine)** — `flutter run -d windows --release` (no debug banner).
   Size the window once (~1600×1000 logical, high-DPI panel → crisp 2×) and keep it for every shot.
   Capture the DWM window frame with ShareX (locked region) or Win+Shift+S.
   For `transfer-running.png`: throttle via the bandwidth slider so a big local→local copy sits
   mid-progress. Skins are palette swaps (`AircloneColors.forSkin`) — showing Finder/GNOME skins *on
   Windows* is honest as "skins", but never label one as a real macOS screenshot.
3. **Android (phone AVD, not the desktop-verification tablet)** — Pixel-class portrait AVD,
   `flutter run --release`. Clean status bar via demo mode
   (`adb shell settings put global sysui_demo_allowed 1` + `com.android.systemui.demo` broadcasts:
   clock 12:00, battery 100, hide notifications), capture with
   `adb exec-out screencap -p > docs/screenshots/android-browser.png`.
4. **Real macOS shots** — unavailable locally (CI only, headless). Not needed for launch: skins are
   demonstrable from Windows; add genuine Finder-chrome shots later from a Mac.
5. **Optimize before commit** — `oxipng -o max --strip all` (strips metadata too); target <300 KB per
   image.

**Scripted vs manual:** manual for launch (the two money shots — mid-drag, mid-transfer — are
transient states that fight an integration-test harness). If screenshots become a per-release chore,
add an `integration_test` that seeds the config and screenshots the static dialogs.

## Sequencing

1. Land beta.1 (done in this pass) → 2. seed demo config + stage folders → 3. capture the 6 desktop
shots → 4. capture the 2 Android shots → 5. optimize + commit `docs/screenshots/` → 6. README hero +
gallery PR (drop the stale-status text at the same time — already fixed in beta.1).

## Status: CAPTURED + SHIPPED (2026-07-09, same day as beta.1)

9 finals live in `docs/screenshots/` and wired into the README (hero `<picture>` light/dark + tour
table + phone section): `explorer-hero(.png/-dark.png)` (mid-drag, drop-target highlighted),
`transfer-running`, `sync-dry-run`, `native-skins` (skin dropdown open), `thumbnails-grid`,
`conflict-guard`, `android-files`, `android-browser`. Captured exactly per this plan: alias/webdav
remotes named like clouds over `D:\AircloneDemo` staged data (desktop: `RCLONE_CONFIG` env; Android:
beta.1 release APK on a Pixel-7 AVD + host `rclone serve webdav` at `10.0.2.2:8090` + demo-mode
status bar). Still open: `mount-manager` + `serve-share` shots (Advanced-mode features; WinFsp needed
for a real mount) and a true-macOS Finder-chrome shot.
