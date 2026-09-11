# Microsoft Store — listing details (English, United States)

Paste-ready copy for Partner Center → Store listing. The Microsoft Store release
is **paid**, so this copy does NOT claim the app is free / no-paywall. Windows-
desktop-focused (no mobile/enterprise details). Includes the rclone non-affiliation
line to avoid trademark/impersonation rejections.

⚠️ **Nothing in this repo pushes this text.** `tool/store_submit.py` creates a
submission by cloning the last published one — listing copy, screenshots, age rating
and pricing all carry over untouched, and only the packages change. Editing this file
therefore changes nothing in the Store until someone pastes the block into Partner
Center. **Pending paste as of 2026-09-10:** the transfers bullet no longer claims a
running transfer can be paused — only the *queue* can be
(`jobs_panel.dart`: *"queued transfers wait; running ones finish"*); scheduled tasks,
folder backup and the tree view are now in the Description and in Product features,
because v0.8 shipped all three while this copy still described a 0.7 app; and the
"What's new" block below was rewritten for 0.8.0.

> **DO NOT reorder the first two lines of the Description.** Store policy
> **10.2.4.1** requires any dependency on non-integrated software to be disclosed
> *within the first two lines*, and certification failed us on 2026-07-29 for an
> undisclosed **VC++** dependency. v0.5.5 also bundles the Visual C++ runtime
> app-local so the dependency is genuinely gone — line 2 keeps the reviewer from
> having to take that on faith. The **CLEAN REMOVAL** paragraph likewise answers
> policy **10.2.7** from the same report.
>
> ⚠️ **CLEAN REMOVAL is an EXE-channel promise today.** A schedule registers a
> Windows Scheduled Task under `Airclone\` (`app/lib/src/state/windows_task_scheduler.dart`),
> and the only code that removes those is `RemoveScheduledTasks` in the Inno
> uninstaller (`app/windows/installer/airclone.iss`) — which a Store MSIX never
> runs. Nothing gates the registration on the install channel either, so the
> packaged product can create entries it has no uninstall path to remove: the same
> 10.2.7 shape as the 2026-07-29 finding. Settle that before pasting a Description
> that says "removes Airclone completely". Walk the new scheduling bullet on a
> packaged install while you are there — registration points Task Scheduler at the
> executable inside `WindowsApps`, and nothing on record says a background run has
> ever been seen to fire from there.

---

## Description

```
Airclone is a modern, easy-to-use file manager for rclone.
Everything it needs is included in the download — the full rclone engine and the Microsoft Visual C++ runtime files ship inside the app, so there is no separate redistributable, runtime, or command-line tool to install.

rclone is a powerful open-source tool that can move and sync files across 70+ cloud storage services — Google Drive, Dropbox, OneDrive, Amazon S3, SFTP, WebDAV and many more. Airclone gives it a clean, fast interface, so you can manage all of your clouds from one app without ever touching the command line.

WHAT YOU CAN DO
• Browse every cloud like a local folder. Your PC's storage and all of your cloud remotes appear side by side in one window, with familiar rows, previews, and right-click actions.
• Move and copy files between clouds. Send a file straight from one cloud to another — the transfer runs as a background job you can watch or cancel, and you can pause the queue so nothing new starts.
• Sync and back up folders. Mirror, copy, move, or two-way sync, with a dry-run preview that shows exactly what will change before anything happens.
• Run it on a schedule. Give a sync or a backup a time — daily, weekly, or every few hours — and Windows runs it even with Airclone closed. Every scheduled task shows its next run and how the last one ended.
• Back up a folder. Three answers — what, where, how often — and it copies only, never syncing or moving. A file that gets replaced is kept beside the new one, so restoring an earlier version is a copy back out of the backup folder.
• See your photos and videos. Image and video thumbnails load right in the app for any remote, cached on your device.
• Open a folder as a tree. A pane can switch to an expandable hierarchy, loaded one folder at a time, so a deep structure is one window instead of ten.
• Work faster with power tools. A built-in rclone command console plus archive create and extract are a click away.
• Stay in control. Nothing is overwritten silently — every file collision asks first: skip, replace, or keep both.

