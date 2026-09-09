<h1 align="center">Airclone</h1>

<p align="center">
  <b>A modern, intuitive, cross-platform GUI for <a href="https://rclone.org/">rclone</a>.</b><br>
  <i>Make every cloud feel like a local folder — on every device.</i>
</p>

<p align="center">
  <i>Windows · macOS · Linux · Android · iOS — one codebase</i>
</p>

<p align="center">
  <b>Get it from a store</b> (auto-updating, signed by the platform) —<br>
  <a href="https://apps.apple.com/app/id6790176897">App Store</a> · iPhone, iPad &amp; Mac &nbsp;|&nbsp;
  <a href="https://play.google.com/store/apps/details?id=com.gigaionllc.airclone">Google Play</a> · Android &nbsp;|&nbsp;
  <a href="https://apps.microsoft.com/detail/9PJ6LRTS2B8X">Microsoft Store</a> · Windows<br>
  <sub>or download a free build from <a href="https://github.com/GigaionLLC/Airclone/releases">Releases</a> — same app, see <a href="#-pricing">Pricing</a></sub>
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/explorer-hero-dark.png">
    <img alt="Airclone dual-pane cloud file explorer — dragging a file from Google Drive to OneDrive" src="docs/screenshots/explorer-hero.png" width="860">
  </picture>
</p>

---

## What is Airclone?

