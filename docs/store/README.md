# 🏪 Store submissions — index

The router for all three app-store channels: the pricing policy every listing obeys, where each
store's runbook, listing copy and assets live, what each store has already rejected us for, and the
audit to run before pressing submit. It does **not** track what is live or in review — see the note
under the table.

**When to read this:** you are about to submit (or resubmit) Airclone to the Microsoft Store,
Google Play or the Apple App Store, you are triaging a certification/upload failure, or you are
editing store listing copy or screenshots.

Airclone is distributed **free** via [GitHub Releases](https://github.com/GigaionLLC/Airclone/releases)
and self-build. The stores are an optional *convenience* channel.

## 💵 Pricing policy — the one rule every platform shares

Each store listing carries a **small fee** that funds only code-signing certificates and
developer-program memberships — *"the fee buys convenience, never features."* The store build and
the free build are the same application; there is no paid tier and no feature gate.

Consequence for copy: **store listing copy must NOT claim the app is free or that nothing is behind
a paywall.** Only the required license-terms field states AGPLv3. Direct-download and self-build
stay free, and that is where "free" may be said.

This is also the reason the Microsoft Store product is an **MSIX** and not an unpackaged EXE — only
a *packaged* product has Store commerce, so the Store collects the fee and **no payment code ever
enters this open-source app**.

Because the fee is the entire point of the store channel, **the Microsoft submission is stage-only**:
run [`submit-msstore.yml`](../../.github/workflows/submit-msstore.yml) with `mode: stage`, then press
**Submit for certification** in Partner Center, which re-derives pricing from the pricing module.
**Never `mode: submit` / `--commit`.** Committing through the Store REST API applies the submission's
own pricing block, and for a product on the advanced pricing model every payload that API will accept
reads back as *Free* — which is how v0.6.8 published at **$0** against a live $1.49 on 2026-08-17, and
once a submission reaches *Publishing* it cannot be stopped by anyone. [`tool/store_submit.py`](../../tool/store_submit.py)
now refuses `--commit` for a product on that pricing model; **do not remove that guard to unblock a
release.** Full account: [`AGENT.md`](../../AGENT.md) rule 10 and
[`dev/msstore-ci-setup.md`](../../dev/msstore-ci-setup.md) §0.

## 🧭 Platforms at a glance

| Platform | Runbook + state doc | Listing copy | Assets |
| :--- | :--- | :--- | :--- |
| **Microsoft Store** | Per-release: [`dev/windows-signing-and-store.md`](../../dev/windows-signing-and-store.md) §2. Submission: Actions → *Submit to Microsoft Store* ([`submit-msstore.yml`](../../.github/workflows/submit-msstore.yml)). Credential + as-built: [`dev/msstore-ci-setup.md`](../../dev/msstore-ci-setup.md) | [`windows/listing-en-US.md`](windows/listing-en-US.md) | [`windows/`](windows/) |
| **Google Play** | Per-release: [`dev/google-play-store.md`](../../dev/google-play-store.md). Production promote: Actions → *Promote on Google Play* ([`promote-play.yml`](../../.github/workflows/promote-play.yml)). One-time service account: [`dev/play-ci-setup.md`](../../dev/play-ci-setup.md) | [`play/listing-en-US.md`](play/listing-en-US.md) | [`play/store-ready/`](play/store-ready/) (+ [`MANIFEST.md`](play/store-ready/MANIFEST.md)), [`play/tv/`](play/tv/) |
| **Mac App Store** | Per-release: [`dev/apple-appstore-and-macos.md`](../../dev/apple-appstore-and-macos.md) §2. As-built account state: [`dev/apple-handoff.md`](../../dev/apple-handoff.md). One-time account + ASC + signing setup: [`dev/plans/apple-appstore-plan.md`](../../dev/plans/apple-appstore-plan.md) | [`apple/listing-en-US.md`](apple/listing-en-US.md) | [`apple/mac/store-ready/`](apple/mac/store-ready/) (+ [`MANIFEST.md`](apple/mac/store-ready/MANIFEST.md)) |
| **iOS App Store** | The same three documents as the Mac App Store — one Apple account, one submission workflow, two platforms | [`apple/listing-ios-en-US.md`](apple/listing-ios-en-US.md) | [`apple/ios/iphone/`](apple/ios/iphone/), [`apple/ios/ipad/`](apple/ios/ipad/) (+ [`MANIFEST.md`](apple/ios/MANIFEST.md)) |
| **macOS direct download** | **Not a store.** Developer-ID signed + notarized zip/DMG on GitHub Releases, fully automated by the tag: [`dev/apple-appstore-and-macos.md`](../../dev/apple-appstore-and-macos.md) §1 | — | — |

**This table deliberately does not say where each store *stands*.** Two hubs both claiming per-store
status is exactly how the Apple rows here sat at "BLOCKED, do not start a submission lane" while
0.6.8 was for sale on both Apple platforms. Live state lives with the machinery that produces it:
each store's own runbook ([`dev/windows-signing-and-store.md`](../../dev/windows-signing-and-store.md),
[`dev/google-play-store.md`](../../dev/google-play-store.md)),
[`dev/apple-handoff.md`](../../dev/apple-handoff.md) for the Apple account,
[`dev/releases/`](../../dev/releases/) plus `git tag` for what has actually shipped, and a `dry-run` of
[`submit-msstore.yml`](../../.github/workflows/submit-msstore.yml) or
[`asc-submit-review.yml`](../../.github/workflows/asc-submit-review.yml) to ask the store itself.
[`dev/README.md`](../../dev/README.md) is the *process* hub and declines per-store status for the same
reason this table does.

