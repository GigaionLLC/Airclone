# 📦 Parcel Plan: Scheduling and backup — make the built thing visible, then make it real

## 📊 State Dashboard
| Metric | Value |
| :--- | :--- |
| **Status** | `IN PROGRESS` — targets **v0.8**. **A, B and E complete.** **C complete** bar the explicit "Remove all background scheduling" control (reconcile-on-launch, the hybrid registration, the migration and the Windows uninstall cleanup are all in). **F complete** bar the battery-optimisation UX — Android background execution and camera-roll backup ship in v0.8, with the measured caveat that a background wake is capped at 8 minutes (Phase 8). **D untouched** and slipping past v0.8. |
| **Version** | `v1.2.0` |
| **Active Persona** | `Builder` |
| **Last Updated** | 2026-09-09 |

---

## 1️⃣ Phase 1: Expansion & Scoping

**Intent.** A user read the README's scheduling claim and said *"I don't see this
feature."* They are right, and for a reason the backlog does not predict.
Scheduling is **built and working**, including OS-level background execution on
Windows — but every door to it sits behind **advanced mode, off by default**, and
on a phone there is no door at all. They also asked about **backup tasks** and
**photo/camera-roll auto-backup**: the first is a naming and safety problem on top
of machinery that already exists, the second is genuinely unbuilt.

**In scope:** making the shipped scheduler discoverable and its per-platform
honesty visible; a task-creation flow that does not require two panes; OS-level
background execution on macOS, Linux and Android; "backup" as a first-class,
safety-constrained task shape; photo auto-backup on Android; closing the
uninstall-residue defect, which worsens with every platform added.

**Out of scope:** cron, 5-field (no demand; interval/daily/weekly covers the
asked-for cases); iOS background scheduling and iOS photo backup (see Phase 5 —
iOS does not permit what this needs); `DocumentsProvider` / File Provider; a
real-time filesystem watcher; deleting source media after upload, ever.

## 2️⃣ Phase 2: Requirements & Context

### 2.1 What exists today — capability × platform

`[adv]` means it exists but sits behind advanced mode, which is **off by default**
(`state/advanced_mode.dart:13` — `build()` returns `false`).

| Capability | Win | mac | Linux | Android | iOS | Proof |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| Saved tasks (persisted) | yes | yes | yes | tablet | tablet | `state/tasks_controller.dart` — SharedPreferences, platform-free |
| A door to reach them | `[adv]` | `[adv]` | `[adv]` | `[adv]` ≥700dp | `[adv]` ≥700dp | `ui/home_screen.dart:939` toolbar + `:569` palette, both `if (advanced)` |
| …on a phone-sized window | no | no | no | no | no | `home_screen.dart:640-642`; no tasks entry anywhere in `ui/mobile_home.dart` |
| Creating a task | needs 2 panes | same | same | same | same | `ui/tasks_panel.dart:176-196` reads BOTH panes and errors if either is empty |
| Schedule editor | `[adv]` | `[adv]` | `[adv]` | `[adv]` | `[adv]` | `ui/tasks_panel.dart:733`; model `state/task_schedule.dart:16` |
| In-app 30s tick | yes | yes | yes | yes | yes | `state/scheduler_controller.dart:76`, armed at `home_screen.dart:97` in `initState` — **before** the shell branch, so it ticks on a phone against a list nobody can populate |
| Missed-slot catch-up | yes | yes | yes | yes | yes | `state/task_schedule.dart:118-133` |
| Per-run history (10, capped) | yes | yes | yes | yes | yes | `TaskRunRecord`, rendered `ui/tasks_panel.dart:346` |
| `--run-task` / `--run-due` | yes | built, unused | built, unused | n/a | n/a | `headless/headless_runner.dart:41-56`, branched at `main.dart:22-24` before `runApp` |
| **OS-level run-while-closed** | `[adv]` | no | no | no | no | `ui/tasks_panel.dart:802` — `_canOsSchedule => Platform.isWindows` |
| Camera roll browsable | n/a | n/a | n/a | yes | no | `state/local_locations.dart:198` adds Camera (DCIM); `:147-160` gives iOS only its own Documents dir |
| **File backup as a feature** | no | no | no | no | no | No `TaskKind`, no "Backup" string — a backup is a `TransferTask` the user must shape by hand |
| **Photo auto-backup** | n/a | n/a | n/a | no | no | No MediaStore, no PHPhotoLibrary, no `READ_MEDIA_*`, no `NSPhotoLibraryUsageDescription` |

**Two things the docs do not record.** The shell is chosen by **width, not
platform** (`home_screen.dart:640`), so an Android tablet or iPad at ≥700dp gets
the *desktop* shell and does see tasks, in-app-only. And the mobile scheduler
timer runs: `home_screen.dart:97` sits in `initState`, before `build()` picks a
shell, so on a phone it ticks every 30s over a list with no way to add to it.

### 2.2 Do not confuse CONFIG backup with FILE backup

`state/external_config_backup.dart` is an opt-in **encrypted copy of
`rclone.conf`** kept outside the Android sandbox so a reinstall does not cost the
user every remote. It is shipped, it works, and it is **not** what was asked
about. Settings must read **"Back up your files"** against the existing
**"Back up your remotes"**.

## 3️⃣ Phase 3: User Clarification

