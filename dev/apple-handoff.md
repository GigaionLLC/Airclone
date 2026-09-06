# Apple App Store — current state and the signing-identity ledger

Where the Apple track stands right now, which signing identity signed what, and
the traps that already cost time. The per-release runbook is
[`dev/apple-appstore-and-macos.md`](apple-appstore-and-macos.md); the
from-nothing account and legal setup is
[`dev/plans/apple-appstore-plan.md`](plans/apple-appstore-plan.md). **Value-free
by design** — real IDs, key paths and account state live in the encrypted vault
(`python tool/vault.py unlock`, then
`dev/vault/notes/apple-appstore-setup-record.md`).

## State (2026-09-06): 0.7.5 SUBMITTED ON BOTH PLATFORMS, ENTIRELY FROM CI

| | macOS | iOS |
| :--- | :--- | :--- |
| Version 0.6.8 | **READY_FOR_SALE** | **READY_FOR_SALE** |
| Version 0.7.5 | **WAITING_FOR_REVIEW** | **WAITING_FOR_REVIEW** |
| Build 123 attached | ✅ | ✅ |
| 0.7.5 audit | ✅ **no gaps** | ✅ **no gaps** |
| Submitted | `f144ba7c…` 15:56:47Z | `22150b3e…` 15:56:24Z |

Both went through `asc-submit-review.yml -f mode=submit -f confirm_version=0.7.5`
— no console, no local key. Export compliance answered in `Info.plist`, listing
refreshed from the repo docs by the same run, audited, then submitted. What is
still human: pressing **release** after approval (`releaseType` stays MANUAL).

### `whatsNew` is required, per-VERSION, and the audit used to miss it

Apple refused both 0.7.5 submissions with *"English (U.S.) — What's New in This
Version — This field is required"*, minutes after a dry-run of the submit
workflow had printed **"No gaps"**. Two independent holes: `asc_listing.py` never
sent the field, and the audit never checked it.

It is the one listing field that does **not** carry forward — description and
keywords persist across versions, this one starts empty on every release. Apple
accepts the same generic line the other two stores get
(`docs/store/store-release-notes.txt`), so there is nothing to write per release.

`asc-submit-review.yml` now refreshes the listing from the docs before it audits,
pinned with `--version` to the string the operator confirmed. That pin closed a
second hazard found while wiring it: `asc_listing.py` took the FIRST version the
API returned for a platform, and iOS lists 0.7.5 **and** 0.6.8 — every previous
run was ordering luck. It also now refuses a version that is not editable.

**The lesson worth keeping: an audit that misses a blocker is worse than no
audit.** It is a green light for a wall.

0.7.4 was never submitted, so it was RENAMED to 0.7.5 rather than created anew —
Apple allows one editable version per platform, and `--create-version` says so
and refuses rather than failing at the API.

### The lanes minted a certificate per run, and nobody noticed for three weeks

Both Apple lanes archived with `CODE_SIGN_STYLE=Automatic` +
`CODE_SIGN_IDENTITY=Apple Development`, so `-allowProvisioningUpdates` minted a
**development certificate on every run** and never revoked it. Ten accumulated
between 2026-08-20 and 2026-09-06 until the account hit Apple's cap, and the
macOS lane then failed with *"Your account has reached the maximum number of
certificates"* — a failure with no relation to anything that had changed, which
is exactly why it read as sudden.

None of them was ever needed. Both lanes re-sign or re-export with the real
distribution identity afterwards, so the archive's signature never reaches the
shipped artifact. Both now archive UNSIGNED and mint nothing.

`asc_ios_signing.py --list-certs` prints every certificate with its id and type —
without it, a cap cannot even be diagnosed, let alone cleared.

### Two steps that used to need a human, and no longer do

**Creating the version record.** `asc_build.py` only ever picked an existing
editable version, so the whole tool sat behind someone clicking "+ Version or
Platform". The API always allowed it — the tool simply never asked.
`--create-version X.Y.Z` (workflow `mode=create`) POSTs it with
`releaseType: MANUAL` set at creation rather than patched afterwards, and refuses
when an editable version already exists, because Apple allows exactly one per
platform and the intent in that case is almost always a rename.

