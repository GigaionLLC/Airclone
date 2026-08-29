# Apple — macOS distribution + App Store

Companion to `dev/windows-signing-and-store.md` and `dev/google-play-store.md`. Two very different
things live under "Apple":

1. **macOS direct download — LIVE.** Developer-ID signed + notarized DMG/zip on GitHub Releases.
2. **Apple App Store (Mac App Store / iOS) — FUTURE**, blocked on the in-process **librclone** engine.

## 1. macOS direct download (LIVE — not a store)

macOS ships the same way as Windows/Linux: a signed binary on the
[Releases](https://github.com/GigaionLLC/Airclone/releases) page. It is **NOT** the Mac App Store — it
passes Gatekeeper via Developer-ID signing + Apple notarization, with no sandbox and no store review.

| Thing | Value |
| :--- | :--- |
| Signing | **Developer ID Application** (org `APPLE_*` secrets; identity auto-discovered by SHA-1 — no identity secret) |
| Hardening | Hardened Runtime **ON**, App Sandbox **OFF**, `Release.entitlements` |
| Notarization | best-effort + **bounded** (`.github/scripts/notarize.sh`: `NOTARY_TIMEOUT=20m`, `NOTARY_RETRIES=2`; never a naked `--wait`) |
| Artifacts | signed **zip** (always) + **DMG** (only if notarize succeeded) |
| Secrets (org-level) | `APPLE_DEVELOPER_ID_APPLICATION_P12_BASE64`, `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID` |

**CI behavior (`release.yml` `macos` job):**
- **Hard gate:** a tag push **fails the job** if the signing-cert secret is absent — never ships an
  unsigned "release."
- The signed zip is uploaded **before** notarization is attempted, so an Apple notary outage/timeout
  can never block a release. On notarize success the zip is re-stapled + re-uploaded (`--clobber`) and
  the DMG gets its own notarize+staple pass.
- If notarization never lands, a `::warning::` fires and the release stays **Developer-ID-signed-only**
  (re-runnable later).

There is **no per-release manual runbook** for macOS direct — it is fully automated by the tag. The
only recurring human step is confirming the notarized zip/DMG replaced the pre-notarization zip on the
release.

## 2. Apple App Store — per-release runbook (macOS **and** iOS)

**Rewritten 2026-08-28.** Both platforms build, sign and upload from CI, and a
whole submission's metadata is pushed from this repo. Real IDs, the App Review
contact and the delivery history live in the encrypted vault
(`python tool/vault.py unlock`) — never here.

### The order that works

Each step is one dispatch. Every tool defaults to a dry run; nothing writes
without `mode=apply` or `--apply`.

| # | Step | Command |
| :-- | :--- | :--- |
| 1 | Listing copy | `gh workflow run asc-listing.yml -f platform=MAC_OS -f what=text -f mode=apply` |
| 2 | Screenshots | `gh workflow run asc-listing.yml -f platform=MAC_OS -f what=screenshots -f device=mac -f mode=apply` |
| 3 | Build + upload | `gh workflow run mas-release.yml -f mode=upload` |
| 4 | Wait for Apple to finish processing | `gh workflow run asc-version.yml -f platform=MAC_OS -f mode=report` until a `VALID` build appears |
| 5 | Attach it + review notes | `... asc-version.yml -f platform=MAC_OS -f mode=apply -f notes=true` |
| 6 | **Human:** export compliance, *Add for Review*, *Manually release* | App Store Connect |

For iOS, substitute `-f platform=IOS`, `-f device=iphone` **and** `-f device=ipad`
(two separate sets — Apple wants one per display type), and
`gh workflow run ios-release.yml -f mode=upload -f signing=ephemeral`.

Screenshots are produced, not written by hand:
`mas-screenshots.yml -f mode=capture` for Mac, `ios-screenshots.yml -f mode=capture`
for iPhone + iPad. Both seed demo content and real CC0 photographs into the app's
own container first.

### Things that are true every time

- **`mode=report` / dry run first.** Every tool prints exactly what it would send.
  A rejected metadata write costs a minute; a wrong one costs a review cycle.
- **A build is not attachable until `processingState` is `VALID`.** `PROCESSING`
  means wait. An empty build list right after an upload is normal for a while.
- **macOS and iOS builds of one release share a build NUMBER**, because it is
  `CFBundleVersion`. The platform lives on the build's `preReleaseVersion`, and
  `asc_build.py` filters on it — attaching an iOS build to a macOS version is
  rejected, and the error is more confusing than the mistake.
- **Retrying a delivery needs a new build number.** Both release lanes take
  `-f build_number=NNN`, which overrides it at build time rather than editing
  `pubspec.yaml` and dragging every other platform along.
- **The App Review contact is required** on `appStoreReviewDetails`, and Apple
  409s the whole request without it — even when only the notes are changing. It is
  personal data: `APPLE_REVIEW_CONTACT` (repo secret) holds it, and the tool
  prefers a contact already on another platform's version.
- **The privacy-policy URL is app-level**, not per-version, and a submission is
  refused without it. `asc_listing.py` checks it on every run.

### iOS signing: mint per run, revoke on the way out

Two automatic routes were tried and **both are dead ends** — do not retry them:

| Attempt | Apple's answer |
| :--- | :--- |
| archive as `Apple Development`, automatic signing | *"Your team has no devices from which to generate a provisioning profile"* — iOS development profiles need a **registered device**; macOS ones do not |
| archive unsigned, export with automatic signing | *"Cloud signing permission error"*, *"No signing certificate 'iOS Distribution' found"* — the same wall macOS hit |

So `ios-release.yml -f signing=ephemeral` mints a distribution certificate through
the **Certificates API** (which an App Manager key can do, unlike cloud signing),
uses it inside that one job, and revokes it in an `always()` step. No distribution
private key is stored anywhere. Two details that matter: the profile is rebuilt
each time, because a surviving profile references the revoked certificate and
cannot sign; and `--revoke` takes an explicit id and never hunts for stale
certificates, since Apple derives a certificate's name from the team and guessing
would revoke something a human created.

### `VERIFY SUCCEEDED` does not mean the build will process

Apple's `altool --validate-app` checks the outer package: signature, entitlements,
embedded profile. It does **not** look inside `Contents/Resources/*.bundle`.
Processing does, and reports by **email, hours later**:

```
ITMS-90284: Invalid Code Signing - The executable
'Airclone.app/Contents/Resources/<plugin>.bundle' must be signed with the
certificate that is contained in the provisioning profile.
```

Every Flutter plugin ships a resource bundle, so this arrives once per plugin —
nine for this app. The cause was the re-sign step choosing its identity with a
grep for `"Apple (Distribution|Development)"`, which does not match
**`3rd Party Mac Developer Application`**, the identity a Mac App Store build is
signed with. It fell back to development, and `-exportArchive` re-signs the app
and its Frameworks but not those bundles.

The lane now signs every nested bundle explicitly and then **asserts the
authority on each one** before export, because a silent mismatch costs a whole
upload and an email you cannot poll for.

### Screenshot seeding: never bake a container path into the config

`flutter drive` reinstalls the app, and a reinstall **preserves the data while
giving the container a new UUID**. So a config seeded with
`remote = <container>/Documents` still exists after the install, and the
photographs still exist beside it — but the path inside it now names the old
container, and rclone lists a directory that is gone. The browser shows
*"Empty folder"*, which is a completed listing with zero entries, not a failure.

That is invisible from outside the process: the config is there, the files are
there, and both look right. The app said it in one line from inside its own
sandbox:

```
PROBE docs=  .../Application/2EBB2267-.../Documents
PROBE conf=  remote = .../Application/CB2C6DC7-.../Documents
```

The demo remote therefore points at **`/tmp/airclone-demo`** on the host. A
simulator app is a host process and can read host paths, so that survives any
number of reinstalls. Content is still copied into each container as well,
because that is what *On My Device* legitimately shows.

### Do not revoke the signing certificate after an upload

`ios-release.yml -f signing=ephemeral` mints a distribution certificate per run
and revokes it on the way out. That is right for `dry-run` and `validate`, where
nothing produced is kept — and **wrong for `upload`**.

The first iOS submission came back **Invalid Binary** within minutes of
*Add for Review*, with the certificate that signed it already revoked. Apple
accepts the upload and processes the build to `VALID` regardless, so nothing
complains until submission. The lane now skips the revoke step for `upload` and
prints the certificate id so it can be revoked by hand once the version is live.

A leftover certificate is a tidiness problem. A revoked one underneath a
submitted build is a blocked release.

### Export compliance

Airclone implements standard confidentiality encryption of its own — rclone
`crypt`, config encryption, the vault, and Go's own TLS, because the engine is
statically linked and never calls Apple's Security framework. The "HTTPS only"
and "Apple's OS crypto only" exemptions are therefore **false**, and
`ITSAppUsesNonExemptEncryption` is deliberately absent from `Info.plist` so a
human answers it rather than a build claiming something untrue.

**Answering "yes" to *available in France*** makes Apple require an uploaded
**ANSSI declaration**, approved before shipping. Answering no removes the
requirement, and availability is independent of the binary — shipping without
France and adding it in a later version costs no rebuild. The full reasoning is in
[`plans/apple-appstore-plan.md`](plans/apple-appstore-plan.md).

### What the MAS build is, and is not

The Mac App Store build is a **strictly smaller** app than the DMG: no OS mount,
no archive create/extract, no "Show in Finder". That is the sandbox, not a
shortcut, and the listing copy says so. "Open with default app" survives, because
it goes through `url_launcher`/NSWorkspace rather than a spawn.

Two entitlement facts that are easy to get wrong:

- **`com.apple.security.network.server` is required, and not for Serve.**
  `librclone_object_server.dart` binds a loopback socket and is the ONLY source of
  preview, thumbnail, video, audio and PDF bytes under the in-process engine.
  Omitting it ships a build with no media at all.
- Under the sandbox `$HOME` is redirected into the container and macOS pre-creates
  `Desktop`/`Documents`/`Downloads` there, so seeded Locations do NOT vanish —
  they render and point at empty folders, which is worse. A MAS build seeds
  nothing and asks for the first folder.

### Verifying without hardware

Nobody on this project owns a Mac, an iPhone or an iPad. Everything above is
verified on GitHub runners:

| Workflow | Answers |
| :--- | :--- |
| [`mas-verify.yml`](../.github/workflows/mas-verify.yml) | does the **sandboxed** Mac build run, with no denials? |
| [`ios-verify.yml`](../.github/workflows/ios-verify.yml) | does the iOS build launch and reach `EnginePhase.ready`? |
| [`ios-release.yml`](../.github/workflows/ios-release.yml) `mode=dry-run` | does the **Release device** archive keep the Go symbols? Needs no Apple credential. |

The trick that makes the Mac half possible: **the App Sandbox is enforced by the
code signature plus the entitlement, not by the App Store.** An ad-hoc signature
with `MacAppStore.entitlements` gives CI the same sandbox a customer gets. That
workflow is also the only Swift compiler this project has.

## See also

- Windows Store per-release runbook: `dev/windows-signing-and-store.md` §2.
- Google Play per-release runbook: `dev/google-play-store.md`.
- Index + pricing policy + pre-submission truth audit: `docs/store/README.md`.
- Automation verdicts + one-time setup: `dev/plans/store-automation-plan.md`.