* **Open Questions:**
  - `[x]` Does "Saved tasks" leave advanced mode, or does a new **Backup** flow
    become the front door with tasks staying advanced? Leaning to the second:
    "back up a folder" is a concept a normal user has; "saved transfer task with a
    `TransferOptions` payload" is not. → **Answer: the second, as built.**
    Settings → Automation is ungated and "Back up a folder" (`ui/backup_wizard.dart`)
    is its primary button; the raw task editor stays advanced.
  - `[x]` **One `--run-due` registration per user, or one OS task per saved task?**
    Unified is simpler, makes uninstall cleanup a single known name, and is the
    only shape that fits launchd-under-sandbox. Cost: a power user can no longer
    see or disable an individual schedule from Windows Task Scheduler.
    → **Answer (user, 2026-09-09): neither — the HYBRID** in §7 C.
    Daily/weekly get an exact trigger of their own; intervals share one poller
    (`state/registration_policy.dart`).
  - `[x]` If unified, what poll cadence? 15 min bounds lateness at 96 wakeups a
    day; 5 min is punctual and expensive. → **Answer: the user's, default 15
    min**, from 5/10/15/30/60 (`state/poll_cadence.dart`). Android has no choice:
    WorkManager's 15-minute floor.
  - `[x]` **Should a scheduled sync be allowed at all without a `--max-delete`
    cap?** → **ANSWERED (user, 2026-09-09): no.** A repeating sync gets a cap with
    a sensible default, editable while setting the schedule up, and **tripping it
    pauses the scheduler for review**. Designed in §4.e.
  - `[ ]` Does the MAS build offer scheduling? `SMAppService.agent` needs a static
    plist in the bundle and an App Review justification; cheapest answer is to
    gate it off as Mount already is. → **Answer:**
  - `[ ]` Linux: is `loginctl enable-linger` acceptable? Without it a `--user`
    timer fires only while the user is logged in. → **Answer:**
  - `[x]` Photo destination convention? Proposal
    `remote:Airclone/Photos/<device-name>/`. → **Answer: as proposed, built**
    (`state/photo_backup.dart`; folder backups use
    `Airclone/Backups/<device>/<source folder>`, `state/backup_task.dart`).
  - `[ ]` Should a failed unattended run raise an OS notification? Today its only
    trace is a `TaskRunRecord` inside a dialog behind advanced mode. → **Answer:**

## 4️⃣ Phase 4: Detailed Execution Plan

### 4.0 Why the user cannot see it

Three gates, in the order they bite:

1. **Advanced mode, default off** (`state/advanced_mode.dart:13`). Both doors are
   `if (advanced)`: `ui/home_screen.dart:939` and `:569`. The only place the
   product mentions scheduling exists is one line of grey text in a settings card.
2. **Shell width.** Below 700dp there is no toolbar and no command palette at all,
   so a phone has zero entry points regardless of advanced mode.
3. **The two-pane requirement.** Even past the first two, "New task" fails unless
   a dual-pane layout is already arranged (`ui/tasks_panel.dart:189-196`).

`_canOsSchedule` is **not** why the user cannot see scheduling. It gates exactly
one checkbox — *"Also run while Airclone is closed"* — inside a dialog they must
already have found. A macOS or Linux user past the three gates sees a complete,
working editor with an honest footnote about in-app-only running.

**Verdict on the README** (`README.md:31-32`): right but undiscoverable on Windows
— where it is in fact *understated*, since it omits that a Windows schedule fires
with the app closed; right but incomplete on macOS/Linux; and **wrong on
phone-sized Android and iOS**, where no job can be saved at all. The README makes
no platform distinction, and the phone is exactly where a user expects "on a
schedule" to mean "in the background".

### 4.a Making it visible and honest — `[S]`

Settings → **Automation**, always visible, listing every saved task with its
schedule, next run, last outcome and one sentence of per-platform truth; the data
is already in `tasksProvider`. **Break the two-pane requirement** with an explicit
From/To picker — the prerequisite for everything mobile. Give the mobile shell a
door under the Transfers tab. One `state/scheduling_policy.dart` following the
`mountEnabledProvider` idiom, with `_canOsSchedule` **deleted**, not left beside
it. Correct the README; write `wiki/features/feat-scheduling.md`, which
`wiki/features/features-index.md:22` has promised at an empty path.

### 4.b OS-level background execution

The unifying move: **stop registering one OS task per saved task; register one
`--run-due` job per user.** `--run-due` already exists and is called by nothing
(`headless_runner.dart:44`). One registration means one name to clean up, and it
is the only shape that fits macOS sandboxing and systemd user units.

- **Windows `[S]`** — replace `Airclone\<id>` with a single `Airclone\Run due
  tasks` on a repeating trigger, keeping the settings `buildTaskXml` already gets
  right. Migration must unregister the existing per-task entries or they orphan.
- **macOS `[M]`** — a LaunchAgent with `StartInterval` and `RunAtLoad`, loaded
  with `launchctl bootstrap gui/$UID`. **Must verify before shipping:** whether a
  `--run-due` launch of the bundle executable shows a Dock icon or steals focus.
  `main.dart:22-24` returns before `runApp`, but activation policy comes from the
  bundle's `Info.plist` and there is no macOS equivalent of
  `windows/runner/main.cpp:24-29`. **Unknowable without building and running it.**
- **Linux `[M]`** — a `oneshot` service plus a timer with **`Persistent=true`**.
  Two traps to surface in the UI rather than discover in a bug report: without
  `loginctl enable-linger` the timer fires only while the user has a session; and
  the unit bakes an absolute path while Linux ships as a tarball the user can
  move, silently breaking every schedule.
