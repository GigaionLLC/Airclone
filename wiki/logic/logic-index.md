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
