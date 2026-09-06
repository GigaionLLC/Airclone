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
| **Write the release notes** | [`releases/`](releases/) — add `releases/vX.Y.Z.md` | CI reads this exact path as `--notes-file` for the **GitHub Release**. The store "what's new" is a different, generic file — see [Release-notes coupling](#-ci-workflows). |
| **Know what changed in a release** | [`releases/vX.Y.Z.md`](releases/) | One curated, user-facing file per shipped tag, `v0.1.0-beta.1` → the latest tag. |
| **Submit to the Microsoft Store** | [`windows-signing-and-store.md`](windows-signing-and-store.md) §2 | Read the dated **PATH DECISION** block first — the product is an **MSIX** again as of 2026-08-08. |
| **Set up / rotate Windows code signing** | [`windows-signing-and-store.md`](windows-signing-and-store.md) §1 | Azure Artifact Signing as-built record + an idempotent `az`/`gh` runbook. |
| **Triage a Windows certification failure** | [`windows-signing-and-store.md`](windows-signing-and-store.md) (2026-07-29 report + uninstall traps) | Expand every collapsed row and download the supporting-files ZIP before starting work. |
| **Submit to Google Play** | [`google-play-store.md`](google-play-store.md) | Per-release runbook. Every tag already reached open testing; production is [`promote-play.yml`](../.github/workflows/promote-play.yml). One-time service-account setup is [`play-ci-setup.md`](play-ci-setup.md) — not the 2026-07 research in `plans/store-automation-plan.md`, which predates the live lane. |
| **Ship macOS (direct download)** | [`apple-appstore-and-macos.md`](apple-appstore-and-macos.md) §1 | Fully automated by the tag — no manual runbook; only confirm the notarized zip/DMG landed. |
| **Submit to the Mac App Store or the iOS App Store** | [`apple-appstore-and-macos.md`](apple-appstore-and-macos.md) §2 | Per-release runbook, every machine step a `gh workflow run` — *Add for Review* included, via [`asc-submit-review.yml`](../.github/workflows/asc-submit-review.yml). The one human act left is pressing **release** after approval (`releaseType` is MANUAL). Real IDs and the App Review contact are in the encrypted vault, not here. |
| **Find out where the Apple track stands right now** | [`apple-handoff.md`](apple-handoff.md) | Per-version state (submitted, in review, for sale), the signing-identity ledger [`apple-revoke-cert.yml`](../.github/workflows/apple-revoke-cert.yml) reads before revoking anything, and the traps already paid for. |
| **Check listing copy, pricing policy, pre-submission audit** | [`../docs/store/README.md`](../docs/store/README.md) | Owns the store-fee policy and the H-17 truth-audit checklist for every platform. |
| **Build the Android rclone engine locally** | [`android/build-rclone.ps1`](android/build-rclone.ps1) | Cross-compiles per ABI into `app/android/app/src/main/jniLibs/<abi>/librclone.so`. CI equivalent: the `android` job. |
| **Build librclone (in-process engine) locally** | [`desktop/build-librclone.ps1`](desktop/build-librclone.ps1) · [`desktop/build-librclone.sh`](desktop/build-librclone.sh) | Verify with [`.github/workflows/librclone.yml`](../.github/workflows/librclone.yml) before depending on it in a release. |
| **Regenerate Play screenshots** | [`store/gen_store_shots.py`](store/gen_store_shots.py) + [`plans/play-screenshots-plan.md`](plans/play-screenshots-plan.md) | Composes raw `adb screencap` PNGs onto Play-legal canvases; `--check` verifies without rewriting. Uploading them is [`play-images.yml`](../.github/workflows/play-images.yml) — no Console file dialog. |
| **Check the backlog / pick up parked work** | [`backlog/backlog-index.md`](backlog/backlog-index.md) → [`backlog/feature-backlog.md`](backlog/feature-backlog.md) | Index is the queue; feature-backlog is the prioritised MoSCoW roadmap with `[D]`/`[M]` platform tags. |
| **Find reliability / hardening work** | [`backlog/hardening-audit-2026-07-15.md`](backlog/hardening-audit-2026-07-15.md) | 18 evidence-linked candidates. Reproduce before implementing — its line numbers have moved. |
| **Start multi-step work** | [`plans/template-plan.md`](plans/template-plan.md), write into [`plans/`](plans/) | Required by rule 6 of [`AGENT.md`](../AGENT.md). |
| **Close out a task** | [`logs/agent-changelog.md`](logs/agent-changelog.md) + [`archive-plans/README.md`](archive-plans/README.md) | The Wrap-Up Protocol in [`AGENT.md`](../AGENT.md): log the entry, sync `wiki/`, move the finished plan. |

---

## 📂 Directory map

| Path | What lives there |
| :--- | :--- |
| [`microsoft-account-setup.md`](microsoft-account-setup.md) | **Start here for anything Microsoft-identity.** The map: MSA vs work account vs guest, which tenant holds what, Partner Center association and role grants, and the order it must all be created in. Rebuild-from-nothing runbook. |
| [`msstore-ci-setup.md`](msstore-ci-setup.md) | The Store **submission** credential and the manual `submit-msstore.yml` workflow, including why it uses the REST API rather than `msstore publish` (paid products). |
| [`windows-signing-and-store.md`](windows-signing-and-store.md) | Windows code signing (as-built + reproduce) **and** the Microsoft Store per-release runbook, MSIX identity plumbing, and certification post-mortems. The largest process doc in `dev/`. |
| [`google-play-store.md`](google-play-store.md) | Per-release Google Play runbook + a reusable facts table (package name, listing path, CI action, versionCode rule) + gotchas. |
| [`play-ci-setup.md`](play-ci-setup.md) | The Play **credential**, as built: service account in Google Cloud, the grants it needs in Play Console, and `PLAY_SERVICE_ACCOUNT_JSON`. Rebuild-from-nothing runbook — read it to rotate the key, not to cut a release. |
| [`android-tv.md`](android-tv.md) | How the one Android bundle also ships to TV: the four manifest lines (`leanback required="false"` is load-bearing), the two banner sizes, the runtime shell switch, and the Play form-factor opt-in that has no API. |
| [`apple-appstore-and-macos.md`](apple-appstore-and-macos.md) | Two lanes under one roof: macOS direct download (Developer ID, automated by the tag) **and** the Apple App Store — Mac App Store + iOS, **live** since 0.6.8 and driven entirely from CI. Per-version state lives in [`apple-handoff.md`](apple-handoff.md). |
| [`apple-handoff.md`](apple-handoff.md) | Where the Apple track stands right now, plus the signing-identity ledger (which certificate signed which build — [`apple-revoke-cert.yml`](../.github/workflows/apple-revoke-cert.yml) names this file) and the rotation recipe for it. Value-free by design. |
| [`secrets/`](secrets/README.md) | **One developer's real account values** (store publisher identity, signing profiles, release hosting) kept OUT of this public repo. `dev-profile.env` is gitignored; only the schema template and its readme are committed. Clone this repo and it will not exist — copy the template and fill in your own. |
| [`vault/`](vault/README.md) | Encrypted working notes — the **Apple account as-built record** (real IDs, key paths, App Review contact), pricing and unreleased planning. `python tool/vault.py unlock` writes `notes/`, which is gitignored; `vault.enc` is committed on purpose so the notes are versioned and backed up rather than living on one machine. This is the only committed route back to the Apple account setup. |
| [`backlog/`](backlog/backlog-index.md) | The queue: index, the prioritised feature roadmap, the 2026-07-15 hardening audit, a settings/advanced-config UX review, and one explicitly historical beta-quality review. |
| [`plans/`](plans/) | Implementation plans, live and shipped alike. Two house styles coexist: YAML frontmatter (`status:`) and a prose `**Status:**` line — that line is what says whether a plan is live, so check both. |
| [`archive-plans/`](archive-plans/README.md) | Where finished plans are moved during wrap-up. Read its README before moving one: source files and CI messages cite plans by path *and* by section number, so a bare `git mv` (or a renumber) dangles a pointer. |
| [`logs/`](logs/agent-changelog.md) | `agent-changelog.md` (per-task audit entries, newest first — current, and rule 5 of [`AGENT.md`](../AGENT.md) makes it mandatory reading) plus `version-history.md`, a **closed** log of the pre-beta alpha run — see [Read these with care](#-read-these-with-care). |
| [`releases/`](releases/) | One curated, user-facing release-note file per shipped tag. **Not decorative** — CI consumes them (see below). House style: user-benefit prose plus a `## Notes` section stating signing status and known limitations. |
| [`store/`](store/gen_store_shots.py) | `gen_store_shots.py` — the Play screenshot compositor, kept in-repo so the next re-shoot is not archaeology. |
| [`android/`](android/build-rclone.ps1) | `build-rclone.ps1` — local cross-compile of the Android rclone engine. |
| [`desktop/`](desktop/build-librclone.ps1) | `build-librclone.ps1` / `build-librclone.sh` — local builds of `librclone.dll` / `.dylib` / `.so` for the FFI engine. |
| [`ios/`](ios/build-librclone-ios.sh) | `build-librclone-ios.sh` + `librclone_ios.go` — the iOS engine. A static **c-archive** `.xcframework` (iOS has no `c-shared`), built from a trimmed re-export rather than rclone's own `librclone`. Run by `ios-release.yml`, `ios-verify.yml` and `librclone-ios.yml`. |
| [`brand/`](brand/make-tv-banner.py) | `make-tv-banner.py` — generates the two Android TV banners from the master icon: the 320×180 launcher tile shipped in the APK and the 1280×720 `tvBanner` uploaded to Play. Both must carry the app name; neither surface draws a label. |

---

## 🤖 CI workflows

Every workflow in [`.github/workflows/`](../.github/workflows/) is listed below — if you add one, add a
row. They fall into three kinds: **build** (make artifacts), **publish on demand** (reach a store; all
`workflow_dispatch`, never a tag side-effect), and **verify/utility** (prove something, or perform one
rare irreversible act). Most of the store lanes are thin wrappers around a script in
[`tool/`](../tool/), named here so you can read what a run will actually do before you start it. All
secrets/variables are named, **never valued** — this repo is public.

### Build

| Workflow | Trigger | What it does |
| :--- | :--- | :--- |
| [`ci.yml`](../.github/workflows/ci.yml) | push to `main`, every PR, manual, weekly cron (Mondays 06:00 UTC) | `analyze-test`: `dart format --set-exit-if-changed` → `flutter analyze` → `flutter test --coverage` (coverage uploaded as an artifact). `rclone-pin`: **warn-only** drift check comparing `RCLONE_VERSION` in `release.yml` against the pins in `dev/android/build-rclone.ps1` and both `dev/desktop/build-librclone.*`, and against the latest upstream rclone. |
| [`release.yml`](../.github/workflows/release.yml) | push of a `v*` tag; manual runs build artifacts only (no Release) | `release` (creates the GitHub Release first, so platform jobs only upload) → `librclone` matrix → `windows`, `linux`, `macos`, `android` in parallel. `RCLONE_VERSION` is pinned once at workflow level for every engine build. The `android` job also uploads to Play **open testing** and then asks Play whether that exact version code landed (`tool/play_tracks.py --expect`). |
| [`librclone.yml`](../.github/workflows/librclone.yml) | manual, or a push touching the build scripts / FFI sources | Per-OS matrix (windows/macos/ubuntu): build librclone → check the artifact is well-formed → run the **live FFI integration test** against the freshly built lib → upload it. The standalone hard gate for the in-process engine. |
| [`librclone-ios.yml`](../.github/workflows/librclone-ios.yml) | manual only | The iOS engine **alone** — builds the c-archive `.xcframework` from [`dev/ios/`](ios/build-librclone-ios.sh) and checks its four exported symbols. Touches nothing Flutter. `ios-verify.yml` covers the same ground and then links and runs the app, so reach for this one only when the Go build itself is what broke. |

### Publish on demand

Nothing here happens because you tagged. Each is a button, and each says what it cannot do.

| Workflow | Backing script | What it does, and its limits |
| :--- | :--- | :--- |
| [`submit-msstore.yml`](../.github/workflows/submit-msstore.yml) | [`tool/store_submit.py`](../tool/store_submit.py) | Downloads the exact signed `airclone.msix` already attached to a release tag — it never rebuilds — and puts it in front of Microsoft. `mode: dry-run` \| **`stage`** \| `submit`; see the mode table below, and use `stage`. |
| [`promote-play.yml`](../.github/workflows/promote-play.yml) | [`tool/play_promote.py`](../tool/play_promote.py) | Promotes the version code **already in open testing** to production at a chosen rollout percent. A metadata edit on that version code, not a re-upload (Play rejects a version code twice). `dry_run` defaults to **true**. |
| [`play-images.yml`](../.github/workflows/play-images.yml) | [`tool/play_images.py`](../tool/play_images.py) | Uploads listing **images** from `docs/store/play/` — phone, tablet, TV screenshots, TV banner, feature graphic, icon. Cannot change text, attach a build, or publish; Play holds the change as a draft. `replace: true` first, or Play appends and you get duplicates. |
| [`asc-listing.yml`](../.github/workflows/asc-listing.yml) | [`tool/asc_listing.py`](../tool/asc_listing.py) (text) · [`tool/asc_screenshots.py`](../tool/asc_screenshots.py) (screenshots) | Pushes Apple listing copy from `docs/store/apple/listing-en-US.md` (macOS) / `listing-ios-en-US.md` (iOS), or uploads screenshots. Metadata only — cannot attach a build and cannot submit. `replace=true` on screenshots: Apple adds a second asset rather than overwriting by filename. |
| [`asc-version.yml`](../.github/workflows/asc-version.yml) | [`tool/asc_build.py`](../tool/asc_build.py) | Everything between "a build finished uploading" and "submit": `create` the version record, `builds`/`report` (did the upload register? is it `VALID`?), `apply` (attach the build, App Review notes, copyright, MANUAL release type), `audit` (**is it submittable?**). Defaults to a dry run; nothing writes without `apply`. |
| [`asc-submit-review.yml`](../.github/workflows/asc-submit-review.yml) | `asc_build.py` + `asc_listing.py` | The point of no return — optionally re-pushes the listing, audits, then **Add for Review**. Double-entry: `confirm_version` must be typed exactly. It does **not** release: `releaseType` stays MANUAL, so an approved version waits for a human. Export compliance is not asked — it is declared by `ITSAppUsesNonExemptEncryption` in both `Info.plist` files. |
| [`ios-release.yml`](../.github/workflows/ios-release.yml) | [`tool/asc_ios_signing.py`](../tool/asc_ios_signing.py) (`ephemeral` path only) | Builds the iOS App Store archive and uploads it as a TestFlight build; submits nothing. `mode: dry-run` (no secrets) \| `validate` \| `upload`. **`signing` defaults to `secrets`** — the stored distribution identity — and that is the path. `ephemeral` mints a certificate per run against Apple's per-team cap; `automatic` does not work at all. |
| [`mas-release.yml`](../.github/workflows/mas-release.yml) | — | Builds the Mac App Store package and uploads it; submits nothing. Same `dry-run`/`validate`/`upload` shape. Archives **unsigned** and signs at export with the stored `APPLE_MAS_*` identity, which is what stopped it minting a throwaway certificate every run. |

### Verify and utility

| Workflow | Trigger | What it does |
| :--- | :--- | :--- |
| [`ios-verify.yml`](../.github/workflows/ios-verify.yml) | manual, or a push touching the FFI/iOS sources | Builds for the iOS **simulator** with librclone statically linked, runs it, and reads the engine banner off the screen. Distinguishes the three failures a build error hides: the link (Go skips its `cgo_ldflag` directives for c-archive), the strip (Release would delete the Go exports), and `DynamicLibrary.process()` resolving the symbols. Needs no Apple secret. |
| [`mas-verify.yml`](../.github/workflows/mas-verify.yml) | manual, or a push touching the flavour/policy/native sources | Builds the **Mac App Store** flavour and runs it sandboxed on a runner Mac. The sandbox is enforced by the signature plus the entitlement, not by the store, so a denied read fails here exactly as it would for a customer. Also the only compiler this project has for the macOS Swift. Needs no Apple secret. |
| [`ios-screenshots.yml`](../.github/workflows/ios-screenshots.yml) | manual | Captures App Store screenshots on iPhone **and** iPad simulators — both are mandatory, the app ships `TARGETED_DEVICE_FAMILY = "1,2"` — at native resolution, so no cropping. `mode: diagnose` (what devices does this runner have?) \| `capture` \| `record`. Uploading them is `asc-listing.yml`. |
| [`mas-screenshots.yml`](../.github/workflows/mas-screenshots.yml) | manual | Captures Mac screenshots of the **sandboxed** build. Apple accepts only four exact sizes, hence `mode: diagnose` before `capture`. Demo data is seeded inside the app's own container, because a sandboxed app cannot be handed a folder without someone clicking through `NSOpenPanel`. |
| [`apple-revoke-cert.yml`](../.github/workflows/apple-revoke-cert.yml) | manual ([`tool/asc_ios_signing.py`](../tool/asc_ios_signing.py)) | ⛔ **Irreversible.** Revokes ONE Apple certificate by id and nothing else — its own workflow so it never sits one wrong dropdown away from a build. Double-entry confirmation. **Never revoke the certificate under a build that is submitted but not yet live**: the first iOS submission came back INVALID BINARY minutes after *Add for Review* for exactly that. Which id signed what is tracked in [`apple-handoff.md`](apple-handoff.md). |

**Release-notes coupling — two different files.** The `release` job uses `dev/releases/$GITHUB_REF_NAME.md`
as `--notes-file` when it exists and emits a `::warning::` + falls back to `--generate-notes` when it
does not. Tags containing `alpha`, `beta`, or `rc` are marked pre-release. If the Release already exists
the job leaves it alone. The store **"what's new"** is *not* that file: it is
[`docs/store/store-release-notes.txt`](../docs/store/store-release-notes.txt), one generic line plus a
link to the releases page, identical every release, copied verbatim to
`distribution/whatsnew/whatsnew-en-US` for Play and read by `tool/asc_listing.py` as Apple's `whatsNew`.
It must stay under **500 bytes** — Play truncates silently past that, so `release.yml` fails loudly
instead. Per-tag distillation was removed on purpose: it shipped a mid-sentence fragment of notes
written for a different audience to every store user. Microsoft is the exception — `tool/store_submit.py`
clones the previous submission's field, so Microsoft's "what's new" is edited by hand in Partner Center.

**Gating — one list per workflow**, because they do not share a set:

| Lane | Secrets | Variables |
| :--- | :--- | :--- |
| `release.yml` | `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`; `APPLE_DEVELOPER_ID_APPLICATION_P12_BASE64`, `APPLE_DEVELOPER_ID_APPLICATION_P12_PASSWORD`, `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID`; `AIRCLONE_KEYSTORE_BASE64`, `AIRCLONE_KEYSTORE_PASSWORD`, `AIRCLONE_KEY_ALIAS`, `AIRCLONE_KEY_PASSWORD`; `PLAY_SERVICE_ACCOUNT_JSON` | `WINDOWS_SIGNING_ENABLED`, `AZURE_SIGNING_ENDPOINT`, `AZURE_SIGNING_ACCOUNT`, `AZURE_SIGNING_PROFILE`, `MSIX_IDENTITY_NAME`, `MSIX_PUBLISHER`, `MSIX_DISPLAY_NAME` |
| `submit-msstore.yml` | `STORE_TENANT_ID`, `STORE_CLIENT_ID`, `STORE_CLIENT_SECRET` | `STORE_APP_ID`, `MSIX_IDENTITY_NAME`, `MSIX_PUBLISHER` |
| Play (`play-images.yml`, `promote-play.yml`) | `PLAY_SERVICE_ACCOUNT_JSON` | — |
| Apple, every lane that talks to App Store Connect | `APPSTORE_ISSUER_ID` (a secret, not a variable — a variable is not masked, and this one appeared verbatim in a public log once), `APPSTORE_API_PRIVATE_KEY` (the `.p8` contents); plus `APPLE_REVIEW_CONTACT` on `asc-version.yml` and `asc-submit-review.yml` | `APPSTORE_API_KEY_ID` |
| Apple build + upload, on top of that | `APPLE_TEAM_ID`; iOS: `APPLE_IOS_DIST_P12_BASE64`, `APPLE_IOS_P12_PASSWORD`, `APPLE_IOS_PROVISIONING_PROFILE_BASE64`. macOS: `APPLE_MAS_APP_P12_BASE64`, `APPLE_MAS_INSTALLER_P12_BASE64`, `APPLE_MAS_P12_PASSWORD`, `APPLE_MAS_PROVISIONING_PROFILE_BASE64` | `APPLE_IOS_PROFILE_NAME` |

Two names that look live and are not: `STORE_PUBLISH_ENABLED` is retired (Store submission is the manual
`submit-msstore.yml`, not a tag side-effect), and `STORE_SELLER_ID` is consumed by **no** workflow or
script — the REST API takes no seller id. Keep the name recorded: it is Partner Center *account* setup,
documented in [`microsoft-account-setup.md`](microsoft-account-setup.md) and
[`msstore-ci-setup.md`](msstore-ci-setup.md).

**What fails hard vs. what degrades quietly** — worth knowing before you trust a job's colour:

| Behaviour | Where |
| :--- | :--- |
| **Hard fail** — tagged build with no Android keystore secret (refuses to publish a debug-signed APK) | `android` job |
| **Hard fail** — tagged build with no Apple signing-cert secret (never ships an unsigned "release") | `macos` job |
| **Hard fail** — the app-local MSVC runtime (`msvcp140.dll`, `vcruntime140*.dll`) is missing from the Release dir | `windows` job |
| **Hard fail** — rclone not bundled / checksum mismatch (was `continue-on-error` until v0.5.3; see below) | `windows` job |
| **Degrades** — `librclone` artifact download is `continue-on-error` → that platform ships **binary-engine-only**, with only a `::warning::` | `windows`, `linux`, `macos` jobs |
| **Degrades** — MSIX build and MSIX upload are `continue-on-error`; a missing `MSIX_*` variable only warns and still produces a package carrying pubspec **placeholder** identity. (Store *submission* is no longer part of a tagged build at all — it is the manual [`submit-msstore.yml`](../.github/workflows/submit-msstore.yml).) | `windows` job |
| **Degrades** — notarization is best-effort and bounded ([`.github/scripts/notarize.sh`](../.github/scripts/notarize.sh)); the signed zip is uploaded **before** notarizing so an Apple outage cannot block a release | `macos` job |

---

## 🚦 What a tag does by itself, and what needs a button

Publishing is deliberately split: things that are cheap to redo happen automatically, things that
cost days or reach every user need a human. Pushing `vX.Y.Z` does **everything in the first table**
with no further action.

| Automatic on a tag | Where |
| :--- | :--- |
| Build + code-sign Windows (signed installer, bundled rclone), macOS (Developer ID + notarized), Linux, Android (release-signed) | [`release.yml`](../.github/workflows/release.yml) |
| Create the GitHub Release from `dev/releases/vX.Y.Z.md` and attach every artifact | `release` job |
| Publish Android to Play **open testing**, then **ask Play whether that exact version code is really there** | `android` job |
| Build the MSIX with injected Store identity and attach it to the release | `windows` job |

| Needs a human to press it | How | Why not automatic |
| :--- | :--- | :--- |
| **Play → production** | Actions → *Promote on Google Play* (default 10% staged) | reaches every user; staged rollout is a judgement call |
| **Microsoft Store submission** | Actions → *Submit to Microsoft Store* | certification takes **days** and a bad submission burns a cycle |
| **Apple: build → App Store Connect** | Actions → *Mac App Store (build + upload)* / *iOS App Store (build + upload)*, `mode: upload` | a tag would upload a build nobody chose to submit, and each one consumes a build number |
| **Apple: Add for Review** | Actions → *Submit to App Review (Apple)*, `mode: submit` | the point of no return — changing a version in review means withdrawing it |
| **Apple: release an approved version** | App Store Connect, by hand | `releaseType` is MANUAL on purpose: approval and publication being the same event is how a version ships before anyone looks at it |

Note the shape of the Apple lanes: every step *is* a workflow, but none is a tag side-effect, and none
of the three Apple rows above will do the next one for you.

**The Microsoft Store workflow has three modes. Use `stage`.**

| Mode | Does |
| :--- | :--- |
| `dry-run` | authenticates, reports pricing and pending state, changes nothing |
| **`stage`** | **the supported route** — uploads the package and leaves an editable draft; a human then presses *Submit for certification* in Partner Center |
| `submit` | ⛔ **refused for this product.** API commit publishes the app at **$0** — it did, on 2026-08-17. See AGENT.md rule 10 |

Set `delete_pending: true` to **supersede** a submission still in certification — but note that only
works up to `PendingCommit`; once Microsoft has it in `Certification`, Partner Center's *Cancel
certification* button is the only lever, and once it reaches *Publishing* nothing can stop it.

Details: [`play-ci-setup.md`](play-ci-setup.md) · [`msstore-ci-setup.md`](msstore-ci-setup.md) ·
[`microsoft-account-setup.md`](microsoft-account-setup.md) ·
[`apple-appstore-and-macos.md`](apple-appstore-and-macos.md) · [`apple-handoff.md`](apple-handoff.md).

---

## ✅ Release checklist

Distilled from the store runbooks — Microsoft, Play, Apple — and the release history since v0.5.x.

1. **Bump the version** in [`app/pubspec.yaml`](../app/pubspec.yaml) (`version: X.Y.Z+N`). The build
   number `+N` is the Play **versionCode** and must strictly increase — the single most common upload
   failure.
2. **Write `dev/releases/vX.Y.Z.md` before tagging.** No file costs you the curated GitHub Release
   notes and nothing else — the stores do not read it. Follow the house style: user-benefit prose, then
   a `## Notes` section naming signing status and known limitations. While you are here, *check* (do
   not rewrite) [`docs/store/store-release-notes.txt`](../docs/store/store-release-notes.txt) — the
   generic line every store shows, under 500 bytes or `release.yml` fails the run.
3. **Green the local gates first:** `dart format --output=none --set-exit-if-changed .`,
   `flutter analyze` (CI fails on **any** info-level lint), `flutter test`. Run `dart format` with the
   SDK version CI pins — 3.47.0, the native SDK on the dev machine. The Docker image floats `stable`
   and lags that pin (see the note above its `image:` line in
   [`docker-compose.yml`](../docker-compose.yml)); an older formatter reformats files the gate then
   rejects, which is exactly how the v0.6.3 release broke. Analyze and test from Docker are fine.
4. **Tag `vX.Y.Z` and push.** An `alpha`/`beta`/`rc` in the tag marks the *GitHub Release* pre-release —
   and nothing more. There is no pre-release gate on Play: a `-rc` tag still publishes to public **open
   testing** like any other. If that is not what you want, do not push the tag.
5. **Verify the artifacts — see the rule below.** Do not move on because the run is green.
6. **Store lanes.** Play open testing already happened (see the table above). For the rest, start with
   the pre-submission truth audit in [`../docs/store/README.md`](../docs/store/README.md), then:
   - **Microsoft** — Actions → *Submit to Microsoft Store* with `mode: stage`, the only supported mode
     (`submit` is refused by [`tool/store_submit.py`](../tool/store_submit.py) because an API commit
     publishes this app at **$0**, which it did on 2026-08-17). Then press *Submit for certification*
     in Partner Center yourself. ([`msstore-ci-setup.md`](msstore-ci-setup.md))
   - **Apple (Mac App Store + iOS)** — the ordered runbook is
     [`apple-appstore-and-macos.md`](apple-appstore-and-macos.md) §2, one `gh workflow run` per step:
     `asc-version.yml -f mode=create` if the version record does not exist yet → `asc-listing.yml`
     (`what=text`, then `what=screenshots` per device) → `mas-release.yml -f mode=upload` and
     `ios-release.yml -f mode=upload -f signing=secrets` (the stored identity; **never**
     `signing=ephemeral`, which mints a certificate per run against Apple's per-team cap) →
     `asc-version.yml -f mode=builds` until a `VALID` build of the right platform appears
     (`mode=builds`, not `mode=report` — it reaches the build list without an editable
     version, which is exactly the window right after an upload) →
     `-f mode=apply` → `-f mode=audit` until it prints *No gaps* → `asc-submit-review.yml -f mode=submit
     -f confirm_version=X.Y.Z`. Run each platform separately. Approval does not publish: `releaseType`
     is MANUAL, so a human presses release. Apple's `whatsNew` is required on every update and is
     **per-version** — it starts empty each release and never carries forward, which is what got both
     0.7.5 submissions refused minutes after an audit printed *No gaps*. `asc-submit-review.yml`'s
     listing refresh is what fills it, and the audit checks it now. Current state:
     [`apple-handoff.md`](apple-handoff.md).
   - **Play production** when you want it — Actions → *Promote on Google Play*, at the rollout percent
     you want; `dry_run` defaults to true, and re-running with a larger percent widens the rollout
     ([`google-play-store.md`](google-play-store.md)).
   - **macOS direct download** needs nothing — it is [fully automated](apple-appstore-and-macos.md) by
     the tag; just confirm the notarized zip/DMG landed.
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

## ⚠️ Read these with care

Two files in `dev/` mislead a skim. Anything else found to be out of date belongs here — and comes
straight back out once it is repaired, because a staleness list naming files somebody already fixed
teaches the next reader to skip the section.

- [`logs/version-history.md`](logs/version-history.md) is a **closed** log of the pre-beta alpha run,
  v0.0.0 → `v0.1.0-beta.1`, and nothing after it. The record since is [`releases/`](releases/) plus
  `git tag`; a new release is written there, never appended here. Its `Level` column is a leftover from
  a three-part numbering idea this repo never used — every Airclone tag is plain semver.
- [`archive-plans/`](archive-plans/README.md) lags what has shipped, because plans are moved there
  during wrap-up rather than when the code lands. A near-empty archive is therefore not evidence that
  nothing has shipped: read the plan's own status line, not the directory it sits in.

Per-store *status* is deliberately not kept here or in [`../docs/store/README.md`](../docs/store/README.md)
— two hubs both claiming it is how the Apple rows there fell two platforms behind. Each store's runbook
owns its own state, and [`apple-handoff.md`](apple-handoff.md) owns Apple's.

---

## 🔒 Public-repo rule

This repository is **public**. Never commit GUIDs of any kind (Partner Center publisher/tenant/seller/
app ids, Azure subscription ids), D-U-N-S numbers, physical addresses, personal email addresses, or
infrastructure hostnames. Use `<placeholder>` tokens in these docs and say where the real value lives —
e.g. "in repo variable `MSIX_PUBLISHER`", "in [`vault/`](vault/README.md)", "in `dev/secrets/`". Signing
secrets live only in GitHub Secrets, which are write-only and cannot be read back; account as-built
records live in the encrypted vault, which is committed as ciphertext and never as plaintext.

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