[rclone](https://rclone.org/) is an extraordinarily capable tool for moving files across 70+ cloud
storage systems — but it's a command-line program. **Airclone turns that power into a point-and-click
experience**, and brings it to the desktop *and* the phone:

- 🗂️ **One UI for every backend** — S3, Google Drive, Dropbox, SFTP, WebDAV, local disks… all appear
  as peers in a single list, with the same rows, gestures, and context menu.
- 🖐️ **Direct manipulation** — drag a folder from one cloud to another to copy it; the transfer runs
  as a live job. Easy one-click sync, and a dry-run mode that runs a job without writing anything.
- ⏰ **Sync & schedule** — Copy, Move, Sync (make the destination match) or Two-way; mark a folder as
  the sync source, then later sync it INTO wherever you are standing. Save a job and run it on a
  schedule *(desktop; on **Windows** a schedule also fires with Airclone closed, elsewhere it runs
  while the app is open — see [Scheduling](wiki/features/feat-scheduling.md))*.
- 💽 **Make it local** — mount a remote as a drive on desktop, or hand any file straight to another
  app from your phone with **Open in another app** and the share sheet.
- 🔒 **Free, open-source, and private** — local-only, no telemetry. All manual power stays free.
- 🏢 **Designed for IT, without phoning home** — what ships today is the immovable part: no account,
  no telemetry, no Airclone-operated endpoint, and mount, serve, reveal-in-file-manager and
  archive each behind a single kill-switch provider — the seam a policy source would flip, and the one the Mac App Store
  build already flips. The wider surface — MDM policy, Vault/KMS
  secrets, on-prem audit, an optional self-hosted control plane — is a specified, phased posture, not
  a shipped feature: [Enterprise Readiness](wiki/core/19-enterprise-readiness.md). Any enterprise
  control that lands flows only through customer-owned channels.

> **Status: 0.x, active development** — the free Windows, macOS, Linux and Android builds ship on the
> [Releases](https://github.com/GigaionLLC/Airclone/releases) page: **Windows** builds are code-signed
> (Azure Artifact Signing, "Gigaion, LLC") and **macOS** builds are Developer ID **signed +
> notarized**. Airclone is also listed on the **App Store** (iOS and macOS), the **Microsoft Store**
> (Windows), and **Google Play** (Android — every tag reaches open testing; production is promoted by
> hand). Windows and Android builds bundle the rclone engine (no first-run download). Stack:
> **Flutter** over a single `RcloneClient` seam — see [Architecture at a glance](#-architecture-at-a-glance).

## 📸 A tour

<table>
  <tr>
    <td width="50%"><img src="docs/screenshots/transfer-running.png" alt="Live transfer job with speed and ETA"><br><sub><b>Live transfers</b> — every copy is an observable job: progress, speed, ETA, pause/cancel.</sub></td>
    <td width="50%"><img src="docs/screenshots/sync-dry-run.png" alt="Sync dialog with Copy/Move/Sync/Two-way modes and a Dry run button"><br><sub><b>Safe sync</b> — Copy / Move / Sync / Two-way, with filters, an rclone-command preview, and one-click <b>dry-run</b>.</sub></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/native-skins.png" alt="Settings showing theme control and native skin dropdown"><br><sub><b>Native skins + dark mode</b> — Explorer, Finder, or GNOME looks, light and dark.</sub></td>
    <td><img src="docs/screenshots/thumbnails-grid.png" alt="Grid view with image thumbnails over a cloud remote"><br><sub><b>Thumbnails everywhere</b> — image/video previews over any remote, cached encrypted (AES-256-GCM).</sub></td>
  </tr>
  <tr>
    <td colspan="2" align="center"><img src="docs/screenshots/conflict-guard.png" alt="Conflict dialog offering Skip, Replace, Keep both" width="720"><br><sub><b>Nothing overwrites silently</b> — paste, Copy/Move to…, download, a drag in from Explorer or Finder, or a hand-off to the other pane: a name collision prompts Skip / Replace / Keep both, and a destination that can't be read transfers nothing rather than assuming it's empty.</sub></td>
  </tr>
</table>

### 📱 On your phone

<p align="center">
  <img src="docs/screenshots/android-files.png" alt="Airclone on Android — local locations and cloud remotes" width="270">
  &nbsp;&nbsp;&nbsp;
  <img src="docs/screenshots/android-browser.png" alt="Airclone on Android — browsing a cloud remote" width="270">
</p>

<p align="center">
  <sub>The full rclone engine ships <b>inside the APK</b> — browse every remote with a touch-first UI,
  run transfers in the background with a live notification, and hand any file to another app with
  <b>Open in another app</b> or the share sheet.</sub>
</p>

## 📚 Documentation

This repo follows a structured documentation methodology. **Agents and contributors start at
[`AGENT.md`](AGENT.md).**

| You want to… | Read |
| :--- | :--- |
| Understand the product | [Vision & North Star](wiki/core/01-vision-north-star.md) · [Product Context](wiki/core/02-product-context.md) |
| Understand the architecture | [Core Architecture](wiki/core/08-core-architecture.md) *(framework choice + the `RcloneClient` seam)* |
| Deploy / govern in an org | [Enterprise Readiness](wiki/core/19-enterprise-readiness.md) · [Security](wiki/core/15-security.md) |
| See the layouts | [App Structure & Layouts](wiki/core/05-app-structure.md) *(desktop + mobile wireframes)* |
| Build UI | [Design System](wiki/core/06-design-system.md) · [`DESIGN.md`](DESIGN.md) |
| See the plan | [Feature Backlog](dev/backlog/feature-backlog.md) · [Cross-Platform Plan](dev/plans/cross-platform-architecture-plan.md) |
| Navigate everything | [System Index](wiki/core/00-system-index.md) |

- `wiki/` — long-lived architecture knowledge (the source of truth).
- `dev/` — operational tooling (plans, backlog, logs).
- `Skills/` — the agentic development & documentation skill library.
- `reference/` — **gitignored** competitive research and notes (never committed).

## 🧱 Architecture at a glance

```
UI (Flutter, shared)  →  State (Dart, shared)  →  RcloneClient interface  →  engine
                                     ├─ desktop:  spawn `rclone rcd` + RC HTTP API
                                     │            (or in-process librclone via dart:ffi)
                                     ├─ Android:  the bundled rclone binary as a jniLib,
                                     │            spawned as a loopback `rcd`
                                     └─ iOS / Mac App Store:  in-process librclone via dart:ffi,
                                                  because neither may spawn a subprocess
```

The whole app talks to one `RcloneClient` interface, so ~95% of the code is platform-agnostic, and
one function — `_resolveEngineMode` in `app/lib/src/state/engine_controller.dart` — decides which
engine runs. See [Core Architecture](wiki/core/08-core-architecture.md).

## 🔧 Building & running

The app lives in [`app/`](app/) (Flutter). This machine builds with **Docker locally** (analyze/test)
and **GitHub Actions for the OS-native binaries**. Desktop builds also need a **Rust toolchain** on
PATH (`super_native_extensions` compiles a crate via cargokit). Full details:
[Directory Structure & Build](wiki/core/04-directory-structure.md).

```powershell
docker compose run --rm flutter flutter analyze   # static analysis
docker compose run --rm flutter flutter test      # unit tests
```

**Downloads:** the store listings above ([App Store](https://apps.apple.com/app/id6790176897) ·
[Google Play](https://play.google.com/store/apps/details?id=com.gigaionllc.airclone) ·
[Microsoft Store](https://apps.microsoft.com/detail/9PJ6LRTS2B8X)) are the auto-updating route.
Windows/macOS/Linux/Android builds are also published on the
[Releases](https://github.com/GigaionLLC/Airclone/releases) page (alpha/beta builds are marked
pre-release; **Windows** builds are code-signed and **macOS** builds are signed + notarized).
**Windows and Android** builds bundle the rclone engine (nothing to download on first launch); other
desktop builds fetch + verify it on first launch, and a desktop build can update the engine from
Settings — except the Microsoft Store package, which updates its engine only when the app itself
updates, through the Store.

## 💸 Pricing

**Airclone is free.** Every build on the [Releases](https://github.com/GigaionLLC/Airclone/releases)
page is free to download and install (ad-hoc / sideload), and you can always build it from source
yourself — no fees, no feature gates, no accounts.

The one exception: the store listings carry a small fee. That fee exists solely to fund the
code-signing certificates and developer-program memberships those stores require — it buys
convenience, not features. The store builds and the free builds are the same app.

| Store | Platforms | Listing |
| :--- | :--- | :--- |
| **Apple App Store** | iPhone, iPad (iOS 15+) and Mac (macOS 12+) — one purchase covers all three | [apps.apple.com](https://apps.apple.com/app/id6790176897) |
| **Google Play** | Android (phone, tablet, Android TV) | [play.google.com](https://play.google.com/store/apps/details?id=com.gigaionllc.airclone) |
| **Microsoft Store** | Windows 10/11 | [apps.microsoft.com](https://apps.microsoft.com/detail/9PJ6LRTS2B8X) |

What the fee buys is the managed path: the store installs it, keeps it updated, and vouches for the
signature. Everything else — Linux, and any platform you would rather install by hand — is on the
[Releases](https://github.com/GigaionLLC/Airclone/releases) page for free, forever.

## 🗺️ Roadmap

**Phase 0** spikes → **Phase 1** desktop MVP → **Phase 2** mobile are **shipped**, iOS included; most
of **Phase 3** advanced (bisync, crypt, scheduling) landed during the alphas. The big remaining item is
the *automatic* half of cross-device profile sync — an encrypted blob kept on one of your own remotes;
the manual half already ships (encrypted config export/import and an offline QR handoff between a
desktop and a phone). Live queue: [Feature Backlog](dev/backlog/feature-backlog.md) · details in the
[Cross-Platform Plan](dev/plans/cross-platform-architecture-plan.md).

## 🤖 Built by AI

Airclone is AI-authored under Gigaion, LLC's direction. Review it with the same judgment you would
apply to any production tool you trust with your files.

> 🥚 *The name is a double wink:* **Airclone** reads as **(AI)rclone** *— an AI‑built companion to
> [rclone](https://rclone.org/) —* and as **air + clone**, *cloning your files through the "air" across
> the clouds rclone reaches.*

## License

Airclone is licensed under the **GNU Affero General Public License v3.0** (AGPLv3) — see
[`LICENSE`](LICENSE). Copyright © 2026 Gigaion, LLC. Built on rclone.