- **Android `[L]`** — move the `airclone/native` channel out of
  `MainActivity.configureFlutterEngine` to Application scope **first**: a
  WorkManager isolate has no Activity, so `nativeLibraryDir` and the foreground
  service are unreachable from it, and nothing else here is testable until that
  lands. Then a `PeriodicWorkRequest` (15-minute floor) to a headless entrypoint
  running the same `dueTasks` selection, `setForeground()` reusing the existing
  `TransferService.kt`, and constraints exposed as settings (unmetered, charging).
  **Do not add a `BOOT_COMPLETED` receiver** — WorkManager reschedules itself
  across reboot. The backlog and the phase3 plan both say to add one; both are
  wrong and should be corrected in the same change. *(Built as written, except
  that the `setForeground()` promotion turned out to be **refused** for a
  background-started periodic wake on Android 12+ — measured, see Phase 8 — so
  a wake is capped at 8 minutes and a big backup runs in slices.)*
- **iOS** — do not build. See Phase 5.

### 4.c Backup as a first-class object — `[M]`

A discriminator, not a parallel object: `TaskKind {transfer, backup, photos}`
defaulting to `transfer` so existing persisted JSON round-trips untouched. A
**Back up a folder** flow that is not the advanced transfer dialog, hard-setting
`mode: copy` (never `sync`, never `move`), `keepReplaced: true` (the already
shipped recoverable-delete mechanism), and a per-device destination subfolder so
two devices backing up to one remote cannot collide. The panel renders a backup
with backup vocabulary and hides the transfer-mode chips, so it cannot be turned
into a destructive sync from inside it.

### 4.d Photo/camera-roll auto-backup — Android `[M]`, iOS not in v0.8

**Android is close to free, and that is the finding worth acting on.** The app
already holds `MANAGE_EXTERNAL_STORAGE`, and `state/local_locations.dart:198`
already surfaces `Camera (DCIM)` as a real path rclone's `local` backend reads. So
photo backup is a `backup` task over `/storage/emulated/0/DCIM` into
`remote:Airclone/Photos/<device>/` on the 4.b WorkManager path. **No new
permission is required.**

| OS | Mechanism | Permission | Notes |
| :--- | :--- | :--- | :--- |
| Android today | `local` over DCIM | **none new** | Simplest path by a wide margin |
| Android without All Files Access | MediaStore / Photo Picker | `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`, `…_VISUAL_USER_SELECTED` | rclone's `local` backend cannot read a `content://` URI — a much larger project |
| iOS | `PHPhotoLibrary` | `NSPhotoLibraryUsageDescription`, plus `.limited` handling | Assets are not files; they must be exported through `PHAssetResourceManager` first, doubling storage during a backup |

Constraints on every platform: **`copy` only, never `move` or `sync`** — a
camera-roll backup that deletes is a data-loss incident, not a feature; an upload
ledger keyed on stable asset identity so a re-run does not re-hash the roll; and
**Wi-Fi-only by default**, because a 40 GB roll on cellular is a bill.

### 4.e The delete cap, and the circuit breaker — `[S]`

Decided by the user, 2026-09-09. Three parts, and the third is the one that turns
a cap from a nuisance into a safety feature.

**1. rclone genuinely supports this, and there are two different flags.** For
one-way `sync`/`copy`/`move`, `--max-delete` is a **count** of files, wired here as
`_config['MaxDelete']` (`state/transfer_options.dart:412-416`, applied only when
`mode == sync`). For `bisync` it is a **percentage**, defaulting to 50
(`transfer_options.dart:51` `maxDeletePercent`). So two-way sync already ships with
a safety net and one-way sync ships with none — `maxDeleteFiles` is `int?`,
default `null`, rendered as `hintText: 'no cap'`.

**What the flag does, precisely, so the UI does not overstate it:** rclone deletes
*during* the run and aborts once the limit is exceeded. It is a **blast-radius
limiter, not a preflight veto** — deletions up to the cap can already have
happened when it trips. "Abort after 100" is enormously better than "delete all
40,000", but it is not "nothing was deleted", and the wording must not imply it.

**2. A default, editable while setting the schedule up.** Proposed default:
**100 files**. The reasoning, since a number pulled from nowhere is worse than
none: the catastrophic case this guards is a source that vanished or emptied, where
rclone would delete the *entire* destination — so any cap far below a real
destination's file count catches it. 100 is high enough not to trip on ordinary
churn (a user tidying a folder) and low enough that a wipe of anything substantial
aborts. The schedule editor shows it **pre-filled, not blank**, and for a repeating
`sync` it cannot be cleared.

**The gap 100 does not close, and what does:** a destination with fewer than 100
files can still be wiped without tripping. That case is covered by the other guard
in Phase B — a task whose **source resolves empty refuses to run at all**. The two
together cover both ends; neither covers both alone, and the plan should not
pretend the cap is sufficient by itself.

**3. Tripping the cap PAUSES THE SCHEDULER, for review.** Not just the task.
The causes of a sudden mass deletion are usually environmental — an external drive
not mounted, a remote whose token expired, a folder renamed — and those affect
*every* task pointing at that source or destination. Letting the other schedules
keep firing while one has already demonstrated the environment is wrong is how one
bad night becomes several.

- A persisted `schedulerPausedProvider` carrying **why**: which task, when, and
  the error.
- `recordRunOutcome` (`state/scheduler_controller.dart:177`) is the single
  convergence point where every scheduled run lands its `{ok, error}` — the
  breaker hooks there and nowhere else, so no future platform can bypass it.
- Paused is **loud**: a banner, not a line in a dialog behind advanced mode. The
  whole failure of this feature so far has been silence.
- Resuming is **explicit**. No auto-resume on next launch, no timeout — the point
  is that a human looks.
- Optional, per the request, but **defaulting to on**.

