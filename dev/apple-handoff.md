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
| **Build attached to the version** | ⛔ **NOT YET — this is the next step** |
| iOS | ⛔ separate track, does not block macOS |

## Next: three steps to submit macOS

**1. Upload the build** — outward-facing, so a human triggers it:

```bash
gh workflow run mas-release.yml --ref main -f mode=upload
```

Puts a build in App Store Connect and **submits nothing**. Modes are
`dry-run` (build only) / `validate` (ask Apple if it would accept it) / `upload`.

**2. Attach it** to version 0.6.8 once Apple finishes processing (minutes). Check
state with the ASC API or the console.

**3. In App Store Connect** — the reviewer notes and copyright are in
[`docs/store/apple/listing-en-US.md`](../docs/store/apple/listing-en-US.md); set
**Sign-in required: NO**, then *Add for Review* and
**"Manually release this version"** so approval and publication stay separate.

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

## iOS: linked, and a lane written; still a separate track

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

Still ahead: `validate`/`upload` need an **Apple Distribution certificate and an
iOS App Store profile** — the Mac certs (`3rd Party Mac Developer *`) do not
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

**`nm -gU` means "undefined only" here, not "defined only".** `-gU` reported all
four Go symbols missing from a binary whose link line demonstrably carried
`-force_load`. Use bare **`nm -g`** and match ` T _symbol$`, the shape the
archive check had been using correctly all along. A verification step that is
wrong in the *pessimistic* direction costs as many runs as one that is wrong in
the optimistic direction — it just feels more responsible while doing it.

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