**Verifying a build registered.** `main()` called `pick_version()` before
anything else, so the build listing was unreachable until a version existed —
which is precisely the window right after an upload where a build can die
silently (macOS 117 and 118 both did). `asc-version.yml -f mode=builds` now
reaches `pick_build()` directly and needs no version record:

    builds visible to this key: 5
      build 122    IOS       VALID   expired=False  2026-09-05T12:57:12
      build 122    MAC_OS    VALID   expired=False  2026-09-05T12:55:59

`UPLOAD SUCCEEDED` still is not evidence on its own — that listing is.

## The signing identities, and how to rotate them

### iOS: a STORED identity, and it is proven (2026-09-05)

`gh workflow run ios-release.yml -f mode=validate -f signing=secrets` produced a
signed 57 MB `.ipa` and Apple answered `No errors validating archive`. No
certificate is minted per release any more, and nothing has to be revoked
afterwards.

| | |
| :--- | :--- |
| Certificate | `YDG7JN3B33` — `Apple Distribution: Gigaion, LLC` |
| Profile | `Airclone iOS App Store` (IOS_APP_STORE) |
| **Both expire** | **2027-09-05** — rotate before then |
| Secrets | `APPLE_IOS_DIST_P12_BASE64`, `APPLE_IOS_P12_PASSWORD`, `APPLE_IOS_PROVISIONING_PROFILE_BASE64` (org, visibility all) |
| Private key backup | Proton Drive `DeveloperFiles/Apple-iOS-Distribution-Signing/` — the ONLY copy, with the script and a README |

**Two things bit during the switch, both now fixed in the repo.**

*Apple 500'd on `POST /v1/profiles`* after deleting the old profile and minting
the certificate, leaving a certificate with no profile. Re-running was unsafe in
both directions: `--force-new` would mint a third certificate against the cap,
and plain `--apply` would pair the new private key with `ios_certs[0]` — a coin
flip once two certificates exist — producing a p12 that signs nothing. Hence
`--profile-only`, which reuses the certificate in `cert-id.txt`.

*The Archive step routed `secrets` into a path its own comment called closed.* An
"Apple Development" archive on iOS needs a registered device; nobody here owns an
iPhone. The branch had never run, because the secrets never existed, so the first
real run failed word-for-word as the comment predicted. Everything now archives
unsigned except the `automatic` experiment, and `-exportArchive` applies the
distribution identity — which is what `ephemeral` always did.

### Every identity, and when it expires

Three separate pairs, and they are not interchangeable — the Mac App Store certs
(`3rd Party Mac Developer *`) do **not** cover iOS, and neither pair has anything
to do with the notarized direct download. Verify a date with
`asc_ios_signing.py --list-certs` before relying on it; where the repo records
none, this table says so rather than guessing.

| Identity | Where it lives | Expires |
| :--- | :--- | :--- |
| Apple Distribution + `Airclone iOS App Store` profile | `APPLE_IOS_DIST_P12_BASE64`, `APPLE_IOS_P12_PASSWORD`, `APPLE_IOS_PROVISIONING_PROFILE_BASE64` | **2027-09-05** |
| `3rd Party Mac Developer` Application + Installer, + the MAS profile | `APPLE_MAS_APP_P12_BASE64`, `APPLE_MAS_INSTALLER_P12_BASE64`, `APPLE_MAS_P12_PASSWORD`, `APPLE_MAS_PROVISIONING_PROFILE_BASE64` | **2027-08-20** (issued 2026-08-20; recorded in the vault record, not re-verified against the API) |
| Developer ID Application + Installer (direct download, not a store) | `APPLE_DEVELOPER_ID_APPLICATION_P12_BASE64` + `_PASSWORD` | 2031, per the plan's §1 table |

**A lapse is silent.** Nothing warns; the lane simply starts failing at signing,
and the message names the identity rather than the expiry.

### Rotating the iOS identity (before 2027-09-05)

