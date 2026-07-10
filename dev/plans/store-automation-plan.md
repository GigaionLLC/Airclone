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

**One-time console setup (maintainer, ~15 min + up to 24 h propagation):**
1. Google Cloud Console → create/select a project → enable **Google Play Android Publisher API**.
2. IAM → Service Accounts → create one (no GCP roles needed) → Keys → **Add key (JSON)** → download.
3. Play Console → Setup → **API access** → link the project → **Grant access** to the service
   account → app permissions: *Release to testing tracks* (+ *Release to production* later) +
   *View app information*.
4. GitHub → org/repo secrets → `PLAY_SERVICE_ACCOUNT_JSON` = the raw JSON file contents.

**Rules that will bite if forgotten:**
- The very FIRST app AAB had to go through the Play Console UI (done — the beta.1 upload).
- Every API upload needs a **strictly higher versionCode** than anything uploaded before —
  the manual upload was `+87`, so the first automated tag must carry `+88` or higher (our
  per-release build-number bump already guarantees this).
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

## Mac App Store — VERDICT: SKIP (stay Developer-ID + notarized)

MAS is structurally incompatible with Airclone as architected — this is not a CI problem:
1. **Runtime-downloaded engine is forbidden**: sandboxed/MAS apps may only exec code bundled and
   signed at build time. rclone would have to be bundled and signed with exactly
   `app-sandbox` + `inherit` entitlements.
2. **Even bundled, an inherit-sandboxed child cannot receive the dynamic security-scoped grants**
   (PowerBox / user-selected folders) the parent obtains — and rclone is the process doing all the
   local file I/O. Core local⇄cloud transfers break.
3. **OS mount is impossible** in the MAS sandbox; serve is fragile.

Making it work = re-architecting macOS onto in-process `librclone`, routing all local I/O through
the host with security-scoped bookmarks, and dropping mount — high effort, degraded product, while
the existing Developer-ID signed + notarized DMG passes Gatekeeper cleanly with zero of those
limits. No known rclone-based file manager ships on MAS. Revisit only alongside an intentional
librclone migration.

## Secrets inventory (delta)

| Name | Lane | Type | Notes |
| :--- | :--- | :--- | :--- |
| `PLAY_SERVICE_ACCOUNT_JSON` | Play (now) | secret | Full publishing rights — scope Play-side permissions to the automated tracks; rotate via new JSON key |
| `APPSTORE_ISSUER_ID` / `APPSTORE_API_KEY_ID` | iOS (later) | variables | Low sensitivity |
| `APPSTORE_API_PRIVATE_KEY` | iOS (later) | secret | .p8, download-once; revoke+reissue in ASC to rotate |
| MAS certs | — | — | Not provisioned (verdict: skip) |

Existing `AIRCLONE_*` (Android upload key) and `APPLE_*` (Developer ID + notary) secrets are
unchanged; the Play lane adds exactly one secret.
