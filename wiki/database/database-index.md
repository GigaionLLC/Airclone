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
| App settings | `db-settings.md` | platform store (file / preferences) | Theme mode, rclone/config path overrides, engine mode and engine flags, mount defaults, download folder, view memory, sidebar and pane layout. Also two small opt-ins: **`recents_enabled`** (off by default) and **`mount_letters_v1`**, a `fs` → mount-point map so a remote lands on the same drive letter every time. |
| Schedules | `db-schedules.md` | inside the `transfer_tasks` preferences blob | A `TaskSchedule` — `interval` / `daily` / `weekly`, **no cron** — attached to a saved task, alongside that task's options, run history and background opt-in. Since v0.8 backups and camera-roll tasks live in the same list under a `TaskKind` discriminator, so this is every repeating job the app has, not just syncs. |
| OS background registrations | `db-os-registrations.md` | Windows Task Scheduler · Android WorkManager | Outside the app's own stores, and they outlive the process: an exact schedule gets `Airclone\<task id>`, every interval one shares a single `Run due tasks` job, and Android holds one periodic request. Reconciled against the saved tasks at launch by `reconcileRegistrations` / `androidWorkReconcilerProvider` — the tasks blob above is the source of truth, these are a projection of it. |
| Survive-uninstall config backup (Android) | `db-external-backup.md` | `<shared storage>/Airclone/` | Opt-in: an encrypted copy of the config under a user passphrase (kept in the OS vault so the refresh runs unattended), or plaintext `rclone.conf` behind a danger screen. One file, and turning it off deletes it. The only store here designed to **survive an uninstall**, which is what drives the startup restore offer. |
| Secrets | `db-secrets.md` | OS keychain / secure storage | Exactly two keys: `airclone.configPassword` (opt-in, cleared when "remember" is turned off) and `airclone.externalBackupPassphrase` (the survive-uninstall passphrase). RC credentials are **not** among them — see *Deliberately not persisted*. See [Security](../core/15-security.md). |
| VFS / preview cache | `db-cache.md` | `<app cache>/airclone_thumbs/` and `<app cache>/airclone_folderthumbs/` (temp dir as fallback) | Transient; safe to clear. Encrypted at rest by `CacheCrypto`, and `cacheMemoryOnlyProvider` suppresses the disk writes entirely. |

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
| The **RC credentials** | Not a secret worth keeping. The `rcd` username and password are a fresh `Random.secure()` token minted per engine start and handed to the child on its command line, so there is nothing to store and nothing that outlives the process to leak. |
