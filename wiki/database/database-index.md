---
type: "index"
name: "Persistence Index"
status: "seed"
description: "Local persistence: rclone config, app settings, schedules, and caches."
---

# 🗄️ Persistence Index

Airclone is largely **stateless about file data** — the source of truth for remotes is rclone's own
`rclone.conf`. This index covers what Airclone *does* persist locally.

## 💾 Persisted Stores (seed)

| Store | Doc | Backing | Notes |
| :--- | :--- | :--- | :--- |
| rclone config (remotes) | `db-rclone-conf.md` | `rclone.conf` via `/config/*` | Never hand-edited; managed through the RC API. May be password-encrypted. |
| Config backups | `db-config-backups.md` | `<app support>/config-backups/rclone-<UTC stamp>.conf` | Snapshot taken **before** any mutating config op (import, replace, restore, remove-all); ten newest kept, older pruned. The reason those actions are offerable at all — see [Remote & Config Management §5](../features/feat-config-management.md). |
| App settings | `db-settings.md` | platform store (file / preferences) | Theme, language, default flags, tray/auto-launch, mount defaults. Also two small opt-ins: **`recents_enabled`** (off by default) and **`mount_letters_v1`**, a `fs` → mount-point map so a remote lands on the same drive letter every time. |
| Schedules | `db-schedules.md` | local file / preferences | Saved sync jobs + cron/trigger definitions. |
| Secrets | `db-secrets.md` | OS keychain / secure storage | Config password, RC credentials — never plain text. See [Security](../core/15-security.md). |
| VFS / preview cache | `db-cache.md` | temp dir | Transient; safe to clear. |

> **Which provider owns each store, and what it actually persists**, is mapped per-provider in
> [State & Context](../core/07-state-context.md). Config read/write goes through the engine's
> `config/*` RC methods — catalogued in [External Integrations](../core/10-external-integrations.md).

## 🚫 Deliberately *not* persisted

Some state is session-only on purpose, and writing it to disk would be a regression, not a feature:

| State | Why it dies with the process |
| :--- | :--- |
| The **recent folders** trail | The *switch* persists, the list does not. A trail nobody opted into puts remote and folder names on the first screen of the app; turning the switch off drops what was already collected rather than hiding it. |
| The **copy/cut clipboard** | A pointer at names inside a folder that may not exist tomorrow. |
| The **marked sync source** | A mark that survived a restart would be a forgotten pointer attached to an operation that **deletes** — see [File Browser §5.2](../features/feat-file-browser.md#52-marked-sync-source-sync-to-here). |
| The **undecryptable-name counter** | A monotonic session counter sampled across one listing, not a record of anything. |
