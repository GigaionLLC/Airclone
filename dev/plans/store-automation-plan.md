---
type: "plan"
name: "Store Submission Automation"
status: "superseded"
description: "Original 2026-07-09 research behind the store lanes. All four are now live: Play (open testing, manual since v0.8.3), Microsoft (stage-only), iOS and macOS (dispatch lanes). Kept for the from-nothing Google Cloud / Play Console walkthrough and the dual-engine channel matrix."
---

# 🏪 Store Submission Automation

> **Superseded — original research, 2026-07-09.** This is where the lanes were designed, not what
> they do now. Every store lane described here as future or gated has shipped. Read the as-built
> docs instead and treat the sections below as history plus one still-useful runbook:
>
> | For | Read |
> | :--- | :--- |
> | Play credentials, from nothing | [`dev/play-ci-setup.md`](../play-ci-setup.md) |
> | Play, per release | [`dev/google-play-store.md`](../google-play-store.md) |
> | Apple, per release | [`dev/apple-appstore-and-macos.md`](../apple-appstore-and-macos.md) · account + gates: [`apple-appstore-plan.md`](apple-appstore-plan.md) · identity ledger: [`dev/apple-handoff.md`](../apple-handoff.md) |
> | Microsoft | [`dev/windows-signing-and-store.md`](../windows-signing-and-store.md) · [`dev/msstore-ci-setup.md`](../msstore-ci-setup.md) |
>
> Kept here rather than deleted: the from-nothing **Google Cloud / Play Console** walkthrough below
> (mirrored as-built in `play-ci-setup.md`, which is the copy that wins) and the **dual-engine
> channel matrix**, which is live architecture rather than a verdict.

Research 2026-07-09 (web-verified tooling state). Goal: `git tag` → GitHub Release → store
submission with no console clicking, keyed off GitHub secrets. Full research trail lives in the
session that produced this; the operative conclusions:

## Google Play — WIRED (release.yml android job)

`r0adkll/upload-google-play@v1` (still the de-facto standard; no first-party Google action exists)
pushed the already-built AAB on every tagged release. SUPERSEDED: since v0.8.3 that is a manual publish-play.yml run. Steps were gated on
`PLAY_SERVICE_ACCOUNT_JSON` existing, so nothing changed until the secret landed.

> **As built, this went to the `beta` track — Play Console's *Open testing*, not internal** — and the
> action input is `tracks` (plural); the singular `track:` this plan assumed is deprecated. Release
> notes are not distilled from `dev/releases/<tag>.md` either: one generic line ships every release
> from `docs/store/store-release-notes.txt`. See `dev/google-play-store.md`.

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
  `flutter build appbundle --release`) and upload it to a testing track manually, once.
- Every API upload needs a **strictly higher versionCode** than anything uploaded before. That is
  the pubspec build number (`+89` as of v0.2.0-beta.2); our per-release bump guarantees monotonicity.
- New SA access can take minutes–hours to propagate; a first-run **403** usually means "wait + retry".
- If the first automated run fails with *"changes cannot be sent for review automatically"*:
  set `changesNotSentForReview: true` for one run, then remove it (it errors the opposite way
  once a reviewed release exists).
- *(Planned, not built this way.)* The intent was that pre-release tags stop at the **internal**
  track, with a production lane added near v1.0.0. As built, **every** tag goes to open testing —
  there is no pre-release gate — and production is the separate manual `promote-play.yml`
  (`--from-track beta --to-track production`, staged rollout, dry run by default). The gotcha in
  `dev/google-play-store.md` is the current one.

## iOS App Store / TestFlight — SHIPPED (this section is how it was scoped)

Written while iOS was unbuilt and gated on an iOS Runner target that could archive. It has since
shipped: `ios-release.yml` builds and uploads, and `asc-submit-review.yml` submits. Only the
credential names below are still current; the signing and upload bullets were both wrong and are
corrected in place.

