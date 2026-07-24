---
type: "plan"
name: "Store Submission Automation"
status: "active"
description: "CI-driven store submission: Google Play internal-track lane (wired), iOS/TestFlight path (gated on the iOS app), Mac App Store verdict: skip."
---

# 🏪 Store Submission Automation

Research 2026-07-09 (web-verified tooling state). Goal: `git tag` → GitHub Release → store
submission with no console clicking, keyed off GitHub secrets. Full research trail lives in the
session that produced this; the operative conclusions:

## Google Play — WIRED (release.yml android job)

`r0adkll/upload-google-play@v1` (still the de-facto standard; no first-party Google action exists)
pushes the already-built AAB to the **internal track** on every tagged release, with plain-text
release notes distilled from `dev/releases/<tag>.md` (Play cap: 500 chars/locale). Steps are gated
on `PLAY_SERVICE_ACCOUNT_JSON` existing, so nothing changes until the secret lands.

### One-time console setup — RUNBOOK (maintainer, ~15 min + up to a few h propagation)

The JSON credential is minted in **Google Cloud**, not Play Console; Play Console only *grants
that service account access*. Three parts:

**A. Create the service account + JSON key — Google Cloud Console (console.cloud.google.com)**
1. Create or pick a project (a dedicated one like `airclone-play-ci` is fine).
2. **APIs & Services → Library →** search **"Google Play Android Developer API" → Enable**.
3. **IAM & Admin → Service Accounts → Create service account** (e.g. `play-ci-publisher`). No GCP
   project roles are needed — skip that step → **Done**.
4. Open the SA → **Keys → Add key → Create new key → JSON → Create**. A `.json` downloads — **this
   is the secret.** Note the SA email: `play-ci-publisher@<project>.iam.gserviceaccount.com`.

**B. Grant it Play access — Play Console (current UI: Users & permissions, NOT the old "API access")**
5. Play Console → **Users and permissions → Invite new users**.
6. **Email** = the SA email from step 4 (service accounts don't accept an invite — access is
   immediate on save).
7. **App permissions → add Airclone**, grant **"Release to testing tracks and manage testing track
   configuration"** + **"View app information and download bulk reports"** (or the app's *Admin* set).
   → **Invite user / Save.**
   *(Older consoles instead expose Setup → **API access** → link the GCP project → Grant access — same
   effect if that page is present.)*

**C. GitHub secret**
8. Repo → **Settings → Secrets and variables → Actions → New repository secret** →
   `PLAY_SERVICE_ACCOUNT_JSON` = the **entire** contents of the downloaded `.json`.

**Rules that will bite if forgotten:**
- The very FIRST app AAB MUST go through the Play Console UI once (the API can't create an app's
  first track release). Grab the `airclone-playstore-aab` artifact from any release run (or
  `flutter build appbundle --release`) and upload it to the **internal** track manually, once.
- Every API upload needs a **strictly higher versionCode** than anything uploaded before. That is
  the pubspec build number (`+89` as of v0.2.0-beta.2); our per-release bump guarantees monotonicity.
- New SA access can take minutes–hours to propagate; a first-run **403** usually means "wait + retry".
- If the first automated run fails with *"changes cannot be sent for review automatically"*:
  set `changesNotSentForReview: true` for one run, then remove it (it errors the opposite way
  once a reviewed release exists).
- Pre-release tags (`-beta.N`) stop at the **internal** track. A production lane
  (`track: production`, `status: inProgress`, `userFraction: 0.1` staged rollout) gets added when
  v1.0.0 approaches — gate it to non-pre-release tags.

## iOS App Store / TestFlight — path known, gated on the iOS app existing

Nothing here matters until an iOS Runner target **builds and archives** (`flutter build ipa`) —
iOS remains unshipped by design (every iOS app is sandboxed → the file-access model redesign
tracked in the roadmap). When it does:
- **Auth:** App Store Connect API key — `APPSTORE_ISSUER_ID` (variable), `APPSTORE_API_KEY_ID`
  (variable), `APPSTORE_API_PRIVATE_KEY` (.p8, secret). Generated in ASC → Users and Access →
  Integrations. Apple's preferred headless model (no 2FA).
- **Signing in CI:** Xcode automatic signing with `-allowProvisioningUpdates` + the ASC key
  (simplest, recommended for a solo maintainer). fastlane `match` only if multiple humans/machines
  must share identities.