PRIVATE BY DESIGN
Airclone runs entirely on your PC. There are no accounts, no tracking, and no telemetry. Your files and your cloud credentials never pass through our servers — because we don't have any.

BUILT ON RCLONE
The full rclone engine ships inside the app, so there is nothing else to install. Airclone is an independent companion to rclone and is not affiliated with, sponsored by, or endorsed by the rclone project.

CLEAN REMOVAL
Uninstalling removes Airclone completely. The uninstaller also offers to delete Airclone's own settings and cached thumbnails; decline and they are kept so a reinstall picks up where you left off. Your rclone configuration file is never touched — it belongs to rclone and is shared with the rclone command line.
```

## What's new in this version

**The Microsoft Store is the deliberate exception to the generic release-notes policy**
([`../store-release-notes.md`](../store-release-notes.md)). Play and the App Store are
fed the same one-liner from `store-release-notes.txt` by machine; nothing feeds this
field. `tool/store_submit.py` creates each submission by **cloning the last published
one**, so this text carries the *previous* release's copy forward untouched and looks
correct in Partner Center while being a release out of date.

So: **rewrite the block below for the version being submitted, then paste it into
Partner Center by hand** — every release, before pressing Submit. See
`dev/windows-signing-and-store.md` §2 Step D. If there is nothing worth writing, paste
the generic line from `store-release-notes.txt` rather than leaving the last one in
place.

```
Backups, and a scheduler you can find.

• Back up a folder, from Settings → Automation. Three answers — what, where, how often — and it copies only, never syncing or moving, so a file lost at the source is still in the backup.
• Files a backup replaces are kept, and restoring one is the file browser you already use: a backup destination is an ordinary folder, and copying back out of it asks before it overwrites anything.
• Settings → Automation is a new home for scheduled tasks — what a schedule means on your PC, every task with its next run and how the last one ended, and a way in that no longer needs two panes arranged first.
• Daily and weekly schedules now fire at the time you picked rather than at the next poll, and a repeating sync always carries a delete cap that pauses the scheduler if it trips.
• An optional tree view: one pane as an expandable folder hierarchy, loaded one folder at a time.

Full release notes: https://github.com/GigaionLLC/Airclone/releases
```

## Short description (<= 270 chars)

```
Airclone is a friendly desktop GUI for rclone — browse, sync, and move files across 70+ cloud storage services (Google Drive, OneDrive, S3, Dropbox, SFTP, WebDAV and more) from one app. No command line, no accounts, no tracking.
```

## Product features (one per line)

```
Manage 70+ cloud storage services from one app
Browse every cloud like a local folder
Copy and move files directly between clouds
Sync and back up with a dry-run preview
Run syncs and backups on a schedule, even with Airclone closed
Folder backup that keeps replaced files so you can restore one
Tree view for deep folder structures
Photo and video thumbnails for any remote
Built-in rclone command console
Create and extract archives
No accounts, no tracking, no telemetry
Full rclone engine built in — nothing else to install
Self-contained install — no Visual C++ redistributable needed
```

## Keywords (up to 7)

```
rclone
cloud storage
file manager
cloud sync
S3
OneDrive
backup
```

## Copyright and trademark info

```
© 2026 Gigaion, LLC. Airclone is an independent companion to rclone and is not affiliated with, sponsored by, or endorsed by the rclone project.
```

## Applicable license terms (required)

```
Airclone is open-source software licensed under the GNU Affero General Public License, version 3 (AGPLv3). Full terms: https://github.com/GigaionLLC/Airclone/blob/main/LICENSE
```

## Developed by

```
Gigaion, LLC
```

## Additional system requirements (optional — Minimum hardware)

```
Windows 10 version 1809 or later (64-bit)
```

## Images (in docs/store/windows/)

- Store logo — 1:1 Box art (required): `store-boxart-1080.png` (use the 1080, not the soft 2160 upscale).
- Store logo — 2:3 Poster (recommended): `store-poster-720x1080.png`.
- Screenshots (drag all 5, in order): `screenshots/01-dual-pane-browse.png` … `05-native-skins.png`.
  Excluded `thumbnails-grid` — its thumbnails are placeholder gradient swatches.