**Detection needs verifying, not guessing.** Over the RC there is no exit code —
only the error string in `job/status`. Matching rclone's max-delete message is
therefore load-bearing and must be **confirmed against a real aborted run** before
it is relied on. If the string proves unstable across rclone versions, the robust
fallback is to pause on *any* failure of a scheduled destructive sync, which is a
slightly blunter rule that cannot silently stop working. Do not ship a breaker
whose trigger has only been reasoned about.

### 4.f DECIDED by the user, 2026-09-09

- **Restore is in v0.8, in full.** Pick a backup, browse what it holds, restore a
  file or the whole folder, to its original place or elsewhere. This makes
  "backup" an honest word. It also means the restore path needs the same conflict
  preflight everything else got in v0.7.6 — restoring *over* live files is a
  write, and it must ask.
- **Retention: keep 30 days, configurable.** A prune pass that understands the
  `keepReplaced` suffix naming, plus a visible "versions are using X GB" so the
  cost is not invisible. Two traps: pruning must never touch a *current* file, only
  a suffixed version; and the prune itself is a delete loop over a remote, so it
  needs the same care as any other destructive path — dry-run-able, and bounded.
- **Photos: camera roll (DCIM) by default, with a picker to add more folders.**
  So the source is a *set* of folders, not a single fixed path.
  - That decides the layout question by implication: **mirror the source
    structure**, since an arbitrary user-chosen folder has no "capture date"
    meaning. By-date remains offerable for the camera roll alone, later.
  - **Still open, and I am defaulting rather than guessing:** videos are included
    (they live in DCIM and a camera-roll backup missing them would surprise
    people) but get their own toggle, because they dominate the byte count and the
    first run's duration.

### 4.h Where it lives in the UI

**Split by activity, not by feature.** Monitoring is continuous and deserves
persistent chrome; setting a backup up is occasional and deserves a door, not a
permanent panel. Putting both in one place is what produces either clutter or a
fifth hiding place, and this feature already has four.

**Monitoring → a third tab in the bottom dock**, beside `Transfers` and
`Recent activity` (`ui/jobs_dock.dart:41-42`). Call it **Scheduled**.

That dock is already the answer to "what is my data doing", which is exactly the
question "did my backup run last night?" is a form of. It costs no new top-level
chrome, it is already resizable (v0.7.1), and it is where someone will look first
without being told. Contents: each task with its next run, its last outcome, a
**Run now**, and a per-task pause. This is also the natural home for the **staleness
warning** — "Photos: last succeeded 9 days ago" belongs next to the runs, not in
Settings.

**The circuit breaker is louder than a tab.** When it trips, the scheduler is off
and every schedule is silently not happening — a red dot on a dock tab is not
enough. It wants a dismissible banner across the top of the window, with the task,
the time, and Resume. Being noisy exactly once, when something is genuinely wrong,
is the whole point.

**Setup → a wizard, launched from that tab and from Settings.** "Back up a folder"
is a three-answer flow (what, where, how often) that someone runs a handful of
times, so it opens, asks, and closes. It is not the advanced transfer dialog and
must not become it — the constraints in §4.c (copy only, versions on, delete cap
defaulted) are what make it a backup rather than a transfer with different words.

**Restore reuses the browser, and this is the cheap win.** A backup destination is
an ordinary remote folder. "Restore from this backup" can open it in the other
pane, at the right path, in the view the user already knows — and then restoring is
copying, through the same conflict preflight that v0.7.6 gave every other transfer.
Almost no new UI, and it inherits every guard rather than growing its own.

**Rejected, with reasons, so they are not re-proposed:**

- *A new top-level section beside the browser.* This is a file manager; a
  permanent Backup mode competing with the panes costs chrome every day to serve
  something used monthly.
- *Settings → Automation as the only home.* Settings is where you configure, not
  where you check. "Did it run?" asked in Settings is a design that answers the
  wrong question. (It still gets a link — just not the primary door.)
- *A sidebar section.* The sidebar is places. Tasks are activities. Mixing them
  breaks the one mental model the sidebar currently has.

**Advanced mode:** the Scheduled tab and the backup wizard are **not** advanced-
gated. The raw saved-task editor, with full `TransferOptions`, stays advanced —
that split is what §4.a is for, and it is the difference between "a backup" as a
concept an ordinary user has and "a saved transfer task with an options payload",
which is not.

### 4.g What people expect that is not yet in this plan

Written down because the gap between "a scheduled copy runs" and "a backup
feature" is mostly these, and every one of them is something a user assumes is
there until the day they need it.

- **🔴 Restore.** The plan describes writing a backup and never reading one back.
  A backup you cannot restore from is a copy. At minimum: pick a backup task, pick
  a point, browse what it holds, restore a file or the folder — to its original
  place or somewhere else. This is the single biggest omission and it is not small.
- **🔴 Retention for replaced versions.** `keepReplaced` renames the old copy with
  a suffix rather than losing it, which is right — and nothing ever removes those.
  A daily backup of a churning folder grows without bound, silently, on storage
  the user pays for. Needs a policy ("keep 30 days" / "keep 10 versions") and a
  way to see what it is costing.
- **🔴 "Your backup has not run since…".** Silent failure is what actually kills
  backups: it stops working, nobody notices, and the discovery happens on the day
  it was needed. A staleness warning is worth more than most of the rest of this
  plan.
- **Run now.** Test a schedule without waiting for its slot. Nobody trusts a
  schedule they have not seen fire once.
- **Pause one task**, not just the global breaker.
- **Do not stack runs.** If a run is still going when the next slot arrives, skip
  rather than start a second one over the same destination.
