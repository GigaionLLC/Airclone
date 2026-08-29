# 🍎 Apple App Store plan — iOS + Mac App Store

## 📊 State Dashboard
| Metric | Value |
| :--- | :--- |
| **Status** | `PROPOSED — awaiting review, nothing executed` |
| **Version** | `v1.0.0` |
| **Last Updated** | 2026-08-16 |
| **Price target** | **$1.49**, matching Microsoft Store and Google Play |
| **Long pole** | Not the account work — **a build Apple will accept** (see Gate C) |

This plan is ordered the way **Apple** forces the work, not the way we would choose it. Each gate
below is blocked by the one before it. Every console URL you will need is inline, so this doc can be
driven top-to-bottom in a browser.

> **Nothing in this plan has been executed.** One thing is *staged but not submitted*: the
> "Request Access to the App Store Connect API" dialog has its agreement checkbox ticked and is
> waiting on a human to press **Submit** (Gate B1). Cancel it if you would rather start clean.

---

## 1️⃣ Verified current state (checked 2026-08-16, not assumed)

| Thing | State | Where |
| :--- | :--- | :--- |
| Apple Developer Program, Gigaion, LLC | ✅ Active | [developer.apple.com/account](https://developer.apple.com/account) |
| App ID `com.gigaionllc.airclone` | ✅ Registered | [Identifiers](https://developer.apple.com/account/resources/identifiers/list) |
| ASC app record **Airclone** (Apple ID `6790176897`) | ✅ Exists — iOS 1.0 **and** macOS 1.0, both *Prepare for Submission* | [App record](https://appstoreconnect.apple.com/apps/6790176897/distribution) |
| Developer ID Application + Installer certs | ✅ Valid to 2031 — these power today's **direct-download** DMG | [Certificates](https://developer.apple.com/account/resources/certificates/list) |
| Free Apps Agreement | ✅ Active | [Business](https://appstoreconnect.apple.com/business) |
| U.S. Form W-9 | ✅ Active | [Business](https://appstoreconnect.apple.com/business) |
| **Paid Apps Agreement** | ⛔ **Pending User Info** — no bank account on file | [Business](https://appstoreconnect.apple.com/business) |
| **EU trader status (DSA)** | ⛔ Not declared | [App Information](https://appstoreconnect.apple.com/apps/6790176897/distribution/info) → *Digital Services Act* |
| **App Store Connect API access** | ⛔ Never requested (no keys can exist yet) | [Integrations → API](https://appstoreconnect.apple.com/access/integrations/api) |
| Apple Distribution / Mac Installer Distribution certs | ⛔ Absent — **App Store signing is not possible today** | [Certificates](https://developer.apple.com/account/resources/certificates/list) |
| Price, availability, category, age rating, privacy | ⛔ All unset | [Pricing](https://appstoreconnect.apple.com/apps/6790176897/distribution/pricing) |
| **An iOS or Mac-App-Store build** | ⛔ **Does not exist** | see Gate C |

Two pieces of good news that shorten the work considerably:

- **`FfiRcloneClient` already ships.** The in-process librclone engine is built, bundled and
  released on macOS today — `release.yml` builds a universal `librclone.dylib` and drops it into
  `Airclone.app/Contents/Frameworks` before codesign. The engine half of the Mac App Store problem
  is already solved and in production.
- **`EngineMode.resolveEngineMode` already has the MAS/iOS branch.** `subprocessAllowed: false`
  forces `inProcess` regardless of user setting. The seam anticipated this.

---

## 2️⃣ Gate A — Legal and financial (Apple blocks *everything* commercial on these)

**These are yours to do. I cannot and will not enter banking or tax details.**

### A1. Add a bank account → Paid Apps Agreement goes Active
🔗 <https://appstoreconnect.apple.com/business>

The Paid Apps Agreement sits at *Pending User Info* purely because no bank account exists; the W-9
is already Active. **Until this is Active the price field will not hold a non-zero value**, so a
$1.49 listing is impossible. Do this early — it is the item with the longest external latency
(bank verification is days, not minutes).

### A2. Declare EU trader status (Digital Services Act)
🔗 [App Information → App Store Regulations & Permits → Digital Services Act → **Set Up**](https://appstoreconnect.apple.com/apps/6790176897/distribution/info)

Apple's own banner: *"Developers must provide their trader status to submit new apps."* This is a
legal declaration about Gigaion, LLC plus **publicly displayed** trader contact information, and
Apple verifies it. Selling a paid app makes you a trader.

⚠️ The contact details you enter here are **shown on the public listing in the EU**. Use a business
address and a business email you are content to publish — and per
[`AGENT.md`](../../AGENT.md), whatever you enter stays out of this repo.

### A3. Decide the App Store price
🔗 <https://appstoreconnect.apple.com/apps/6790176897/distribution/pricing>

Apple's global pricing has a **$1.49** point, so the cross-store price is achievable exactly. Two
notes specific to Apple:

- The price is set **once for the app record and applies to both iOS and macOS** — you cannot price
  the Mac version differently without a separate app record.
- Tax Category is already *App Store software*. Correct; leave it.

Also on this page and worth an explicit decision — **App Distribution Methods** defaults to
*"Public — Discoverable by anyone on the App Store."* Confirm it stays Public. This is the exact
setting that was silently wrong on the Microsoft Store and capped discovery from launch.

---

## 3️⃣ Gate B — Credentials for automation

### B1. Request App Store Connect API access
🔗 <https://appstoreconnect.apple.com/access/integrations/api>

One-time, free, org-wide. The dialog is currently **staged with its checkbox ticked** — it needs a
human to press **Submit** because it is an agreement ("use the API for internal development,
testing, and reporting within your team only"). Access is granted immediately; no waiting.

### B2. Generate a Team Key
Same page, after B1. Role: **App Manager** (enough to upload builds and manage versions; *not*
Admin, which would let a CI secret manage users and agreements — the same reasoning that put the
Microsoft CI credential on Developer rather than Manager).

The key yields three values:

| Value | Where it goes | Sensitivity |
| :--- | :--- | :--- |
| Issuer ID | repo/org **variable** `APPSTORE_ISSUER_ID` | low |
| Key ID | repo/org **variable** `APPSTORE_API_KEY_ID` | low |
| `AuthKey_XXXX.p8` | org **secret** `APPSTORE_API_PRIVATE_KEY` | **download-once, never recoverable** |

⚠️ **The .p8 downloads exactly once.** Apple will not show it again; losing it means revoking and
reissuing. Save it before closing the page.
🔗 Secrets go to <https://github.com/organizations/GigaionLLC/settings/secrets/actions>

### B3. App Store signing certificates — let CI create them
No Apple Distribution or Mac Installer Distribution certificate exists yet. Rather than minting
these by hand (which needs a Mac and a CSR), `xcodebuild -allowProvisioningUpdates` with the ASC API
key creates and fetches both certificates and provisioning profiles automatically on the runner.
This is the documented path for a solo maintainer and avoids fastlane `match` entirely.

Fallback if automatic signing fights us: create them manually at
🔗 <https://developer.apple.com/account/resources/certificates/add> — but try automatic first.

---

## 4️⃣ Gate C — A build Apple will accept ← **the real work**

This is where the schedule lives. Everything above is a few hours of forms; this is engineering.

### C1. Mac App Store (recommended first — weeks closer than iOS)

| # | Work | Why Apple forces it |
| :-- | :--- | :--- |
| 1 | **App Sandbox ON** | Mandatory for MAS. Both `DebugProfile.entitlements` and `Release.entitlements` currently set `com.apple.security.app-sandbox` to `false`, with comments explaining why — those comments describe the *direct-download* build and stay true for it. MAS needs a **separate** entitlements file, not an edit to the existing one. |
| 2 | **Force the in-process engine** | A sandboxed app may only exec code bundled and signed at build time, and an `inherit`-sandboxed child cannot receive the parent's security-scoped folder grants. `resolveEngineMode(subprocessAllowed: false)` already handles this; the MAS build must pass `subprocessAllowed: false` and compile out the spawn path. |
| 3 | **Security-scoped bookmarks** | The sandbox denies `dart:io` access to arbitrary paths. Local browsing needs an `NSOpenPanel` grant, a persisted bookmark, and `startAccessingSecurityScopedResource` on resolve. **This does not exist** — `state/bookmarks_controller.dart` is Airclone's *favourites* feature, an unrelated thing with a colliding name. New platform channel + Dart plumbing, and every local path read must route through it. |
| 4 | **Hide subprocess-only features** | OS mount (FUSE is impossible in the sandbox), the command console (`core/command` re-execs rclone), and archive create/extract (spawns the `rclone archive` CLI). All must be absent from the UI, not merely disabled. |
| 5 | **MAS export + installer signing** | `xcodebuild -exportArchive` with `method: app-store`, signed by Apple Distribution, packaged by Mac Installer Distribution. |

**Feature-parity consequence, stated plainly:** the Mac App Store build is a *strictly smaller* app
than the DMG — no mount, no console, no archive operations. That is inherent to the sandbox, not a
shortcut. The DMG remains the full-featured build and should keep being recommended for power users.
This needs to be reflected in the listing copy so a buyer is not surprised.

### C2. iOS (after macOS)

Everything in C1 plus:

| # | Work | Risk |
| :-- | :--- | :--- |
| 6 | **librclone for iOS** — `GOOS=ios GOARCH=arm64 -buildmode=c-archive`, packaged as an `.xcframework`. `dev/desktop/build-librclone.sh` only emits `c-shared` for darwin/linux/windows today. | **Off-road, but proven.** See the corrected assessment below. |
| 7 | ~~**FFI must resolve from the process**~~ — **DONE 2026-08-28.** `librcloneIsStaticallyLinked('ios')` makes `defaultLibrclonePath()` return the empty sentinel and the worker takes `DynamicLibrary.process()`. `librcloneLibraryAvailable()` replaces the three `File(...).existsSync()` probes, which would otherwise report "not bundled in this build" on the one platform where the engine is *always* present. | ✅ |
| 8 | **File-access model redesign** — **first cut done 2026-08-28.** The Locations sidebar seeds exactly one entry on iOS, the container's `Documents`, and `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` make that the Files app's *On My iPhone → Airclone*, so it is a shared folder rather than a private hole. `/` is no longer offered and the **+ button is hidden** — `file_selector` has no `getDirectoryPath` on iOS, so it would have thrown. Still open: pulling in a file the user picks elsewhere in Files (`UIDocumentPicker`). | 🟡 usable |
| 9 | **Info.plist keys** — `NSCameraUsageDescription` and `NSFaceIDUsageDescription` **added 2026-08-28**; both dependencies are real (`mobile_scanner` for Offline-QR import, `local_auth` behind `biometric_unlock.dart`), so the strings describe what the app actually does. `ITSAppUsesNonExemptEncryption` is deliberately **absent** — see the note below. | ✅ |
| 10 | **Plugin sweep on device** | The dependency set is largely iOS-capable (`media_kit`, `pdfrx`, `mobile_scanner`, `file_selector`, `local_auth`, `super_drag_and_drop`). `flutter_acrylic` and `desktop_multi_window` are desktop-only and already `Platform`-guarded. Verify, don't assume. |

**RESULT (2026-08-21): librclone BUILDS for iOS.** Both slices, on a CI Mac, with
no hardware:

```
== iphoneos arm64 ==          platform 2   (PLATFORM_IOS)
== iphonesimulator arm64 ==   platform 7   (PLATFORM_IOSSIMULATOR)
xcframework successfully written out
_RcloneInitialize / _RcloneFinalize / _RcloneRPC / _RcloneFreeString  all exported
```

The **simulator slice worked**, which the research expected to be blocked:
golang/go#57442 is still open, and Go stamps simulator archives as device
binaries. The community `-target arm64-apple-ios13.0-simulator` fix produced a
correct `platform 7` stamp on the current toolchain. The trimmed wrapper and the
`storj.io/common` patch both worked first time.

**IT RUNS (2026-08-28).** `ios-verify.yml` installed the app on a booted
simulator, launched it, and screenshotted the Home view:

```
the engine is linked into: Runner.app/Runner.debug.dylib
-- x86_64 --   _RcloneInitialize/_RcloneFinalize/_RcloneRPC/_RcloneFreeString defined
-- arm64 --    (same)
the app is still running after the run window
```

The screenshot is the load-bearing part. `_MobileFiles` renders `EngineGate`
unless `engine.phase == EnginePhase.ready`, and the capture shows the ordinary
Files view - *This phone / On My Device / Cloud* - so the engine reached **ready**.
That means `DynamicLibrary.process()` resolved all four symbols, `RcloneInitialize`
ran, and `config/setpath` succeeded against the app-private config. rclone's
author's warning ("until it tries to link it with the wrong linker") is answered.

It also shows the iOS local pane working as designed: one seeded location, the
container's Documents, and no **+** beside it.

Build: [`dev/ios/build-librclone-ios.sh`](../ios/build-librclone-ios.sh) via
[`librclone-ios.yml`](../../.github/workflows/librclone-ios.yml).

**INTEGRATION (2026-08-28): the archive is now wired into the app.** Three build
settings on all three Runner configurations, and nothing else — no `project.pbxproj`
file-reference surgery, because a `-force_load` of an absolute path needs none:

```
"OTHER_LDFLAGS[sdk=iphoneos*]"        = -framework CoreFoundation -framework Security -lresolv
                                        -Wl,-u,_RcloneInitialize  (and the other three)
                                        -force_load $(SRCROOT)/librclone/device/librclone.a
"OTHER_LDFLAGS[sdk=iphonesimulator*]" = ...  -force_load $(SRCROOT)/librclone/simulator/librclone.a
STRIP_STYLE                           = non-global
```

**`-force_load` is not enough on its own.** The link carries `-dead_strip`, and
nothing in the app references the Go exports — they exist only to be looked up at
runtime — so the linker loads the archive and then throws it away again. The four
`-Wl,-u,_Rclone*` flags name each symbol as required, which makes it a
dead-strip root. This applies to **Debug and Release alike**: an early reading
that the Debug dylib was immune, because dylibs export their globals, was
contradicted by the next run and is recorded here only so nobody re-derives it.

Those two paths are **stable by construction**, written by the build script, and deliberately not
into the `.xcframework`: xcodebuild names the slice directories itself, and `ios-arm64-simulator`
becomes `ios-arm64_x86_64-simulator` the moment a second architecture appears. The xcframework is
still produced — it is the portable form, and creating it validates the platform stamps — but
nothing in this repo links against it.

**A Debug app bundle is two Mach-Os.** Xcode 16+ builds Debug with
`ENABLE_DEBUG_DYLIB = YES`: the code lands in `Runner.debug.dylib` and `Runner`
is a launcher stub. Nothing is wrong with that — `DynamicLibrary.process()` still
resolves, because the dylib is loaded into the same process — but a symbol check
pointed at `Runner` reports the engine missing from a perfectly good build. Scan
the bundle. Release has no debug dylib.

**The simulator archive must be FAT (arm64 + x86_64).** `flutter build ios --simulator` always emits
a universal binary, and `-force_load` of an archive that lacks an architecture is only a *warning*:
the link succeeds, that slice silently contains no engine, and the first sign of trouble is symbols
that are simply not in the binary. This is exactly how the first integration run failed — a green
build over an empty binary.

`-force_load` also settles the dead-stripping problem: nothing in Swift references
the Go exports, so without it the linker would drop the archive members and leave
`dlsym` with nothing to find. The conditional form matters — a plain
`OTHER_LDFLAGS` would be *replaced*, not merged, whenever an `[sdk=...]` variant
matches, so both variants carry the full list rather than relying on the
unconditional one.

**PROVEN 2026-08-28 (Release, device):** `ios-release.yml -f mode=dry-run` archives a
Release App Store build for `generic/platform=iOS` and finds all four exports intact:

```
Runner  (67552944 bytes, archs: arm64)
   0000000101aa0890 T _RcloneFinalize      0000000101aa0844 T _RcloneInitialize
   0000000101aa0940 T _RcloneFreeString    0000000101aa08dc T _RcloneRPC
```

That is the configuration that ships: `-dead_strip` on, strip phase run,
no debug dylib. It needs no Apple credential, so it is the cheapest way to check
the engine survives a real archive.

Proof is [`ios-verify.yml`](../../.github/workflows/ios-verify.yml), which builds
for the simulator, asserts the four symbols survive into the linked binary, then
installs, launches and screenshots the app. Three different failures live between
"the archive builds" and "the engine answers", and only running it tells them
apart: the link (Go omits its own `//go:cgo_ldflag` for `c-archive`), the strip
(Release removes all symbols by default) and the runtime lookup.

**`ITSAppUsesNonExemptEncryption` is deliberately NOT set — this one is yours.**
Setting it to `false` would be a US export-control declaration made by a machine
on the LLC's behalf, and it would very likely be *wrong*: Airclone encrypts the
user's rclone config with a passphrase, which is data confidentiality, not the
HTTPS-only case the exemption is usually claimed for. Leaving the key out means
App Store Connect asks at upload time and a human answers. That is the correct
place for it. The likely honest answer is "yes, uses encryption" plus the
mass-market 5D992 exemption, which carries an annual self-classification report
to BIS — worth deciding once, deliberately, rather than defaulting.

**CORRECTION (researched 2026-08-18).** An earlier draft of this plan said rclone upstream
ships gomobile bindings covering iOS. **That was wrong.** Upstream's gomobile binding is
Android-only; `librclone/README.md` says merely *"iOS has not been tested (but should
probably work)"*. rclone **disabled** its iOS builds in 2021 (issue #5124, still open), and
PR #5919, which added iOS support, was **closed unmerged in June 2026**.

The good news is stronger than the bad: **two apps ship rclone embedded on iOS today**, and
one publishes its whole recipe.

- **Rclone GUI** (App Store, MPL-2.0, [VitalysRDT/rclone-gui-ios](https://github.com/VitalysRDT/rclone-gui-ios))
  builds an `RcloneKit.xcframework` from **stock, unpatched rclone v1.74.3**. Its
  `scripts/build-rclone.sh` is a working reference for the whole sequence: per-slice
  `gomobile bind`, then `clang -dynamiclib -force_load`, then `dsymutil`, then
  `xcodebuild -create-xcframework`.
- **S3Drive** (App Store) is **Flutter + librclone** — our exact stack.

Four specifics that change the build, all found by research rather than guessed:

1. **Do not build the stock `librclone` package.** It imports `cmd/mount`, `cmd/cmount` and
   `cmd/mount2`. On `ios/arm64` all three fall to rclone's own `*_unsupported.go` stubs, but
   on **`ios/amd64` (Intel simulator) `cmd/mount2` is REAL** (`linux || (darwin && amd64)`)
   and drags in go-fuse and cobra. Build a ~30-line wrapper package importing only
   `backend/all`, `fs/operations` and **`fs/sync`**.
2. **`fs/sync` is not optional.** Upstream's own gomobile binding omits it — and
   `transfer_service.dart` dispatches `sync/copy`/`sync/move`, so taking that binding
   verbatim would silently lose every directory transfer.
3. **The arm64 simulator slice is blocked by an open Go bug** ([golang/go#57442](https://github.com/golang/go/issues/57442)):
   the archive is stamped as a device binary and `create-xcframework` rejects it. Device-only
   first; simulator is its own mini-project. This weakens the simulator-screenshot plan in
   Gate E — macOS screenshots are unaffected.
4. **`storj.io/common` needs a one-file patch** — a `go:linkname` into the Go runtime that
   breaks the c-archive relink. Storj is a stock rclone backend, so we will hit it.

**The warning that matters most for us:** S3Drive, also Flutter + librclone, shipped an iOS
build that **froze its UI thread** once more than one rclone operation ran. Go declined to
add a `GOMAXPROCS` knob for gomobile ([golang/go#65603](https://github.com/golang/go/issues/65603),
closed as not planned); they fixed it in app code by dispatching off the UI thread. Airclone
already runs librclone on a worker isolate, which should help — but this must be tested
under real concurrent load, not assumed.

**The linker facts that cost people the most time** (verified against the Go 1.26 source, not
folklore):

- **`c-shared` is not supported on iOS at all** — `c-archive` is the only option, and
  `ios/arm64` additionally *requires* `CGO_ENABLED=1` at the toolchain level.
- **Go does NOT apply its own `//go:cgo_ldflag` directives for `c-archive`.** It skips the
  host link entirely and just `ar`-packs the objects, so the framework references stay
  undefined. **The Xcode target must add `-framework CoreFoundation -framework Security
  -lresolv`** — Security because modern Go reaches the system trust store through it, so
  every HTTPS call depends on it.
- **Use a separate `GOCACHE` per target.** A shared cache silently poisons a simulator
  archive with device-tagged artifacts.
- **Set the xcframework to "Do Not Embed"**, or App Store Connect rejects the bundle with an
  invalid-bundle-structure error.
- **Drop `-fembed-bitcode`** from any recipe copied from the internet, including gomobile's
  own still-present code. Bitcode was removed in Xcode 16.

Also required on the Xcode side: `STRIP_STYLE = Non-Global Symbols` (Release strips all
symbols by default and would remove the Go exports), and `-force_load` on the archive so the
linker does not drop a library nothing in Swift references.

The UI itself is the *least* of it — the phone shell built for Android (`MobileHomeScreen`, the `+`
FAB and bottom sheets) carries over, and iPad gets the desktop layout for free via the existing
700px width gate.

**Targets today:** `TARGETED_DEVICE_FAMILY = "1,2"` (iPhone **and** iPad) and
`IPHONEOS_DEPLOYMENT_TARGET = 13.0`. iPad support means **iPad screenshots are mandatory** — see
Gate E. Dropping to iPhone-only is a legitimate way to halve the screenshot and QA burden for a
first submission.

### C3. How we test without a Mac — and where Xcode Cloud actually fits

**GitHub Actions `macos-latest` runners are real Macs, and they are free for public repos.**
`GigaionLLC/Airclone` is public, and `release.yml` already builds, signs and notarizes macOS there
every release. We are not short of Mac *compute*.

What we lack is **interactive** use — clicking around, seeing the UI, debugging a hang.
**Xcode Cloud does not solve that either.** It is CI, not a remote desktop; it gives builds, test
runs and TestFlight distribution, all of which GitHub Actions already gives us with the toolchain we
maintain.

| Option | Interactive? | Cost | Verdict |
| :--- | :--- | :--- | :--- |
| GitHub Actions macOS runner | No | Free (public repo) | **Use this.** Already wired. |
| iOS Simulator on that runner, driven by `xcrun simctl` + screenshots | No, but *visual* | Free | **Use this** — the blind-but-verified loop, same pattern as the Windows `uidrive.ps1` rig |
| Xcode Cloud | No | 25 compute-h/mo free, **paid above** | Skip. Duplicates what we have and adds a bill. |
| TestFlight on a real iPhone/iPad | **Yes** | Free (needs a device) | Best interactive option if you have any iOS device |
| Rented cloud Mac | Yes | **Paid** | Only if a MacBook stays out of reach |

**Recommendation:** skip Xcode Cloud. Build on GH Actions, verify visually with simulator
screenshots, and get interactive coverage from TestFlight on a real device — then move to a MacBook
when one arrives. Revisit Xcode Cloud only if we exhaust GH runner minutes, and note its free tier is
25 compute-hours/month.

🔗 Xcode Cloud, if we ever do reconsider: App Store Connect → any app → **Xcode Cloud**.
(The direct URL embeds the team UUID, which is also the `APPSTORE_ISSUER_ID` — a PRIVATE
value, so it is not written here. It is in the vault.)

---

## 5️⃣ Gate D — Upload lanes (mirroring Play and Microsoft)

The shape you asked for maps onto Apple cleanly, and Apple gives us a **third** safety gate for free:

| Stage | Trigger | Equivalent |
| :--- | :--- | :--- |
| Tag push → build → **TestFlight** | Automatic | Play "open testing" |
| **Submit for App Review** | Manual workflow-dispatch | `promote-play.yml` |
| **Release after approval** | Human button in ASC — *"Manually release this version"* | (no Microsoft/Play equivalent) |

That last one deserves emphasis: on the version page, choosing **"Manually release this version"**
means even an *approved* build sits and waits. Approval and publication are separate events. Given
what a committed submission did on the Microsoft Store, this setting should be non-negotiable.

**As built (2026-08-28):** two dispatch-only lanes, one per platform, rather than the single
`submit-appstore.yml` sketched here — the signing story differs enough between them that one
workflow with a platform switch would have been mostly branches.

| Lane | Modes | State |
| :--- | :--- | :--- |
| [`mas-release.yml`](../../.github/workflows/mas-release.yml) | `dry-run` / `validate` / `upload` | ✅ Apple-validated |
| [`ios-release.yml`](../../.github/workflows/ios-release.yml) | `dry-run` / `validate` / `upload` | 🟡 written; `dry-run` needs no secret, `validate`/`upload` need the certs below |

`ios-release.yml`'s **`dry-run` deliberately requires no Apple credential at all**: it archives with
`CODE_SIGNING_ALLOWED=NO` purely to prove the DEVICE slice links and keeps its Go symbols, which the
simulator job cannot tell you. It is the cheapest possible check of the thing most likely to break.

**SOLVED 2026-08-28 — no secret needed at all.** `signing=ephemeral` mints the
certificate and profile through the Certificates API inside the job, signs,
exports, and revokes the certificate in an `always()` step. Apple validated the
result: `VERIFY SUCCEEDED with no errors` on a 57 MB `.ipa`.

Two routes were tried before this and both are dead ends worth not repeating:

| Attempt | Apple's answer |
| :--- | :--- |
| archive as `Apple Development`, automatic | *"Your team has no devices from which to generate a provisioning profile"* — iOS dev profiles need a registered device; macOS ones do not |
| archive unsigned, export automatic | *"Cloud signing permission error"*, *"No signing certificate 'iOS Distribution' found"* — the same limit macOS hit |

The stored-p12 path below still works and remains the default; it is simply no
longer the only way in.

Still needed before `validate` works, because the Mac certificates (`3rd Party Mac Developer *`) do
not cover iOS:

| Secret / variable | What |
| :--- | :--- |
| `APPLE_IOS_DIST_P12_BASE64` | an **Apple Distribution** certificate + key, as a base64 `.p12` |
| `APPLE_IOS_P12_PASSWORD` | its export password |
| `APPLE_IOS_PROVISIONING_PROFILE_BASE64` | an **iOS App Store** profile for `com.gigaionllc.airclone` |
| `APPLE_IOS_PROFILE_NAME` *(var, optional)* | the profile's name if it is not `Airclone iOS App Store` |

The Certificates API can mint the certificate with the existing App Manager key — that is how the Mac
pair was created, after Xcode's cloud signing refused. See §3e of the vault record.

- ~~**New:** `submit-appstore.yml`~~ — superseded by the two lanes above.
- **Extend:** `release.yml` — `ios`/`mas` jobs uploading to TestFlight via
  `apple-actions/upload-testflight-build`, gated on `APPSTORE_API_PRIVATE_KEY` existing so nothing
  changes until the secret lands (exactly how the Play lane was introduced).
- **Verify by artifact** (AGENT.md rule 9): after upload, query the ASC API and assert the build
  number CI just produced is actually visible in TestFlight. A green upload step is not evidence.

**TestFlight caveat:** *internal* testing (your own team, up to 100 people) needs no review and is
instant. *External* testing needs a Beta App Review per build stream. Auto-to-internal is genuinely
automatic; auto-to-external is not, and no CI can change that.

🔗 TestFlight: <https://appstoreconnect.apple.com/apps/6790176897/testflight/ios>

---

## 6️⃣ Gate E — Listing metadata and screenshots

**Screenshot sizes CONFIRMED on CI 2026-08-28** — the runner's simulators produce
Apple's required sizes natively, so nothing is rescaled or cropped:

| Simulator | Native capture | Apple's requirement |
| :--- | :--- | :--- |
| iPhone 17 Pro Max | **1320 x 2868** | 6.9" — exact |
| iPad Pro 13-inch (M5) | **2064 x 2752** | 13" — exact |

The Mac rig had to set a display mode, pin a window and centre-crop to hit
1280x800. `xcrun simctl io screenshot` just gives the right pixels.
[`ios-screenshots.yml`](../../.github/workflows/ios-screenshots.yml) has a
`diagnose` mode that reports this, because simulator device names change with
Xcode and finding that out 20 minutes into a capture is expensive.

Copy lives in the repo, not in a browser tab:
[`listing-en-US.md`](../../docs/store/apple/listing-en-US.md) for macOS and
[`listing-ios-en-US.md`](../../docs/store/apple/listing-ios-en-US.md) for iOS.
Both are pushed by [`tool/asc_listing.py`](../../tool/asc_listing.py), so the
console cannot drift from the document that justifies each decision.

Apple will not accept **Add for Review** until every one of these is filled. All live under the app
record; the per-platform pages are separate and both must be completed if both platforms ship.

🔗 App Information: <https://appstoreconnect.apple.com/apps/6790176897/distribution/info>
🔗 iOS version: <https://appstoreconnect.apple.com/apps/6790176897/distribution/ios/version/inflight>
🔗 macOS version: <https://appstoreconnect.apple.com/apps/6790176897/distribution/macos/version/inflight>
🔗 App Privacy: <https://appstoreconnect.apple.com/apps/6790176897/distribution/privacy>

### E1. Once, for the whole record
- **Primary category** — *Utilities*, with *Productivity* secondary. (*Developer Tools* is tempting
  and wrong; it hurts discovery for a file manager.)
- **Content rights** — declare no third-party content.
- **Age rating** questionnaire → will land at 4+.
- **App Privacy** — Airclone collects nothing. "Data Not Collected" is the honest answer and matches
  [`PRIVACY.md`](../../PRIVACY.md) and the no-telemetry stance.
- **App Encryption Documentation** — the app does use non-Apple crypto (rclone's config encryption,
  crypt remotes, our Argon2id QR sealing). The exemption that applies is **publicly available /
  open-source cryptography**; declare it rather than leaving the questionnaire to ambush every
  upload. Setting `ITSAppUsesNonExemptEncryption` in `Info.plist` answers it at build time.

### E2. Per platform, per version
Description (4,000), Promotional Text (170), Keywords (100), Support URL, Marketing URL, Copyright
(200), Version, and App Review notes.

⚠️ Two copy rules this repo already learned the hard way, both in
[`docs/store/README.md`](../../docs/store/README.md):
- **Never claim the app is "free" or "no paywall"** in store copy — the store build is paid.
- **Never point a reviewer at the command console.** It cost review cycles on the Microsoft Store
  when our own tester notes cited a command the console blocks. On MAS/iOS the console is absent
  anyway, so the notes must not mention it at all.

Add a third, Apple-specific: **the rclone non-affiliation line must be present**, or the listing
risks a trademark/impersonation rejection.

### E3. Screenshots — exact requirements

Apple validates dimensions strictly and rejects off-by-one sizes.

| Platform | Size accepted | Count | How to capture |
| :--- | :--- | :--- | :--- |
| **Mac** | **1280×800**, 1440×900, 2560×1600, or 2880×1800 | up to 10 (**ship 5–6**) | macOS runner in CI, or a MacBook when one arrives |
| **iPhone 6.5"** | 1242×2688, 2688×1242, 1284×2778, or 2778×1284 | up to 10 (**ship 5–6**) | iOS Simulator — `xcrun simctl io booted screenshot` gives exact device pixels for free |
| **iPad** | 13" / 12.9" sizes, only because `TARGETED_DEVICE_FAMILY = "1,2"` | up to 10 (**ship 3–4**) | Simulator, same method — or drop iPad support and skip entirely |

**Proposed shot list** (reusing the `D:\AircloneDemo` alias-remote demo data and the CC0 media
already vetted in [`docs/store/play/DEMO-MEDIA-PROVENANCE.md`](../../docs/store/play/DEMO-MEDIA-PROVENANCE.md)):

1. **Dual-pane explorer**, cloud remote on one side, local on the other — the hero shot
2. **Photo gallery grid** with real thumbnails — the feature a Play reviewer complained about
3. **A transfer in flight**, jobs dock showing speed and ETA
4. **Add-remote wizard**, provider picker open — shows breadth of providers
5. **Media preview** — image or video open
6. *(Mac only)* **Home view** with the native macOS skin

⚠️ **Google rejected a screenshot from this project as "placeholder images or stock photos"** when it
showed gradient tiles named `IMG_0100.jpg…`. Every Apple screenshot must use the restocked real
media, and none may show synthetic gradients.

⚠️ **A MAS screenshot must not show mount, console, or archive** — features the sandboxed build does
not have. A screenshot of a feature the shipped binary lacks is a straightforward rejection.

**Storage convention:** follow the established layout —
`docs/store/apple/{mac,iphone-6.5,ipad-13}/` with a `store-ready/` subfolder and a `MANIFEST.md`
recording what each shot is and why, exactly as `docs/store/play/` does.

---

## 7️⃣ Gate F — Submit, review, release

1. Build lands in TestFlight (automatic on tag).
2. Attach the build to the version, fill review notes, **Add for Review**.
3. Set **"Manually release this version"** — always.
4. Review takes ~24–48h typically. Rejections arrive as a message thread in ASC; reply there.
5. On approval, press **Release** deliberately.

🔗 Submission status and reviewer messages: <https://appstoreconnect.apple.com/apps/6790176897/distribution>

**Anticipated review friction, worth pre-empting in the notes:**
- *"What does this app do without an account?"* — Airclone is a client for the user's own storage;
  there is nothing to sign into. Say so, and set *Sign-in required* to **off**.
- **Guideline 4.7 / 2.5.2 (executing code)** — the sandboxed builds ship no console and spawn no
  binaries; the engine is statically linked. Being explicit here heads off a whole category of
  question.
- **Guideline 2.1 (completeness)** — the reviewer needs a remote to browse. Consider a short note
  explaining they can add any provider, or supply a throwaway read-only remote.

---

## 8️⃣ Risks and unknowns, ranked

| Risk | Severity | Mitigation |
| :--- | :--- | :--- |
| **librclone will not link for iOS** in this repo's pinned configuration | **Medium** (was High) | Two shipping App Store apps prove it works, and one publishes its build script. The compile is the easy half — rclone's author: *"until it tries to link it with the wrong linker"*. Spike on a `macos-latest` runner; it needs no Mac and no device. |
| **Sandbox breaks local file access** in ways not visible until a device runs it | **High** | Build MAS early and test on a real Mac; this is the failure most likely to be invisible in CI |
| No interactive Mac for debugging | Medium | Simulator screenshots + TestFlight on a device; MacBook when available |
| Paid Apps Agreement latency | Medium | Start A1 **now** — it is the longest external wait in the plan |
| iOS file-access redesign is larger than it looks | Medium | Ship macOS first; let it de-risk the sandbox work |
| Apple rejects on feature parity between MAS and DMG | Low | Listing copy states plainly what the store build does |

---

## 9️⃣ Recommended sequence

**Now, in parallel:**
- **You:** A1 bank account, A2 trader status, B1 Submit the staged API-access dialog.
- **Me:** the librclone-for-iOS spike (C2.6) — the single highest-uncertainty item, and it needs no
  account access at all.

**Then:** B2 API key + secrets → C1 Mac App Store build → D upload lanes → E metadata and
screenshots → F submit **macOS first**.

**iOS follows**, once the sandbox work has proven itself on macOS and the librclone spike has
answered whether iOS is weeks or months away.

---

## 🔟 Decisions I need from you

1. **macOS first, or both together?** I recommend macOS first — it is far closer, and it de-risks
   iOS.
2. **Keep iPad support?** Dropping to iPhone-only removes a whole screenshot set and a QA surface
   for the first submission. iPad can be added in any later version.
3. **Xcode Cloud** — I recommend skipping it (GH Actions already gives us Macs, free). Confirm.
4. **MAS feature parity** — confirm you are content shipping a Mac App Store build without mount,
   console, or archive, with the DMG remaining the full build.
5. **Do you have any iOS device** for TestFlight? It changes how blind the iOS work has to be.

## See also
- [`dev/apple-appstore-and-macos.md`](../apple-appstore-and-macos.md) — the LIVE direct-download
  macOS path, and the pre-existing "do not attempt yet" verdict this plan supersedes.
- [`dev/plans/dual-engine-plan.md`](dual-engine-plan.md) — the librclone/FFI engine this depends on.
- [`dev/plans/store-automation-plan.md`](store-automation-plan.md) — where the Apple CI lanes were
  first scoped.
- [`docs/store/README.md`](../../docs/store/README.md) — pricing policy and the pre-submission truth
  audit that applies to every store.
- [`dev/msstore-ci-setup.md`](../msstore-ci-setup.md) — what went wrong on the Microsoft Store, and
  why the manual-release gate matters.
