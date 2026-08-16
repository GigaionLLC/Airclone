# ⚙️ dev — Operational Hub

`dev/` is Airclone's **process and operations** library — how work is planned, logged, built, signed,
released, and submitted to stores — as opposed to [`wiki/`](../wiki/core/00-system-index.md), which
documents **how the code works**.

**When to read this:** you are about to cut a release, submit to a store, build the rclone/librclone
engines by hand, pick up a parked item from the backlog, write or archive a plan, or find out what
actually changed in a shipped version — and you need the exact file rather than a directory to browse.

---

## 🧭 Task router

| I want to… | Go to | Notes |
| :--- | :--- | :--- |
| **Cut a release** | [Release checklist](#-release-checklist) below, then [`.github/workflows/release.yml`](../.github/workflows/release.yml) | Trigger is a `v*` tag push. Notes must exist *before* the tag. |
| **Write the release notes** | [`releases/`](releases/) — add `releases/vX.Y.Z.md` | CI reads this exact path as `--notes-file`; the Android job also distils it for Play. |
| **Know what changed in a release** | [`releases/vX.Y.Z.md`](releases/) | One curated, user-facing file per tag, `v0.1.0-beta.1` → `v0.6.1`. |
| **Submit to the Microsoft Store** | [`windows-signing-and-store.md`](windows-signing-and-store.md) §2 | Read the dated **PATH DECISION** block first — the product is an **MSIX** again as of 2026-08-08. |
| **Set up / rotate Windows code signing** | [`windows-signing-and-store.md`](windows-signing-and-store.md) §1 | Azure Artifact Signing as-built record + an idempotent `az`/`gh` runbook. |
| **Triage a Windows certification failure** | [`windows-signing-and-store.md`](windows-signing-and-store.md) (2026-07-29 report + uninstall traps) | Expand every collapsed row and download the supporting-files ZIP before starting work. |
| **Submit to Google Play** | [`google-play-store.md`](google-play-store.md) | Per-release runbook A→F. One-time service-account setup is in [`plans/store-automation-plan.md`](plans/store-automation-plan.md). |
| **Ship macOS (direct download)** | [`apple-appstore-and-macos.md`](apple-appstore-and-macos.md) §1 | Fully automated by the tag — no manual runbook; only confirm the notarized zip/DMG landed. |
| **Work toward Mac App Store / iOS** | [`apple-appstore-and-macos.md`](apple-appstore-and-macos.md) §2 → [`plans/dual-engine-plan.md`](plans/dual-engine-plan.md) | Blocked on the in-process `librclone` engine; do not wire MAS/TestFlight CI before it. |
| **Check listing copy, pricing policy, pre-submission audit** | [`../docs/store/README.md`](../docs/store/README.md) | Owns the store-fee policy and the H-17 truth-audit checklist for every platform. |
| **Build the Android rclone engine locally** | [`android/build-rclone.ps1`](android/build-rclone.ps1) | Cross-compiles per ABI into `app/android/app/src/main/jniLibs/<abi>/librclone.so`. CI equivalent: the `android` job. |
| **Build librclone (in-process engine) locally** | [`desktop/build-librclone.ps1`](desktop/build-librclone.ps1) · [`desktop/build-librclone.sh`](desktop/build-librclone.sh) | Verify with [`.github/workflows/librclone.yml`](../.github/workflows/librclone.yml) before depending on it in a release. |
| **Regenerate Play screenshots** | [`store/gen_store_shots.py`](store/gen_store_shots.py) + [`plans/play-screenshots-plan.md`](plans/play-screenshots-plan.md) | Composes raw `adb screencap` PNGs onto Play-legal canvases; `--check` verifies without rewriting. |
| **Check the backlog / pick up parked work** | [`backlog/backlog-index.md`](backlog/backlog-index.md) → [`backlog/feature-backlog.md`](backlog/feature-backlog.md) | Index is the queue; feature-backlog is the prioritised MoSCoW roadmap with `[D]`/`[M]` platform tags. |
| **Find reliability / hardening work** | [`backlog/hardening-audit-2026-07-15.md`](backlog/hardening-audit-2026-07-15.md) | 18 evidence-linked candidates. Reproduce before implementing — its line numbers have moved. |
| **Start multi-step work** | [`plans/template-plan.md`](plans/template-plan.md), write into [`plans/`](plans/) | Required by rule 6 of [`AGENT.md`](../AGENT.md). |
| **Close out a task** | [`logs/agent-changelog.md`](logs/agent-changelog.md) + [`archive-plans/README.md`](archive-plans/README.md) | The Wrap-Up Protocol in [`AGENT.md`](../AGENT.md): log the entry, sync `wiki/`, move the finished plan. |

---

## 📂 Directory map

| Path | What lives there |
| :--- | :--- |
| [`windows-signing-and-store.md`](windows-signing-and-store.md) | Windows code signing (as-built + reproduce) **and** the Microsoft Store per-release runbook, MSIX identity plumbing, and certification post-mortems. The largest process doc; the freshest decision in `dev/`. |
| [`google-play-store.md`](google-play-store.md) | Per-release Google Play runbook + a reusable facts table (package name, listing path, CI action, versionCode rule) + gotchas. |
| [`apple-appstore-and-macos.md`](apple-appstore-and-macos.md) | Two lanes under one roof: macOS direct download (live, automated) and Mac App Store / iOS (future, blocked on dual-engine). |
| [`secrets/`](secrets/README.md) | **One developer's real account values** (store publisher identity, signing profiles, release hosting) kept OUT of this public repo. `dev-profile.env` is gitignored; only the schema template and its readme are committed. Clone this repo and it will not exist — copy the template and fill in your own. |
| [`backlog/`](backlog/backlog-index.md) | The queue: index, the prioritised feature roadmap, the 2026-07-15 hardening audit, a settings/advanced-config UX review, and one explicitly historical beta-quality review. |
| [`plans/`](plans/) | Active implementation plans. Two house styles coexist: YAML frontmatter (`status:`) and a prose `**Status:**` line — check both when judging whether a plan is live. |
| [`archive-plans/`](archive-plans/README.md) | Where finished plans are moved during wrap-up so `plans/` only shows live work. |
| [`logs/`](logs/agent-changelog.md) | `agent-changelog.md` (per-task audit entries, newest first) and `version-history.md` (release log + versioning policy). Both are stale — see [Known staleness](#-known-staleness). |
| [`releases/`](releases/) | 24 curated, user-facing release-note files, one per tag. **Not decorative** — CI consumes them (see below). House style: user-benefit prose plus a `## Notes` section stating signing status and known limitations. |
| [`store/`](store/gen_store_shots.py) | `gen_store_shots.py` — the Play screenshot compositor, kept in-repo so the next re-shoot is not archaeology. |
| [`android/`](android/build-rclone.ps1) | `build-rclone.ps1` — local cross-compile of the Android rclone engine. |
| [`desktop/`](desktop/build-librclone.ps1) | `build-librclone.ps1` / `build-librclone.sh` — local builds of `librclone.dll` / `.dylib` / `.so` for the FFI engine. |

---

## 🤖 CI workflows

Three workflows in [`.github/workflows/`](../.github/workflows/). All secrets/variables below are
named, **never valued** — this repo is public.

| Workflow | Trigger | What it does |
| :--- | :--- | :--- |
| [`ci.yml`](../.github/workflows/ci.yml) | push to `main`, every PR, manual, weekly cron (Mondays 06:00 UTC) | `analyze-test`: `dart format --set-exit-if-changed` → `flutter analyze` → `flutter test --coverage` (coverage uploaded as an artifact). `rclone-pin`: **warn-only** drift check comparing `RCLONE_VERSION` in `release.yml` against the pins in `dev/android/build-rclone.ps1` and both `dev/desktop/build-librclone.*`, and against the latest upstream rclone. |
| [`librclone.yml`](../.github/workflows/librclone.yml) | manual, or a push touching the build scripts / FFI sources | Per-OS matrix (windows/macos/ubuntu): build librclone → check the artifact is well-formed → run the **live FFI integration test** against the freshly built lib → upload it. The standalone hard gate for the in-process engine. |
| [`release.yml`](../.github/workflows/release.yml) | push of a `v*` tag; manual runs build artifacts only (no Release) | `release` (creates the GitHub Release first, so platform jobs only upload) → `librclone` matrix → `windows`, `linux`, `macos`, `android` in parallel. `RCLONE_VERSION` is pinned once at workflow level for every engine build. |

**Release-notes coupling.** The `release` job uses `dev/releases/$GITHUB_REF_NAME.md` as `--notes-file`
when it exists and emits a `::warning::` + falls back to `--generate-notes` when it does not. Tags
containing `alpha`, `beta`, or `rc` are marked pre-release. If the Release already exists the job leaves
it alone. The `android` job distils the same file to `distribution/whatsnew/whatsnew-en-US`, capped at
480 bytes.

**Gating — variables** (repo/org Actions *variables*): `WINDOWS_SIGNING_ENABLED`,
`AZURE_SIGNING_ENDPOINT`, `AZURE_SIGNING_ACCOUNT`, `AZURE_SIGNING_PROFILE`, `MSIX_IDENTITY_NAME`,
`MSIX_PUBLISHER`, `MSIX_DISPLAY_NAME`, `STORE_APP_ID`. (`STORE_PUBLISH_ENABLED` is retired —
Store submission is the manual `submit-msstore.yml` workflow, not a tag side-effect.)

**Gating — secrets:** `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`; `STORE_TENANT_ID`,
`STORE_CLIENT_ID`, `STORE_CLIENT_SECRET`, `STORE_SELLER_ID`;
`APPLE_DEVELOPER_ID_APPLICATION_P12_BASE64`, `APPLE_DEVELOPER_ID_APPLICATION_P12_PASSWORD`,
`APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID`; `AIRCLONE_KEYSTORE_BASE64`,
`AIRCLONE_KEYSTORE_PASSWORD`, `AIRCLONE_KEY_ALIAS`, `AIRCLONE_KEY_PASSWORD`;
`PLAY_SERVICE_ACCOUNT_JSON`.
(The list above is read straight from `release.yml`; the Apple secret table in
[`apple-appstore-and-macos.md`](apple-appstore-and-macos.md) omits `APPLE_DEVELOPER_ID_APPLICATION_P12_PASSWORD`.)

**What fails hard vs. what degrades quietly** — worth knowing before you trust a job's colour:

| Behaviour | Where |
| :--- | :--- |
| **Hard fail** — tagged build with no Android keystore secret (refuses to publish a debug-signed APK) | `android` job |
| **Hard fail** — tagged build with no Apple signing-cert secret (never ships an unsigned "release") | `macos` job |
| **Hard fail** — the app-local MSVC runtime (`msvcp140.dll`, `vcruntime140*.dll`) is missing from the Release dir | `windows` job |
| **Hard fail** — rclone not bundled / checksum mismatch (was `continue-on-error` until v0.5.3; see below) | `windows` job |
| **Degrades** — `librclone` artifact download is `continue-on-error` → that platform ships **binary-engine-only**, with only a `::warning::` | `windows`, `linux`, `macos` jobs |
| **Degrades** — MSIX build, MSIX upload, and the `msstore publish` step are all `continue-on-error`; a missing `MSIX_*` variable only warns and still produces a package carrying pubspec **placeholder** identity | `windows` job |
| **Degrades** — notarization is best-effort and bounded ([`.github/scripts/notarize.sh`](../.github/scripts/notarize.sh)); the signed zip is uploaded **before** notarizing so an Apple outage cannot block a release | `macos` job |

---

## ✅ Release checklist

Distilled from the three store runbooks and the v0.5.x–v0.6.x release history.

1. **Bump the version** in [`app/pubspec.yaml`](../app/pubspec.yaml) (`version: X.Y.Z+N`). The build
   number `+N` is the Play **versionCode** and must strictly increase — the single most common upload
   failure.
2. **Write `dev/releases/vX.Y.Z.md` before tagging.** No file = generated notes on the GitHub Release
   *and* a one-line fallback in the Play what's-new. Follow the house style: user-benefit prose, then a
   `## Notes` section naming signing status and known limitations.
3. **Green the local gates first:** `dart format --output=none --set-exit-if-changed .`,
   `flutter analyze` (CI fails on **any** info-level lint), `flutter test`.
4. **Tag `vX.Y.Z` and push.** An `alpha`/`beta`/`rc` in the tag marks the Release pre-release.
5. **Verify the artifacts — see the rule below.** Do not move on because the run is green.
6. **Store lanes**, if this release goes to a store: run the pre-submission truth audit in
   [`../docs/store/README.md`](../docs/store/README.md), then the platform runbook
   ([Microsoft](windows-signing-and-store.md) §2 · [Play](google-play-store.md) ·
   [macOS/Apple](apple-appstore-and-macos.md)).
7. **Wrap up:** changelog entry in [`logs/agent-changelog.md`](logs/agent-changelog.md), sync any
   `wiki/` doc whose described behaviour changed, and move any finished plan to
   [`archive-plans/`](archive-plans/README.md).

### 🔍 Verify BY INSPECTING THE ARTIFACT, not by trusting a green check

**Three releases (v0.5.0 – v0.5.2) shipped with no rclone engine behind green CI checks**, because the
bundling step was `continue-on-error` and its failure was invisible in the run summary. The step is
fatal now (v0.5.3), but `continue-on-error` still guards the librclone download and the entire MSIX
lane, so a green run still does not prove an artifact is complete. A second instance of the same class:
the **v0.6.0 MSIX shipped with placeholder identity** — Partner Center rejected it four times, and
v0.6.1 exists only to fix that.

Download the assets and check:

| Asset | Confirm |
| :--- | :--- |
| `airclone-windows-x64.zip` / `airclone-setup-x64.exe` | `rclone.exe` is inside; `msvcp140.dll` + `vcruntime140.dll` + `vcruntime140_1.dll` sit next to `airclone.exe`; `Get-AuthenticodeSignature` returns **Valid**, timestamped, for the installer, `airclone.exe` and `rclone.exe`. |
| `airclone.msix` | Only submittable when the `MSIX_*` variables were set for that run — otherwise it carries placeholder identity and Partner Center rejects it before certification starts. |
| `airclone-macos.zip` / `airclone-macos.dmg` | The **notarized, stapled** zip replaced the pre-notarization upload; the DMG is present only when notarization succeeded. |
| `airclone-android-<abi>.apk` / `airclone-playstore.aab` | Install on a real device or emulator, launch, browse a remote. (`airclone-android-universal.apk` is the single-APK convenience build.) |
| `airclone-linux-x64.tar.gz` | Extracts and runs; `librclone.so` present if the in-process engine was expected. |

---

## ⚠️ Known staleness

Verified against the current tree — treat these files as **context, not truth**, until they are repaired:

- [`logs/version-history.md`](logs/version-history.md) — newest row is `v0.1.0-beta.1`; nothing for
  v0.2–v0.6. Its "3-Level System" policy describes a `1.02.003` numbering scheme this repo has never
  used: real tags are plain semver (`app/pubspec.yaml` is `0.6.1+110`, latest tag `v0.6.1`).
- [`logs/agent-changelog.md`](logs/agent-changelog.md) — newest entry is 2026-07-15, despite the
  Wrap-Up Protocol making an entry mandatory. Its "new entries go above this line" marker sits *below*
  the newest entry.
- [`archive-plans/README.md`](archive-plans/README.md) — still "none yet" although shipped plans exist
  in [`plans/`](plans/).
- [`plans/`](plans/) — several plans still read `planned`/`proposed` for work that shipped
  ([`command-console-plan.md`](plans/command-console-plan.md),
  [`config-portability-plan.md`](plans/config-portability-plan.md),
  [`popout-image-viewer-plan.md`](plans/popout-image-viewer-plan.md);
  [`config-transfer-simplify-plan.md`](plans/config-transfer-simplify-plan.md) carries no status
  marker at all). Check the code before believing a plan's status.
- [`../docs/store/README.md`](../docs/store/README.md) — its platform table still describes the
  Microsoft Store product as an unpackaged Win32 EXE, which the 2026-08-08 MSIX decision in
  [`windows-signing-and-store.md`](windows-signing-and-store.md) reverses.

---

## 🔒 Public-repo rule

This repository is **public**. Never commit GUIDs of any kind (Partner Center publisher/tenant/seller/
app ids, Azure subscription ids), D-U-N-S numbers, physical addresses, personal email addresses, or
infrastructure hostnames. Use `<placeholder>` tokens in these docs and say where the real value lives —
e.g. "in repo variable `MSIX_PUBLISHER`", "in private notes". Signing secrets live only in GitHub
Secrets, which are write-only and cannot be read back.

---

## Related

- [`../wiki/core/00-system-index.md`](../wiki/core/00-system-index.md) — the architecture library's
  master router (this hub is its operational counterpart).
- [`../docs/store/README.md`](../docs/store/README.md) — store submission index: pricing policy, the
  pre-submission truth audit, and per-platform listing assets.
- [`../AGENT.md`](../AGENT.md) — agent entry point: mandatory reading order, core development rules,
  and the Wrap-Up Protocol that feeds `logs/` and `archive-plans/`.
- [`../wiki/core/17-docs-blueprint.md`](../wiki/core/17-docs-blueprint.md) — how this documentation
  library is organised and extended.
- [`../wiki/core/18-knowledge-capture.md`](../wiki/core/18-knowledge-capture.md) — where decisions and
  gotchas get recorded.
- [`../wiki/core/14-performance-standards.md`](../wiki/core/14-performance-standards.md) — the
  concurrency budgets and reliability invariants a release is expected to hold.
