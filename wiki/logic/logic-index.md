---
type: "index"
name: "Logic Index"
status: "seed"
description: "Core utilities, helpers, and the rclone control layer."
---

# 🧠 Logic Index

Core non-UI logic: the rclone control layer and shared utilities.

## ⚙️ Planned Modules (seed)

| Module | Doc | Purpose |
| :--- | :--- | :--- |
| RcloneClient interface | `util-rclone-client.md` | The single contract the UI uses to drive rclone (JSON method surface). Satisfied by the spawned-`rcd` HTTP transport and the in-process `librclone` transport; [08](../core/08-core-architecture.md) §3 owns which runs where. |
| Daemon transport (desktop + Android) | `util-rcd-transport.md` | Spawns/manages `rclone rcd`, talks RC over loopback HTTP with auth. |
| In-process transport (mandatory on iOS / Mac App Store, selectable elsewhere) | `util-librclone-transport.md` | Calls `librclone`'s C ABI (`RcloneRPC(method, input)`) in-process over `dart:ffi`. The choice is `EngineMode` + `resolveEngineMode` in [`engine_mode.dart`](../../app/lib/src/state/engine_mode.dart): forced where a subprocess is disallowed, offered as a setting wherever the library is bundled, and picked by `auto` when no binary is available. |
| Provider schema → form | `util-provider-schema.md` | Turns `/config/providers` option schemas into dynamic config forms. |
| Job/stats polling | `util-jobs.md` | Async job lifecycle, `/job/status`, `/core/stats` grouping, progress. |
| Formatters | `util-format.md` | Bytes, transfer rates, durations, ETA. |

## 🧪 Shipped decision helpers (pure — reuse these, don't re-derive them)

These are the small, engine-free functions that decide whether an action is safe. They are pure so the
rule is unit-tested without an rclone. Most exist because the *impure* version of it lost somebody's
data at least once; the rest decide what the product may honestly promise before it promises it.

| Helper | Where | What it decides |
| :--- | :--- | :--- |
| `planPaste` / `uniqueName` | [`name_conflict.dart`](../../app/lib/src/state/name_conflict.dart) | Names → the concrete transfer list under Skip / Replace / Keep-both. `uniqueName` puts the counter before the extension (`report (2).pdf`) and counts against names already handed out in the same batch. |
| `syncTargetRefusal` | [`sync_source.dart`](../../app/lib/src/state/sync_source.dart) | Whether a source/destination pair overlaps (identical or nested, either direction, case-insensitive, `\` normalized) — and therefore must be **refused**, not warned about. A shared name prefix is not containment. |
| `previewFrom` / `previewConfig` | [`sync_preview.dart`](../../app/lib/src/state/sync_preview.dart) | An `operations/check` comparison → what a transfer would create, overwrite and delete under this mode and these flags; and the minimal `_config` a preview must compare under so its idea of "differs" matches the run's. |
| `hiddenForBackend` | [`undecryptable_names.dart`](../../app/lib/src/state/undecryptable_names.dart) | How many entries rclone withheld from one listing may honestly be attributed to this pane. Errs toward a miss, never a false alarm. |
| `existingRemoteNames` | [`remotes_provider.dart`](../../app/lib/src/state/remotes_provider.dart) | Whether a remote name is free — returning `null`, not an empty set, when the config cannot be read, so an unreadable config can never read as "free". |
| `isReplacedVersion` / `prunableVersions` / `prunableVersionsRecursive` | [`backup_retention.dart`](../../app/lib/src/state/backup_retention.dart) | What a prune may delete. `isReplacedVersion` is, in the file's own words, the single most dangerous predicate in the backup feature — a prune is a delete loop over a remote and a false positive deletes live data, so the suffix must be a whole dot-separated segment and never the first one. `prunableVersions` then keeps any version that is the **only** remaining copy of its live file; the recursive form groups by parent folder first, so `a/report.pdf` can never vouch for `b/report.replaced.pdf`. Deleting is elsewhere ([`backup_prune.dart`](../../app/lib/src/state/backup_prune.dart), dry-run by default and capped at `kMaxPrunePerPass` = 500). |
| `withScheduledDeleteCap` | [`transfer_options.dart`](../../app/lib/src/state/transfer_options.dart) | The delete cap (`kDefaultScheduledDeleteCap` = 100) a repeating one-way Sync gets when the user chose none. Applied when a task **runs**, not only when it is defined, so tasks saved before the cap existed are covered. A cap the user chose — including a deliberate `0` — is never overridden, and copy/move/bisync are returned untouched. |
| `backupOptions` / `isBackupShaped` | [`task_kind.dart`](../../app/lib/src/state/task_kind.dart) | The three constraints that make a task a backup rather than a transfer: copy (never sync or move), keep replaced versions, no dry run. Enforced at definition **and** again at run time, so a task edited through the raw advanced dialog cannot run as something else under a backup's name. |
| `schedulingSupportFor` | [`scheduling_policy.dart`](../../app/lib/src/state/scheduling_policy.dart) | What "run on a schedule" means on the platform you are standing on — `none` / `whileOpen` / `background` — from the OS name, so it is testable anywhere. An OS it has never heard of gets `none` rather than a guess: promising a background run that was never wired is the failure the file exists to stop. |
| `registrationShapeFor` / `desiredRegistrations` / `clampPollMinutes` | [`registration_policy.dart`](../../app/lib/src/state/registration_policy.dart) | How a schedule gets itself run while the app is closed: an exact wall-clock schedule takes its own OS trigger, an interval one joins the single shared `Run due tasks` poller, and a platform without background execution registers nothing. `desiredRegistrations` answers for the whole set at once, because reconciling "which triggers" and "does the poller exist" separately is how one of them ends up orphaned. |
| `seedRunWhileClosed` | [`scheduler_registration.dart`](../../app/lib/src/state/scheduler_registration.dart) | Carries a background opt-in forward that used to be inferred from Task Scheduler. Only ever turns the flag **on** — inferring "they must not want this" from an absent registration would undo a choice rather than recover one, and a reconcile run against un-seeded tasks would delete every registration. |
| `dueTasks` | [`scheduler_controller.dart`](../../app/lib/src/state/scheduler_controller.dart) | Which saved tasks are due at a given instant. Three gates in order: it has a schedule; it is not a two-way task whose baseline was never established (that first `--resync` is destructive and must be done by hand once); `isDue` fires for the schedule given `lastRun`. |

The user-facing behaviour these sit under is
[File Browser §5.1–5.2](../features/feat-file-browser.md#51-nothing-lands-on-an-existing-name-without-asking),
[Remote & Config Management §2](../features/feat-config-management.md),
[Backup §4](../features/feat-backup.md#4-versions-and-pruning-them) and
[Scheduling §5](../features/feat-scheduling.md#5-unattended-safety-the-delete-cap-and-the-circuit-breaker).

> **Where these topics live today.** The per-module docs above are still seeds; the shipped behaviour
> is documented in the core brain. Check there before writing a new helper:
> the `RcloneClient` seam and both transports → [External Integrations](../core/10-external-integrations.md);
> existing formatters and their precision rules → [Utility Standards](../core/12-utility-standards.md);
> job/stats polling budgets → [Performance & Reliability Standards](../core/14-performance-standards.md)
> and [State & Context](../core/07-state-context.md);
> input checks and error surfacing → [Validation Standards](../core/11-validation-standards.md).