- **Auth:** App Store Connect API key — `APPSTORE_API_KEY_ID` (**variable**), `APPSTORE_ISSUER_ID`
  and `APPSTORE_API_PRIVATE_KEY` (.p8) (**secrets**; this plan put the issuer id in a variable, the
  lanes read it from a secret). Generated in ASC → Users and Access → Integrations. Apple's
  preferred headless model (no 2FA).
- **Signing in CI:** a **stored** Apple Distribution `.p12` + App Store provisioning profile in org
  secrets — `ios-release.yml` `signing=secrets`, its default. Both Apple lanes archive **unsigned**
  (`CODE_SIGNING_ALLOWED=NO`) and sign at export. This plan originally recommended Xcode automatic
  signing with `-allowProvisioningUpdates`; **do not** — `CODE_SIGN_STYLE=Automatic` at archive time
  minted a fresh development certificate per run against Apple's hard per-team cap, and the mode
  survives in the workflow only as a recorded experiment labelled "does NOT work". `signing=ephemeral`
  is the fallback: it mints cert and profile through the Certificates API in-job, revokes only on
  dry-run/validate, and deliberately leaves an upload's certificate alive — revoking one under a build
  still in review returns INVALID BINARY, which has happened here. Those accumulate and are cleared
  afterwards with `apple-revoke-cert.yml`.
- **Upload:** `xcrun altool --validate-app` / `--upload-app` with the ASC API key. That is what both
  shipped lanes use (`ios-release.yml`, `mas-release.yml`) and Apple has accepted builds through it.
  This plan called altool a dead end; that deprecation is about **notarization**, not App Store
  delivery, and nothing here uses `apple-actions/upload-testflight-build` — don't swap out a working
  upload step on the strength of the old note.
- Prereqs checklist: register `com.gigaionllc.airclone` (iOS) in the developer portal, create the
  ASC app record, then wire the lane.

## Mac App Store — VERDICT: SUPERSEDED (see REVISED below)

> This SKIP verdict was **overtaken** by the REVISED decision further down (dual-engine mode makes MAS
> viable), and macOS has since shipped on the Mac App Store. Current Apple status + the LIVE macOS
> direct-download path live in `dev/apple-appstore-and-macos.md`; the account-level gates are
> `dev/plans/apple-appstore-plan.md` and the identity ledger is `dev/apple-handoff.md`; the store-doc
> index is `docs/store/README.md`.

The pre-2026-07-09 reasoning, kept because it is *why* the architecture is what it is: MAS is
structurally incompatible with Airclone as architected **under the subprocess engine** — this was
never a CI problem:
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
| `APPSTORE_API_KEY_ID` | iOS + macOS | variable | Low sensitivity |
| `APPSTORE_ISSUER_ID` | iOS + macOS | secret | This plan filed it as a variable; the lanes read a secret |
| `APPSTORE_API_PRIVATE_KEY` | iOS + macOS | secret | .p8, download-once; revoke+reissue in ASC to rotate |
| `APPLE_MAS_APP_P12_BASE64` / `APPLE_MAS_INSTALLER_P12_BASE64` / `APPLE_MAS_P12_PASSWORD` / `APPLE_MAS_PROVISIONING_PROFILE_BASE64` | Mac App Store | secrets | **Provisioned** (org secrets) — the skip verdict above was reversed; `mas-release.yml` imports these into a job keychain and signs at export |
| `APPLE_IOS_DIST_P12_BASE64` / `APPLE_IOS_P12_PASSWORD` / `APPLE_IOS_PROVISIONING_PROFILE_BASE64` | iOS | secrets | **Provisioned** (org secrets) — the stored identity `ios-release.yml signing=secrets` uses; expiry and rotation are tracked in `dev/apple-handoff.md` |

Existing `AIRCLONE_*` (Android upload key) and `APPLE_*` (Developer ID + notary) secrets are
unchanged; the Play lane adds exactly one secret.
