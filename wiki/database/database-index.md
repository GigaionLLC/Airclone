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
| App settings | `db-settings.md` | platform store (file / preferences) | Theme, language, default flags, tray/auto-launch, mount defaults. |
| Schedules | `db-schedules.md` | local file / preferences | Saved sync jobs + cron/trigger definitions. |
| Secrets | `db-secrets.md` | OS keychain / secure storage | Config password, RC credentials — never plain text. See [Security](../core/15-security.md). |
| VFS / preview cache | `db-cache.md` | temp dir | Transient; safe to clear. |
