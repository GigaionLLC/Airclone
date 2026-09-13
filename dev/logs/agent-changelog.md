# 📝 Agent Changelog

All changes made by AI agents are tracked chronologically below (most recent first).

Coverage has two holes, so treat a missing date as "not written down" rather than "nothing
happened": nothing was logged between 2026-07-02 and 2026-07-15, or between 2026-07-15 and
2026-08-11 — that span is v0.2.0-beta.1 through v0.6.1, some two dozen releases, recorded only in
[`dev/releases/`](../releases/).

---

<!-- New entries go immediately BELOW this comment, most recent first. Keep this comment where
     it is: it used to say ABOVE, which pushed it further down the file with every entry until
     it sat hundreds of lines under the newest one and pointed writers at the wrong place. -->

## [2026-09-12] - v0.8.3 through v0.13.1: a browser, a security audit, and the disk you do not have

**Agent:** Claude Opus 5 - `main`
**Files Modified:** 255 across the v0.8.0→v0.13.1 range, 109 of them new, +19.7k/-3.7k. Seven
releases, logged as one entry because nothing was logged at all for six of them and a gap is worse
than a summary. `dev/releases/v0.8.3.md` through `v0.13.1.md` are the per-version record; this is
what a future session needs to know that those do not say.
**Database/API Changes:** tags `v0.8.3`, `v0.9.0`, `v0.10.0`, `v0.11.0`, `v0.12.0`, `v0.13.0`,
`v0.13.1`. Apple: v0.9.0 released to the App Store and Mac App Store, v0.12.0 submitted. Microsoft:
v0.12.0 **staged and waiting on a human** to press *Submit for certification* in Partner Center.
Play: open testing published per tag by hand; **production is still on 0.8.0** (code 126) because
promoting is a deliberate act, not a side effect of a tag.

**What shipped**

