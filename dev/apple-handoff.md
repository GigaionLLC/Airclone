# Apple App Store — session handoff

Where the Apple track stands, what to do next, and the traps that already cost
time. Written 2026-08-21. **Value-free by design** — real IDs, key paths and
account state live in the encrypted vault (`python tool/vault.py unlock`, then
`dev/vault/notes/apple-appstore-setup-record.md`).

## State: macOS is one button from submission

Working tree clean, everything pushed to `main` (head `e17002f`).

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

## iOS: librclone builds, nothing else does

`dev/ios/build-librclone-ios.sh` + `librclone-ios.yml` produce a working
xcframework — device **and** simulator slices, all four FFI symbols exported.
The simulator slice was expected to be blocked by golang/go#57442; the
`-target …-simulator` triple works on the current toolchain.

**It does not run yet.** Still ahead: link the archive into the Runner target,
`DynamicLibrary.process()` instead of `open()`, the linker flags Go does not apply
for `c-archive` (`-framework CoreFoundation -framework Security -lresolv`), and a
local-file-access redesign for a platform with no arbitrary filesystem. See
`dev/plans/apple-appstore-plan.md` Gate C2.

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
gh workflow run librclone-ios.yml --ref main
python tool/check-docs.py            # must be 0 broken before committing
cd app && flutter analyze && flutter test
```

Signing certs and the provisioning profile **expire 2027-08-20**. The lane breaks
silently when they lapse.