The migration off `ephemeral` is **done** — see the section above. What follows is
the same recipe read as a rotation, because it is the only place the from-nothing
details are written down.

**It needs the `.p8` in hand**, which lives in Proton Drive under
`DeveloperFiles/Apple-StoreConnect-API-Files/` (outside this repo, by design, and
Apple only lets it be downloaded once). No machine here can mint an iOS identity
without it, and CI's copy is a secret it cannot hand back. The stored
`dev/secrets/apple-csr/distribution.p12` does NOT help — it is a
`3rd Party Mac Developer Application` certificate, Mac App Store only.

Order matters, because Apple caps distribution certificates per team:

1. **Free a slot first** by revoking a spare id whose version is live
   (`apple-revoke-cert.yml`, and check the ledger below). Skipping this risks the
   mint below failing at the cap.
2. Fetch the `.p8`, then:
   ```
   python tool/asc_ios_signing.py <key.p8> <keyid> <issuerid> --apply --force-new
   ```
   `--force-new` is required whenever the existing certificates' private keys are
   gone — every `ephemeral` run discarded its own — because reusing a certificate
   whose key you do not hold produces a p12 that signs nothing.
3. Run the three `gh secret set` lines the script prints (org scope, visibility
   all). They read from files — do not paste values.
4. Prove it before relying on it:
   `gh workflow run ios-release.yml --ref main -f mode=validate -f signing=secrets`
5. If Apple fails partway — it 500'd on `POST /v1/profiles` once, after the old
   profile was deleted and the new certificate minted — resume with
   `--profile-only`, which reuses the certificate recorded in `cert-id.txt`.
   Re-running `--force-new` instead mints a third certificate against the cap.

Nothing in this repo needs changing for a rotation. `ios-release.yml` already
defaults to `signing: secrets`, and `tool/asc_ios_signing.py` was written for
exactly this — it emits pre-base64'd files and prints the `gh secret set` lines,
reading from files so no secret ever reaches a transcript.

### Outstanding iOS distribution certificates — the ledger

`apple-revoke-cert.yml` names this table as the record of which id signed what.
Every `ephemeral` run minted one and deliberately did not revoke it, so they
accumulate against Apple's cap (typically 3) and have to be cleared by hand once
the version they signed is live.

| Certificate | Signed | State |
| :--- | :--- | :--- |
| `YQF53PS6AW` | 0.6.8 build 118 | ✅ **revoked 2026-09-05** (0.6.8 was live) |
| `3NWQMKV4UB` | 0.7.4 build 122 | ⛔ **do not revoke** while 0.7.5 is in review — see below |
| `YDG7JN3B33` | the STORED identity, all future releases | ⛔ **never revoke** while it is in the secrets |

Revoking no longer needs a machine with the `.p8` on it: CI already holds the key
as an org secret, so `apple-revoke-cert.yml` does one id at a time, with the id
typed twice and checked before the key is even written to disk. A live app is
unaffected by revoking the certificate that signed it; a build still in review is
not.

⚠️ **The old condition on `3NWQMKV4UB` — "until 0.7.4 is live" — can never be
met.** 0.7.4 was renamed to 0.7.5 rather than shipped, and 0.7.5 carries build
**123**, not the 122 this certificate signed. So 122 is attached to nothing and
will never ship, which reads like "safe to revoke now".

**Do not act on that reasoning while 0.7.5 is in review.** The cost of being
wrong is not symmetric: revoking early is what returned INVALID BINARY on the
first iOS submission, minutes after Add for Review, and it cannot be undone —
whereas waiting costs nothing but a slot against a cap that is not currently
full. Revisit once 0.7.5 is **live on both platforms**, and revoke only after
confirming with `asc_ios_signing.py --list-certs` which id signs the shipped
build.

## Rules that are not negotiable here

- **No machine presses RELEASE, and no machine submits without a typed
  confirmation and a clean audit.** Submission itself is automated
  (`asc-submit-review.yml`), but `mode=submit` requires `confirm_version` typed
  exactly and refuses on any audit gap, and `releaseType` is MANUAL from the
  moment the version record is created — so an approved version sits and waits
  for a human. The Microsoft Store rule stands unchanged and separately: a
  submission there is **staged only, never committed via the API**, because a
  machine once committed one and published this app at **$0**, unstoppable once
  started. See AGENT.md rule 10.
