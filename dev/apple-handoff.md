# Apple App Store — session handoff

Where the Apple track stands, what to do next, and the traps that already cost
time. Written 2026-08-21, updated 2026-08-28. **Value-free by design** — real
IDs, key paths and account state live in the encrypted vault
(`python tool/vault.py unlock`, then
`dev/vault/notes/apple-appstore-setup-record.md`).

## State: macOS is one button from submission

Working tree clean, everything pushed to `main`.

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

## Next: three steps to submit macOS

**1. Upload the build** — DONE 2026-08-28:

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

**3. In App Store Connect, by hand** — three things, all deliberately outside the
tooling: answer **export compliance** on the build (a legal declaration — see
below), press *Add for Review*, and choose **"Manually release this version"** so
approval and publication stay separate.

## Rules that are not negotiable here

- **No machine presses submit or release.** On the Microsoft Store a machine was
  allowed to commit a submission and published this app at **$0**, unstoppable
  once started. See AGENT.md rules 10–13.
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

## iOS: the engine RUNS; signing is what is left

Done since the first version of this note:

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

**The iOS lane WORKS, with no stored certificate (2026-08-28).**
`ios-release.yml -f mode=validate -f signing=ephemeral` mints a distribution
certificate through the Certificates API, signs, exports a 57 MB `.ipa`, gets
`VERIFY SUCCEEDED with no errors` from Apple, and revokes the certificate on the
way out. Nothing long-lived is stored.

Both automatic-signing routes were tried first and both are dead ends, so do not
retry them: an iOS *development* profile needs a **registered device** and this
team has none, and `exportArchive` gives **"Cloud signing permission error"** for
distribution with an App Manager key - the same answer macOS gave.

The `signing=secrets` path still exists and needs an **Apple Distribution
certificate and an iOS App Store profile** — the Mac certs (`3rd Party Mac Developer *`) do not
cover iOS. The Certificates API can mint them with the existing App Manager key.
And `UIDocumentPicker`, so a file can be pulled in from elsewhere in Files.
See `dev/plans/apple-appstore-plan.md` Gate C2 and Gate D.

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

Signing certs and the provisioning profile **expire 2027-08-20**. The lane breaks
silently when they lapse.
