# Airclone in-app self-update — design

> Status: **part built** (2026-09-14). Owner: Airclone maintainers. Target: v0.14.x.
>
> | Stage | State |
> |---|---|
> | CI publishes a manifest | **done** - `release.yml` job `checksums`; signs it when `MINISIGN_SECRET_KEY` exists |
> | The signing key itself | **NOT done, and a person's job** - [`../update/signing-key-setup.md`](../update/signing-key-setup.md) |
> | Trust primitives | **done** - `update/minisign.dart`, `sums.dart`, `version_compare.dart`, `update_trust.dart` |
> | Gates | **done** - `update/self_update_target.dart` (store channel + package) |
> | Download and verify | **done** - `update/update_fetch.dart`, tested against a server that lies eight ways |
> | Install: AppImage | **done** - `update/install_appimage.dart`, tested on Linux CI |
> | Install: Windows installer | **done** - `update/install_windows.dart`; the silent flags are tested, a real install is not |
> | Install: tar.gz, portable zip, macOS app | **not built** - each needs a helper process to swap a tree the running app is inside; they download, verify, and say where the file is |
> | UI | **done** - Settings -> Updates, and only when a key AND a replaceable package are both present |
>
> Nothing is user-visible until the key exists: with no key `kCanVerifyUpdates` is false and every
> build behaves exactly as it does today.
> Supersedes nothing; extends the existing update check in `app/lib/src/state/app_info.dart`.
> Related: `dev/backlog/hardening-audit-2026-07-15.md` H-10, `dev/plans/flathub-plan.md`, `dev/plans/apple-appstore-plan.md`.

---

## 1. The decision

