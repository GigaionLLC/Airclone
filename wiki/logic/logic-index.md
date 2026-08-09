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
| RcloneClient interface | `util-rclone-client.md` | The single contract the UI uses to drive rclone (JSON method surface). Satisfied by the desktop `rcd`-HTTP transport and the mobile in-process `librclone` transport. |
| Daemon transport (desktop) | `util-rcd-transport.md` | Spawns/manages `rclone rcd`, talks RC over loopback HTTP with auth. |
| In-process transport (mobile) | `util-librclone-transport.md` | Calls `librclone`/gomobile `RcloneRPC(method, input)` in-process. |
| Provider schema → form | `util-provider-schema.md` | Turns `/config/providers` option schemas into dynamic config forms. |
| Job/stats polling | `util-jobs.md` | Async job lifecycle, `/job/status`, `/core/stats` grouping, progress. |
| Formatters | `util-format.md` | Bytes, transfer rates, durations, ETA. |

> **Where these topics live today.** The per-module docs above are still seeds; the shipped behaviour
> is documented in the core brain. Check there before writing a new helper:
> the `RcloneClient` seam and both transports → [External Integrations](../core/10-external-integrations.md);
> existing formatters and their precision rules → [Utility Standards](../core/12-utility-standards.md);
> job/stats polling budgets → [Performance & Reliability Standards](../core/14-performance-standards.md)
> and [State & Context](../core/07-state-context.md);
> input checks and error surfacing → [Validation Standards](../core/11-validation-standards.md).
