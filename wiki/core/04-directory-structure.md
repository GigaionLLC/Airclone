---
type: "core"
name: "Directory Structure & Build"
status: "stable"
dependencies: ["08-core-architecture"]
description: "Physical repo layout, where things live, and how to build/dev/release (Docker + GitHub Actions)."
---

# 📁 Directory Structure & Build

## Repo layout

```
Airclone/
├─ app/                     # The Flutter application (the product)
│  ├─ lib/
│  │  ├─ main.dart          # entry: ProviderScope → AircloneApp
│  │  └─ src/
│  │     ├─ rclone/         # engine seam (platform-agnostic + desktop transport)
│  │     │  ├─ rclone_client.dart        # RcloneClient interface + EngineStatus
│  │     │  ├─ http_rclone_client.dart   # desktop: spawn `rclone rcd` + RC HTTP
│  │     │  ├─ rclone_engine.dart        # locate / download+verify the rclone binary
│  │     │  └─ models/                   # Remote, RcloneFile
│  │     ├─ state/          # Riverpod controllers (engine, remotes, browser)
│  │     └─ ui/             # app shell, home screen, theme tokens, format helpers
│  ├─ test/                 # unit tests (run in the Linux container / CI)
│  ├─ windows/ macos/ linux/ android/ ios/   # generated platform runners
│  └─ pubspec.yaml          # name: airclone · version: <semver>-alpha.N
├─ wiki/                    # architecture knowledge (source of truth)
├─ dev/                     # plans, backlog, logs
├─ Skills/                  # agentic dev/doc skill library
├─ reference/               # GITIGNORED competitive research (never committed)
├─ tool/                    # dev helper scripts (flutter.ps1/.sh, scaffold.ps1)
├─ .github/workflows/       # ci.yml (analyze/test) · release.yml (platform binaries)
└─ docker-compose.yml       # the `flutter` dev container
```

The **shared core** (`lib/src/rclone` interface, `models`, `state`, `ui`) is platform-agnostic;
Windows is the reference implementation. Only the engine **transport** and OS-integration bits are
platform-specific — see [08-core-architecture.md](08-core-architecture.md).

## Build & dev workflow

This machine has **no native Flutter/Visual Studio** — we use **Docker (linux/amd64) for local
checks** and **GitHub Actions for the OS-native binaries** (a Linux container cannot build a Windows
or macOS desktop app).

### Local (Docker) — analyze, test, format, codegen
```powershell
# Run docker via PowerShell (Git-Bash mangles `-w /work`). Pub cache is a named volume.
docker compose run --rm flutter flutter pub get
docker compose run --rm flutter flutter analyze
docker compose run --rm flutter flutter test
docker compose run --rm flutter dart format lib test
# or the wrapper:
./tool/flutter.ps1 analyze
```
First-time project scaffold (already done): `./tool/scaffold.ps1`.

### CI / releases (GitHub Actions — free on the public repo)
- **`ci.yml`** — on push/PR: `dart format` check, `flutter analyze`, `flutter test` (ubuntu).
- **`release.yml`** — on a `v*` tag: builds **Windows** (windows-latest/MSVC), **macOS**
  (macos-latest/Xcode), **Linux**, **Android**, and publishes a **GitHub Release** with the binaries
  attached (marked pre-release when the tag contains `alpha`/`beta`/`rc`).

### Cutting an alpha
```bash
git tag v0.1.0-alpha.1
git push origin v0.1.0-alpha.1   # → release.yml builds + publishes downloadable binaries
```

### Running the Windows app
Download the `airclone-windows-x64.zip` from the GitHub Release (built on a Windows runner), or —
for fast local iteration — install Flutter + Visual Studio (Desktop C++) natively and
`flutter run -d windows` from `app/`.

### Install / upgrade a local test copy
`tool/install-windows.ps1` installs to `%LOCALAPPDATA%\Programs\Airclone` (Start-Menu shortcut,
pre-seeded rclone engine). Re-running it with a newer tag performs a **proper in-place upgrade** —
it stops the running app, swaps the binaries, and relaunches, while **keeping your rclone config and
engine**:
```powershell
./tool/install-windows.ps1 -Tag v0.1.0-alpha.2   # install
./tool/install-windows.ps1 -Tag v0.1.0-alpha.3   # upgrade in place
```
`tool/run-windows.ps1` is the throwaway screenshot harness (download → launch → capture → clean up).
A future in-app auto-updater (checks GitHub Releases, downloads + swaps) is on the roadmap.

> **Engine note:** on first launch the app locates `rclone` (PATH / app-managed dir) and, if missing,
> offers to download + SHA256-verify the latest official build into the app-support dir. No separate
> install needed.

---

**Related:** [Core Architecture](08-core-architecture.md) · [System Index](00-system-index.md)