- **v0.8.3** — [issue #3](https://github.com/GigaionLLC/Airclone/issues/3): an empty card reader
  blanked the window. See [`bug-reports.md`](../bug-reports.md), whose worked example is this fix.
- **v0.9.0** — the **Web UI**. Airclone serves its own Flutter web build over an authenticated
  local server. Linux also began shipping its own engine.
- **v0.10.0** — network stream playback, and one media-format table
  (`state/media_formats.dart`) instead of five drifting extension lists.
- **v0.11.0** — file transfer through the Web UI, and the Web UI became **HTTPS-only** with a
  generated self-signed certificate and an import directory for a real one.
- **v0.12.0** — online-only cloud files are marked rather than silently downloaded, including a
  macOS `SF_DATALESS` probe, and folders carry the marker too.
- **v0.13.0 / v0.13.1** — [issue #4](https://github.com/GigaionLLC/Airclone/issues/4): file
  operations from inside the preview.

**The security audit (v0.10–v0.11), because it changed rules rather than lines**

Three findings are worth carrying forward, all of them in code that had already been reviewed:

1. **media_kit's DEFAULT protocol whitelist includes `file`**, with `allowed_extensions=ALL`
   hardcoded. A crafted `.m3u8` naming a local path could therefore open it. Preview now passes an
   explicit protocol list with **no `file`** (`kPreviewProtocols`), and network streaming gets a
   wider one only because the user typed the URL.
2. **mpv's `http-header-fields` is GLOBAL**, so engine credentials were replayed to any host a
   manifest named. Headers now cross `sendableHeaders`, which returns `{}` for anything that is not
   loopback.
3. **A redaction rule silently died** because a word-boundary escape written through an unquoted
   heredoc arrived as a literal backspace byte instead of the two characters it was typed as. It compiled, analysed clean, and disabled the rule. `cat -A` found it.

Rules 15–18 in [`AGENT.md`](../../AGENT.md) came out of this run: invariants get a comment saying
*why*, secrets never go in argv, a library's default is not a safe default, and invisible characters
are real. Rule ordering in `state/diagnostics.dart` is load-bearing — the PEM rule must run first
or the generic `key = value` rule mangles the header before it matches.

**What a future session should not have to rediscover**

- **Apple's `PENDING_DEVELOPER_RELEASE` looks exactly like "still queued"** through
  `asc-version.yml`, which answers every non-editable state with the same refusal. That misread cost
  hours on a version that was approved and waiting on us. `asc-release.yml -f mode=dry-run` prints
  the real state; `tool/asc_build.py --release` then releases it.
- **Play open testing is manual since v0.8.3** (`publish-play.yml`). It fired on every tag before
  that, which is the kind of thing you find out by seeing a build in testing you did not send.
- `dev/plans/advanced-file-manager-research.md` is **research, not a task list** — bulk transfers,
  multi-user and federation, with the finding that transfers are already parallel and unbounded.


## [2026-09-09] - v0.8.0: backups, a scheduler you can find, and the runs nobody is watching

**Agent:** Claude Opus 5 - `main`
**Files Modified:** 90 across the v0.7.7→v0.8.0 range, 60 of them new. New Dart state:
`backup_task`, `backup_prune`, `backup_restore`, `backup_retention`, `photo_backup`, `task_kind`,
`tree_state`, `scheduler_pause`, `scheduler_registration`, `scheduling_policy`,
`registration_policy`, `poll_cadence`, and the four `android_work_*` files. New UI:
`backup_wizard`, `backup_actions`, `photo_backup_section`, `from_to_picker`, `tree_view`,
`file_row`, `tv_row_actions`. New Kotlin: `DueTasksWorker`, `WorkChannel`, `NativeChannel`,
`AircloneApplication`. 27 new test files. Plus `.github/workflows/store-feedback.yml` and
`tool/play_reviews.py` (new), `app/windows/installer/airclone.iss`, `app/pubspec.yaml`
(`0.8.0+126`), `dev/releases/v0.8.0.md` and `dev/archive-plans/tree-view-plan.md` (new), and the
`wiki/features/feat-backup.md` + `feat-scheduling.md` pair.
**Database/API Changes:** tag `v0.8.0` pushed (722ec03), which is what creates the GitHub Release
and uploads to Play **open testing**. No store submission for this version is recorded in this
repo — read the live answer rather than assuming one: *Store feedback*
(`.github/workflows/store-feedback.yml`) prints every Play track's serving version, and
`asc-version.yml -f mode=builds` is the same question for Apple.

**Summary:** Scheduling had been shipping for several releases and a user could not find it. Every
door sat behind advanced mode, behind a 700 dp shell, and behind a two-pane layout you had to
arrange first. This release makes it findable, makes it safe to leave running, and builds backups on
top of it.

**A backup is a task with its dangerous options taken away.** Copy only, keep what it replaces,
never a dry run — applied at creation *and* re-applied every run, so a task edited through the raw
advanced dialog cannot run as something other than what its name says. Backups land under
`<destination>/Airclone/Backups/<device>/<folder>`; the device segment exists because two machines
backing up to one remote would otherwise merge, and the first sign of that is a restore putting a
laptop's files on a phone. Restore is deliberately **not** a bespoke path: the button opens the
backup's destination in the other pane and copying back out goes through the same conflict
preflight as every other transfer. A private restore path would have had to grow its own version of
that guard, later and worse.

**The prune resolves every uncertainty to "do not delete".** The current file is never touched; a
version whose current file is gone is kept, because it is the only copy left; no modification time
means unknown age, not old enough; more than 500 to delete and it refuses **entirely** rather than
deleting some, because a pass that large is more likely a bug than a backlog; an unreadable folder
deletes nothing. The confirm dialog *is* the dry run — `prune()` defaults to reporting, so the list
you approve was produced by exactly the code that will act on it.

**Code with no door is not a feature.** An audit before tagging (e7443c5) found that nothing in the
UI called `backupPrunerProvider`, `backupRetentionProvider`, `canRestoreFrom` or `versionBytes`.
Backup, retention and restore were all built, all tested, and all unreachable. Worth repeating as a
check rather than a story: after the tests pass, grep for a caller.

**The circuit breaker ignored the runs it most exists for.** `state/scheduler_pause.dart` is global,
persisted and has no auto-resume; it was hooked at `recordRunOutcome` and checked at the top of
`tick()`. That covers the in-app tick and nothing else — a Windows Scheduled Task or an Android
WorkManager wake would have kept going while a human was being asked to look. 505b765 added the
check to `headless_runner.dart` during warm-up, before any task is selected, and b26543b is the test
that pins it (`app/test/headless_breaker_test.dart`). 505b765 fixed the other half too:
`scheduling_policy.dart`
mapped Android to background support while `registration_policy.dart` had no Android branch at all,
so the platform was told it could schedule and then denied a registration shape.

**Android background execution, without the `workmanager` plugin.** `DueTasksWorker.kt` is our own
`CoroutineWorker` that boots a headless `FlutterEngine` and runs `androidWorkEntrypoint`. The
prerequisite landed first — the `airclone/native` channel moved out of `MainActivity` into the
Application-scoped `NativeChannel.kt`, so `nativeLibraryDir` resolves with no Activity. Measured on
Android 15: Android 12+ refuses to promote a background-started periodic wake to the foreground
(`mAllowStartForeground false`), so a wake runs inside the plain worker's budget with the Dart run
capped at 8 minutes, and a large first backup proceeds in slices, one per wake. No `BOOT_COMPLETED`
receiver — WorkManager re-arms its own requests, and ours would be a second wakeup source with
nothing to add. `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` is deliberately never requested (Play policy).

**Windows registration became a rule, not a preference.** `registration_policy.dart`: a schedule
that names a wall-clock time gets an exact OS trigger, one that names only a gap joins a single
shared poller (15 minutes by default, 5–60). And **uninstalling now removes the tasks** (3033597) —
they used to be left behind, firing forever at an executable that no longer existed, on a machine
the user believes is clean. Same shape as the Store 10.2.7 finding that already cost a certification
round, just not about files.

**The tree view was built around the invariant it could break.** v0.5.0's stale-path rule says a
pane clears its entries on navigate, because an operation built from `state.path` + a stale entry
list resolves to the wrong object. A tree holds many folders' listings at once and does *not* clear
them, so every operation resolves its parent from the **node**, never from `state.path` — pinned by
`test/tree_node_paths_test.dart`. `ViewMode` is now `{list, grid, media, tree}`, desktop only.

**Monitoring, because the repo has no watchers.** A Google TV user sent a three-bug report out of
band — a persistent focus ring over every film (our own, drawn around a video surface measured at 36
px under the loading spinner and never re-measured), D-pad focus landing on the row overflow menu,
and no way to change track in the audio player. All real, all fixed the same day (2a26933,
fc14ffb), and none of it visible through any channel this repo watched. `store-feedback.yml` now
runs daily; Play serves roughly the last week of reviews, so a run that only happens when somebody
remembers is not a substitute for a scheduled one.

## [2026-09-09] - v0.7.7: five bugs from one user session on the flow that shipped the day before

**Agent:** Claude Opus 5 - `main`
**Files Modified:** 36. In `app/lib/src/state/`: `sync_preview`, `file_ops`, `remotes_provider`,
`cloud_placeholder`. In `app/lib/src/ui/`: `sync_preview_dialog`, `sync_here_action`,
`preview_dialog`, `remove_all_remotes`, `overflow_name`. In `app/test/`:
`cloud_placeholder_wrapper`, `overflow_name`. Plus `app/pubspec.yaml`, `dev/releases/v0.7.7.md`
(new), and the docs pass that ran alongside: four root docs, six `dev/` docs, twelve `wiki/` pages
and `docs/store/README.md`.
**Database/API Changes:** tag `v0.7.7` pushed (63f8c2c). No store submission for this version is
recorded here, and the `store-feedback.yml` header notes that establishing that fact afterwards took
reconstructing it from three workflows' start times — which is the digging that lane now prevents.

**Summary:** Everything here came from one user exercising the "mark a folder, sync into it" flow
that had shipped in v0.7.6, plus one guard that was closed and quietly reopened.

**A preview that cannot finish is a preview that lies.** Comparing two locations ran as a single
request under a 30-second limit, and 13,356 files do not compare in thirty seconds — so the preview
failed on exactly the folders big enough to need one. It runs as a background job now, with no
deadline to miss, and **cancel actually stops the job** rather than only closing the window and
leaving the work running.

**"Sync … to here" looked like a dead button.** It walked the whole source recursively before
anything appeared on screen. It now asks the source one quick question, and both steps say which is
running. The thorough walk is not gone — it still guards a one-way Sync you have chosen to run
against a source that looks populated but contains no files, which would otherwise empty the
destination. It just happens after you have said what you want, and it can be cancelled.

**One fault, three surfaces.** The un-draggable scrollbar in the preview list turned out to be the
same fault in the remove-all-remotes list and in **every text-file preview**, where it had been
broken since it shipped. Worth the habit: when a widget-level bug shows up once, grep for the
pattern before fixing only the instance you were shown.

**Absent and null are not the same thing, and the difference was a multi-GB download.**
`isLocalBacked()` is tri-state on purpose — null means UNRESOLVED and a tree-walking caller must
treat it as "might be local". `union` and `combine` take a list of upstreams rather than one remote,
so this module cannot follow them and they were meant to stay **absent** from the map. But
`remotes_provider` built the map inline over every name in the config, so they arrived
present-with-null, which reads as a definitive "not online-only" — and a union sitting on a sync
folder went straight past the dedupe consent prompt into a recursive hashing pass. Introduced while
closing the previous bug in the same area, and found by a docs pass looking for drift.

**Its test had been green the whole time, for the wrong reason.** The assertion was right — an
unfollowable remote stays unknown — but the test built its input by hand instead of the way the app
builds it at runtime, so it never exercised the path that broke. It now builds its input the same
way the app does, and it fails against the old code. A test that constructs its own fixture is
testing the fixture.

## [2026-09-09] - v0.7.6 out to every store, and two guards that were made to fail before they were kept

**Agent:** Claude Opus 5 - `main`
**Files Modified:** 19. In `app/lib/src/ui/`: `browser_pane`, `inspector_panel`,
`selection_actions`, `dedupe_dialog`. In `app/lib/src/state/`: `add_remote_controller`,
`encrypt_remote_controller`, `remotes_provider`, `cloud_placeholder`, `transfer_options`. In
`app/test/`: `download_conflict`, `create_overwrite_guard`, `cloud_placeholder_wrapper`,
`transfer_options_build`. Plus `.github/workflows/ios-release.yml`, `app/pubspec.yaml`,
`dev/releases/v0.7.6.md` (new), `dev/google-play-store.md`, `dev/apple-handoff.md` and
`wiki/core/14-performance-standards.md`.
**Database/API Changes:** GitHub release **v0.7.6** published with 11 artifacts. Google Play: build
**124 promoted from beta to production at a 10% staged rollout** — the dry run first, then
`committed — production now serving 124`. Microsoft Store: submission **1152921505701850674**
STAGED and deliberately not committed. App Store Connect: 0.7.6 version records **created** on both
IOS and MAC_OS, `PREPARE_FOR_SUBMISSION`, `releaseType` MANUAL from creation; the two build lanes
were still uploading when this was written, so nothing is attached or submitted yet. Four
certificates revoked through `apple-revoke-cert.yml` in four separate runs: `3NWQMKV4UB` plus the
three DEVELOPMENT ids `K9HRGKWVT4`, `QF79989974`, `LN52H3LGTM`. Four load-bearing ones remain.

**Summary:** Everything shipped here has one shape — an operation that destroyed or hid something
and reported success.

**Five transfer paths overwrote the destination with no prompt.** `showCopyConflictDialog` had
exactly one caller. Paste, "Copy to…" and "Move to…" went through `transferNamesIntoFolder` and
asked before replacing; Download (toolbar, inspector, selection), an OS drag-and-drop in, and the
pane-to-pane transfer button went straight at `TransferService`, and rclone replaces by default.
All five now route through the same helper, which lists the destination, offers
Skip / Replace / Keep both, and **refuses when the destination cannot be read** rather than assuming
it is empty. Two shape details worth keeping: a drop can carry paths from several source folders
while the helper takes one source folder per call, so the drop groups by folder
and runs one checked transfer per group; and the pane-to-pane path now clears the selection only
when a transfer was actually dispatched, because cancelling a prompt used to be indistinguishable
from succeeding.

**`config/create` on an existing name silently REPLACES that remote** — exit 0, no diff, nothing in
the response to tell it apart from a create. Both wizards called it unchecked. On a `crypt` remote
that is data loss with no error anywhere: the files stay put, the new key cannot decrypt their
names, rclone skips them and returns an empty listing, and the pane faithfully draws "Empty folder".
The encryption wizard's own round-trip canary does not catch it either — it only ever proved the NEW
key was self-consistent. A user hit exactly this. Both paths now consult one shared
`existingRemoteNames()` in `remotes_provider.dart` and fail **closed**: an unreadable `config/dump`
refuses the create rather than assuming the name is free.

**The cloud-hydration guard was bypassed by the case it exists for.** It resolved a path only when
`remote.type == 'local'`, so a `crypt`, `alias`, `chunker` or `compress` remote sitting on a local
path reported the wrapper type, `localAbsolutePath()` returned null, and `wouldHydrateOnRead()`
turned that into "safe to read" at all five consult sites. Dedupe was the sharp edge — both its
placeholder probe and its consent dialog sat behind that same type check, so it went straight to a
recursive `operations/list` with `showHash`, reading every file in a subtree end to end.
`resolveLocalBackingRoot()` now follows the chain; `isLocalBacked()` is deliberately **tri-state**,
where null means unresolved and a tree-walking caller must treat it as "might be local". A peer
session then found the live case that was missed: a named local remote with no root of its own
(`localdisk:`) resolved nothing on a relative browse path, so dedupe counted **zero** placeholders
and read that confident zero as "nothing is online-only". Dedupe now counts how many entries it
could resolve at all, and zero-resolved-with-files-present asks about the whole scan.

**The iOS export step was still authorising Xcode to mint signing assets.** `ios-release.yml` passed
`-allowProvisioningUpdates` and the App Store Connect key to `-exportArchive` on every signing mode
including the default. The *archive* step had been gated to the `automatic` experiment on 2026-09-06
and the 0.7.5 entry below records the export flag as gone too — for `mas-release.yml` that was true,
for this lane it was not, and the code is what settled it. `secrets` and `ephemeral` both sign
manually from an identity already in the keychain against a profile already on disk; neither needs
the flag or the key. Both now go only to `automatic`.

**Four certificates revoked, after checking rather than after guessing.** `3NWQMKV4UB` had carried an
unsatisfiable condition — "revoke once 0.7.4 is live" — and 0.7.4 was renamed to 0.7.5 and carries
build 123, not the 122 it signed. A rule that can never be met gets read as "no longer applies",
which is the dangerous direction: revoking early is what returned INVALID BINARY minutes after the
first iOS Add for Review. The test actually used was **wait until the version is live**, then
confirm with `--list-certs` which id signs the shipped build. The three DEVELOPMENT ids went the same
way, and only after verifying that neither active profile embedded any of them.

**Two lessons, and they are the part that generalises.**

**A regression test that has never failed proves nothing.** Both new guards were run RED against the
old code before being kept — the download prompt genuinely absent ("Found 0 widgets with text 1 of 1
already exist here"), and `config/create` genuinely firing on a name already present and again on a
config that could not be read. One of those red runs then earned its keep by exposing a real bug in
the fix itself. `resolveLocalBackingRoot`'s cycle test (`a:` → `b:` → `a:`) failed, and not because
the depth guard was missing: a remote named `b` is written `b:`, which is indistinguishable from a
drive letter by shape, so the resolver returned the literal path `"b:"` and ended the cycle by
accident. **The CONFIG has to be the authority, not the string shape** — look the head up in
`config/dump` first, and fall back to a drive letter only when no such remote exists and the
separator a bare remote reference never carries (`C:/x`, `C:\x`) is present. Had that test been
written green-first it would have passed for the wrong reason and hidden the bug it was aimed at.

**With several sessions committing into one working tree, stage by path.** Three others were landing
work here — eight commits interleaved with mine, including the empty-folder notice, the sync-source
flow, the import replace option and remove-all-remotes. `git add -A` in that situation silently
sweeps up somebody else's half-finished work; at one point the tree held a test file that did not
compile, which also makes a local full-suite run meaningless until it lands. Stage the paths you
touched, and treat CI on the pushed commit as the real check. The same crowding hit the release
notes: six follow-up passes after they were first written, five of them because something had landed
in the meantime. A tag cut from HEAD takes everything on main whether the notes mention it or not —
which is also why the release title stopped calling 0.7.6 a fix release.

Also removed `TransferOptions.extraFlags`: it was rendered into the "rclone cmd" tab and dropped by
`buildRcCall`, by design and by its own doc comment. Nothing ever set it, so it never actually lied
— but the only thing a dead field like that can do is make the preview describe a command that is
not the one that runs, and that tab is what people copy out and run by hand.

**Verified:** **831 tests** pass in a local full-suite run on HEAD; CI green on every commit of the
release, which is what actually runs `flutter analyze` and `dart format --set-exit-if-changed`; the
published v0.7.6 release carries all 11 artifacts.


## [2026-09-06] - 0.7.5 submitted to Apple from CI, and a documentation library brought back to the tree

**Agent:** Claude Opus 5 - `main`
**Files Modified:** 82. `tool/asc_listing.py`, `tool/asc_build.py`, `tool/store_submit.py`,
`.github/workflows/{asc-listing,asc-submit-review,asc-version,ci,ios-release,mas-release}.yml`,
seven plans moved `dev/plans/` -> `dev/archive-plans/` with their inbound references, and
corrections across `dev/`, `docs/store/`, `wiki/` and the four root entry-point docs.
**Database/API Changes:** App Store Connect - `whatsNew` written for IOS and MAC_OS 0.7.5; both
platforms **submitted for review** (submissions `22150b3e...` and `f144ba7c...`), both now
WAITING_FOR_REVIEW, `releaseType` MANUAL. Microsoft submission `1152921505701820746` was staged by
CI and then submitted by hand in Partner Center by the repo owner.

**Summary:** Apple refused both 0.7.5 submissions with *"English (U.S.) - What's New in This
Version - This field is required"*, minutes after a dry run of the submit workflow printed
**"No gaps"**. Two independent holes: `asc_listing.py` never sent the field, and the audit never
checked it. `whatsNew` is the one listing field that is per-VERSION rather than per-listing, so it
starts empty every release and never carries forward; Apple accepts the same generic line the other
stores get. Both are fixed, and `asc-submit-review.yml` now refreshes the listing from the repo docs
before it audits, pinned with `--version` to the string the operator confirmed.

Wiring that in exposed a second hazard: `asc_listing.py` took the FIRST version the API returned for
a platform, with no state filter and no pin. iOS lists 0.7.5 *and* 0.6.8, so every previous run was
ordering luck - a reordered response would have written new notes onto the live version. It now
takes `--version` and refuses a version that is not editable.

**The documentation pass.** 17 agents audited every doc against the tree and verified each finding
before it was acted on; 181 survived, 96 of them able to make a reader take a wrong action. Nine
agents then applied them across disjoint file groups, and a checker read every diff back looking for
deleted setup knowledge, new falsehoods and leaked identifiers. That check earned its place: it
caught a claim that `asc-submit-review.yml` "makes you type the version twice" (it has one field,
typed once) which had been written into six files, a pointer to an export-compliance heading renamed
in the same batch, and a restored-then-lost `az login` Graph scope whose doubled slash cannot be
re-derived.

The three instructions that mattered most are gone: the Apple runbook no longer tells anyone to mint
an ephemeral certificate per release, to answer export compliance by hand, or to press Add for
Review in the console. None of those is true any more and following them causes real damage - ten
certificates accumulated against Apple's cap before anyone noticed.

**Also:** `ci.yml` gained a `docs` job running `tool/check-docs.py` (its own docstring had promised
CI that never existed) and `compileall` over `tool/`, where nine scripts first execute against live
store APIs. Three workflows interpolated a free-form dispatch input straight into a shell; they now
pass it through `env:`, quoted. And `librclone_object_server.dart` held a literal NUL byte in a
string, which made git and grep treat the whole file as binary - written as `\u0000` it is text
again and its diffs can be reviewed.

**Verified:** 740 tests pass, `flutter analyze` clean, `dart format` clean, `check-docs.py` reports
0 broken links across 114 docs.


## [2026-09-06] - v0.7.5, and the Apple release lanes stop minting a certificate per run

**Agent:** Claude Opus 5 - `main`
**Files Modified:** `app/lib/src/ui/destination_picker.dart`,
`app/test/destination_picker_test.dart` (new), `app/pubspec.yaml`,
`dev/releases/v0.7.5.md` (new), `.github/workflows/{mas-release,ios-release,asc-version}.yml`,
`.github/workflows/apple-revoke-cert.yml` (new), `tool/asc_build.py`, `tool/asc_ios_signing.py`,
`dev/apple-handoff.md`, `dev/plans/apple-appstore-plan.md`
**Database/API Changes:** Play open testing serves **123**. Microsoft submission
**1152921505701820746** STAGED (superseded the uncommitted 0.7.4 draft - the Store allows one
pending). App Store Connect: 0.7.4 RENAMED to 0.7.5 on both platforms, build 123 attached, both
audits **no gaps**. Nine certificates revoked.

**Summary:** "Copy to doesn't show the option to copy to one of the internal or local drives." The
picker read `remotesProvider` alone - cloud remotes plus one synthetic home folder - so a disk in
the sidebar two inches away could not be chosen. It now shows the sidebar's own LOCATIONS / DISKS /
CLOUD, and local disks survive an engine that is down, because they never needed it.

Then 0.7.5 was used to test the release automation end to end, and it found things.

**Both Apple lanes were minting a development certificate on every archive and never revoking it.**
Ten accumulated between 2026-08-20 and 2026-09-06 until the account hit Apple's cap, and the macOS
lane failed with "Your account has reached the maximum number of certificates" - unrelated to
anything that had changed, which is why it read as sudden. NONE was ever needed: both lanes re-sign
or re-export with the real distribution identity, so the archive signature never reaches the shipped
artifact. Both now archive unsigned, and the export's `-allowProvisioningUpdates` - a second minting
path it did not need, since the plist names every identity - is gone too. Verified by artifact: a
full run now leaves the certificate count unchanged. Two comments in that file had drifted into
being FALSE ("no .p12 is stored" when stored MAS certs are imported), which is how three weeks of
minting read as deliberate to anyone who looked.

**Export compliance: I was wrong twice and Apple settled it.** `POST /v1/appEncryptionDeclarations`
returns "Cannot create unless either containsProprietaryCryptography is True or
containsThirdPartyCryptography and availableOnFrenchStore are both True". Airclone uses only
published algorithms and France is already excluded (confirmed: 174 of 175 territories, France
false), so there is nothing to declare - the encryption is EXEMPT, and
`usesNonExemptEncryption=false` is correct, exactly as the three shipped builds already had it. The
earlier claims that those were "very likely wrong" and that a declaration needed the UI were both
mistaken.

---

## [2026-09-05] - rclone 1.75.1 security update, two diagnostics fixes, v0.7.3 + v0.7.4 shipped to every store

**Agent:** Claude Opus 5 - `main`
**Files Modified:** `.github/workflows/release.yml`, `dev/android/build-rclone.ps1`,
`dev/desktop/build-librclone.{ps1,sh}`, `app/lib/src/rclone/http_rclone_client.dart`,
`app/test/{engine_log,rc_retry}_test.dart`, `app/pubspec.yaml`,
`dev/releases/v0.7.{3,4}.md` (new), `dev/apple-handoff.md`
**Database/API Changes:** Play open testing serves **121** (v0.7.3) then **122** (v0.7.4), both
confirmed by Play's own API. Microsoft Store submission **1152921505701820202** STAGED, not
submitted. App Store Connect: build 122 uploaded for **both** iOS and macOS.

**Summary:** rclone 1.75.1 landed as a SECURITY release and several advisories hit surfaces we
ship - archive zip-slip (we ship archive extract), local symlink escapes and a panic on a Range read
past a symlink's end (previews ARE Range reads), listing entries escaping the root, and headers
leaking across hosts on redirect. Plus two `accounting` memory leaks specific to a long-running rcd
with stats groups, which is exactly our engine. All four pin sites moved together. Verified against
a real binary first, per the standing rule in that pin comment: SHA-256 matched upstream, Range
serving still answers 206, `config/create` still demands `parameters`, and the v0.7.2 mount options
still reshape. The MSIX was then unpacked and its bundled rclone.exe RUN - v1.75.1 - because three
Windows releases once shipped with no rclone at all behind a green log.

v0.7.4 carries two fixes that came out of ONE user diagnostics report, the first time that log has
paid for itself. An `operations/about` refusal from crypt-over-S3 was sitting at the top of a
problem report wearing the word ERROR while being entirely correct behaviour; capability probes we
make on our own initiative are now filtered out, matched on METHOD NAME so it survives rclone
rewording and cannot swallow a failure the user actually asked for. And a dropped keep-alive socket
is now retried once - read-only methods only, allowlist fails closed, timeouts excluded because a
timeout means the engine is still working. A recovered blip is still recorded, at info, with its own
rate-limit budget: going silent would have destroyed the evidence this fix was built from.

**Apple is blocked on a human and the doc now says so loudly.** 0.6.8 is READY_FOR_SALE on both
platforms and no 0.7.4 version record exists; `asc_build.py` never creates one. Also established:
`signing=secrets` for iOS CANNOT work - those secrets do not exist in the org and never did - so
`ephemeral` is the only path, and it retains a certificate each run. Two are now outstanding.

---

## [2026-09-05] - v0.7.2 shipped (mount tuning)

**Agent:** Claude Opus 5 - `main`
**Files Modified:** `app/pubspec.yaml` (0.7.2+120), `dev/releases/v0.7.2.md` (new)
**Database/API Changes:** Google Play open testing (beta) now serves version code **120** -
Play's own API answered `beta [120] completed at 100%  v0.7.2`. GitHub Release v0.7.2 published
with 11 assets. Production promotion remains manual.

**Summary:** Tagged the mount-tuning work. CI was green on the exact commit before the tag rather
than after it, and all four platform jobs passed.

The release notes are deliberately split between what was established and what was not. The mount
settings are **verified** - each read back off a running engine via `vfs/stats` and confirmed to
have arrived - because rclone silently ignores an option key it does not recognise, so "no error"
proves nothing. The **improvement is not measured**: no before/after timing, no percentage claimed,
and the notes say so in their own section rather than implying a win the release cannot show. The
measurement genuinely could not be done here - it needs a real cloud remote with a live upload, and
a local-to-local mount has no network to contend for - so it stays open rather than being faked.
Users are told plainly that if a mount still stalls, that is worth reporting, because it would mean
the cause is elsewhere.

Also surfaced rather than buried: the new disk cache is **per mount**, so three mounted drives can
use three times the 10 GiB cap.

---

## [2026-09-04] - Mount tuning: good defaults, and one place to change them

**Agent:** Claude Opus 5 - `main`
**Files Modified:** `app/lib/src/rclone/models/mount_options.dart` (new),
`app/lib/src/state/mount_defaults.dart` (new), `app/lib/src/ui/{disclosure,mount_options_editor}.dart`
(new), `app/lib/src/state/mount_controller.dart`, `app/lib/src/ui/{mount_panel,settings_screen,
add_remote_dialog}.dart`, `app/test/{mount_options,mount_options_ui,mount}_test.dart`,
`wiki/core/14-performance-standards.md`, `dev/archive-plans/mount-tuning-plan.md`
**Database/API Changes:** `mount/mount` now carries the full `vfsOpt` set plus a `mountOpt`, where it
previously sent only `vfsOpt.CacheMode`.

**Summary:** "When something is uploading from the mount, Explorer won't load other folders or
thumbnails — is it because we didn't set reasonable parallel transfers?" The direction was right and
the lever was not. `--transfers` would make it WORSE: the VFS writeback queue already runs that many
uploads at once. The stall is on the READ side, and we were sending rclone exactly one option and
taking stock defaults for the rest. `--vfs-cache-mode writes` means, in rclone's own words, "files
opened for read only are still read directly from the remote" - so every thumbnail was an uncached
network read, every time; `--vfs-read-chunk-size` is 128Mi with no doubling limit, so reading a
thumbnail's first few KB started a 128 MiB request; `--attr-timeout` is 1s.

Now `full` with a 10Gi/24h cap, 32Mi chunks doubling to 1Gi, a 5s attr timeout and fast
fingerprinting - every knob behind ONE editor widget used in two places. Settings holds the defaults
for new mounts; the mount dialog holds a transient copy behind a disclosure whose collapsed line
doubles as the summary ("Cache: full · 10Gi · 24h") and says "(N changed)" with a reset when it
deviates. That is what keeps two places to set a thing from being confusing. `_AdvancedSection` was
promoted out of `add_remote_dialog.dart` to `ui/disclosure.dart` rather than copied.

**The verification is the part worth remembering.** rclone reshapes `vfsOpt`/`mountOpt` through
`encoding/json`, so an unknown key is SILENTLY DROPPED - mounting with a misspelled `ChunkSizee`
returns a clean `{"mountPoint": "Z:"}`, no warning, option ignored. Proven, not assumed. So the
options were read back off a live `rcd` via `vfs/stats` and every one had arrived in rclone's own
units (`CacheMaxSize` 10737418240, `ChunkSize` 33554432, `CacheMaxAge` 86400000000000ns). Mount
options are not in `vfs/stats`, so `AttrTimeout`/`NetworkMode` were confirmed the other way round: a
bad value is REJECTED naming the Go struct field, which an ignored key could never do. Both rules
are now in the performance standards. **Still outstanding, and deliberately not claimed:** a
before/after measurement on a real mount with an upload running. The options demonstrably take
effect; that they fix the stall is still reasoning from rclone's documented behaviour.

---

## [2026-09-04] - v0.7.1 shipped, and the TV fixes verified with a remote

**Agent:** Claude Opus 5 - `main`
**Files Modified:** `app/pubspec.yaml` (0.7.1+119), `dev/releases/v0.7.1.md` (new),
`dev/android-tv.md`
**Database/API Changes:** Google Play **open testing (beta) now serves version code
119** - Play's own API answered `beta [119] completed at 100%  v0.7.1`, which is the
release job's verification step, not a green check. GitHub Release v0.7.1 published with
11 assets (per-ABI + universal APKs, .aab, signed Windows zip/installer/MSIX, notarized
macOS .dmg/.zip, Linux tarball). Production promotion deliberately NOT automatic.

**Summary:** Tagged v0.7.1 with the three field-report fixes, after driving the reported
flows on a real Android TV emulator (API 36, 1080p) with **D-pad keys only** - a mouse
click in the emulator proves nothing, because it is an input a remote cannot produce.
Confirmed frame by frame: an encrypted config's **Unlock** button reached by pressing
DOWN from the passphrase field and activated (the literal bug reported), and "Add a
remote" opened with a seeded focus ring, its search field left in one press, a storage
type selected, and the form's primary button reached the same way. Both the modal
bottom sheet and the dialog got a visible ring and a starting focus - the two things
every dialog previously had none of.

That run also turned up a gap that is NOT ours and NOT a regression: a stock Android TV
image has **no document picker**, so `ACTION_OPEN_DOCUMENT` resolves to
`com.android.tv.frameworkpackagestubs/.Stubs$DocumentsStub` and "Import File Config"
silently does nothing on such a device. The reporter clearly has a file manager
installed (they reached the passphrase step), so it is not their bug. Recorded in
`dev/android-tv.md` and under "Known gap" in the release notes; making the app SAY so,
and point at QR import, is queued separately.

---

## [2026-09-03] - Three field reports: a mount freeze, a cramped transfers list, and a TV remote that could not press Unlock

**Agent:** Claude Opus 5 - `main`
**Files Modified:** `app/lib/src/rclone/http_rclone_client.dart`,
`app/lib/src/state/config_transfer_controller.dart`, `app/lib/src/state/pane_layout.dart`,
`app/lib/src/ui/{tv,app,mobile_home,home_screen,jobs_dock,jobs_panel,stats_panel,pane_split}.dart`
(`jobs_dock.dart` is new), `app/test/{tv_dpad,transfers_panel,engine_log}_test.dart` (new),
`wiki/core/{05-app-structure,14-performance-standards}.md`, `dev/android-tv.md`
**Database/API Changes:** None
**Summary:** Three reports, three different causes.

**The Windows mount freeze is ours, and it is a pipe.** `rcd`'s stderr was only read
`if (kDebugMode)` and its stdout was never read at all. An unread pipe blocks its WRITER once the
buffer fills, and Dart's Windows pipes hold **1 KiB**; rclone logs under Go's one global `log` mutex,
so a single blocked line stalls every goroutine that logs next - including the ones serving an OS
mount. That is exactly the reported shape: a burst of transfers, Explorer wedged on the mounted
drive, recovering only when Airclone is killed (which closes the read end and takes `rcd` with it).
Release builds - the only builds that mount - were the ones holding the pipe shut. Both streams are
now drained unconditionally; retention stayed conservative (ERROR/CRITICAL only, de-duplicated,
100 a session) because `-vv` echoes the rc credentials. `config_transfer_controller` had the same
unread stdout. A timed-out RC call now also leaves one diagnostics line a minute, so a future freeze
can be told apart from "Airclone is slow" from the outside.

**"The transfers list is compacted and I couldn't resize it" was a fixed 100px box.** The dock HAS
been resizable since v0.6; what did not resize was the live per-file strip inside it, pinned at 100px
while the job list underneath took every pixel a drag added. It now takes half the surface and
scrolls, shared by the desktop dock and the phone/TV tab (`TransfersTabBody`), the divider lights up
under the pointer, double-clicking it or the new chevron toggles tall/default, and a job moving more
files than its row shows has a tappable expander instead of a dead "+N more". Pulling `JobsDock` out
of `home_screen.dart` made the real dock testable, which immediately found a pre-existing overflow:
`kMinJobsDockHeight` was 90, less than the panel header it had to hold. Now 140, with a compacted
header to match.

**The Google TV remote could not reach a dialog at all**, for two independent reasons. The TV focus
theme, ring and seed wrapped the home screen's `Scaffold` body - but a `showDialog` route is a
SIBLING in the Navigator's overlay, not a descendant, so every dialog had no ring, no seeded focus,
and Material's invisible-across-a-room wash. They now wrap the whole app from `MaterialApp.builder`
(`TvShell`), with `TvFocusSeed` seeding whichever route just took focus. Separately, Flutter binds a
bare ArrowUp/ArrowDown to a text-editing intent on Android and `EditableText` enables it whenever the
selection is valid - always - so the passphrase field consumed the key to move its caret and the
D-pad could never leave it. `TvDpadEscape` rebinds the two vertical arrows to
`DirectionalFocusIntent(ignoreTextFields: false)`, which the field's own action honours. Every trap
has a paired test of the UN-wrapped widget, so a refactor that drops a wrapper fails in CI rather
than in a living room. analyze/test/format green (707 tests).

---

## [2026-08-29] - Airclone submitted to the Mac App Store and the iOS App Store

**Agent:** Claude Opus 5 - `main`
**Files Modified:** `tool/asc_build.py`, `tool/asc_screenshots.py`,
`tool/asc_ios_signing.py`, `.github/workflows/{asc-version,asc-listing,ios-release,ios-screenshots}.yml`,
`app/integration_test/**`, `docs/store/apple/ios/**`,
`dev/apple-appstore-and-macos.md`, `dev/apple-handoff.md`, `dev/vault/vault.enc`
**Database/API Changes:** macOS 0.6.8 (build 119) and iOS 0.6.8 (build 118) both
WAITING_FOR_REVIEW. Copyright, MANUAL release type, export compliance and four
iOS screenshots per device set on both.
**Summary:** Both platforms submitted. Three things I had already called finished
turned out not to be. The audit reported "no gaps" while release type was
AFTER_APPROVAL - the setting that makes approval and publication one event -
because copyright and release type live on the version and the audit only checked
localization fields. The screenshot fallback shipped a picture of the iOS home
screen to the App Store, because it ran unconditionally after flutter drive had
uninstalled the app and overwrote the real capture; it now runs only when the
driver produced nothing and refuses to save a screenshot if the launch fails. And
the first iOS submission came back INVALID BINARY because signing=ephemeral
revoked the certificate that signed the build under review - a safety claim I had
written into a commit message without testing it at the only step where it could
fail. Build 118 with a retained certificate was accepted.

## [2026-08-28] - Both stores driven as far as a machine can take them

**Agent:** Claude Opus 5 - `main`
**Files Modified:** `tool/asc_build.py` (new), `tool/asc_ios_signing.py`,
`tool/asc_listing.py`, `tool/asc_screenshots.py`,
`.github/workflows/{asc-version,asc-listing,ios-screenshots}.yml` (new),
`.github/workflows/ios-release.yml`, `docs/store/apple/listing-ios-en-US.md` (new),
`docs/store/apple/ios/**` (new), `app/lib/src/ui/{home_screen,home_view}.dart`
**Database/API Changes:** macOS build uploaded to App Store Connect; macOS review
notes set; iOS version corrected 1.0 to 0.6.8; iOS listing text, review notes and
both screenshot sets published. Nothing submitted.
**Summary:** macOS: built, signed, Apple-validated and uploaded
(UPLOAD SUCCEEDED, delivery UUID issued); review notes and sign-in-NO set through
the API. iOS: the whole listing is complete except the build - version, copy,
notes, and iPhone/iPad screenshots at Apple's exact sizes, captured on
simulators. The iOS signing blocker turned out to be real and unavoidable (dev
profiles need a registered device; cloud signing cannot mint a distribution cert
with an App Manager key) so the lane now mints a certificate through the
Certificates API per run and revokes it on the way out - VERIFY SUCCEEDED on a
57MB ipa, with no distribution key stored anywhere. The screenshots also found
two live UI defects: an empty DISKS header rendering over nothing (present in the
sandboxed Mac build too) and an iPad calling itself "This computer".

## [2026-08-28] - iOS: librclone RUNS - engine reaches ready on a simulator

**Agent:** Claude Opus 5 - `main`
**Files Modified:** `app/ios/Runner.xcodeproj/project.pbxproj`,
`.github/workflows/ios-verify.yml`, `.github/workflows/ios-release.yml`,
`dev/plans/apple-appstore-plan.md`, `dev/apple-handoff.md`,
`dev/vault/vault.enc`
**Database/API Changes:** None
**Summary:** Two real defects and three broken diagnostics stood between "the
archive builds" and "the engine answers". `-force_load` does not survive
`-dead_strip`: nothing references the Go exports, so the linker loaded the archive
and threw it away - fixed with `-Wl,-u,_Rclone*` roots on all three Runner
configurations. And every check that reported this was itself wrong at least once:
one truncated by `head -20`, one aborted by `grep -c` exiting 1, one aborted
because GitHub runs `run:` as `bash -e {0}` so `set -uo pipefail` never disabled
errexit. Each looked exactly like "the symbols are missing". Both lanes now print
every rclone symbol nm can see, on every Mach-O, pass or fail. Result: the Release
device archive keeps all four exports, and the simulator build launches and
reaches EnginePhase.ready - proven by the screenshot, since the UI renders
EngineGate until it does.

## [2026-08-28] - iOS: fat simulator archive, a real local pane, a TestFlight lane

**Agent:** Claude Opus 5 - `main`
**Files Modified:** `dev/ios/build-librclone-ios.sh`,
`app/ios/Runner.xcodeproj/project.pbxproj`, `app/ios/Runner/Info.plist`,
`app/lib/src/state/local_locations.dart`, `app/lib/main.dart`,
`app/lib/src/ui/home_screen.dart`, `app/lib/src/rclone/rclone_engine.dart`,
`app/test/mas_locations_test.dart`, `.github/workflows/ios-release.yml` (new),
`.github/workflows/ios-verify.yml`, `.github/workflows/mas-verify.yml`,
`dev/plans/apple-appstore-plan.md`, `dev/apple-handoff.md`
**Database/API Changes:** None
**Summary:** The first integration run linked cleanly and produced a binary with
none of the four Go symbols in it. `flutter build ios --simulator` always emits a
fat x86_64+arm64 binary, the archive was arm64 only, and `-force_load` of an
archive missing an architecture is a WARNING - so the link succeeded over an
empty slice. Fixed by building a third `ios/amd64` slice and lipo-ing one fat
simulator archive, and by linking stable `device/` and `simulator/` paths instead
of the xcframework's slice directories, which renamed themselves to
`ios-arm64_x86_64-simulator` on this very change. ios-verify now prints the
resolved OTHER_LDFLAGS/STRIP_STYLE/ARCHS before building, keeps the build log so
linker warnings survive, checks symbols per architecture, and fails when the app
is not running. iOS also gained an honest local pane - the container's Documents,
exposed to the Files app - and `ios-release.yml`, whose dry-run mode needs no
Apple credential and exists to prove the DEVICE slice links.

## [2026-08-28] - iOS: link librclone into the app and prove it at runtime

**Agent:** Claude Opus 5 - `main`
**Files Modified:** `app/lib/src/rclone/librclone_ffi.dart`,
`app/lib/src/state/engine_controller.dart`, `app/lib/src/ui/settings_screen.dart`,
`app/test/ffi_rclone_client_test.dart`, `app/ios/Runner.xcodeproj/project.pbxproj`,
`app/ios/Runner/Info.plist`, `.github/workflows/ios-verify.yml` (new),
`.gitignore`, `dev/plans/apple-appstore-plan.md`
**Database/API Changes:** None
**Summary:** The iOS c-archive is now linked into the Runner target and Dart
resolves its symbols from the process instead of a file. Three build settings do
the linking - the two sdk-conditional `OTHER_LDFLAGS` (CoreFoundation, Security,
libresolv and a `-force_load`, because Go does not apply its own cgo_ldflags for
c-archive and nothing in Swift references the exports) plus
`STRIP_STYLE = non-global`, without which Release would strip the Go symbols and
break `dlsym`. `ios-verify.yml` builds for the simulator, asserts the four symbols
survive into the linked binary, then installs, launches and screenshots the app,
because the link, the strip and the runtime lookup fail differently and only
running it tells them apart. `ITSAppUsesNonExemptEncryption` was deliberately left
unset: it is a US export-control declaration, the app does encrypt user config
with a passphrase, and the questionnaire puts that answer in front of a human.

## [2026-08-21] - Mac App Store screenshots captured on CI; iOS librclone builds

**Agent:** Claude Opus 5 - `main`
**Files Modified:** `.github/workflows/mas-screenshots.yml` (new),
`librclone-ios.yml` (new), `dev/ios/{build-librclone-ios.sh,librclone_ios.go,clangwrap.sh}` (new),
`docs/store/apple/mac/store-ready/*` (new, 5 PNGs + MANIFEST),
`docs/store/apple/listing-en-US.md`, `dev/plans/apple-appstore-plan.md`
**Database/API Changes:** macOS App Store version string set to 0.6.8 via the App
Store Connect API, matching the app instead of the placeholder 1.0.
**Summary:** Five store-ready Mac screenshots, all exactly 1280x800, captured on a
GitHub runner with no Mac in the building - including a gallery view of real CC0
photographs. And librclone now builds for iOS: both device and simulator slices,
all four FFI symbols exported, packaged as an xcframework.

The screenshot work took ten runs, and the instructive failures were all the same
shape - **macOS automation reporting success while doing nothing**. `osascript`
clicks and keystrokes silently no-op without accessibility permission; System
Events' `click at` returns no error and delivers no click; and a `|| true` hid both
for four runs. Flutter renders its own widgets, so System Events cannot address
them by name at all (-1728). `cliclick` posts real CGEvents and works - which is
what this repo's Windows screenshot rig already did.

Other traps now recorded: the runner's display offers none of Apple's exact sizes
(fixed by setting 1920x1080, pinning the window to 1280x800 centred, and letting
sips centre-crop); macOS 26 raises a screen-recording consent prompt that lands IN
the frame (killing UserNotificationCenter clears it); and the toolbar re-lays out
once a remote is open, so coordinates must be read off captured frames.

The seeded demo remote failed for three runs because path_provider keys
application-support by BUNDLE IDENTIFIER on macOS - I identified that correctly,
then talked myself out of it when an unrelated edit dropped the copy, and looked
elsewhere. The step now asserts the file is non-empty.

On iOS: the simulator slice was expected to be blocked by golang/go#57442, and the
community -target ...-simulator triple produced a correct platform 7 stamp. The
trimmed wrapper (avoiding cmd/mount2, importing fs/sync explicitly) and the
storj.io/common linkname patch both worked first time. This does NOT prove it
runs - linking into Runner and a real RPC round-trip are still ahead.

---

## [2026-08-20] - Mac App Store lane validated by Apple

**Agent:** Claude Opus 5 - `main`
**Files Modified:** `.github/workflows/mas-release.yml` (new), `mas-verify.yml` (new),
`app/macos/Runner/{SecurityScopedBookmarks.swift,MainFlutterWindow.swift,MacAppStore.entitlements,Info.plist}`,
`Runner.xcodeproj/project.pbxproj`, `app/lib/src/state/{mac_bookmarks.dart,local_locations.dart,native_actions_policy.dart,archive_service.dart,os_integration.dart}`,
`app/lib/src/ui/{home_screen,context_menu}.dart`, `docs/store/apple/listing-en-US.md` (new),
`dev/apple-appstore-and-macos.md`, `docs/store/README.md`
**Database/API Changes:** Distribution certificates and the Mac App Store
provisioning profile created through the App Store Connect API. Org secrets added:
`APPLE_MAS_APP_P12_BASE64`, `APPLE_MAS_INSTALLER_P12_BASE64`, `APPLE_MAS_P12_PASSWORD`,
`APPLE_MAS_PROVISIONING_PROFILE_BASE64`. `APPSTORE_ISSUER_ID` moved from variable to
secret after it was printed in a public CI log.
**Summary:** `xcrun altool --validate-app` returns **VERIFY SUCCEEDED with no errors**
for a 136 MB signed `Airclone.pkg`. Nothing uploaded, nothing submitted.

Security-scoped bookmarks landed (Swift + Dart + schema), so a sandboxed build can
read the folders a user grants. `mas-verify.yml` proves on real Apple hardware that
the sandboxed app launches with `engine ok - rclone v1.75.0` and zero denials - the
App Sandbox is enforced by signature+entitlement, not by the App Store, so an ad-hoc
signature on a CI Mac reproduces exactly what a customer gets.

Nine failed runs preceded the green one. The instructive ones: `open -a` resolves an
app NAME not a path; a workspace-wide `CODE_SIGN_ENTITLEMENTS` is applied to every
SPM plugin target; `set -e`+pipefail kills `X=$(...|grep)` at the assignment so the
guard below is unreachable; a locked keychain makes `-allowProvisioningUpdates`
create nothing and report no error; and "Cloud signing permission error" restricts
only Xcode's cloud path, not the Certificates API - testing that boundary is what
kept the CI key at App Manager instead of Admin.

Apple's two rejections were declarative, not structural: a missing
`LSApplicationCategoryType`, and `keychain-access-groups`, which is unsupported on
macOS and had been added here on a correct-for-iOS assumption.

---

## [2026-08-19] - Apple App Store account configured; MAS build foundation; encrypted notes vault

**Agent:** Claude Opus 5 - `main`
**Files Modified:** `app/lib/src/state/build_flavor.dart` (new), `engine_controller.dart`,
`mount_policy.dart`, `serve_policy.dart`, `app/lib/src/ui/settings_screen.dart`,
`app/macos/Runner/MacAppStore.entitlements` (new), `app/test/engine_mode_test.dart`,
`config_override_test.dart`, `tool/vault.py` (new), `dev/vault/` (new),
`dev/plans/apple-appstore-plan.md` (new), `dev/secrets/dev-profile.example.env`, `.gitignore`
**Database/API Changes:** App Store Connect API now reachable from CI. Org secret
`APPSTORE_API_PRIVATE_KEY` plus org variables `APPSTORE_ISSUER_ID` and `APPSTORE_API_KEY_ID`
added (visibility `all`, matching the existing `APPLE_*` credentials). The key is an
App Store Connect **Team Key** with the **App Manager** role - not Admin, which would give a
CI secret control of users, roles and agreements.

**Summary:** Took the Apple track from "app record exists" to "everything Apple gates on
paperwork is done": categories, content rights, age rating (4+ globally), App Privacy
(Data Not Collected), subtitle, bank account, Paid Apps Agreement, EU DSA trader status,
$1.49 in 175 countries, availability, and Public/discoverable distribution verified by
reading the selected radio rather than trusting the "(default)" label.

Two traps worth remembering. An updated **Apple Developer Program License Agreement** blocks
App Store Connect and presents as *"We can't process your request"* on one sub-page while
others load fine - the banner naming the cause appears only on the Apps list, never on the
failing page. And **$1.49 is not in Apple's default price dropdown** (it jumps $0.99 to
$1.99, and searching "1.49" returns $14.99); it exists only behind "See Additional Prices".
Without that link the obvious move is to break price parity with the other two stores.

On the build: `build_flavor.dart` adds the compile-time `AIRCLONE_MAS` flag, so the spawn
path is const-folded out of a store build, plus two pure predicates -
`subprocessAllowedFor` and `configMustBeAppPrivateFor` - that make the sandbox policy
unit-testable with no Mac. Mount and Serve gate off through the existing one-line policy
providers. `MacAppStore.entitlements` is new, and its first draft was WRONG: it omitted
`com.apple.security.network.server` on the reasoning that Serve was the only consumer. It
is not - `librclone_object_server.dart` binds a loopback socket and is the ONLY source of
preview, thumbnail, video, audio and PDF bytes under the in-process engine, so that build
would have shipped with no media at all.

`resolveConfigPath` lost its Android-specific parameters: the constraint was never about
Android but about platforms that cannot spawn `rclone config file` to locate their own
config, which would break config backup, restore and export on an otherwise-working
sandboxed build. `flutter analyze` caught a third call site that would have shown a
confidently wrong config path in Settings.

Also added `tool/vault.py` and `dev/vault/`, an encrypted notes vault modelled on the
sibling RD-API-Server repo (ported to Python; this repo has no Node). `vault.enc` is
committed, `notes/` and the passphrase are not: scrypt N=2^16 to AES-256-GCM, fresh salt and
IV per lock, verified by round-trip checksum and by confirming a one-byte ciphertext flip
fails loudly. The split from `dev/secrets/` is deliberate and is the security argument -
sensitive **notes** go in the vault, **credentials** never get committed in any form,
because this repo is public and a leaked passphrase would expose every historical revision.

---

## [2026-08-17] - Microsoft Store submission automated; v0.6.7 submitted for certification

**Agent:** Claude Opus 5 — `main`
**Files Modified:** `.github/workflows/submit-msstore.yml`, `tool/store_submit.py` (new),
`dev/msstore-ci-setup.md`, `dev/microsoft-account-setup.md` (new),
`dev/windows-signing-and-store.md`, `dev/README.md`, `.gitignore`
**Database/API Changes:** Microsoft Store submission REST API now driven from CI. Org secret
`STORE_SELLER_ID` added; `STORE_CLIENT_SECRET` rotated (old secret destroyed by `credential reset`).
The Entra app `GigaionLLC-StoreSubmit` granted the **Developer** role on the Partner Center account,
and the Partner Center account associated with the surviving Entra tenant.
**Summary:** The Store lane had been written but never executed, and running it surfaced fault after
fault. In the workflow: the `MSStore.CLI` dotnet tool no longer exists on nuget.org, and
`msstore <cmd> --help` needs credentials so it cannot run before `reconfigure`. In the credential:
the Entra app had never been added in Partner Center at all, and the stored secret was unusable —
most likely the CRLF a PowerShell stdin pipe appends, which fails identically to a wrong secret.
Both produce the same opaque `Really failed to auth`. Then the CLI itself proved a dead end: it
refuses to update a **paid** product, so `tool/store_submit.py` drives the submission REST API
directly (create → retire old packages → upload to the SAS URL → commit → bounded poll), with a
package-identity check first because identity mismatches cost this app four review cycles.

**The pricing incident — the app was published FREE, and the lesson is the expensive part.** For a
product on the advanced pricing model the v1 API cannot express the real price: it returns
`priceId: "Base"`, refuses that value on write, refuses an omitted pricing object, and accepts only a
payload that reads back as `Free`. A first submission was cancelled mid-certification on the strength
of that readback. Then a staged draft was observed still showing $1.49 in Partner Center, the alarm
was declared a false positive, the guard was loosened, and v0.6.8 was API-committed. It published at
**$0**.

Both observations had been correct; the variable nobody isolated was **stage vs commit**. The PUT is
harmless — a staged draft keeps the real price. It is `commit` that applies the submission's pricing
block, and the only block the API accepts says Free. Submitting from Partner Center instead
re-derives pricing from the pricing module, which is why the v0.6.7 stage-then-submit path published
correctly. Once a submission reaches *Publishing* nothing can stop it, and the API cannot even clear
a submission in `Certification` (409). Recovery was a fresh submission restoring $1.49, during whose
certification the app remained free.

`store_submit.py` now refuses `--commit` for an advanced-pricing product, checked before creating
anything. AGENT.md gains rules 10-13 covering this, Partner Center's silent-save and viewport traps,
the cp1252 stdout crash that killed a run mid-submission, and the meta-rule: a contradiction between
two observations is evidence of a missing variable, not proof one was wrong.

**Also fixed while in the pricing module:** the product was set to *available but not discoverable*
(direct link only), so it never appeared in Store search or browse — unrelated to any release, and
silently capping discovery since launch.

Also added: `mode: stage`, which uploads the package and leaves an editable draft for a human to
check and submit (the practical middle ground); superseding a submission still in certification so a
newer build never queues behind an older one; and `dev/microsoft-account-setup.md`, the from-nothing
runbook for the whole Microsoft identity layer. Two earlier claims were corrected rather than left
standing: the role is Developer (not Manager, which would give a CI secret control of users, roles
and tenants), and the app registration was never destroyed by the tenant deletion.

---

## [2026-08-16] - Android video thumbnails, repeat playback, Flutter 3.47, and automated Play publishing

**Agent:** Claude Opus 5 — `main`
**Files Modified:** `app/lib/src/state/thumbnail_service.dart`, `android_native.dart`,
`media_prefs.dart` (new), `pane_layout.dart`, `app/lib/src/ui/media_preview.dart`, `home_screen.dart`,
`pane_split.dart`, `paste_action.dart`, `MainActivity.kt`, `res/xml/network_security_config.xml` (new),
`AndroidManifest.xml`, `app/pubspec.yaml`, `settings.gradle.kts`, `gradle-wrapper.properties`,
5 new test files, `.github/workflows/release.yml`, `promote-play.yml` (new), `ci.yml`,
`tool/play_promote.py` + `play_tracks.py` (new), `dev/play-ci-setup.md` (new),
`dev/plans/transfer-coordinator-plan.md` (new), `AGENT.md`, `README.md`, wiki + store docs
**Database/API Changes:** New `airclone/native` channel method `videoThumbnail`. Google Play
Developer API now used from CI (service account, org-level GCP project, no billing attached).
**Summary:** Video tiles were empty on Android for two independent reasons: libmpv decodes into a
Surface so its `screenshot` has no CPU-readable frame, and Android's media stack refuses cleartext
even to `127.0.0.1`, so `MediaMetadataRetriever` could not read the engine's own object URL
(symptom: `Unable to instantiate an extractor`, no exception reaching Dart). Fixed with a native
frame grabber plus a loopback-only cleartext exemption, and a blank-frame guard (`isFlatRgba`) so a
flat capture is never cached as a thumbnail. Added repeat playback (`PlaylistMode.single`, persisted,
applied after `open()` and re-applied on toggle) and a resizable Transfers dock. Moved the toolchain
to Flutter 3.47 (pdfrx 2.x, Gradle 8.14.3, AGP 8.11.1, Kotlin 2.2.20) after floating `channel:
stable` broke every platform job mid-release — CI is now version-pinned. Truth pass on the README
removed three claims the code does not support. Google Play publishing is automated end-to-end: every
tag uploads to open testing, production ships from a `workflow_dispatch` button that promotes the
existing version code, with guards that refuse to narrow a live rollout or downgrade users, and a
verification step that asks Play what it actually holds rather than trusting a green check. Releases
v0.6.3 → v0.6.6 shipped; 678 tests pass, analyze + doc linter clean.

---

## [2026-08-11] - "Survive uninstall": an opt-in, encrypted config backup outside the sandbox

**Agent:** Claude Opus 5 — `main`
**Files Modified:** `app/lib/src/state/external_config_backup.dart` (new),
`app/lib/src/ui/external_backup_dialogs.dart` (new), `settings_screen.dart`, `home_screen.dart`,
`config_import_dialog.dart`, `app/test/external_config_backup_test.dart` (new),
`wiki/core/15-security.md`
**Database/API Changes:** None.
**Summary:** Closes the "a reinstall loses every remote" gap left by `allowBackup=false`, without
weakening it. Settings → Config → **Survive uninstall** mirrors the config to
`<shared storage>/Airclone/`, which uninstall does not delete. Turning it on **asks for a
passphrase** and seals an ACFG2 envelope (AES-256-GCM over Argon2id, in `compute()` so the automatic
refresh never janks the UI); continuing without one is possible but only behind a danger screen
listing what it means plus a checkbox acknowledgement. Off by default. The backup refreshes itself
whenever remotes change (SHA-256 digest guard), only one file may ever exist (a failed delete of a
*plaintext* file is raised, not swallowed), turning it off deletes the file, and writes are
`.part`-then-rename. Restore reuses the normal import wizard via a new `initialBytes` parameter, so
it gets the same passphrase prompt, mandatory preview and collision handling; the offer fires
reactively because a fresh install has no storage permission when it launches. Verified end-to-end
on Android 15: enable → uninstall (file survives, no plaintext secrets) → reinstall (app data gone)
→ automatic offer → passphrase → merge → remotes back. 649 tests pass, analyze clean.

---

## [2026-08-11] - Store-compliant updates, Android hand-off + import fixes, local diagnostics

**Agent:** Claude Opus 5 — `main`
**Files Modified:** `app/lib/src/state/{install_source,diagnostics,app_info,open_external}.dart`,
`app/lib/src/ui/{dialog_body,settings_screen,config_import_dialog,open_external_action,app}.dart`
(+ 20 dialogs re-wrapped), `app/android/.../MainActivity.kt`, `res/xml/file_paths.xml`,
`app/test/{install_source,diagnostics}_test.dart`, `wiki/core/{10-external-integrations,15-security}.md`
**Database/API Changes:** New `airclone/native` method `installerPackage`; new `openExternal` error
code `not_shareable`.
**Summary:** Fixes the **Microsoft Store v0.6.0 certification failure (policy 10.2.5)** — the update
check now detects its install channel (MSIX / Play / Amazon / F-Droid / Galaxy / App Store / Flathub
/ Snap / direct) and a store-managed build makes **no GitHub request at all**, offering only the
store's own page; `UpdateStatus` is sealed so no build can fall through to a download link. Also
fixes "Open in another app" on Android local files (`file_paths.xml` had only the cache staging dir,
so a `/storage/emulated/0/DCIM/…` path threw *"Failed to find configured root"*; shared storage is
now a root, with a staged-copy fallback for SD/USB volumes), and the Android config-import failure
(every dialog was a fixed desktop pixel width, so the preview's action Row clipped **Merge** off the
right edge — `DialogBody` clamps width app-wide and the action rows now wrap). Adds a no-telemetry
**diagnostics log** (redaction at ingest, copy/share a report) wired to the import, hand-off and
uncaught-error paths. Verified on an Android 15 emulator that the config does **not** survive
uninstall/reinstall (by design — `allowBackup=false`); the Config section now says so before the
user finds out. 642 tests pass, `flutter analyze` clean.

---

## [2026-07-15 20:12] - Reliability and product hardening audit handoff

**Agent:** Codex (GPT-5)
**Files Modified:**
- `dev/backlog/hardening-audit-2026-07-15.md`
- `dev/backlog/backlog-index.md`
- `dev/backlog/beta-quality-review.md`
- `dev/backlog/feature-backlog.md`
- `dev/logs/agent-changelog.md`
**Database/API Changes:** None
**Summary:** Added a durable, prioritized handoff for the v0.5 audit with 18 evidence-linked candidate
fixes, acceptance notes, implementation order, and cross-links from the master and historical beta
backlogs; no product code changed.

## Everything before 2026-07-15 — the alpha run

Entries for `v0.1.0-alpha.85` back to the repository's first commit used to sit here: about 1,800
lines, roughly two thirds of this file, covering 2026-06-28 to 2026-07-02.

They were removed on 2026-09-12 because they were the SECOND copy. The consolidated table of all 88
alpha builds is [`version-history.md`](version-history.md), which opens by calling itself *"the one
consolidated table of the alpha run, kept because nothing else lists those 88 builds in one place"* —
a claim this file quietly falsified while nobody was reading that far down.

Nothing is lost. The table is there, every one of those commits is in `git log`, and this file keeps
the span that rule 5 makes mandatory reading. If you need the prose for one alpha build rather than
its row, `git log --follow dev/logs/agent-changelog.md` will find it.

Worth knowing about the remaining span, because it looks continuous and is not: nothing was logged
between 2026-07-02 and 2026-07-15, or between 2026-07-15 and 2026-08-11 — that second gap is
`v0.2.0-beta.1` through `v0.6.1`, some two dozen releases. `dev/releases/` is the record for those.
