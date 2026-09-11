# Mac App Store — listing details (English, United States)

⚠️ **This file is MACHINE-READ.** [`tool/asc_listing.py`](../../../tool/asc_listing.py) sends
its copy straight to App Store Connect, driven by
[`asc-listing.yml`](../../../.github/workflows/asc-listing.yml) and again by
[`asc-submit-review.yml`](../../../.github/workflows/asc-submit-review.yml)
immediately before every submission. Editing this file changes the **live**
listing on the next run. Four structural rules follow from how it is parsed:

- The headings `Description`, `Promotional text` and `Keywords` are load-bearing.
  Do not rename them.
- Each field is **the first fenced block after its heading**, so never let another
  code fence come between a heading and the block it owns.
- The parser matches the *first occurrence of the literal heading text anywhere in
  the file*, so writing one of those heading strings in prose above its real
  heading silently re-anchors the field to the wrong fence. That is why this
  warning names them without their `##` prefix, and why the keyword marker below
  is quoted rather than reproduced.
- **Keywords are the exception, and the dangerous one.** This doc keeps a
  *rejected* keyword alternative for the record and it sits **first**, so the
  parser anchors on the bold `Use this one` marker rather than on the heading.
  Delete or reword that marker and the next run silently ships the rejected set,
  third-party trademarks and all.

The iOS copy is a separate document — [`listing-ios-en-US.md`](listing-ios-en-US.md) —
because the iOS build is a different shape of app, not this one in a smaller window.

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
• Move and copy between clouds directly. Send a file from one cloud to another — the transfer runs as a background job you can watch or cancel, and you can pause the queue so nothing new starts.
• Sync and back up folders. Mirror, copy, move or two-way sync, with a dry-run preview that shows exactly what will change before anything happens.
• Back up a folder. Three answers — what, where, how often — and it copies only, never syncing or moving. A file the backup replaces is kept beside the new one, so restoring an earlier version is a copy back out of the backup folder. Scheduled tasks run while Airclone is open, and a run missed while it was closed starts once on next launch.
• See your photos and videos. Image and video thumbnails load right in the app for any remote, cached on your Mac.
• Open a folder as a tree. A pane can switch to an expandable hierarchy, loaded one folder at a time, so a deep structure is one window instead of ten.
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

**No version number is pinned here** — it is a per-release fact and this doc cannot
track it. The version record must equal `app/pubspec.yaml`'s version: Apple requires
the submitted version and the build's `CFBundleShortVersionString` to agree, and
three stores disagreeing about what version Airclone is would be worse than a
modest-looking number. The record is created by `tool/asc_build.py --create-version
X.Y.Z` (releaseType MANUAL) and pinned at submit time by `asc-submit-review.yml`'s
`confirm_version`.

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

To try it without configuring a real cloud account: the "Locations" list starts empty, which is deliberate — a sandboxed build seeds no folders of its own, because under the sandbox the home directory is redirected into the app's container and a seeded entry would point somewhere that is not the user's folder. Use the + button beside "Locations" to grant access to any folder through the standard macOS panel, then browse, copy and move files within it — this exercises the same transfer engine used for cloud remotes.

To try a cloud remote, use the + button beside "Cloud" and pick any provider; the app walks through that provider's normal setup.

On code execution (guidelines 2.5.2 / 4.7): this build spawns no processes and downloads no code. The rclone engine is statically bundled and runs in-process, which is why mounting a cloud as a disk and archive create/extract are absent from this edition.

On the com.apple.security.network.server entitlement (guideline 2.4.5): it is used only for an internal loopback bridge and nothing listens for connections from other devices. The embedded rclone library exposes a JSON-RPC interface and cannot hand raw file bytes to the app, so image previews, thumbnails, video and audio playback and the PDF viewer stream through a small HTTP endpoint inside the app's own process. It binds InternetAddress.loopbackIPv4 on an ephemeral port, is bound to 127.0.0.1 only, and each request carries a per-session Authorization token. App Sandbox requires this entitlement to call listen() at all, loopback included; without it the build has no previews, thumbnails, media playback or PDF viewer. rclone's own "serve" feature, which does expose a real network server, is deliberately disabled in this build and unreachable by the user.
```

⚠️ Do **not** mention the command console in these notes, and do not include it in a
screenshot.

## Screenshots — Mac, 1280×800 / 1440×900 / 2560×1600 / 2880×1800

Captured automatically on a CI Mac and uploaded from `mac/store-ready/` by
`tool/asc_screenshots.py`. **What ships is whatever is in that directory**, so
[`mac/store-ready/MANIFEST.md`](mac/store-ready/MANIFEST.md) is the single source of
truth for the set — what is banked, how the exact dimensions are achieved, and which
shots are still worth adding. Do not keep a second wish-list here; the two would
disagree within a release.

Two constraints on any shot, which belong with the copy rather than with the rig:

⚠️ **Use the restocked real media** from `D:\AircloneDemo` — Google rejected a
screenshot from this project as *"placeholder images or stock photos"* when it
showed gradient tiles named `IMG_0100.jpg…`. See
[`../play/DEMO-MEDIA-PROVENANCE.md`](../play/DEMO-MEDIA-PROVENANCE.md).

⚠️ **No screenshot may show mount, archive or "Show in Finder"** — the sandboxed
build does not have them.