- **Never name the command console** in reviewer notes or show it in a
  screenshot. It cost Microsoft review cycles.
- **No screenshot may show mount, archive or "Show in Finder"** — the sandboxed
  build genuinely lacks them, and showing a feature the binary does not have is a
  rejection.
- Store copy must **never claim the app is free**; the store build is paid.
- The **rclone non-affiliation line** must stay in the description.

## The Mac App Store build is a smaller app, on purpose

Sandbox ON forces the in-process librclone engine and removes OS mount, archive
create/extract and Show in Finder. `state/build_flavor.dart` carries the
compile-time `AIRCLONE_MAS` flag; policy providers gate the features; the config
lives in app-private storage. The listing's `ABOUT THIS VERSION` paragraph says so
plainly — deliberate, so a buyer is not surprised.

`com.apple.security.network.server` is **required** and not for Serve: the
in-process engine serves preview/thumbnail/media bytes over a loopback socket.
Removing it ships a build with no media at all.

## Traps already paid for — do not rediscover these

**macOS automation reports success while doing nothing.** `osascript` clicks and
keystrokes silently no-op without accessibility permission; System Events'
`click at` returns no error and delivers no click. A defensive `|| true` hid both
for four runs. Use **`cliclick`** (real CGEvents), like the Windows rig already did.

**Flutter renders its own widgets** — System Events cannot address them by name
(`-1728`). Drive by coordinate, and read coordinates off captured frames: the
toolbar re-lays out once a remote is open.

**`path_provider` keys application-support by BUNDLE IDENTIFIER on macOS**, not app
name. Seeding the demo config anywhere else silently does nothing.

**`-force_load` of an archive missing an architecture is a WARNING.** The link
succeeds, that slice contains no engine, and nothing says so until symbols turn
out not to be in the binary. `flutter build ios --simulator` always emits a fat
x86_64+arm64 binary, so the simulator archive must be fat too — and symbol checks
must be **per architecture**, because a bare `nm` on a universal file is not a
per-slice answer.

**Link stable paths, never xcframework slice directories.** xcodebuild renames
`ios-arm64-simulator` to `ios-arm64_x86_64-simulator` the moment a second
architecture appears.

**`-force_load` does not survive `-dead_strip`.** Both appear on the link line,
and nothing in the app references the Go exports — they exist only to be looked
up at runtime — so the archive is loaded and then thrown away. Name each symbol
with `-Wl,-u,_Rclone*` to make it a dead-strip root. This bites **Debug as well
as Release**; an early guess that the Debug dylib was immune (dylibs export their
globals) did not survive the next run's evidence.

**Xcode 16+ splits a Debug app in two.** `ENABLE_DEBUG_DYLIB = YES` puts the
app's code in `Runner.debug.dylib` and leaves `Runner` as a launcher stub, so
`nm Runner` finds nothing however correct the link was. **Scan the whole bundle**
and report which Mach-O holds the engine; Release has no debug dylib and the same
scan covers it.

**Do not hard-code nm's type letter.** `grep " T _sym$"` reported four symbols
missing from a binary that contained all four. Match the last field with awk and
reject only `U`.

**GitHub runs every `run:` block as `bash -e {0}` — errexit is ALREADY ON.**
`set -uo pipefail` does not undo it; only `set +e` does. This aborted three
separate diagnostics in the iOS lane, every time on a `grep` that legitimately
found nothing, which is exactly the case worth reporting. A step that dies at its
first empty `grep` looks identical to a step whose subject is missing.

**A check must print what it SAW, not just its verdict.** Every wrong theory in
this lane — `nm -gU` semantics, the debug dylib being immune, the archive "not
being linked" — survived a full CI round trip because the step reported a boolean.
Three separate diagnostics then failed in their own right: one truncated by
`head -20`, one aborted by `grep -c` exiting 1 under `pipefail`, one that counted
matches without ever showing them. Print the lines.