**Windows code signing** (Azure Artifact Signing, subject `Gigaion, LLC`) is **LIVE since v0.5.1** and
runs on every tagged release — the signing half of
[`dev/windows-signing-and-store.md`](../../dev/windows-signing-and-store.md).

**Apple signing** is a **stored** identity, not one minted per run. The iOS App Store lane
([`ios-release.yml`](../../.github/workflows/ios-release.yml), default `signing: secrets`) reads a
distribution certificate and provisioning profile from the org secrets `APPLE_IOS_DIST_P12_BASE64`,
`APPLE_IOS_P12_PASSWORD` and `APPLE_IOS_PROVISIONING_PROFILE_BASE64`; **both expire 2027-09-05**, which
is worth a diary entry because expiry breaks the lane with an error that looks like nothing changed.
Both Apple lanes archive **unsigned** (`CODE_SIGNING_ALLOWED=NO`) and apply the distribution identity
at export, so the archive's signature never matters — everywhere except `ios-release.yml`'s
`signing=automatic`, an experiment kept only because Apple's error strings for it are worth having
written down. Nothing ships that way. Since v0.7.6 the flag that authorises Xcode to *create* signing
assets on the fly, `-allowProvisioningUpdates`, reaches that experiment and nothing else: in
`ios-release.yml` it is now passed at neither the archive nor the export step unless
`signing=automatic`, and `mas-release.yml` passes it nowhere at all. It used to go to every iOS run
including the default, which is how unused certificates piled up against Apple's per-team cap —
`signing=secrets` signs manually from an identity already in the keychain and a profile already on
disk, and needs the flag for nothing. Surplus certificates are revoked one at a time by
[`apple-revoke-cert.yml`](../../.github/workflows/apple-revoke-cert.yml) — **never while the build they
signed is submitted but not yet live**, which produces an INVALID BINARY. Which certificate signed which build is tracked in
[`dev/apple-handoff.md`](../../dev/apple-handoff.md), in the clear — a certificate id is not a
secret (it appears in the workflow's own input description, and the certificate itself is public).
The *private key* is what must never be here, and it is not: it lives in the org secrets and one
offline backup.

One-time Apple account, App Store Connect and signing setup, from nothing:
[`dev/plans/apple-appstore-plan.md`](../../dev/plans/apple-appstore-plan.md). The original 2026-07-09
per-store automation research is
[`dev/plans/store-automation-plan.md`](../../dev/plans/store-automation-plan.md) — superseded, and it
says how the lanes were designed rather than what they do now.

---

## 🪟 Microsoft Store

**Path decision (2026-08-08): the product is an MSIX package again**, reversing the 2026-07-23
decision to ship an unpackaged Win32 EXE. Submissions target the packaged reservation
**"Airclone: Cloud File Manager"** (identity name `GigaionLLC.AircloneCloudFileManager`). The
superseded EXE decision is kept in a `<details>` block in the runbook for context.

Navigating the runbook during the transition: §2's A–F steps are still written for the EXE path.
Under MSIX, **step B** (self-hosted versioned, non-redirecting installer URL) and **step C**
(Package details / installer parameters / Inno exit-code map) no longer apply — the package is
uploaded to Partner Center instead (§§2b–2g). Steps **D** (listing), **D2** (tester notes),
**D3** (restricted-capability justification — MSIX only), **E** and **F** still apply, as does step
A's rule: **verify by artifact, not by the green check.**

The `--store` MSIX is built **unsigned by design** — Partner Center signs it — so the Azure signing
pass covers `airclone.exe`, `rclone.exe` and the Inno installer, not the MSIX.

### MSIX package identity — CI-injected, never committed

`Package/Identity/Publisher` is a Partner-Center-assigned **GUID** and this repo is **public**, so
identity is injected at build time by [`release.yml`](../../.github/workflows/release.yml) from
**repo variables**, while `app/pubspec.yaml` keeps inert `PLACEHOLDER.*` values. **Never write the
real values into any file in this repo.**

| Manifest field | Source | Committed? |
| :--- | :--- | :--- |
| `Package/Identity/Name` | repo variable **`MSIX_IDENTITY_NAME`** → `--identity-name` | no |
| `Package/Identity/Publisher` (`CN=<GUID>`) | repo variable **`MSIX_PUBLISHER`** → `--publisher` | **no — this is the GUID** |
| `Package/Properties/DisplayName` | repo variable **`MSIX_DISPLAY_NAME`** → `--display-name` (must be a **reserved** app name; also becomes the Start-menu tile) | no |
| `Package/Properties/PublisherDisplayName` | `msix_config.publisher_display_name` in `app/pubspec.yaml` = `Gigaion, LLC` | yes — a company name, not a GUID |

Two things that cost a release each:

- **All four are validated on upload and the FIRST failure masks the rest.** Fix them as a set,
  not one round-trip per field.
- **A missing variable is not fatal to the build.** CI emits a `::warning::` and still produces a
  package — one Partner Center will reject. That silence is exactly how v0.6.0 shipped with
  placeholder identity.

### How a submission actually leaves this repo

Submission is a **manual Actions dispatch**, not something a tag does: *Submit to Microsoft Store*
([`submit-msstore.yml`](../../.github/workflows/submit-msstore.yml)) run against a release tag, with
`mode` = `dry-run` / `stage` / `submit`. It does **not** rebuild — it downloads the exact
`airclone.msix` attached to that release (unsigned by design, as above - the executables inside it are Azure-signed), checks the package identity against the
repo variables before Partner Center can spend a review cycle on a mismatch, and then drives the Store
submission REST API through [`tool/store_submit.py`](../../tool/store_submit.py). Manual is deliberate,
for the same reason `promote-play.yml` is: certification takes **days**, and deciding a build is worth
a review cycle is a human call.

`mode: stage` is the only route we use — see the pricing policy above for why `submit` is forbidden.
`dry-run` creates nothing and is the cheapest way to read the product's real state, including what is
pending and what the live pricing is.

It does **not** use `msstore publish`. The Microsoft Store Developer CLI refuses to update a **paid**
product ("App updates are supported only for Free products"), which no amount of credential work
changes, and making the app free would defund the certificates the fee pays for. The old
`STORE_PUBLISH_ENABLED` master switch is **retired** — with submission behind a manual dispatch there
is nothing to gate, so do not go looking for it. Credential setup, the Entra registration and the
Partner Center role: [`dev/msstore-ci-setup.md`](../../dev/msstore-ci-setup.md).

### Rejection and incident history — Microsoft Store

| When | What was rejected / failed | Root cause | Fixed by |
| :--- | :--- | :--- | :--- |
| 2026-07-23 | Package URL refused ("the package URL redirects to another URL"; "does not contain, Win32 Package" while the asset 404s) | GitHub release URLs 302-redirect to a temporary signed host | Self-host a **direct, versioned, non-redirecting** URL (EXE path only) |
| 2026-07-23 | Downloader-stub installer rejected (policy 10.2.x) | rclone bundling had **silently never worked** — a `continue-on-error` SHA256SUMS parse bug | v0.5.3: file-based parse, step made **fatal** |
| 2026-07-23 | Silent-install / Add-Remove-Programs validation could not see the app | Per-user install writes ARP under HKCU | v0.5.4: `PrivilegesRequiredOverridesAllowed` + `DefaultDirName={autopf}`; the Store passes `/ALLUSERS` |
| 2026-07-23 | Publisher mismatch | `AppPublisher` must equal the Store publisher / cert subject | Set to `Gigaion, LLC` |
| **2026-07-29 (v0.5.4) — certification FAILED** | **10.2.4.1** undisclosed dependency on **VC++** | Flutter's Windows build links the dynamic MSVC runtime, which is not part of Windows; we shipped neither the DLLs nor a disclosure | v0.5.5: bundle the runtime **app-local** (CI hard-fails without it) + disclose in the **first two lines** of the Description |
| " | **10.1.2.10** "Unusable Feature: Create a local remote" | **Self-inflicted:** our own tester notes told the reviewer to run `config create local local` in the command console, which the console **blocks by design** | v0.5.5: rewrote the notes to the real two-click UI path, and [`blockedMessage()`](../../app/lib/src/state/console/rclone_commands.dart#L205) now names the in-app alternative for every blocked verb |
| " | **10.2.7** Product Removal — files left in `C:\Program Files\Airclone` | An orphaned `rcd` held a handle on the copy inside the install dir; and anything running from `{app}` at uninstall locks its own file | v0.5.5: quit the engine on window close + kill-on-close Job Object. v0.5.7: `InitializeUninstall` terminates processes under `{app}` — filtered `-notlike 'unins*'`, or the uninstaller returns -1 |
| **2026-08-08 (v0.6.0 MSIX) — rejected 4×** | Every rejection was package identity | The 2026-07-12 placeholders were never replaced; Partner Center reported only the `PublisherDisplayName` mismatch first, masking the other three | v0.6.1: identity injected by CI from repo variables + a loud warning when unset (see [`dev/releases/v0.6.1.md`](../../dev/releases/v0.6.1.md)) |
| **2026-08-10 (v0.6.0/v0.6.1) — certification FAILED** | **10.2.5** Installing and Updating Store Apps — "The product updates outside the Store." Cited **Settings → Check for updates → "Open release"**, which opened the GitHub releases page | One binary ships through every channel, so nothing at compile time told the MSIX apart from the Inno installer; the update check was unconditional | v0.6.2: [`install_source.dart`](../../app/lib/src/state/install_source.dart) resolves the channel at runtime and a store build makes **no GitHub request at all**, offering only the Store. `UpdateStatus` is **sealed** so no build can fall through to a download link (see [`10-external-integrations.md §5.1`](../../wiki/core/10-external-integrations.md)) |
| **2026-08-17 (v0.6.8) — published FREE** | Not a rejection — a **self-inflicted** one. The $1.49 listing published at **$0** and stayed free for the entire certification cycle of the fix | The submission was **committed through the REST API**. `commit` applies the submission's own pricing block, and for a product on the advanced pricing model every payload that API will accept reads back as *Free*; once a submission reaches *Publishing* it cannot be stopped by anyone, by any means | Stage-only forever — `mode: stage`, then Submit in Partner Center, which re-derives pricing from the pricing module — plus a refusal in [`tool/store_submit.py`](../../tool/store_submit.py) for any product on that pricing model. Full account: [`AGENT.md`](../../AGENT.md) rule 10 and [`dev/msstore-ci-setup.md`](../../dev/msstore-ci-setup.md) §0 |

Two process rules that came out of the 2026-07-29 report and belong in every future round:

- On a failed certification, **expand every collapsed row** and download **Supporting files → ZIP**
  before starting work. The collapsed summary carries no actionable detail — 10.1.2.10 looked like a
  symptom of the VC++ finding and was unrelated.
- **Walk the tester notes yourself, in the shipping build, before submitting.** Every step in that
  field is a promise about behaviour, and one stale instruction failed the whole submission.

---

## 🤖 Google Play

Package `com.gigaionllc.airclone`. Every `v*` tag uploads the AAB to **open testing** automatically
(`release.yml`, `tracks: beta` — Play's API name for Open testing), carrying the release notes from
`store-release-notes.txt`, and then asks Play whether the version code actually arrived: the *Verify
the build really landed in open testing* step fails the release if it did not, because a Play upload
can report success and land nothing.

**CI never touches production**, and that is the deliberate boundary rather than a missing credential:
promotion is the separate manual [`promote-play.yml`](../../.github/workflows/promote-play.yml) —
a rollout percent you pick (default **10%** staged, `dry_run` on by default), widened by re-running at
a larger percent; narrowing a live rollout is refused unless you override it. Note
what this boundary does *not* include — there is no pre-release gate, so an `-rc` tag reaches public
open testing exactly like any other.

| What | Where |
| :--- | :--- |
| Per-release runbook | [`dev/google-play-store.md`](../../dev/google-play-store.md) |
| Listing copy + screenshot checklist | [`play/listing-en-US.md`](play/listing-en-US.md) — **text is pasted into the Console by hand**; nothing in this repo pushes it |
| Upload the listing images | Actions → **Play Store listing images** ([`play-images.yml`](../../.github/workflows/play-images.yml)) — images only, `replace: true`, report before apply |
| "What's new" copy (≤500 **bytes**/locale) | [`store-release-notes.md`](store-release-notes.md) — one generic line every release, copied from `store-release-notes.txt` into `distribution/whatsnew/whatsnew-en-US` by the release job; the detail lives on the GitHub release |
| Android TV assets | [`play/tv/MANIFEST.md`](play/tv/MANIFEST.md) — screenshots and banner, and the two traps that produced a wrong set first |
| Upload-ready assets + slot map | [`play/store-ready/MANIFEST.md`](play/store-ready/MANIFEST.md) |
| Demo-media licences | [`play/DEMO-MEDIA-PROVENANCE.md`](play/DEMO-MEDIA-PROVENANCE.md) |
| One-time service-account setup | **[`dev/play-ci-setup.md`](../../dev/play-ci-setup.md)** — the as-built runbook (every command, every gotcha), for a new Google account or a rotated key. Original research: [`dev/plans/store-automation-plan.md`](../../dev/plans/store-automation-plan.md) § Google Play |
| Promote a build to production | Actions → **Promote on Google Play** → Run workflow ([`promote-play.yml`](../../.github/workflows/promote-play.yml), [`tool/play_promote.py`](../../tool/play_promote.py)) — no Console login |

### Rejection & review history — Google Play

| When | Finding | Root cause | Fixed by |
| :--- | :--- | :--- | :--- |
| (listing review) | Screenshots read as **"placeholder images or stock photos"** — the thumbnail shot had to be pulled from the listing | The demo remote's photos were synthetic gradient tiles named `IMG_0100.jpg … IMG_0105.jpg` | 2026-08-07: restocked the demo remote with **real CC0 photographs** (provenance file above); the gallery shot ships again on phone and **both** tablet sizes as `03-gallery.png`, and the set grew to 8 phone / 6 per tablet |
| (user review) | *"the preview function for video files stored in the cloud often doesn't work"* | Not one bug — a class of **invisible** preview failures (a failed video rendered as a black rectangle indistinguishable from a slow load) | v0.6.0: failure/loading states, **Try again**, **Open in another app**, and single-flight video thumbnails on mobile |
| (self-caught, pre-submission) | Listing claimed a **"Show in Files"** integration | No DocumentsProvider, no SAF, no such toggle — SAF is a parked backlog item. Exactly the class of claim that earns an "Unusable Feature" finding | Replaced with the capability that *is* real (hand a file to another app / share sheet). This is the truth audit below working as intended |
| (recurring risk) | Upload refused | **versionCode ≤ a previously uploaded one** — the single most common Play upload failure | Bump the pubspec build number (`version: X.Y.Z+N`) every release |

Two standing constraints, both deliberate rather than open TODOs:

- **No "video playing" screenshot.** The Android emulator cannot render video (`eglCreateContext`
  fails) and no physical device was available, so capturing the loading/error state and presenting
  it as the feature would misrepresent the app. Same reason the release notes carry a
  known-limitation line about Android video playback being unverified.
- **Demo remotes are named for what their backing type makes plausible** (Home-NAS, Studio-Drive,
  Archive-Backups) — a remote named after a real provider whose subtitle read `webdav` had the same
  credibility smell as the placeholder images.

---

## 🍎 Apple

**Both Apple platforms are LIVE** — the Mac App Store and the iOS App Store each carry a shipped
version. Which version, and whether anything is in review, is deliberately *not* recorded here:
[`dev/apple-handoff.md`](../../dev/apple-handoff.md) is the as-built account record and the only
place that tracks per-version state.

Submission is Actions → **Submit to App Review (Apple)**
([`asc-submit-review.yml`](../../.github/workflows/asc-submit-review.yml)) with `mode: submit` and the
version string typed into `confirm_version`; it refreshes the listing text from the docs in this
folder, audits the version, and refuses on any gap. It does **not** release: `releaseType` stays
MANUAL, so an approved version waits for a human to press release, because approval and publication
being the same event is how a version ships before anyone looks at it. The build-and-upload lanes are
[`ios-release.yml`](../../.github/workflows/ios-release.yml) and
[`mas-release.yml`](../../.github/workflows/mas-release.yml); listing text and screenshots are pushed
by [`asc-listing.yml`](../../.github/workflows/asc-listing.yml) and
[`tool/asc_screenshots.py`](../../tool/asc_screenshots.py).

The unblock *was* the **librclone / dart:ffi** dual engine, now shipped. What ships is built inside
the release lanes themselves (`release.yml`'s `librclone` job, and the build steps in
[`mas-release.yml`](../../.github/workflows/mas-release.yml) /
[`ios-release.yml`](../../.github/workflows/ios-release.yml));
[`librclone.yml`](../../.github/workflows/librclone.yml) is the standalone *verification* lane and
[`librclone-ios.yml`](../../.github/workflows/librclone-ios.yml) the isolated iOS spike — a sandboxed app may only exec code
bundled and signed at build time, and iOS cannot spawn subprocesses at all. That history is still
load-bearing: it is why the Mac App Store build embeds rclone in-process, why it needs
`com.apple.security.network.server` for its internal preview bridge, and why neither Apple build has
mount or archive.

**France is deliberately EXCLUDED from availability.** Export compliance is answered declaratively by
`ITSAppUsesNonExemptEncryption=false` in `app/ios/Runner/Info.plist` and `app/macos/Runner/Info.plist`,
and that answer is only true while France stays out: Apple will not create an App Encryption
Declaration unless the app uses proprietary cryptography, or third-party cryptography *and* is sold in
France, so adding France silently turns the shipped key into a false declaration with nothing about
the build changing to say so. `tool/asc_build.py --audit` checks it as the **"french store"** row.
Anyone changing territory availability must read
[`dev/plans/apple-appstore-plan.md`](../../dev/plans/apple-appstore-plan.md) first — enabling France
requires an ANSSI declaration uploaded and approved *before* shipping.

### Rejection history — Apple

The exact reply texts that were sent, and the reasoning behind each sentence, are in
[`apple/review-replies.md`](apple/review-replies.md).

| When | What was rejected | Root cause | Answered by |
| :--- | :--- | :--- | :--- |
| 0.6.8, macOS | **2.4.5** — `com.apple.security.network.server` with no outward-facing server to justify it | The embedded librclone exposes JSON-RPC only and cannot hand raw bytes to the app, so previews, thumbnails, media playback and the PDF viewer stream through a loopback HTTP endpoint inside the app's own process — and App Sandbox needs that entitlement to call `listen()` at all, loopback included | A reply naming the binding call (`InternetAddress.loopbackIPv4`, ephemeral port, per-session token) and volunteering that rclone's own `serve` is disabled in this build. Accepted on resubmission. **Do not remove the entitlement to silence the scan** — that deletes every preview from the MAS build |
| 0.6.8, iOS | **2.1** information needed — Apple asked for a screen recording from physical hardware | Nobody on this project owns an iPhone | A simulator recording, with the limitation stated in sentence two, plus the argument that matters: there are no gated flows (no login, no purchase, no UGC), so nothing is hidden from a reviewer. Accepted |

**macOS direct download** is live but is *not* a store: Developer-ID signing + notarization, no
sandbox, no review, fully automated by the tag. A tag push **fails the job** if the signing cert
secret is absent (never ships an unsigned "release"); notarization is best-effort and bounded, so an
Apple notary outage degrades the release to signed-only rather than blocking it. The only recurring
human step is confirming the notarized zip/DMG replaced the pre-notarization zip on the release.

---

## ✅ Pre-submission truth audit — run before EVERY submission

Per [`dev/backlog/hardening-audit-2026-07-15.md`](../../dev/backlog/hardening-audit-2026-07-15.md)
**H-17**: never ship listing copy, screenshots or tester notes that describe capability the tagged
build does not have. Both stores have already burned us on exactly this — a Play listing claiming
"Show in Files" (no such feature) and a Microsoft tester-notes field pointing the reviewer at a
console command the app deliberately blocks (certification failure, policy 10.1.2.10).

The harder class is the claim that *reads* true. Every listing described a transfer you can "watch,
pause or cancel"; the only pause control in the app pauses the **queue** —
[`jobs_panel.dart`](../../app/lib/src/ui/jobs_panel.dart), *"queued transfers wait; running ones
finish"* — and a running transfer cannot be paused at all. Nothing about that sentence looks like a
lie until you go looking for the button, which is why this audit is a walk through the build rather
than a read of the copy.

- [ ] Re-read that platform's `listing-en-US.md` **against what the build actually does** — remove or
      soften anything planned, partial, or desktop-only for that platform.
- [ ] Re-read the **tester/reviewer notes** and walk every step yourself in the shipping build.
      Never point a reviewer at a command console; the blocked verbs are in
      [`rclone_commands.dart`](../../app/lib/src/state/console/rclone_commands.dart).
- [ ] Confirm the copy does **not** claim "free" / "no paywall" (pricing policy above).
- [ ] Confirm the rclone **non-affiliation** line is present (avoids trademark/impersonation rejection).
- [ ] Confirm the **privacy-policy URL** resolves:
      `https://github.com/GigaionLLC/Airclone/blob/main/PRIVACY.md`.
- [ ] Confirm screenshots match the shipped UI and contain no placeholder-looking media — check the
      platform's asset manifest.
- [ ] Confirm the **version / versionCode** was bumped. Every store rejects a non-increasing version,
      and a Microsoft resubmission needs a new version regardless.
- [ ] Confirm the per-version **release-notes / "What's new"** field is populated **for this version**.
      It is per-version, not per-listing, and starts empty every release — renaming a version does not
      carry it over. Apple **refuses the submission** without `whatsNew` (both 0.7.5 submissions were
      refused on 2026-09-06 with *"English (U.S.) — What's New in This Version — This field is
      required"*, minutes after a dry run printed "No gaps"); `asc-submit-review.yml` now sends it from
      `store-release-notes.txt` before auditing. Play reads `distribution/whatsnew/whatsnew-en-US`,
      which the release job writes from the same file. **Microsoft is the exception:**
      `tool/store_submit.py` clones the previous submission, so its "What's new" silently carries the
      *last* release's text forward and must be edited by hand in Partner Center.
- [ ] **Microsoft Store only —** all four MSIX identity fields match Partner Center → Product
      management → Product identity **as a set** (first mismatch masks the rest); the first **two
      lines** of the Description still disclose the bundled Visual C++ runtime (policy 10.2.4.1) and
      the build still bundles it; and install → run → uninstall on a **clean VM with no VC++
      Redistributable** leaves nothing in `C:\Program Files\Airclone` (policy 10.2.7) with
      uninstaller exit code **0**.
- [ ] **Every store —** the build offers **no route to a download outside that store**. Install the
      real store artifact (or fake the attribution: `adb install -r -i com.android.vending <apk>`),
      open **Settings → Check for updates**, and confirm it names the store and links only to it.
      A GitHub "Open release" button here is what failed Microsoft certification on 2026-08-10
      (policy 10.2.5); Google Play and the App Store enforce the same rule. Anything new that links
      outward — a "download the desktop app" nudge, a changelog link, an engine updater — has to be
      gated on `installSourceProvider` the same way.
- [ ] On a **failed** certification, expand **every** collapsed row and download the **Supporting
      files ZIP** before starting work — the collapsed summary has no detail.

One rule out of the `whatsNew` incident, because it generalises past release notes: **an audit that
misses a blocker is worse than no audit** — it is a green light for a wall. When a store starts
requiring a field, add it to `tool/asc_build.py`'s audit rows, not only to this list. A checklist a
human runs and a check a machine runs fail differently, and only one of them runs every time.

## 🔒 PII / public-repo reminder

This repo is **PUBLIC**. Never commit D-U-N-S numbers, physical addresses, personal emails, or any
GUID — seller, tenant, app, subscription, Partner Center product, or `CN=<GUID>` publisher IDs. Use
`<placeholder>` tokens in these docs and name where the real value lives (e.g. "in repo variable
`MSIX_PUBLISHER`"); keep real values in private notes only.

## Related

### The workflows and scripts that actually submit

| Button (Actions) | Workflow | What it drives |
| :--- | :--- | :--- |
| *Submit to Microsoft Store* | [`submit-msstore.yml`](../../.github/workflows/submit-msstore.yml) | [`tool/store_submit.py`](../../tool/store_submit.py) — stage the release's MSIX, then Submit in Partner Center |
| *Submit to App Review (Apple)* | [`asc-submit-review.yml`](../../.github/workflows/asc-submit-review.yml) | [`tool/asc_build.py`](../../tool/asc_build.py) — refresh listing, audit, submit; release stays manual |
| *App Store Connect (listing text + screenshots)* | [`asc-listing.yml`](../../.github/workflows/asc-listing.yml) | [`tool/asc_listing.py`](../../tool/asc_listing.py) and [`tool/asc_screenshots.py`](../../tool/asc_screenshots.py) — one platform and one thing per run: `what=text` sends that platform's `apple/listing-*.md` plus `whatsNew`; `what=screenshots` uploads one `device` set |
| *Play Store listing images* | [`play-images.yml`](../../.github/workflows/play-images.yml) | [`tool/play_images.py`](../../tool/play_images.py) — images only; Play text is still pasted by hand |
| *Promote on Google Play* | [`promote-play.yml`](../../.github/workflows/promote-play.yml) | [`tool/play_promote.py`](../../tool/play_promote.py) — open testing → production |

### Documents

- [`dev/windows-signing-and-store.md`](../../dev/windows-signing-and-store.md) — Windows signing as-built + the Microsoft Store runbook, certification post-mortems, MSIX identity plumbing.
- [`dev/msstore-ci-setup.md`](../../dev/msstore-ci-setup.md) — the Microsoft submission credential from nothing, the commit trap in full, and why not `msstore publish`.
- [`dev/google-play-store.md`](../../dev/google-play-store.md) — the per-release Play runbook and its gotchas.
- [`dev/apple-appstore-and-macos.md`](../../dev/apple-appstore-and-macos.md) — the Apple runbook: macOS direct distribution and the App Store lanes.
- [`dev/apple-handoff.md`](../../dev/apple-handoff.md) — Apple as-built state: what is live, the `whatsNew` lesson, and the certificate-cap incident.
- [`dev/plans/apple-appstore-plan.md`](../../dev/plans/apple-appstore-plan.md) — the from-nothing Apple account, App Store Connect and signing setup, plus the export-compliance analysis.
- [`dev/plans/store-automation-plan.md`](../../dev/plans/store-automation-plan.md) — the original 2026-07-09 automation verdict per store, **superseded**. The live one-time setup runbooks are [`dev/play-ci-setup.md`](../../dev/play-ci-setup.md), [`dev/msstore-ci-setup.md`](../../dev/msstore-ci-setup.md) and [`dev/plans/apple-appstore-plan.md`](../../dev/plans/apple-appstore-plan.md).
- [`dev/README.md`](../../dev/README.md) — the operational hub: releases, platforms, backlog, process.
- [`dev/backlog/hardening-audit-2026-07-15.md`](../../dev/backlog/hardening-audit-2026-07-15.md) — H-17, the origin of the truth audit above.
- [`.github/workflows/release.yml`](../../.github/workflows/release.yml) — what a `vX.Y.Z` tag actually builds, signs and uploads.
- [`wiki/core/00-system-index.md`](../../wiki/core/00-system-index.md) — the architecture library's master router.
