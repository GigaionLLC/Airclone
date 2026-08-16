# 🏪 Store submissions — index

The router for all three app-store channels: current path and status per store, where the
per-release runbook and listing copy live, and what each store has already rejected us for.

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

## 🧭 Platforms at a glance

| Platform | Path & status | Listing copy | Assets | Per-release runbook |
| :--- | :--- | :--- | :--- | :--- |
| **Microsoft Store** | **MSIX (packaged)** since the 2026-08-08 path reversal — supersedes the unpackaged EXE product that shipped v0.5.x. Manual per-release; CI submission wired but OFF. | [`windows/listing-en-US.md`](windows/listing-en-US.md) | [`windows/`](windows/) | [`dev/windows-signing-and-store.md`](../../dev/windows-signing-and-store.md) §2 |
| **Google Play** | **LIVE listing**. Since 2026-08-16 CI is **live**: every `v*` tag uploads to **open testing** automatically, and production ships from Actions → *Promote on Google Play* (see [`dev/play-ci-setup.md`](../../dev/play-ci-setup.md)). | [`play/listing-en-US.md`](play/listing-en-US.md) | [`play/store-ready/`](play/store-ready/) (+ [`MANIFEST.md`](play/store-ready/MANIFEST.md)) | [`dev/google-play-store.md`](../../dev/google-play-store.md) |
| **Apple App Store (MAS / iOS)** | **FUTURE** — never submitted; blocked on the in-process **librclone** dual-engine work. Do not start a submission lane. | — | — | [`dev/apple-appstore-and-macos.md`](../../dev/apple-appstore-and-macos.md) §2 |
| **macOS direct download** | **LIVE — not a store.** Developer-ID signed + notarized zip/DMG on GitHub Releases, fully automated by the tag. | — | — | [`dev/apple-appstore-and-macos.md`](../../dev/apple-appstore-and-macos.md) §1 (no manual runbook) |

**Windows code signing** (Azure Artifact Signing, subject `Gigaion, LLC`) is **LIVE since v0.5.1** and
runs on every tagged release — the signing half of
[`dev/windows-signing-and-store.md`](../../dev/windows-signing-and-store.md). Automation state and
one-time setup for every platform: [`dev/plans/store-automation-plan.md`](../../dev/plans/store-automation-plan.md).

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

CI submission (`msstore publish`) is gated on `STORE_PUBLISH_ENABLED` and stays **off** until one
manual submission has succeeded end to end.

### Rejection history — Microsoft Store

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

Two process rules that came out of the 2026-07-29 report and belong in every future round:

- On a failed certification, **expand every collapsed row** and download **Supporting files → ZIP**
  before starting work. The collapsed summary carries no actionable detail — 10.1.2.10 looked like a
  symptom of the VC++ finding and was unrelated.
- **Walk the tester notes yourself, in the shipping build, before submitting.** Every step in that
  field is a promise about behaviour, and one stale instruction failed the whole submission.

---

## 🤖 Google Play

Package `com.gigaionllc.airclone`. Listing is live; the AAB goes to the **internal** track. CI is
fully wired (`r0adkll/upload-google-play@v1`) but only runs when `PLAY_SERVICE_ACCOUNT_JSON` is set —
it is not, so every upload today is manual. CI never touches production.

| What | Where |
| :--- | :--- |
| Per-release runbook | [`dev/google-play-store.md`](../../dev/google-play-store.md) |
| Listing copy + screenshot checklist | [`play/listing-en-US.md`](play/listing-en-US.md) |
| "What's new" copy (≤500 chars/locale) | [`play/whats-new-v0.6.0.md`](play/whats-new-v0.6.0.md) — still accurate for v0.6.1, which changed only the Store package identity |
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

**No App Store submission exists and none should be started.** The Mac App Store is structurally
incompatible with today's subprocess engine (a sandboxed app may only exec code bundled and signed
at build time; an inherit-sandboxed child cannot hold the parent's security-scoped grants), and iOS
cannot spawn subprocesses at all. The unblock is the **librclone / dart:ffi** dual-engine work —
see [`dev/apple-appstore-and-macos.md`](../../dev/apple-appstore-and-macos.md) §2 for the
prerequisites checklist and [`dev/plans/dual-engine-plan.md`](../../dev/plans/dual-engine-plan.md)
for the build order.

There is therefore **no Apple rejection history** — nothing has ever been reviewed.

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

## 🔒 PII / public-repo reminder

This repo is **PUBLIC**. Never commit D-U-N-S numbers, physical addresses, personal emails, or any
GUID — seller, tenant, app, subscription, Partner Center product, or `CN=<GUID>` publisher IDs. Use
`<placeholder>` tokens in these docs and name where the real value lives (e.g. "in repo variable
`MSIX_PUBLISHER`"); keep real values in private notes only.

## Related

- [`dev/windows-signing-and-store.md`](../../dev/windows-signing-and-store.md) — Windows signing as-built + the Microsoft Store runbook, certification post-mortems, MSIX identity plumbing.
- [`dev/google-play-store.md`](../../dev/google-play-store.md) — the per-release Play runbook and its gotchas.
- [`dev/apple-appstore-and-macos.md`](../../dev/apple-appstore-and-macos.md) — macOS direct distribution (live) and the MAS/iOS prerequisites.
- [`dev/plans/store-automation-plan.md`](../../dev/plans/store-automation-plan.md) — one-time CI/credential setup and the automation verdict per store.
- [`dev/README.md`](../../dev/README.md) — the operational hub: releases, platforms, backlog, process.
- [`dev/backlog/hardening-audit-2026-07-15.md`](../../dev/backlog/hardening-audit-2026-07-15.md) — H-17, the origin of the truth audit above.
- [`.github/workflows/release.yml`](../../.github/workflows/release.yml) — what a `vX.Y.Z` tag actually builds, signs and uploads.
- [`wiki/core/00-system-index.md`](../../wiki/core/00-system-index.md) — the architecture library's master router.