- **Sensible default exclusions** on a folder backup — `node_modules`, `.git`,
  `Thumbs.db`, `.DS_Store`, partial-download files. Offered, not imposed.
- **Backup to an encrypted remote** as a first-class choice; the crypt wizard
  already exists, so the flow can offer it rather than making the user go and
  build one first.
- **Bandwidth limit while a backup runs**, so an overnight job does not make the
  connection unusable if it slips into the working day. `core/bwlimit` is wired.

Photo backup specifically:

- **What counts as a photo.** Camera roll only, or screenshots, downloads and
  WhatsApp media too? People usually mean the camera roll and are surprised by
  the rest — but only some of them.
- **Videos or not.** A separate toggle. Videos dominate the byte count and the
  first run's duration.
- **How it is organised at the destination:** mirror DCIM, or reorganise by
  capture date (`2026/09/…`). Mirroring is honest and predictable; by-date is what
  most photo tools do and what most people picture.
- **Progress that means something** — "1,204 of 8,331" beats a spinner on a job
  that runs for hours.
- **HEIC and Live Photos** — a Live Photo is a still plus a paired video, and
  backing up only one half is a data-loss surprise nobody expects.

## 5️⃣ Phase 5: Product Owner Review — risks and traps

* **Status:** `PENDING`
* **Findings:**
  - [🚫] **A scheduled destructive sync carries no confirm and no cap. This is the
    most serious finding here.** `ui/transfer_options_dialog.dart:14-19` documents
    that the destructive-sync confirm deliberately does not fire when `isRunNow`
    is false, and `ui/tasks_panel.dart:199` creates tasks with that default.
    Meanwhile `maxDeleteFiles` defaults to `null` (`state/transfer_options.dart:105`),
    rendered as `hintText: 'no cap'`, and `MaxDelete` is only sent when non-null.
    Neither `scheduler_controller.dart` nor the headless path adds a gate — both
    call `transferAdvancedRaw` directly. **The one transfer shape this codebase
    guards hardest is the one that can be scheduled unattended, uncapped and
    unconfirmed.** Required: a destructive-intent acknowledgement at *definition*
    time, worded for a repeating unattended run rather than one happening now; a
    mandatory delete cap on any repeating `sync`, defaulted rather than blank; a
    visible failure trace that does not require finding a dialog behind advanced
    mode; and an empty-source refusal, since an empty source is how a sync wipes a
    destination.
  - [🚫] **Uninstall residue, verified, and about to get worse.**
    `app/windows/installer/airclone.iss` has no `[UninstallRun]` and no `schtasks`
    call, so Windows tasks survive uninstall pointing at a deleted exe. Deleting a
    task in-app *does* unregister, so only uninstall is unclean. **The other
    platforms are worse: they have no uninstaller at all** — macOS ships as a DMG
    dragged to the Trash, Linux as a tarball the user deletes. A LaunchAgent or a
    systemd timer would survive both, forever, pointing at nothing. Adding macOS
    and Linux without solving this multiplies a known defect by three. Required,
    and what makes the unified `--run-due` design worth it: one registration under
    one known name; an `[UninstallRun]` on Windows; **reconcile-on-launch** that
    removes any registration whose target path is no longer us or whose task list
    is empty; and an explicit **"Remove all background scheduling"** in Settings.
  - [⚠️] **iOS cannot host this feature, and the plan should say so plainly rather
    than defer vaguely.** iOS permits `BGAppRefreshTask` (seconds, opportunistically
    scheduled from learned usage), `BGProcessingTask` (minutes, system-scheduled,
    in practice when idle and charging, with no time-of-day guarantee), and
    background `URLSession` for transfers *the system* performs. That last is the
    killer: the in-process librclone engine does its own HTTP inside the app
    process, so it cannot hand work to a background `URLSession` without replacing
    rclone's transport. **iOS can offer "back up when you open the app" and an
    opportunistic task that may run tonight or Thursday. It cannot offer "every
    day at 9pm".** A daily/weekly picker on iOS would be a lie the OS enforces.
  - [⚠️] **Android battery optimisation and foreground-service limits.** Doze and
    App Standby defer periodic work; a rarely-opened app lands in `RARE` or
    `RESTRICTED` and its 15-minute period becomes hours. Android 12+ forbids
    starting a foreground service from the background except through sanctioned
    routes — WorkManager's `setForeground()` was assumed to be one, which is why
    4.b routes through it. **Measured wrong (2026-09-09, Phase 8):** for a
    periodic wake started in the background the promotion is refused; only
    expedited work and a visible app are exempt. Android 15 caps `dataSync` runtime at roughly 6h/day, after which
    `onTimeout()` fires, so a first full roll backup must be **resumable**, not
    restart-from-zero. **Do not request `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`** —
    Play policy restricts it, and risking the listing to shave scheduling latency
    is a bad trade. Detect the restricted state and explain it instead.
  - [⚠️] **The SharedPreferences race gets worse.** `headless_runner.dart:31-37`
    already documents a last-writer-wins race between a headless run and a live
    GUI, accepted because "background runs are expected with the app closed". A
    `--run-due` poll every 15 minutes **regardless** breaks that assumption — the
    two will now routinely overlap. Cheapest fix: the OS job no-ops when a GUI
    instance is live.
  - [⚠️] **The encrypted-config gate lives in the wrong layer** — implemented in
    the Windows dialog path (`ui/tasks_panel.dart:843-864`). Every new platform
    would re-implement it, and one that forgets ships a schedule that exits 2 on
    every fire with no history entry, invisibly. Move it into the shared policy
    layer before the second platform lands, not after.

