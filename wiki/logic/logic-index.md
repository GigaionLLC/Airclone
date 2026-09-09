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
| In-process transport (iOS + Mac App Store) | `util-librclone-transport.md` | Calls `librclone`'s C ABI (`RcloneRPC(method, input)`) in-process over `dart:ffi`. |
| Provider schema → form | `util-provider-schema.md` | Turns `/config/providers` option schemas into dynamic config forms. |
| Job/stats polling | `util-jobs.md` | Async job lifecycle, `/job/status`, `/core/stats` grouping, progress. |
| Formatters | `util-format.md` | Bytes, transfer rates, durations, ETA. |

## 🧪 Shipped decision helpers (pure — reuse these, don't re-derive them)

These are the small, engine-free functions that decide whether an action is safe. They are pure so the
rule is unit-tested without an rclone, and each one exists because the *impure* version of it lost
somebody's data at least once.

| Helper | Where | What it decides |
| :--- | :--- | :--- |
| `planPaste` / `uniqueName` | [`name_conflict.dart`](../../app/lib/src/state/name_conflict.dart) | Names → the concrete transfer list under Skip / Replace / Keep-both. `uniqueName` puts the counter before the extension (`report (2).pdf`) and counts against names already handed out in the same batch. |
| `syncTargetRefusal` | [`sync_source.dart`](../../app/lib/src/state/sync_source.dart) | Whether a source/destination pair overlaps (identical or nested, either direction, case-insensitive, `\` normalized) — and therefore must be **refused**, not warned about. A shared name prefix is not containment. |
| `previewFrom` / `previewConfig` | [`sync_preview.dart`](../../app/lib/src/state/sync_preview.dart) | An `operations/check` comparison → what a transfer would create, overwrite and delete under this mode and these flags; and the minimal `_config` a preview must compare under so its idea of "differs" matches the run's. |
| `hiddenForBackend` | [`undecryptable_names.dart`](../../app/lib/src/state/undecryptable_names.dart) | How many entries rclone withheld from one listing may honestly be attributed to this pane. Errs toward a miss, never a false alarm. |
| `existingRemoteNames` | [`remotes_provider.dart`](../../app/lib/src/state/remotes_provider.dart) | Whether a remote name is free — returning `null`, not an empty set, when the config cannot be read, so an unreadable config can never read as "free". |

The user-facing behaviour these sit under is
[File Browser §5.1–5.2](../features/feat-file-browser.md#51-nothing-lands-on-an-existing-name-without-asking)
and [Remote & Config Management §2](../features/feat-config-management.md).

> **Where these topics live today.** The per-module docs above are still seeds; the shipped behaviour
> is documented in the core brain. Check there before writing a new helper:
> the `RcloneClient` seam and both transports → [External Integrations](../core/10-external-integrations.md);
> existing formatters and their precision rules → [Utility Standards](../core/12-utility-standards.md);
> job/stats polling budgets → [Performance & Reliability Standards](../core/14-performance-standards.md)
> and [State & Context](../core/07-state-context.md);
> input checks and error surfacing → [Validation Standards](../core/11-validation-standards.md).