- **Upload:** `apple-actions/upload-testflight-build@v4` (uses the ASC API; runs on macOS or
  Linux). `xcrun altool` is a dead end (already deprecated for notarization; don't build on it).
- Prereqs checklist: register `com.gigaionllc.airclone` (iOS) in the developer portal, create the
  ASC app record, then wire the lane.

## Mac App Store — VERDICT: SUPERSEDED (see REVISED below)

> This SKIP verdict was **overtaken** by the REVISED decision further down (dual-engine mode makes MAS
> viable). Current Apple status + the LIVE macOS direct-download path live in
> `dev/apple-appstore-and-macos.md`; the store-doc index is `docs/store/README.md`.

MAS is structurally incompatible with Airclone as architected **under the subprocess engine** — this is
not a CI problem:
1. **Runtime-downloaded engine is forbidden**: sandboxed/MAS apps may only exec code bundled and
   signed at build time. rclone would have to be bundled and signed with exactly
   `app-sandbox` + `inherit` entitlements.
2. **Even bundled, an inherit-sandboxed child cannot receive the dynamic security-scoped grants**
   (PowerBox / user-selected folders) the parent obtains — and rclone is the process doing all the
   local file I/O. Core local⇄cloud transfers break.
3. **OS mount is impossible** in the MAS sandbox; serve is fragile.

Making it work = re-architecting macOS onto in-process `librclone`, routing all local I/O through
the host with security-scoped bookmarks, and dropping mount — while the existing Developer-ID
signed + notarized DMG passes Gatekeeper cleanly with zero of those limits. No known rclone-based
file manager ships on MAS.

### REVISED (2026-07-09, maintainer decision): dual-engine mode makes MAS a real option

The verdict above assumed the subprocess architecture. Decision: pursue a **dual-engine backend**
behind the existing `RcloneClient` seam —
- **`HttpRcloneClient`** (today): spawns `rclone rcd`, full features incl. OS mount. Default for
  DMG/Developer-ID, Windows, Linux, Android(-as-subprocess).
- **`LibRcloneClient`** (new): in-process `librclone` over dart:ffi (RPC(method, params) mirrors
  the RC API). **In-process I/O holds the host's security-scoped grants — this dissolves MAS
  blocker #2** (the grant-inheritance problem). File access via NSOpenPanel grants + persisted
  security-scoped bookmarks.

Channel matrix (2026-07-09, extended to Windows by maintainer request):
- **Windows zip / macOS DMG / Linux** = BOTH engines: subprocess `rcd` default (full features incl.
  OS mount), in-process librclone selectable in Settings → Engine. Windows bonus: a bundled
  `librclone.dll` gives a zero-download first launch and removes the spawned-exe surface AV
  heuristics occasionally flag.
- **Mac App Store build** = librclone-only (binary/spawn path compile-time disabled with honest
  copy "unavailable in the App Store edition", mount hidden).
- **iOS** = librclone-only — iOS cannot spawn subprocesses AT ALL, so this work is a hard
  prerequisite for the iOS app regardless of MAS.

Build order: (1) `LibRcloneClient` (dart:ffi; the Dart side is platform-agnostic) + cgo builds of
librclone — macOS universal dylib AND windows amd64 dll (mingw-w64 in CI) first, Linux .so next —
behind a Settings → Engine toggle, feature-scoped to explore/transfer/sync (no mount/serve);
(2) security-scoped bookmark plumbing for macOS local paths; (3) MAS target + entitlements + the
iOS/MAS submission lanes from this plan. Mount stays a subprocess-channel feature (FUSE is
impossible on MAS, and librclone builds skip it everywhere). Tracked as its own backlog item:
dual-engine (librclone).

## Secrets inventory (delta)

| Name | Lane | Type | Notes |
| :--- | :--- | :--- | :--- |
| `PLAY_SERVICE_ACCOUNT_JSON` | Play (now) | secret | Full publishing rights — scope Play-side permissions to the automated tracks; rotate via new JSON key |
| `APPSTORE_ISSUER_ID` / `APPSTORE_API_KEY_ID` | iOS (later) | variables | Low sensitivity |
| `APPSTORE_API_PRIVATE_KEY` | iOS (later) | secret | .p8, download-once; revoke+reissue in ASC to rotate |
| MAS certs | — | — | Not provisioned (verdict: skip) |

Existing `AIRCLONE_*` (Android upload key) and `APPLE_*` (Developer ID + notary) secrets are
unchanged; the Play lane adds exactly one secret.