## 6️⃣ Phase 6: Senior Dev Hygiene Review

* **Status:** `PENDING`
* **Findings:**
  - [⚠️] **DRY** — `_canOsSchedule` must be **deleted**, not supplemented. One
    provider read by every surface. Three scattered platform checks is how the
    current invisibility happened.
  - [⚠️] **Abstraction** — `WindowsTaskScheduler` is well-shaped (pure
    `buildTaskXml` plus an injectable `ProcessRunner`). Extract an `OsScheduler`
    interface so launchd and systemd get the same split and the same unit tests
    `app/test/windows_task_scheduler_test.dart` already gives Windows.
  - [⚠️] **Technical debt** — existing per-task Windows registrations must be
    migrated and removed, not abandoned. An abandoned one re-fires forever.
  - [✅] **Error handling** — the inline-surface-never-throw discipline in
    `register()` / `_save()` is right; copy it verbatim.
  - [⚠️] **Testability** — `dueTasks`, `isDue`, `nextRun` and `buildTaskXml` are
    pure and already covered. Every new definition builder — plist, unit file —
    lands the same way: a pure function pinned by a golden-string test, **before**
    any process is spawned.

## 7️⃣ Phase 7: Implementation Checklist

Phases A–C are the release; D–F are the stretch and may slip without making A–C
incoherent.

- `[~]` **A — Visibility and honesty `[S]`.** Half landed 2026-09-09:
  - `[x]` **Settings → Automation, not advanced-gated.** States what a schedule
    means on this platform, lists every scheduled task with cadence / next run /
    last outcome, surfaces a tripped breaker, and opens the panel. A widget test
    pumps it with advanced mode forced OFF, because that is the regression.
  - `[x]` **`scheduling_policy.dart` replacing `_canOsSchedule`.** A
    `SchedulingSupport` of `background` / `whileOpen` / `none`, decided by a pure
    function of the OS name so it is testable from any platform, plus the one
    honest sentence per level. An unknown OS gets `none`, not a guess.
  - `[x]` **README corrected** — it promised scheduling with no platform
    distinction, which understated Windows and was simply wrong on a phone.
  - `[x]` **`feat-scheduling.md` written.**
  - `[x]` **From/To picker** — `ui/from_to_picker.dart`. The panes now only
    pre-fill it; they are no longer a requirement, so the whole chain
    Settings → Automation → Saved tasks → New task works in easy mode with one
    pane. It refuses only the source-equals-destination case, with the reason
    shown rather than just a disabled button.
  - `[~]` **Mobile entry point.** Settings reaches a phone, so the door is
    there. The blocker turned out NOT to be scheduling: `transfer_options_dialog`
    is a hard-coded `SizedBox(width: 720, height: 560)` and overflows by 115 px
    at 375×812 (measured 2026-09-09) — exactly the fixed-desktop-width dialog
    problem `DialogBody` exists to solve. Tracked separately; it blocks task
    creation on mobile generally, not just scheduling.
