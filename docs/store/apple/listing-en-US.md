# Mac App Store — listing details (English, United States)

Paste-ready copy for App Store Connect → macOS version.

**Decisions taken 2026-08-21** (both were flagged as judgement calls; either is one
edit to reverse):
- The `ABOUT THIS VERSION` paragraph **stays**. Someone paying $1.49 and then
  discovering the sandboxed build has no mount or archive is a bad review we would
  have earned, and a listing that matches the binary reads well to a reviewer.
- Keywords use the **conservative set**, without third-party marks. A rejection
  costs a review cycle on a first submission; the marginal discovery does not.
  Terms can be added in a later version once approved - that direction is cheap,
  the reverse is not.

Three constraints shape every word here, and each one has already cost this project
a review cycle on another store:

1. **The App Store build is paid**, so nothing may claim the app is free or has no
   paywall (`docs/store/README.md` pricing policy).
2. **The rclone non-affiliation line must be present**, or the listing risks a
   trademark/impersonation rejection.
3. **Never point a reviewer at the command console.** Our own tester notes cited a
   command the console blocks and it cost Microsoft review cycles.

And one that is specific to Apple:

4. **The Mac App Store build is a strictly smaller app than the DMG** — the App
   Sandbox makes OS mount, archive create/extract and "Show in Finder" impossible.
   The copy must not promise them. A screenshot showing them would be a
   straightforward rejection.

---

## Subtitle (30 max) — **already set in App Store Connect**

```
Every cloud, one file manager
```

## Promotional text (170 max)

Editable without a new version, unlike the description — use it for what is new.

```
Browse, move and sync files across 70+ cloud services from one Mac app. Photo and video thumbnails, background transfers, and a dry-run preview before anything changes.
```

## Description (4,000 max)

```
Airclone is a modern, easy-to-use file manager for the clouds you already use.

It is built on rclone, the open-source engine that can move and sync files across 70+ storage services — Google Drive, Dropbox, OneDrive, Amazon S3, Backblaze B2, SFTP, WebDAV and many more. Airclone gives it a clean, fast Mac interface, so you can manage all of your storage from one window without ever touching a command line.

WHAT YOU CAN DO
• Browse every cloud like a local folder. Your Mac's folders and all of your cloud remotes sit side by side, with familiar rows, previews and right-click actions.
• Move and copy between clouds directly. Send a file from one cloud to another — the transfer runs as a background job you can watch, pause or cancel.
• Sync and back up folders. Mirror, copy, move or two-way sync, with a dry-run preview that shows exactly what will change before anything happens.
• See your photos and videos. Image and video thumbnails load right in the app for any remote, cached on your Mac.
• Stay in control. Nothing is overwritten silently — every collision asks first: skip, replace, or keep both.

YOUR FILES STAY YOURS
Airclone runs entirely on your Mac. There are no accounts to create, no tracking and no telemetry. Your files and your cloud credentials never pass through our servers, because we do not have any.

Airclone asks for access to a folder the first time you add it, using the standard macOS panel, and remembers that choice. It can only ever read the folders you have chosen.

BUILT ON RCLONE
The rclone engine is built into the app, so there is nothing else to install and no command line to learn. Airclone is an independent companion to rclone and is not affiliated with, sponsored by, or endorsed by the rclone project.

ABOUT THIS VERSION
This is the Mac App Store edition, which runs inside Apple's App Sandbox. Mounting a cloud as a disk, and creating or extracting archives, are not available here — those need access the sandbox does not permit. A direct-download edition with those features is available from the Airclone website.
```

## Keywords (100 max, comma-separated)

**Use this one** (78 characters):

```
cloud storage,file manager,sync,backup,file transfer,s3,webdav,sftp,remote files
```

Rejected alternative, kept for the record (90 characters). `dropbox`, `onedrive`
and `drive` are third-party trademarks; naming genuinely supported services is
normal for a client app and usually accepted, but Apple *has* rejected keyword
sets over third-party marks, and a first submission is the wrong place to spend a
review cycle finding out:

```
cloud storage,file manager,sync,backup,file transfer,s3,webdav,sftp,drive,dropbox,onedrive
```

`rclone` is deliberately **absent from keywords** even though it is central to the
description — a trademark in the keyword field is the highest-risk placement.

## URLs

**Version: 0.6.8** — set in App Store Connect to match the app, rather than the
placeholder 1.0 the record was created with. Apple requires the submitted version
and the build's CFBundleShortVersionString to agree, and three stores disagreeing
about what version Airclone is would be worse than a modest-looking number.

| Field | Value |
| :--- | :--- |
| Support URL | `https://github.com/GigaionLLC/Airclone` |
| Marketing URL | *(optional — leave blank unless there is a product page)* |

## Copyright

```
2026 Gigaion, LLC
```

## App Review Information

**Sign-in required: NO.** Set the toggle off — there is no account.

Notes (4,000 max):

```
Airclone is a file manager for cloud storage that the user already owns. There is no Airclone account, no sign-in and no server of ours involved — the app talks directly to whichever storage the user configures, using their own credentials, which stay on the Mac.

To try it without configuring a real cloud account: the sidebar's local folders work immediately. Use the + button beside "Locations" to grant access to any folder, then browse, copy and move files within it — this exercises the same transfer engine used for cloud remotes.

To try a cloud remote, use the + button beside "Cloud" and pick any provider; the app walks through that provider's normal setup.

On code execution (guidelines 2.5.2 / 4.7): this build spawns no processes and downloads no code. The rclone engine is statically bundled and runs in-process, which is why mounting a cloud as a disk and archive create/extract are absent from this edition.
```

⚠️ Do **not** mention the command console in these notes, and do not include it in a
screenshot.

## Screenshots — Mac, 1280×800 / 1440×900 / 2560×1600 / 2880×1800

Ship 5–6. Captured automatically on a CI Mac — see
[`mac/store-ready/MANIFEST.md`](mac/store-ready/MANIFEST.md) for what is banked so
far and how the exact dimensions are achieved.

1. Dual-pane explorer — cloud on one side, local on the other (hero)
2. Photo gallery grid with real thumbnails
3. A transfer in flight, jobs dock showing speed and ETA
4. Add-remote wizard, provider picker open
5. Media preview open
6. Home view with the native macOS skin

⚠️ **Use the restocked real media** from `D:\AircloneDemo` — Google rejected a
screenshot from this project as *"placeholder images or stock photos"* when it
showed gradient tiles named `IMG_0100.jpg…`. See
[`../play/DEMO-MEDIA-PROVENANCE.md`](../play/DEMO-MEDIA-PROVENANCE.md).

⚠️ **No screenshot may show mount, archive or "Show in Finder"** — the sandboxed
build does not have them.