**A locked keychain makes `-allowProvisioningUpdates` create nothing and report no
error** (`0 valid identities found`). The lane creates an ephemeral keychain.

**A command-line `xcodebuild` build setting applies to EVERY target** in the
workspace, including each SPM plugin — which is why the MAS entitlements are
swapped onto `Release.entitlements` in CI rather than passed as
`CODE_SIGN_ENTITLEMENTS`.

**Xcode's cloud signing cannot mint a distribution certificate with an App Manager
key** ("Cloud signing permission error"), but the **Certificates API can**. That
is why the key stays App Manager instead of Admin.

**A `.swift` file not referenced in `project.pbxproj` is never compiled** — four
edits are needed to add one.

**Set the execute bit through git** (`git update-index --chmod=+x`); `chmod` on a
Windows checkout does not reach the index.

## Useful commands

```bash
python tool/vault.py unlock          # account record, real IDs, cert expiry
gh run list --workflow=mas-release.yml --limit 3
gh workflow run mas-screenshots.yml --ref main -f mode=capture
gh workflow run ios-verify.yml --ref main -f configuration=release
gh workflow run ios-release.yml --ref main -f mode=dry-run   # no secret needed
python tool/check-docs.py            # must be 0 broken before committing
cd app && flutter analyze && flutter test
```

## History (newest first)

Everything below describes a state that has since changed. It is kept because the
reasoning outlived the state, not because any of it is still the thing to do.

### Previously (2026-09-05): `ephemeral` was the only path

`ios-release.yml -f signing=secrets` failed in seconds with
`missing: APPLE_IOS_DIST_P12_BASE64(secret) APPLE_IOS_PROVISIONING_PROFILE_BASE64(secret)`.
Those secrets **did not exist**. The org had `APPLE_MAS_*` (Mac App Store) and
`APPLE_DEVELOPER_ID_*` (notarised direct download) only — confirmed against
`gh secret list --org GigaionLLC`. So build 118 also went out on `ephemeral`,
which is where the retained certificates in the ledger came from. The refusal is
cheap and happens before any build work, so the wrong choice cost a minute, not a
build number.