- `[~]` **B — Safety for unattended runs `[S]`.** Half landed 2026-09-09:
  - `[x]` **Delete cap defaulted to 100 and not clearable** on a repeating sync.
    `withScheduledDeleteCap` in `state/transfer_options.dart` applies it at RUN
    time (so tasks saved before the cap existed are covered — those are exactly
    the uncapped scheduled syncs already sitting in people's configs), and the
    schedule editor pre-fills the number so it is applied visibly rather than
    silently. Blanking the field saves the default, never "unlimited".
  - `[x]` **Circuit breaker that pauses the whole scheduler on a trip** (§4.e).
    `state/scheduler_pause.dart` — persisted, global, no auto-resume; hooked at
    `recordRunOutcome`'s single terminal path, checked at the top of `tick()`,
    and surfaced as a banner with the engine's verbatim error plus a Resume
    button at the top of the tasks dialog.
  - `[x]` **Empty-source refusal.** `SchedulerController._sourceIsUnsafe` — a
    scheduled one-way Sync lists its source before dispatching and refuses if it
    is empty **or unreadable**. Unreadable counting as unsafe is a deliberate
    difference from the interactive preflight: a human watching a preview can be
    told "could not read that" and decide, a timer at 3am cannot. The refusal is
    recorded as a failed run so it shows up in Settings → Automation rather than
    being the silent stop this whole feature exists to prevent. Copy, Move and
    bisync are not gated — none of them deletes at the destination to match a
    source.
  - `[x]` **A failure trace outside advanced mode.** The Automation section's
    per-task row shows the last run's outcome with the engine's error verbatim.
  - `[ ]` Definition-time destructive acknowledgement. **Reconsider before
    building:** the schedule editor already states, at definition time, that Sync
    deletes whatever the source no longer has, that an empty source means the
    whole destination, and the exact cap number it will stop at. A separate
    "I understand" checkbox on top of that is a click-through, and click-throughs
    train people to dismiss the warning that matters. Decide whether this item
    still earns its place.

  **Still unverified:** `isDeleteCapError` is a text match against rclone's
  error string (the RC gives no exit code) and has NOT been checked against a
  real aborted run. If the wording varies across rclone versions, the fallback
  is to pause on any failure of a scheduled destructive sync — blunter, but it
  cannot silently stop working, and silently-stopped-working is the failure this
  whole feature exists to prevent.
- `[~]` **C — Unify on `--run-due` and clean up after ourselves `[M]`.**
  - `[x]` **Uninstall leaves no scheduled tasks behind.** `RemoveScheduledTasks`
    in `windows/installer/airclone.iss` clears the whole `Airclone\` task folder
    at `usPostUninstall`, unconditionally. Shape-independent — it is the right
    cleanup whether registration stays per-task or becomes unified — so it landed
    without waiting on that decision. Verified against a real Task Scheduler, not
    reasoned about; see `dev/windows-signing-and-store.md` for the two things
    that did not work.
  - `[~]` **HYBRID, decided by the user 2026-09-09** — not unified, and not
    per-task either. The rule is in `state/registration_policy.dart` and it is a
    rule rather than a preference: **a schedule that names an exact time gets an
    exact OS trigger; one that names only a gap joins a single shared poller.**
    A daily 09:00 task should fire at 09:00, which Task Scheduler does for free
    with no wakeups in between and a poller can only approximate; an "every two
    hours" task is already polling by nature, so a private OS entry buys nothing
    and adds a second wakeup source to keep in sync. This also keeps what the
    unified shape would have cost — a power user can still see and disable their
    daily and weekly schedules individually in Task Scheduler.
    - `[x]` The rule, `desiredRegistrations` (both halves decided together, so
      the poller cannot be orphaned), and `buildDueRunnerXml`.
    - `[x]` **Cadence is the user's, default 15 minutes**, choosable from
      5/10/15/30/60 and clamped rather than snapped so a hand-edited or legacy
      value is honoured if sane. It only bounds lateness for the schedules that
      reach the poller at all — a daily 09:00 task is unaffected, which is worth
      saying in the UI before someone turns it down to 5 for no benefit.
    - `[x]` **Reconciling, and the migration inside it.**
      `WindowsTaskScheduler.reconcile` makes Task Scheduler match the saved
      tasks; `planReconcile` decides what to create and delete. The migration is
      not a migration: a per-task entry for an interval schedule is simply *not
      desired* any more, so it appears in `toDelete` like any other stale
      registration. No version check, no one-shot upgrade step to get wrong, and
      the code that keeps things right every day is the code that cleans it up.
    - `[x]` **`TransferTask.runWhileClosed`, persisted.** It used to be probed
      from Task Scheduler, which worked only while every task had its own entry.
      Absent from old JSON, so it loads false — and a reconcile against that
      reads "nobody wants background runs" and deletes the lot. `seedRunWhileClosed`
      runs first at launch and carries the opt-in forward from what is actually
      registered. It only ever turns the flag **on**: a failed `listRegistered()`
      returns an empty set, and inferring opt-out from that would undo a choice
      rather than recover one.
    - `[x]` **Reconcile-on-launch**, from `SchedulerController.build()` — the
      provider HomeScreen force-reads at startup, so it cannot be skipped by a
      widget that never builds. It waits for the saved tasks to hydrate first;
      acting on the empty list `build()` returns would unregister everything.
      (`test/reconcile_launch_test.dart`.)
    - `[ ]` "Remove all background scheduling" as an explicit control — the
      one piece of C still open.
  - `[~]` **GUI-live no-op to close the prefs race.** Done on Android: the
    periodic wake returns immediately when an Activity is on screen
    (`DueTasksWorker.kt`). NOT done on Windows — `headless_runner.dart` still
    documents the last-writer-wins race as accepted, and the shared poller now
    fires every 15 minutes regardless.
- `[ ]` **D — macOS launchd + Linux systemd-user `[M]`.** Untouched, and
  slipping past v0.8. Pure builders with golden tests first; verify the macOS
  headless launch shows no Dock icon **before** shipping; surface the linger
  requirement.
- `[x]` **E — Backup as a first-class task `[M]`.** Shipped, and further than
  this line asked: `TaskKind {transfer, backup, photos}` with the three
  constraints re-applied at run time (`state/task_kind.dart`); the wizard
  (`ui/backup_wizard.dart`, not advanced-gated, desktop and Android); the
  per-device destination (`state/backup_task.dart`); retention + the dry-run-by-
  default prune with its 500 cap and keep-when-ambiguous rules
  (`state/backup_retention.dart`, `state/backup_prune.dart`); restore as
  open-in-the-other-pane (`ui/backup_actions.dart` → `openBackupForRestore`)
  and the cleanup dialog that shows "Delete N old versions (X MB)" before it
  does. Documented in `wiki/features/feat-backup.md`. Still open there: no
  scheduled prune, no standing "versions are using X GB" figure.
- `[x]` **F — Android background + photo backup `[L]`.** Shipped, bar the
  battery-optimisation UX (last item). Landed 2026-09-09:
  - `[x]` **Application-scoped `airclone/native` channel** — `NativeChannel.kt`,
    built on the application `Context` with the Activity as an optional
    provider; `MainActivity` registers it and a worker registers the same
    handler on its own headless engine. `AircloneApplication` also tracks
    whether an Activity is on screen.
  - `[x]` **WorkManager periodic wake** — our own `DueTasksWorker.kt`
    (`CoroutineWorker`, no `workmanager` plugin): boots a second
    `FlutterEngine`, runs `androidWorkEntrypoint` →
    `runHeadlessInProcess(--run-due)`, *attempts* `setForeground()` reusing
    `TransferService`'s notification channel (refused on Android 12+ for a
    background-started periodic wake — see Phase 8 — so the run is then capped
    at 8 minutes and proceeds in slices), yields when the app is on screen (the
    in-app scheduler owns due tasks then), and stamps its outcome for Settings. `WorkChannel.kt` + `state/android_work_channel.dart`
    enqueue/update/cancel the one unique request; `android_work_registration.dart`
    is the pure rule + reconciler (force-read from HomeScreen).
  - `[x]` **Constraints as settings** — `android_work_settings.dart`: Wi-Fi-only
    (default ON) and charging (default OFF); Settings → Automation →
    "Background on this phone".
  - `[x]` **Camera-roll backup** — `state/photo_backup.dart` +
    `ui/photo_backup_section.dart`: a set of folders under internal storage
    (DCIM default, add via the in-app folder picker — never SAF), mirrored into
    `remote:Airclone/Photos/<device>/`, videos on their own toggle, copy-only
    via `backupOptions`, `runWhileClosed: true`. Rules are an ORDERED
    `--filter` list (video excludes, then folder includes, then `- **`) — a
    mixed include/exclude would let the include win first.
  - `[x]` **Headless path now enforces what the in-app path does** —
    `headless_runner.dart` applies `backupOptions` / `withScheduledDeleteCap`
    and the empty-source refusal; it used to dispatch raw options.
  - `[x]` `BOOT_COMPLETED` guidance corrected in `dev/backlog/feature-backlog.md`
    and `dev/plans/phase3-continuation-plan.md`.
  - `[x]` `scheduling_policy.dart` now maps `android` to `background`, so
    Settings → Automation's sentence and the "Also run while closed" checkbox
    (`canRunWhileClosed`) know the platform can run in the background.
  - `[ ]` Battery-optimisation state detection and explanation (never the
    exemption request). **The one piece of F still open.**

**Explicitly not doing in v0.8:** cron; iOS background execution; iOS photo
backup; `DocumentsProvider` / File Provider; a filesystem watcher; deleting source
media after upload.

## 8️⃣ Phase 8: Verification Dashboard

* **Verification Status:** `PENDING`
* **Report:**
  - `[~]` A schedule registered through the OS path **actually fires with the
    app closed**, proven by the run landing in `TaskRunRecord` — not by the
    registration call returning 0. A clean exit code proved nothing in the
    mount-tuning plan either. **Android: proven** (the last two items below).
    **Windows: not recorded here** — nothing in this plan cites a run that
    Task Scheduler started landing in a task's history.
  - `[x]` Uninstall (Windows) leaves **no** registration behind — verified
    against a real Task Scheduler (Phase 7 C, `RemoveScheduledTasks` in
    `airclone.iss`; the two things that did not work are in
    `dev/windows-signing-and-store.md`).
  - `[ ]` Delete-the-app (macOS, Linux) leaves **no** registration behind.
    Not applicable until Phase D registers anything there.
  - `[ ]` Golden-string tests pin the plist and unit-file output before any
    `launchctl` or `systemctl` is spawned.
  - `[x]` A repeating `sync` cannot be saved without a delete cap. Covered by
    `test/scheduler_delete_cap_test.dart` (the helper, and the cap reaching the
    engine as `_config.MaxDelete`) and `test/scheduler_pause_ui_test.dart` (the
    editor pre-fills it; an emptied field saves the default, not "no cap").
    Both suites were confirmed RED against the code with the fix removed.
  - `[ ]` A run that trips the cap actually pauses the scheduler **against a
    real rclone abort**, not a synthesised error string. This is the one that
    matters and the one still outstanding — see the caveat in Phase 7 B.
  - `[ ]` macOS: a `--run-due` launch shows no Dock icon and steals no focus.
  - `[x]` Android: a periodic run survives reboot with no `BOOT_COMPLETED`
    receiver, confirming the correction to the backlog. **Verified 2026-09-09
    on the API 35 emulator:** `adb reboot`, then WorkManager's own diagnostics
    (`am broadcast -a androidx.work.diagnostics.REQUEST_DIAGNOSTICS`) list
    `DueTasksWorker · ENQUEUED · airclone.run-due` and `dumpsys jobscheduler`
    holds `androidx.work.systemjobscheduler:u0aNNN/3`; the only
    `BOOT_COMPLETED` receivers on the package are WorkManager's
    `RescheduleReceiver` and the profile installer's.
  - `[x]` Android: the background worker actually runs a due task with NO
    Activity: proven 2026-09-09 — the headless engine reached
    `nativeLibraryDir`, spawned rclone, and logged
    `[OK  ] Photo backup [photo-test-1] — 181555 bytes` with exactly the four
    JPGs mirrored under `…/Photos/<device>/DCIM/Camera/` and the `.mp4`
    excluded. **Measured, contradicting §4.b / Phase 5:** Android 15 REFUSES
    `setForeground()` to a periodic wake started in the background
    (`startForegroundService() not allowed due to mAllowStartForeground
    false`) — it is not one of the 12+ exemptions; only expedited work and a
    visible app are. A background wake therefore runs inside the plain
    worker's ~10-minute budget (the Dart run is capped at 8 min so it ends
    cleanly), and a big first backup proceeds in slices, one per wake,
    resuming where it stopped. The promotion does succeed for the one-off the
    user launches from inside the app.

## 9️⃣ Phase 9: User Verification

* **Status:** `PENDING`
* **User Feedback:** The report that opened this plan — *"the README advertises
  scheduling, I don't see this feature"* — is the acceptance test. Close it by
  having them find scheduling **without being told where it is**.

## 🔟 Phase 10: Wrap Up & Archival

* **System Context Updates:** `wiki/features/feat-scheduling.md` (new, and overdue
  — `features-index.md:22` has referenced it while it did not exist);
  `dev/backlog/feature-backlog.md` updated for the platforms that land, the
  uninstall defect closed if it ships, and the `BOOT_COMPLETED` guidance
  corrected; `dev/plans/phase3-continuation-plan.md` items 3 and 4 marked against
  reality.