Airclone gains a **manual, button-driven, verify-then-install updater that exists only in direct-download desktop builds**. At release time CI publishes one `SHA256SUMS` manifest covering every release asset plus a detached **minisign (Ed25519) signature** of that manifest; the app embeds the public key via `--dart-define` from a CI repo variable, verifies the signature *before* it trusts any hash, verifies the streamed download's SHA-256 against the verified manifest, and then — on Windows and macOS only — additionally verifies the operating system's own code signature (Authenticode / Developer ID + stapled notarization ticket) on the artifact it is about to execute. Install is per-package: the Inno installer runs itself silently, the portable zip and the Linux tar.gz are swapped by the freshly-verified copy of Airclone running from a staging directory, the AppImage is renamed over in place, and the macOS `.app` is swapped by the new app's own binary (which is signed by the same Team ID, satisfying macOS App Management). **What was rejected:** Sparkle/WinSparkle via `auto_updater` (no Linux, 22 months stale, two separate key systems, and the private key rides in a bare file on Windows); `desktop_updater` (native code on three platforms plus a .NET wrapper, and it depends on `cryptography_plus`, a fork of the `cryptography` Airclone already ships — two copies of the same primitives); Velopack/Squirrel (their trust model is a SHA-256 from an unsigned feed — the maintainer says so in velopack#975 — and Velopack's "wait 60s then kill the app" is a data-integrity event for a file manager mid-transfer); zsync/AppImageUpdate as the mechanism (a delightful delta protocol, but it means shelling out to a tool the user may not have, and it moves verification outside our control); signing each artifact separately (one signed manifest gives filename→hash binding for free, which is Syncthing's cross-platform-substitution defence, at one signing step instead of nine); and relying on Authenticode/Gatekeeper *alone* (Linux has no equivalent at all, Windows signing is conditional on `vars.WINDOWS_SIGNING_ENABLED`, and macOS notarization in `release.yml` is deliberately `continue-on-error`).

---

## 2. The verification chain

### 2.1 What is published at release time

`release.yml` gains one job, `checksums`, which runs `needs: [windows, linux, macos, android]` and therefore after every `gh release upload --clobber` (including the macOS job's second, stapled upload of `airclone-macos.zip`). It **re-downloads the assets from the release**, not from workflow artifacts — the v0.5.0–v0.5.2 lesson is that a green check is not evidence; only the bytes a user would get are.

| File | Contents | Signed by |
|---|---|---|
| `SHA256SUMS` | one `<sha256hex>  <asset-name>` line per release asset, `sha256sum` format (two spaces) | — (it is the signed payload) |
| `SHA256SUMS.minisig` | minisign detached signature, prehashed variant (`ED`), trusted comment `airclone <tag> <ISO-8601 date>` | release key |
| `SHA256SUMS.minisig.2` | present **only during a key rotation window**: the same manifest signed with the other key | the other release key |

The trusted comment is part of the signed payload (minisign's global signature covers `signature_bytes ‖ trusted_comment_text`), so the **version is signed**. This is the one thing Sparkle-without-`SURequireSignedFeed`, Tauri's `latest.json` and electron-updater's `latest.yml` all get wrong: an artifact signature proves *we built this*, not *this is current*. Binding the tag into the signed comment plus a strict monotonic-version rule in the client is what closes replay.

Unchanged and still load-bearing:

* Windows: `airclone.exe`, the bundled `rclone.exe` and `airclone-setup-x64.exe` are Authenticode-signed by Azure Artifact Signing when `vars.WINDOWS_SIGNING_ENABLED == 'true'` (release.yml:316–365). The portable zip is created **after** signing, so its contents are signed even though the zip itself cannot be.
* macOS: `Airclone.app` and `airclone-macos.dmg` are Developer-ID signed, notarized and stapled (release.yml:783–908). Notarization is best-effort; the `.dmg` **only exists when it succeeded**.
* Linux: nothing OS-level exists. minisign is the entire provenance story there, which is precisely why it is mandatory rather than additive.

### 2.2 What the app checks, in order

Implemented as `Future<VerifiedUpdate> resolveAndVerify(...)` in a new `app/lib/src/update/update_verifier.dart`. Every step is fail-closed; there is no "could not check, proceeding".

1. **Store gate.** `await ref.watch(installSourceProvider.future)`; if `source.managedByStore` → `StoreManagedUpdates`, return, **no network call**. (§4.)
2. **Package gate.** `selfUpdateTargetFor(...)` → `SelfUpdateTarget`. `unsupported` means the rest of this list never runs; the UI shows today's "Open release" button only.
3. **Resolve the release.** `GET https://api.github.com/repos/$kUpdateRepo/releases/latest`, read `tag_name`. Compare with `PackageInfo.version` using a new `compareAppVersions()` (real semver, prerelease-aware) — **not** today's `!tag.contains(current)`, which reports `0.9.1` as up-to-date against `v0.9.10` (app_info.dart:93). Not strictly newer → "up to date", stop.
4. **Preflight, before any large download.** Probe writability by *attempting* it — create and delete a temp file in the install directory **and its parent** (you need the parent to rename over a child). Never read permission bits: that is the mydia bug, which reported a read-only Flatpak `/app` as writable and burned 60 MB before crashing. Also check free space ≥ 3× the expected asset size. Failure → refuse now, with the reason, and offer "Open release".
5. **Fetch the manifest.** `GET …/releases/download/<tag>/SHA256SUMS` (hard cap 1 MiB, 30 s connect / 5 min total) and `SHA256SUMS.minisig` (cap 16 KiB). Either fetch failing → refuse.
6. **Parse the signature.** Exactly 4 lines; line 2 base64-decodes to exactly 74 bytes; algorithm `ED` (prehashed) or `Ed`; **key id must equal the id of one trusted key** (`kUpdatePublicKey`, `kUpdatePublicKeyNext`). Anything else → refuse. If `SHA256SUMS.minisig.2` exists, each `(signature, key)` pair is tried and any one passing is enough.
7. **Verify the signature over the manifest.** `ED`: Ed25519 over `BLAKE2b-512(manifest bytes)`. `Ed`: Ed25519 over the raw bytes. Then verify the **global** signature over `signature_bytes ‖ trusted_comment`. Both must pass. `Ed25519.verify()` **throws** `StateError`/`ArgumentError` on a wrong-length key or signature rather than returning false — every call site wraps in `try/catch` and a throw means *refused*, never *accepted*.
8. **Bind the version.** Parse the verified trusted comment; require the tag in it to equal the tag from step 3 **and** to be strictly newer than the running version. A genuinely-signed older manifest replayed by a stale mirror or a hostile cache is refused here.
9. **Look up the asset hash** for the exact asset filename for this target (`airclone-setup-x64.exe`, `airclone-windows-x64.zip`, `airclone-macos.dmg`, `Airclone-x86_64.AppImage`, `airclone-linux-x64.tar.gz`) in the **verified manifest text**, by exact name. Missing → refuse. Never "any matching hash in the file": the by-name lookup *is* the cross-platform-substitution defence, and `app/test/update_verifier_test.dart` pins it with a manifest that contains a valid hash for the wrong platform's asset.
10. **Stream and hash in one pass.** Write to `<staging>/<asset>.part`, feeding `sha256.startChunkedConversion` as bytes arrive. Abort mid-stream the moment `received > 512 MiB` or `received > contentLength`. Hashing runs off the UI isolate (`Isolate.run`) — 92 MiB measured at 645 ms AOT, ~39 dropped frames if it ran on the UI thread.
11. **Compare.** Digest ≠ manifest entry → delete the `.part`, refuse.
12. **Commit the file.** `rename('<asset>.part', '<asset>')` after `flush: true`. The rename is the commit point; a partially-written file never wears the real name.
13. **OS signature check**, on the exact file just committed and on nothing else (no re-resolving paths between verify and use):
    * **Windows** — `WinVerifyTrust` with `WINTRUST_ACTION_GENERIC_VERIFY_V2`, `dwUIChoice = WTD_UI_NONE`, `fdwRevocationChecks = WTD_REVOKE_WHOLECHAIN`, then, *between* `WTD_STATEACTION_VERIFY` and the mandatory `WTD_STATEACTION_CLOSE`, walk `WTHelperProvDataFromStateData` → `WTHelperGetProvSignerFromChain` → `WTHelperGetProvCertFromChain` and compare the signer **subject** against the pin (§5). `ERROR_SUCCESS` alone is not authenticity — it is satisfied by anyone holding a $200 OV certificate. Hand-written `dart:ffi` bindings to `wintrust.dll`; `package:win32` has no wintrust coverage. Model on `packages/airclone_rc/lib/src/windows_child_job_io.dart` but **invert its error policy**: that class swallows everything by design; this one refuses on any error. The `CLOSE` call goes in a `finally`.
    * **macOS** — `codesign --verify --deep --strict --verbose=2` on the staged `.app` (`--deep` is correct for *verifying*; Quinn's "--deep considered harmful" is about signing), then the Sparkle continuity check (§5), then `xcrun stapler validate`. Never `codesign --check-notarization` — the man page says it forces an **online** check.
    * **Linux** — none exists. Steps 5–12 are the whole chain.
14. **Install** per §3.

**Every failure**, at every step: delete everything staged, `logDiagnostic(DiagLevel.error, 'update', '<stage> failed', detail: …)` naming the stage (fetch / parse / signature / version / hash / os-signature / install), show one honest sentence in the UI, and leave "Open release" reachable. Support can then tell a TLS-inspecting corporate proxy apart from an attack, which is impossible if every failure reads "update failed".

### 2.3 What this protects against — and what it does not

**Protects against:** a hostile or intercepting network, including one that can forge TLS; a compromised CDN, mirror or cache serving swapped bytes; a corrupted or truncated download; *replay* of an older but genuinely-signed release (step 8); serving one platform's genuine artifact in place of another's (step 9); and, on Windows and macOS, an artifact that is not signed by the identity that ships Airclone (step 13).

**Does not protect against:** an attacker who already has **write access to the installed binary** — they can patch out the embedded public key, and `--dart-define` values sit in the AOT binary as plaintext (verified by grep). Authenticode and notarization are the layers that cover that, and only partly. It does not protect against a **simultaneous compromise of the GitHub release and the signing key**, which share one origin. It does not stop a **freeze attack**: an adversary who can withhold the manifest can hold you on your current version indefinitely, and no offline check can tell "there is no update" from "you are not being shown one". It does not make the *installer's* privileged actions safe — a verified installer still runs with whatever privileges it inherits. And it says nothing about certificate **revocation** on macOS: `codesign --verify` validates against local anchors, so offline verification proves "signed by us at build time", not "still trusted today".

---

## 3. Per-package install flow

The running-process problem is the same everywhere and has exactly three shapes: *a process can rename its own image but not overwrite it* (Windows), *a process keeps its inode alive across a rename of the name* (POSIX), and *the swapper must not be the thing being swapped*.

Common to all: the engine is stopped first (`state.client?.quit()`), which also lets `WindowsChildJob`'s `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` reap `rclone.exe` children — the same orphaned-`rcd` problem that failed Store certification in v0.5.4. Staging always lives on the **same volume** as the target, never in `$TMPDIR` (which is frequently `noexec`, and a cross-volume rename is not atomic).

### 3.1 Windows — Inno installer (`SelfUpdateTarget.windowsInstaller`)

Detected by `windowsInstallerPresent()` (`unins000.exe` beside the exe), already in `build_kind.dart:92`.

1. Stage + verify `airclone-setup-x64.exe` into `<app support>/updates/<tag>/`.
2. `Process.start(setupPath, ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/RESTARTAPPLICATIONS', '/LOG=<diagnostics dir>\\update-<tag>.log'], mode: ProcessStartMode.detached)`.
3. **Do not exit first, and do not call `WindowsChildJob.adopt()` on this process.** `airclone.iss:61` sets `CloseApplications=force`, so Setup terminates Airclone itself via Restart Manager. Adopting it into the job would kill Setup the instant it killed us, leaving `{app}` half-replaced. A comment saying exactly this goes at the spawn site.
4. Do **not** pass `/ALLUSERS` or `/CURRENTUSER`: `UsePreviousPrivileges` (default `yes`) reads the registry, reuses the existing install mode, and self-elevates for a per-machine install in Program Files. The UI warns that a UAC prompt may appear for those installs.
5. **Restart.** `airclone.iss:82` carries `skipifsilent` on its `[Run]` entry and `RestartApplications=no`, so a silent update would close Airclone and never bring it back. Two changes fix this together: the app calls `RegisterApplicationRestart(nullptr, 0)` at startup on Windows (omitting `RESTART_NO_PATCH`, so update-driven restarts are permitted), and the updater passes `/RESTARTAPPLICATIONS`. Caveat, stated in the UI: the OS only restarts a process that has been running ≥ 60 s.
6. Exit codes are mapped, not lumped: `0` success; `2`/`5` user cancelled (not an error, no failure card); `1`/`3`/`4` install failure; `7` Setup cannot proceed; `8` same plus a reboot is needed. Unknown codes are reported as-is with the log path.

### 3.2 Windows — portable zip (`SelfUpdateTarget.windowsPortable`)

No uninstaller, no registered location, and a Flutter release tree holds `flutter_windows.dll`, every plugin DLL and `rclone.exe` open. Per-file rename-then-replace across dozens of files has no clean rollback point, so the swap is done by a **separate process running from the new tree** — and that process is the new Airclone itself, so no extra binary has to be built or signed.

1. Stage + verify `airclone-windows-x64.zip`; extract to `<parentOfInstallDir>\.airclone-update-<tag>\` (same volume).
2. Authenticode-verify `<staging>\airclone.exe` (§2.2 step 13). The zip cannot carry a signature; its contents can.
3. Write `<staging>\update.json` = `{ "target": "<installDir>", "waitPid": <pid>, "fromVersion": "...", "toVersion": "..." }`.
4. `Process.start('<staging>\\airclone.exe', ['--apply-update'], mode: detached)`; **not** adopted into the job object. Then quit the app cleanly (stop the engine, flush state).
5. The staged process (headless path, `app/lib/src/headless/`) waits for `waitPid` to exit (poll `OpenProcess`, 60 s cap), then:
   `rename(installDir, installDir + '.old-<fromVersion>')` → `createDirectory(installDir)` → **copy** the staging tree into it → `Process.start('<installDir>\\airclone.exe', [], mode: detached)` → exit.
   Copy, not rename, because the swapper's own image lives inside the staging directory and renaming a directory that contains a running executable is not reliably permitted on Windows.
6. **Rollback:** if the copy fails at any point, delete the partial `installDir`, rename `.old-<v>` back, and launch it. The user is never left without a working Airclone.
7. **Sweep on next launch:** the new build deletes `*.old-*` and `.airclone-update-*` beside itself, once, at startup.

### 3.3 macOS — `.app` bundle (`SelfUpdateTarget.macAppBundle`)

1. Refuse up front and offer the DMG instead when: the bundle path contains `/AppTranslocation/` (translocated — read-only random path, no supported detection API beyond the path, and self-update can never work until the user moves the app); the bundle sits on a read-only mount or inside a mounted `.dmg`; or the Sparkle authorization test says escalation is needed — `!(writable(bundlePath) && writable(parent))`, **or** a probe file cannot be `chown`ed to the bundle's owner/group (a `.pkg`-installed bundle is `root:wheel`). **Airclone does not escalate.** A privileged installer is a permanent attack surface for a file manager, and Sparkle — the most-reviewed implementation in existence — still shipped GHSA-g3hp-f6mg-559v.
2. Prefer `airclone-macos.dmg`; fall back to `airclone-macos.zip` when the manifest has no dmg entry (notarization is `continue-on-error`, so a release legitimately ships without one).
3. Stage into `<parentOfApp>/.airclone-update-<tag>/` (same volume — `renamex_np` requires it), `hdiutil attach -nobrowse -readonly -noautoopen`, `ditto` the app out, `hdiutil detach`.
4. Verify at the **final staged path** (§2.2 step 13) and never re-copy afterwards — that is the TOCTOU window.
5. `xattr -d -r com.apple.quarantine <staged>.app`, recursively, failures non-fatal but logged. Do this even though Dart's HTTP client sets no quarantine: Ventura 13.1+ surprised developers by applying it anyway, and the consequence is a Gatekeeper prompt or a permanently un-updatable translocated app.
6. Hand off to `<staged>/Airclone.app/Contents/MacOS/airclone --apply-update`. **This is what satisfies macOS 13+ App Management**: the swapper is signed with the same Team ID as the app it modifies, so no TCC prompt, no `NSUpdateSecurityPolicy` key, no Full Disk Access. A shell script driving `mv` would be blocked with an EPERM your Dart code only sees as a failed rename.
7. The swapper waits for the parent PID, then `renamex_np(installPath, stagedPath, RENAME_SWAP)` via a tiny `DynamicLibrary.process().lookupFunction` binding, falling back to move-aside/move-in/rollback when `RENAME_SWAP` is unavailable. Before the swap it copies the old bundle's owner/group onto the new one and touches its mtime (LaunchServices re-registration).
8. `/usr/bin/gktool scan <installPath>` when macOS ≥ 14.4, then `open -n <installPath>` and exit. Without the `gktool` pre-warm the cdhash change guarantees a "Verifying…" dialog on an update the user already approved. macOS 15 removed the Control-click → Open escape hatch, so a botched swap is expensive — the rollback path is not optional.

### 3.4 Linux — AppImage (`SelfUpdateTarget.linuxAppImage`)

1. Target is `HostPlatform.environment['APPIMAGE']` — the absolute path of the running image. **Never `Platform.resolvedExecutable`**, which under an AppImage resolves into the ephemeral `/tmp/.mount_*` FUSE mount: a different inode that vanishes on exit. `APPIMAGE` absent (an `--appimage-extract-and-run` launch, or a scrubbed environment) → `unsupported`, not tar.gz.
2. Stage to `<dirOf($APPIMAGE)>/.airclone-update-<tag>.part` — the same directory, never `/tmp` (`noexec`). Verify. `chmod` to the current image's mode.
3. `fsync` the file, hardlink the old image aside as `<name>.old`, `rename()` the staged file over `$APPIMAGE`, `fsync` the directory.
4. **Keep the filename byte-identical.** Desktop integration (`appimaged`, AppImageLauncher) writes an absolute `Exec=` into `~/.local/share/applications/`. Appending a version — which electron-updater does by default — strands the menu entry, the dock pin and every file association.
5. `Process.start(appimagePath, [], mode: detached)` and exit. The running instance keeps the old inode alive through the FUSE mount until it goes away.
6. Sweep `<name>.old` on the next successful launch.

### 3.5 Linux — tar.gz (`SelfUpdateTarget.linuxTarGz`)

Same state machine as the Windows portable zip, with POSIX mechanics. The replaceable unit is the **whole bundle directory**: `dev/linux/build-appimage.sh:26` records that a Flutter Linux app resolves `data/` and `lib/` relative to its own binary, and flattening yields "Failed to load AOT snapshot".

1. Stage + verify `airclone-linux-x64.tar.gz`; extract to `<installDir>.new-<tag>` (sibling, same volume).
2. `Process.start('<staging>/airclone', ['--apply-update'], mode: detached)` after writing `update.json`, then exit.
3. The swapper waits for the parent, then two atomic renames: `rename(installDir, installDir + '.old-<v>')`, `rename(staging, installDir)`. Unlike Windows, a POSIX rename of a directory containing the running executable is fine — inodes, not paths. Roll back by renaming `.old-<v>` into place if the second rename fails.
4. Relaunch a **stable** path: `~/.local/bin/airclone` if it exists and resolves into the install, else `<installDir>/airclone`. Not `Platform.resolvedExecutable`, which after the swap still points into the directory just renamed aside.
5. **Never rewrite files under a live bundle.** Flutter opens `data/flutter_assets` lazily by path; mutating the running directory faults a session in ways that look like random asset corruption. Swap the directory, never its contents.
6. Sweep `.old-*` on next launch.

---

## 4. What is refused, and where the gate lives

Gates are layered so that no single bug reaches a download. Outermost first.

| # | Gate | File | Refuses |
|---|---|---|---|
| 1 | `InstallSource.managedByStore` (`channel != directDownload`) | `app/lib/src/state/install_source.dart:92`, consumed at `app/lib/src/state/app_info.dart:79` | Microsoft Store, Google Play, Amazon Appstore, F-Droid, Galaxy Store, App Store, **Mac App Store**, Flathub, Snap Store — **before any network call**. Not "the button is hidden": the request never happens. MS Store policy 10.2.5 failed v0.6.0 over a mere link. |
| 2 | `sealed class UpdateStatus` | `app/lib/src/state/app_info.dart:23` | Structural: every consumer must handle `StoreManagedUpdates` exhaustively. The install affordance hangs **only** off the `ReleaseUpdateInfo` arm. Adding a third subclass or a non-exhaustive `switch` would silently remove this. |
| 3 | `kMacAppStoreBuild`, `kFlathubChannel` | `app/lib/src/state/build_flavor.dart:30,73` | Compile-time. The MAS build must not *contain* the updater (Guideline 2.4.5(vii)); `bool.fromEnvironment` const-folds the branch and it is tree-shaken out, exactly as the subprocess-spawn path already is. The whole `update/` surface sits behind `if (!kMacAppStoreBuild)`. |
| 4 | `kUpdatePublicKey.isEmpty` | new `app/lib/src/update/update_trust.dart` | Any build with no key configured. Self-update is simply absent; the check and "Open release" behave exactly as today. |
| 5 | `selfUpdateTargetFor(...)` → `unsupported` | new `app/lib/src/state/self_update_target.dart` | **MSIX** (also caught by gate 1); **Flatpak release bundle** — `linuxInstallSource()` correctly calls it `directDownload` (it updates from the releases page), but `/app` is read-only and it physically cannot apply an update, so it must be its own case saying "download the new bundle and `flatpak install` it"; **Snap**; **AppImage launched without `$APPIMAGE`**; **Android and iOS**, always; **web**. |
| 6 | Headless entry points | `app/lib/src/headless/headless_runner.dart` | `--run-due` and `--run-task` must never reach an updater. There is no user to press a button, and a scheduled backup is not consent. Only `--apply-update` participates, and it installs nothing it has not been handed by a verified parent. |
| 7 | Preflight writability probe | `update_installer.dart` | Root-owned `/opt/airclone`, Program Files without elevation, read-only mounts, immutable attributes. Attempted-write probe, never a mode-bit read. **No privilege escalation is ever attempted** on any platform. |

Gate 5 deliberately does **not** consume the display strings from `build_kind.dart` — parsing `'Flatpak (release bundle)'` would be fragile. Instead `self_update_target.dart` mirrors its pure, environment-injected shape, and `app/test/self_update_target_test.dart` is a **table test over the same five Linux environments** asserting that `linuxBuildKind(env)` and `linuxSelfUpdateTarget(env)` agree, so the two cannot drift silently.

---

## 5. The fork story

Airclone is AGPLv3 and expects forks. The endpoint and the key are **a pair**: a fork that repoints one and not the other gets either a confusing hard failure or silent insecurity. They are declared side by side, with a comment saying so.

`app/lib/src/update/update_trust.dart` — all `const`, because `String.fromEnvironment` on a non-`const` `final` silently yields `''` (flutter/flutter#59110):

| Define | Default | Meaning |
|---|---|---|
| `AIRCLONE_UPDATE_REPO` | `GigaionLLC/Airclone` | `owner/repo` for the releases API and asset URLs. Also replaces the hardcoded `_kReleasesUrl` in `app_info.dart:67`. |
| `AIRCLONE_UPDATE_PUBKEY` | `''` | minisign public key, the full `RWQ…` line-2 form. Empty ⇒ **self-update disabled**, fail-closed. |
| `AIRCLONE_UPDATE_PUBKEY_NEXT` | `''` | Second accepted key, for rotation windows only. |
| `AIRCLONE_UPDATE_WIN_PUBLISHER` | `''` | Expected Authenticode signer subject. Empty ⇒ pin by **continuity**: the downloaded installer's signer subject must equal the running `airclone.exe`'s own signer subject. |
| `AIRCLONE_UPDATE_MAC_TEAM_ID` | `''` | Expected Team ID. Empty ⇒ pin by continuity: `SecCodeCopyDesignatedRequirement` on the running app, checked against the staged bundle. |

CI passes these from **repository variables** (`vars.*`), never secrets — define values are plaintext in the AOT binary (verified by grep), and a verification key is public by construction. This mirrors the existing `vars.WINDOWS_SIGNING_ENABLED` / `vars.MSIX_IDENTITY_NAME` idiom.

**What a fork changes:** generate a keypair (`minisign -G -p airclone.pub -s airclone.key`), set `vars.AIRCLONE_UPDATE_PUBKEY` to the `RWQ…` line from `airclone.pub`, set `vars.AIRCLONE_UPDATE_REPO` to their own `owner/repo`, put the secret key in their own environment secret, and — if they sign Windows or macOS with their own identity — either leave the publisher/Team-ID defines empty (continuity does the right thing automatically for a consistently self-signed fork) or set them explicitly.

**Failure behaviours, all fail-closed and all logged to `state/diagnostics.dart`:**

* **Key missing** (`AIRCLONE_UPDATE_PUBKEY == ''`) → no download path is built at all; the UI is today's check-and-link. Not "no key, so skip verification".
* **Key malformed** → validated at **startup**, not at download time: base64-decodes to 42 bytes, prefix `Ed`. A typo'd repo variable is discovered on first launch of a CI build, not by a user six weeks later. `DiagLevel.error`, and self-update stays off.
* **Repo overridden, key not** → a loud startup diagnostic (`update key is missing but the update repository was overridden — self-update is off`) and self-update off. This is the fork that would otherwise point at its own host while trusting upstream's key.
* **Key does not match the signature** (wrong key id, or a verify failure) → refuse, never install, and say so in one sentence (§6). This is also what an upstream user of a fork's build sees, which is the correct outcome.
* **Running build unsigned, publisher/Team pin unresolvable** → the Windows-installer and macOS paths refuse with "this copy of Airclone isn't signed, so Airclone can't check who built the update" and fall back to "Open release". Hash + minisign alone are not accepted as a substitute for the OS check on platforms that have one.

The first 8 characters of the embedded key id are printed in the diagnostics report (`state/diagnostics.dart`), so a stale-`--dart-define`-cache build is identifiable from a user report. Any release job that changes these defines runs `flutter clean` first — defines do not reliably invalidate cached artifacts, especially through Xcode.

---

## 6. The UI

One place, the place users already look: **Settings → Storage & updates → Updates**, i.e. `_UpdatesSection` / `_UpdateResult` in `app/lib/src/ui/settings_screen.dart:2551–2694`. The shape is copied from `_EngineVersionSection` (settings_screen.dart:1533–1688), which is already exactly the interaction the product owner described: a row, a `TextButton`, and — only after a check finds something — a `FilledButton.icon`.

**Nothing runs at launch. Nothing runs in the background. There is no timer, no interval setting, and no "check automatically" toggle to forget to default to off.** `Check for updates` calls `ref.invalidate(updateCheckProvider)` first, so a second press in the same session actually re-checks (today it silently returns the cached result).

States, and the exact copy:

| State | Row |
|---|---|
| Idle | `Airclone 0.13.6` … `[Check for updates]` |
| Checking | spinner + `Checking…` |
| Up to date | ✓ `You're up to date` |
| Store-managed | 🏪 `Airclone updates through the Microsoft Store.` `[Open the Microsoft Store]` *(unchanged)* |
| Update available, installable | ⬆ `v0.14.0 available` … `[Download and install]` + secondary `Open release` |
| Update available, package can't self-update | ⬆ `v0.14.0 available` — `This copy of Airclone can't replace itself. Open the release page to download the new one.` `[Open release]` |
| Downloading | progress bar + `Downloading v0.14.0 — 41 MB of 92 MB` |
| Verifying | spinner + `Checking the download is really from Airclone…` |
| Ready (Windows installer) | `Ready to install. Airclone will close, update, and reopen.` `[Install now]` |
| Ready (other targets) | `Ready to install. Airclone will close and reopen.` `[Install now]` |
| Installing | spinner + `Installing… don't close Airclone.` |
| Verification refused | ⚠ `Airclone couldn't verify this download, so it wasn't installed. Nothing on your computer was changed.` + `Details are in Settings → Diagnostics.` `[Open release]` |
| Install failed | ⚠ `The update didn't finish, and Airclone was put back the way it was.` `[Open release]` |
| Can't write | ⚠ `Airclone can't update itself here — it doesn't have permission to write to <path>. Download the new version and replace it yourself.` `[Open release]` |
| Elevation expected (Windows per-machine) | note under the button: `Windows will ask for permission, because Airclone is installed for everyone on this PC.` |
| Flatpak release bundle | `This Flatpak can't update itself. Download the new bundle and install it with flatpak install.` `[Open release]` |
| Translocated macOS app | `Move Airclone to your Applications folder first — macOS is running it from a read-only copy.` |

Rules the copy follows: never the word "signature", "checksum", "hash", "minisign" or "Authenticode" in the UI (all of them in the diagnostics log); never blame the user; always say whether anything was changed; always leave a manual route out. And before the first install, the user is told plainly what will happen — a silent background download-and-execute is both the malware shape AV heuristics look for and the thing users are most upset to discover after the fact.

A first-run note ships in `dev/releases/<tag>.md` and the UI's release row for Windows: a freshly signed installer shows a SmartScreen prompt for the first weeks and several hundred installs — EV certificates no longer bypass this, and there is no consumer submission mechanism. Tell early adopters to check the publisher name in the prompt rather than to click through.

---

## 7. CI changes

### 7.1 New job in `.github/workflows/release.yml`

```yaml
  checksums:
    needs: [windows, linux, macos, android]
    if: ${{ !cancelled() && startsWith(github.ref, 'refs/tags/') }}
    runs-on: ubuntu-latest
    environment: release-signing          # required reviewers; scopes the key
    steps:
      - uses: actions/checkout@v5
      - name: Install minisign
        run: sudo apt-get update && sudo apt-get install -y minisign
      - name: Download every published asset
        env: { GH_TOKEN: "${{ secrets.GITHUB_TOKEN }}" }
        run: |
          set -euo pipefail
          mkdir assets && cd assets
          # From the RELEASE, not from workflow artifacts: only the bytes a user
          # would actually get are evidence. (v0.5.0-v0.5.2 lesson.)
          gh release download "$GITHUB_REF_NAME" --repo "$GITHUB_REPOSITORY" --pattern '*'
          sha256sum * > ../SHA256SUMS
      - name: Sign the manifest
        env:
          MINISIGN_SECRET_KEY: ${{ secrets.MINISIGN_SECRET_KEY }}       # base64 of airclone.key
          MINISIGN_PASSWORD:   ${{ secrets.MINISIGN_PASSWORD }}
        run: |
          set -euo pipefail
          umask 077
          echo "$MINISIGN_SECRET_KEY" | base64 -d > "$RUNNER_TEMP/airclone.key"
          echo "$MINISIGN_PASSWORD" | minisign -S -s "$RUNNER_TEMP/airclone.key" \
            -m SHA256SUMS \
            -t "airclone $GITHUB_REF_NAME $(date -u +%Y-%m-%dT%H:%M:%SZ)"
          shred -u "$RUNNER_TEMP/airclone.key"
      - name: Upload manifest + signature
        env: { GH_TOKEN: "${{ secrets.GITHUB_TOKEN }}" }
        run: |
          gh release upload "$GITHUB_REF_NAME" SHA256SUMS SHA256SUMS.minisig \
            --clobber --repo "$GITHUB_REPOSITORY"

  verify-release:
    needs: checksums
    runs-on: ubuntu-latest        # NO continue-on-error. This job may fail the release.
    steps:
      - name: Verify what the release actually serves
        env: { GH_TOKEN: "${{ secrets.GITHUB_TOKEN }}" }
        run: |
          set -euo pipefail
          sudo apt-get update && sudo apt-get install -y minisign
          gh release download "$GITHUB_REF_NAME" --repo "$GITHUB_REPOSITORY" \
            --pattern 'SHA256SUMS*' \
            --pattern 'airclone-setup-x64.exe' --pattern 'airclone-windows-x64.zip' \
            --pattern 'Airclone-x86_64.AppImage' --pattern 'airclone-linux-x64.tar.gz' \
            --pattern 'airclone-macos.*'
          echo "${{ vars.AIRCLONE_UPDATE_PUBKEY }}" > pub.tmp
          minisign -V -p pub.tmp -m SHA256SUMS          # && matters: no pipe-to-checker
          sha256sum -c --ignore-missing SHA256SUMS
          grep -q "$GITHUB_REF_NAME" <(minisign -V -p pub.tmp -m SHA256SUMS)  # tag in trusted comment
```

The `minisign -V … && sha256sum -c` chaining is deliberate: rclone issue #8024 is exactly the bug where piping `gpg --decrypt` into a checker discards the verifier's exit code and a **bad** signature still exits 0.

Every platform build additionally gains `--dart-define=AIRCLONE_UPDATE_PUBKEY=${{ vars.AIRCLONE_UPDATE_PUBKEY }} --dart-define=AIRCLONE_UPDATE_REPO=${{ vars.AIRCLONE_UPDATE_REPO }}` (plus `_NEXT` during a rotation). `mas-release.yml` does **not**: the MAS build must not contain the code.

`dev/releases/<tag>.md` gains a standing "Verify your download" block:

```
minisign -Vm SHA256SUMS -P RWQ…            # the key is published in SECURITY.md
sha256sum -c --ignore-missing SHA256SUMS
```

### 7.2 Where the key lives, and how it is protected

* **Public half:** `vars.AIRCLONE_UPDATE_PUBKEY` (repo variable, plaintext by design), also published in `SECURITY.md` and the wiki so it can be checked out-of-band.
* **Secret half:** `secrets.MINISIGN_SECRET_KEY` (base64 of the password-protected `.key`) and `secrets.MINISIGN_PASSWORD`, both scoped to a GitHub **Environment** named `release-signing` with **required reviewers**, so no workflow outside the tagged-release path — and no fork PR — can reach them. The key file is written with `umask 077` into `$RUNNER_TEMP`, used once, and `shred`ed. It is never checked out, never printed, never passed to another job.
* This is a **different key from Azure Artifact Signing and from the Apple Developer ID**, rotated independently. A leak of one does not imply the other.
* An **offline backup** of the secret key lives outside GitHub, in the same place as the Apple `.p12` and the Android keystore (the private `dev/secrets/` custody documented in `dev/plans/apple-appstore-plan.md`). Losing it strands every installed user with no in-app path forward — minisign has no revocation mechanism at all.

### 7.3 Key rotation

Planned, three releases wide, no user action:

1. **Release N** — app ships `AIRCLONE_UPDATE_PUBKEY = old`, `AIRCLONE_UPDATE_PUBKEY_NEXT = new`. CI still signs with **old** only. Every user who updates to N now trusts both.
2. **Release N+1** — CI signs with **both**: `SHA256SUMS.minisig` (old) and `SHA256SUMS.minisig.2` (new). Users on N-2 and older can still verify via the old signature; users on N can verify either.
3. **Release N+2** — CI signs with **new** only; app ships `PUBKEY = new`, `PUBKEY_NEXT = ''`.

Emergency rotation (key compromised or lost) cannot be done in-band: publish the new key in `SECURITY.md`, in the release notes and on the site, and tell users to download once manually. Say that plainly rather than pretending otherwise. The app's refusal message already points at "Open release", so the manual path is always one click away.

---

## 8. Implementation plan

Each stage is independently shippable, independently revertible, and leaves the app working if the next stage never lands.

### Stage 0 — CI publishes a verifiable release *(no app change)*
`release.yml`: the `checksums` + `verify-release` jobs above; `vars.AIRCLONE_UPDATE_PUBKEY`; `secrets.MINISIGN_SECRET_KEY` in the `release-signing` environment; the verify block in `dev/releases/<tag>.md`.
**Proves it:** `verify-release` is the test — it fails the workflow if the manifest, the signature, or any asset hash is wrong, and a deliberate one-byte corruption in a scratch tag must make it red. No human needed.

### Stage 1 — Trust primitives *(pure Dart, no UI, no network)*
New: `app/lib/src/update/update_trust.dart` (the `const` defines + startup key validation), `app/lib/src/update/minisign.dart` (parse + verify, `DartEd25519` + `DartBlake2b` from `package:cryptography/dart.dart`, already a dependency — **no new packages**), `app/lib/src/update/sums.dart` (reusing the `parseSha256Sums` shape from `rclone_engine.dart:439`), `compareAppVersions()` in `app_info.dart`.
**Tests** (`app/test/minisign_test.dart`, `update_trust_test.dart`, `app_version_compare_test.dart`): a golden fixture manifest + signature committed under `app/test/fixtures/update/`; five negative controls that must all *refuse, not throw*: tampered payload, tampered trusted comment, wrong key id, malformed base64, wrong line count; a malformed-length key and signature (proving the `try/catch` converts the `StateError`/`ArgumentError` into a refusal); `compareAppVersions('0.9.1','0.9.10') < 0` (the bug in today's `contains`); prerelease ordering `0.14.0-rc.1 < 0.14.0`.

### Stage 2 — Gates and a correct check *(no download)*
New: `app/lib/src/state/self_update_target.dart`. `updateCheckProvider` uses `compareAppVersions`; the Check button calls `ref.invalidate`.
**Tests** (`self_update_target_test.dart`, extend `install_source_test.dart`): every `InstallChannel` where `managedByStore` maps to `unsupported`; the five Linux environments cross-checked against `linuxBuildKind`; a widget test that for each store channel the rendered `_UpdateResult` contains **no** install affordance and no GitHub URL; a test that `updateCheckProvider` issues zero HTTP requests for a store-managed source (inject a client that throws on use).

### Stage 3 — Download and verify, install nothing
`update_verifier.dart` implements §2.2 steps 3–12 end to end; the UI gains Downloading / Verifying / Ready states and a `Show in folder` action. Diagnostics wiring.
**Tests:** an in-process `HttpServer` fixture serving a real manifest, signature and payload; asserts the happy path; asserts refusal on a wrong hash, a wrong asset name in the manifest, a replayed older signed manifest (the version-binding check), a `Content-Length` over cap, and a mid-stream size-cap breach; asserts the `.part` file is deleted on every refusal and that no file ever wears the final name unverified.

### Stage 4 — Windows installer flow
Installer launch + exit-code mapping; `wintrust.dll` FFI in `app/lib/src/update/windows_authenticode.dart`; `RegisterApplicationRestart` at startup; `/RESTARTAPPLICATIONS`.
**Tests:** pure unit tests over the exit-code map (0/2/5/1/3/4/7/8/unknown → the right `InstallOutcome`); a Windows CI test that `windows_authenticode.verify()` returns *trusted + subject* for a known-signed system binary (`C:\Windows\System32\notepad.exe`) and refuses for a byte-patched copy of it; a source test asserting `WindowsChildJob.adopt` does not appear anywhere under `lib/src/update/`. Human verification is needed once for the real end-to-end install and restart.

### Stage 5 — Linux AppImage
`$APPIMAGE` targeting, same-directory staging, filename-stable rename, relaunch, `.old` sweep.
**Tests:** the path logic is pure and injected (`environment`, a filesystem façade) so the "no `$APPIMAGE` ⇒ unsupported", "staging is a sibling of the image", "final filename equals the original filename" and "rollback restores `.old`" cases are unit-tested. CI runs the swap against a dummy file tree on `ubuntu-latest`; a real AppImage self-replacement is verified once by hand.

### Stage 6 — Directory swap: Windows portable zip + Linux tar.gz
`--apply-update` headless mode; `update.json`; wait-for-PID; move-aside/copy (Windows) or double-rename (POSIX); rollback; startup sweep.
**Tests:** `app/test/update_swap_test.dart` drives the swapper against temp directories on the CI runner for both platforms — success, failure mid-copy (rollback leaves the original intact and launchable), a stale `.old-*` swept on next launch, and a refusal when `update.json` names a target that does not contain an `airclone` binary. The wait-for-PID loop is tested against a short-lived child process.

### Stage 7 — macOS `.app`
DMG mount, `ditto`, `codesign`/`stapler`/requirement pin, quarantine strip, `renamex_np(RENAME_SWAP)`, `gktool scan`, relaunch; translocation and authorization refusals.
**Tests:** the refusal predicates are pure and unit-tested off-macOS (translocated path, read-only parent, chown-probe failure). On `macos-latest` CI: verify a locally-built signed app against its own designated requirement; assert a resigned-with-another-identity copy is refused. The swap itself is verified once by hand on a fresh VM, network off, downloaded through Safari so quarantine is real — the only test that actually proves the stapled ticket carries first launch.

### Stage 8 — Documentation, diagnostics, CLI
`PRIVACY.md` §"Network connections Airclone makes" gains the release-asset destination (`objects.githubusercontent.com`, the redirect target) — the file currently names exactly two destinations and asserts store builds make neither request. Same for `wiki/core/15-security.md:35-37` and `wiki/core/10-external-integrations.md` §5.1, and the checklist in `docs/store/README.md:338`. Diagnostics report gains the update target, the key id prefix and the last update outcome. Optional: `airclone --check-for-update` with AppImageUpdate's exit-code contract (0 up to date, 1 update available, 2+ error), `airclone --update`, and an `AIRCLONE_NO_UPDATE_CHECK=1` opt-out for package maintainers and enterprise deployments.
**Tests:** a docs test (or a CI grep) asserting that every host the app can contact appears in `PRIVACY.md`.

---

## 9. Open questions for the product owner

1. **Portable zip: self-swap, or download-and-reveal?** The requirement says it must update itself, and §3.2 does that without any new binary. But it is the riskiest path here — a multi-file locked tree, a swapper that is itself a freshly-downloaded Flutter app, and a user-chosen location that may be read-only. Is "download, verify, and open the folder with the new zip" acceptable for v1, with the swap in v2?
2. **Prereleases.** Airclone ships `-alpha/-beta/-rc` tags regularly, and `releases/latest` excludes them. A user running `v0.14.0-rc.2` will be told they are up to date against `v0.13.6`, or offered a downgrade. Should the updater (a) ignore prereleases entirely, (b) offer prereleases only to users already on one, or (c) gain a visible "include prereleases" choice? This also decides whether the `/latest` endpoint is usable at all.
3. **Sideloaded Android APKs.** They classify as `directDownload`, so the gate lets them through, but installing an APK needs `REQUEST_INSTALL_PACKAGES` — a sensitive permission that must be declared for *every* build including the Play one, and which Play scrutinises. Recommendation: `unsupported` on Android, permanently. Confirm.
4. **Key custody.** Personal or organisational? Who holds the offline backup, and where is it written down? Is an HSM or a hardware token worth it, given the key signs one file per release and `minisign` has no HSM support (which would mean switching to cosign/sigstore instead)?
5. **Windows publisher pin.** Continuity (match the running exe's signer subject) handles Azure's frequent leaf rotation automatically but breaks the day Airclone deliberately changes signing identity. Do we want an explicit accepted-subject list in `vars.AIRCLONE_UPDATE_WIN_PUBLISHER` from the start instead?
6. **The self-hosted Store installer.** `airclone-microsoft-store` records that the Package URL must not redirect, so the Store installer is self-hosted at `gigaion.com/releases/airclone/<ver>/`. Those users are detected as `directDownload` (no MSIX) and would be updated from GitHub. Is that correct, or should the updater follow the host it was installed from — which would need a fourth define, `AIRCLONE_UPDATE_BASE_URL`?
7. **Disk cost of rollback.** Keeping `.old-<version>` until the next successful launch roughly doubles the install footprint for one session (~200 MB on desktop). Acceptable, or sweep immediately after the new build starts?
8. **The engine updater's own gap.** `rclone_engine.dart:230` downloads rclone's `SHA256SUMS` and compares the hash fail-closed, but never verifies the **OpenPGP clearsign signature** on that file — rclone's own `selfupdate` refuses to trust it until `CheckDetachedSignature` passes. Closing that needs a Dart OpenPGP verifier for a **1024-bit DSA key from 2001 with SHA-1 digests**, which several modern libraries refuse by policy. Options: prototype it, pin the expected rclone zip hash at Airclone build time (CI already downloads a signed `rclone.exe`), or accept the gap and document it. Separate piece of work — should it ride along with this one?
9. **`SECURITY.md`.** Does one exist to publish the key in, and is it the right home for the verification instructions and the rotation policy?