Ephemeral was a deliberate security posture ("no distribution private key ever
leaves the runner"), and it was coherent while the certificate was revoked at the
end of every run. That premise died when revoking after an upload produced the
build-117 INVALID BINARY and the lane started retaining: from then on we paid a
long-lived certificate's operational cost — a slot consumed per release and a
manual revoke each time — while still discarding the private key, so the retained
certificate was useless to us AND to an attacker. Worst of both, which is what
settled the switch. Storing one was never a new exposure in kind either: the org
already held `APPLE_MAS_APP_P12_BASE64` and `APPLE_MAS_INSTALLER_P12_BASE64`, the
same class of material for macOS.

### Previously (2026-09-05): 0.7.4's builds, and what they proved

| | macOS | iOS |
| :--- | :--- | :--- |
| Build 122 uploaded | ✅ `UPLOAD SUCCEEDED` (UUID 799e7838…) | ✅ `UPLOAD SUCCEEDED` (UUID db0a8c14…) |
| Build 122 **registered** VALID | ✅ confirmed 2026-09-05 | ✅ confirmed 2026-09-05 |

0.7.4 was created on both platforms with `mode=create`, had build 122 attached,
and took review notes, copyright and the full listing text. Both audits reported
no gaps. It was then renamed to 0.7.5 rather than submitted.

### Previously (2026-08-29): BOTH PLATFORMS SUBMITTED

| | macOS | iOS |
| :--- | :--- | :--- |
| Version 0.6.8 | **WAITING_FOR_REVIEW** | **WAITING_FOR_REVIEW** |
| Build | 119 | 118 (117 was rejected) |
| Release type | **MANUAL** | **MANUAL** |

**Release type MANUAL on both is the point.** An approved version waits for a
human rather than publishing itself. It was found set to `AFTER_APPROVAL` on
macOS *after* the audit had twice reported "no gaps" - copyright and release type
live on the version, not the localization, and the audit only checked
localization fields.

#### The iOS rejection, and what actually fixed it

Build 117 was submitted and came back **Invalid Binary** within minutes.
`signing=ephemeral` had revoked its distribution certificate at the end of the
run that uploaded it. Apple accepts the upload and processes the build to `VALID`
regardless, so nothing complains until submission.

Build 118 was uploaded with its certificate **retained** and submitted without
incident. The lane no longer revokes after an `upload`, and prints the
certificate id instead.

That is a hypothesis confirmed by outcome rather than by Apple's own words: the
email carries the reason and was not needed in the end, but nothing in the API
ever explains an `INVALID_BINARY`.

The shape of what follows a submission has not changed: Apple reviews within
about 48 hours and emails; on approval **neither version goes live by itself**,
because `releaseType` is MANUAL; on rejection the message names the guideline, and
the fix is to re-upload with a new `-f build_number`, re-attach, and resubmit.

### Previously (2026-08-28): builds uploaded, submission still human

| | macOS | iOS |
| :--- | :--- | :--- |
| Build uploaded, Apple-accepted | ✅ `UPLOAD SUCCEEDED` | ✅ `UPLOAD SUCCEEDED` |
| Build **registered** by Apple | ✅ build 119 `VALID` (117 and 118 died silently — see below) | ✅ build 117 `VALID` |
| Build attached to version 0.6.8 | ✅ | ✅ |
| **Submission audit** (`asc-version.yml -f mode=audit`) | ✅ **no gaps** | ✅ **no gaps** |
| Listing text, keywords, promo | ✅ | ✅ |
| Screenshots | ✅ 5 x 1280x800 | ✅ iPhone 1320x2868 + iPad 2064x2752 |
| Review notes + contact | ✅ | ✅ |
| Export compliance, Add for Review, Manually release | ⛔ human | ⛔ human |

**Two things blocked a human-free finish**, and both are now closed:

1. ~~The review contact~~ **DONE.** It lives in the `APPLE_REVIEW_CONTACT` repo
   secret as JSON — personal data, so it reaches Apple directly and is never
   written to this repo or printed. `asc_build.py` prefers a contact already on
   another platform's version and falls back to the secret.

   ~~Export compliance is the live one.~~ **Also done**, declaratively:
   `ITSAppUsesNonExemptEncryption=false` in both `Info.plist` files, valid only
   while France stays excluded from availability. See the plan's "Export
   compliance: SETTLED".
2. ~~The macOS build never registered.~~ **SOLVED 2026-08-29 by Apple's email.**
   `ITMS-90284: Invalid Code Signing` — nine times, once per Flutter plugin
   resource bundle in `Contents/Resources/*.bundle`. The re-sign step picked its
   identity with a grep for `"Apple (Distribution|Development)"`, which does not
   match **`3rd Party Mac Developer Application`** — the identity a Mac App Store
   build needs and the one inside the provisioning profile — so it silently fell
   back to the development identity. `-exportArchive` re-signs the app and its
   Frameworks but not those bundles, and **Apple's own validator does not look
   inside them either**, which is exactly how `VERIFY SUCCEEDED with no errors`
   and a rejected build coexist. The lane now signs every nested bundle with the
   store identity and asserts the authority on each one before export.

   The old text, kept because the reasoning was sound and only the conclusion was
   unavailable: **the macOS build never registered.** `altool` returned
   `UPLOAD SUCCEEDED with no errors` with a delivery UUID, and 2.5 hours later
   `/v1/builds` shows only the iOS one. The iOS build from the *same* release
   processed fine, so this is specific to the Mac package. **Apple emails the
   account holder when a build fails processing** — that message is the only
   place the reason exists.

### Previously (2026-08-28): macOS is one button from submission

| | |
| :--- | :--- |
| Account, agreements, EU trader status, bank | ✅ done |
| Pricing **$1.49**, 175 countries, Public/discoverable | ✅ done |
| Categories, content rights, age rating **4+**, App Privacy (published) | ✅ done |
| macOS version **0.6.8**, `PREPARE_FOR_SUBMISSION` | ✅ |
| Description, keywords, promo text, support URL | ✅ pushed via API |
| **5 screenshots**, all exactly 1280×800, `COMPLETE` | ✅ uploaded |
| `.pkg` build+sign lane, **Apple-validated** (`VERIFY SUCCEEDED with no errors`) | ✅ |
| Build **uploaded** to App Store Connect (2026-08-28) | ✅ `UPLOAD SUCCEEDED with no errors` |
| **Build attached to the version** | ⏳ waiting on Apple's processing |
| Export compliance, *Add for Review*, *Manually release* | ⛔ **human only** |
| iOS | ⛔ separate track, does not block macOS |

### Previously (2026-08-28): the three steps to submit macOS, before any of it was automated

All three of these are now inside the tooling — the runbook has the current
sequence. They are recorded because the shape of the sequence did not change,
only who performs it.

**1. Upload the build:**

```bash
gh workflow run mas-release.yml --ref main -f mode=upload
```

Puts a build in App Store Connect and **submits nothing**. Modes are
`dry-run` (build only) / `validate` (ask Apple if it would accept it) / `upload`.

**2. Attach it and set the review notes** — one dispatch, once Apple's processing
finishes (a build is not attachable until `processingState` is `VALID`):

```bash
gh workflow run asc-version.yml --ref main -f platform=MAC_OS -f mode=apply -f notes=true
```

Run it with `-f mode=report` first; that changes nothing and prints the build
list. It refuses to touch a version that is not in an editable state.

**3. In App Store Connect, by hand** — three things that were deliberately
outside the tooling at the time: answer **export compliance** on the build, press
*Add for Review*, and choose **"Manually release this version"**. The first is
now answered by `Info.plist`, the second by `asc-submit-review.yml`, and the
third is set at version creation. Only the final **Release** press is still a
human act.

### Previously (2026-08-28): the engine RUNS; signing was what was left

The signing half is solved — see the stored identity above. The engine facts held
and are the reason the iOS lane exists at all:

- **The archive is linked into the app.** Three build settings on all three
  Runner configurations do it — two sdk-conditional `OTHER_LDFLAGS` carrying
  CoreFoundation, Security, libresolv and a `-force_load`, plus
  `STRIP_STYLE = non-global`. No `project.pbxproj` file-reference surgery: a
  `-force_load` of an absolute path needs none, and it settles dead-stripping too.
- **Dart resolves from the process.** `librcloneIsStaticallyLinked('ios')` →
  empty path sentinel → `DynamicLibrary.process()`.
  `librcloneLibraryAvailable()` replaces the `File(...).existsSync()` probes.
- **A real local pane.** Locations seeds exactly the container's `Documents`,
  which `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` expose as
  the Files app's *On My iPhone → Airclone*. `/` is not offered and the **+**
  button is hidden — `file_selector` has no `getDirectoryPath` on iOS.
- **Two workflows.** [`ios-verify.yml`](../.github/workflows/ios-verify.yml)
  builds for the simulator, checks the symbols per architecture, then installs,
  launches and screenshots the app — and fails if it is not running.
  [`ios-release.yml`](../.github/workflows/ios-release.yml) is the TestFlight
  lane; its **`dry-run` needs no Apple credential** and exists to prove the
  DEVICE slice links, which the simulator job cannot tell you.

**Proven 2026-08-28**, on CI, with no hardware: the Release *device* archive keeps
all four exports (`ios-release.yml -f mode=dry-run`, no Apple credential needed),
and the Debug simulator build launches and reaches `EnginePhase.ready` - which the
screenshot shows, because the UI renders `EngineGate` until it does.

The remaining gap at the time was an **Apple Distribution certificate and an iOS
App Store profile** — the Mac certs (`3rd Party Mac Developer *`) do not cover
iOS — plus `UIDocumentPicker`, so a file can be pulled in from elsewhere in
Files. The first is done; the second is still open. See
`dev/plans/apple-appstore-plan.md` Gate C2 and Gate D.
