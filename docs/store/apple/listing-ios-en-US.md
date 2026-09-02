# App Store (iOS) — listing details (English, United States)

Paste-ready copy for App Store Connect → **iOS** version. The Mac copy lives in
[`listing-en-US.md`](listing-en-US.md); this is a separate document rather than a
find-and-replace of it, because the iOS build is a *different shape of app*, not
the Mac one with a smaller window.

The same four constraints apply as on the Mac listing, and each has already cost
this project a review cycle somewhere:

1. **The App Store build is paid** — nothing may claim the app is free.
2. **The rclone non-affiliation line must be present.**
3. **Never point a reviewer at the command console.**
4. **The copy must not promise what the binary cannot do.**

And one that is specific to iOS, and sharper than the Mac sandbox:

5. **iOS has no arbitrary local filesystem.** "Local" on iOS is the app's own
   folder, which the Files app shows as *On My iPhone → Airclone*. There is no
   folder picker, no browsing the device, no mount, and no archive. Cloud remotes
   are the full experience; the local side is a shared drop-box.

---

## Subtitle (30 max)

```
Every cloud, one file manager
```

Same as the Mac listing, and it stays true here.

## Promotional text (170 max)

Editable without a new version, unlike the description.

```
Browse, move and sync files across 70+ clouds from your iPhone or iPad. Photo and video thumbnails, background transfers, and a dry-run preview before anything changes.
```

## Description (4,000 max)

```
Airclone is a modern, easy-to-use file manager for the clouds you already use.

It is built on rclone, the open-source engine that can move and sync files across 70+ storage services — Google Drive, Dropbox, OneDrive, Amazon S3, Backblaze B2, SFTP, WebDAV and many more. Airclone gives it a clean, fast interface on your iPhone and iPad, so you can manage all of your storage from one app without ever touching a command line.

WHAT YOU CAN DO
• Browse every cloud like a folder. All of your remotes sit side by side, with familiar rows, previews and long-press actions.
• Move and copy between clouds directly. Send a file from one cloud to another — the transfer runs as a background job you can watch, pause or cancel.
• Sync and back up folders. Mirror, copy, move or two-way sync, with a dry-run preview that shows exactly what will change before anything happens.
• See your photos and videos. Image and video thumbnails load right in the app for any remote.
• Stay in control. Nothing is overwritten silently — every collision asks first: skip, replace, or keep both.

YOUR FILES STAY YOURS
Airclone runs entirely on your device. There are no accounts to create, no tracking and no telemetry. Your files and your cloud credentials never pass through our servers, because we do not have any.

BUILT ON RCLONE
The rclone engine is built into the app, so there is nothing else to install and no command line to learn. Airclone is an independent companion to rclone and is not affiliated with, sponsored by, or endorsed by the rclone project.

ABOUT FILES ON THIS DEVICE
iOS does not let an app browse your whole device, so Airclone's local side is its own folder — the one the Files app shows under "On My iPhone" as Airclone. Anything you copy down from a cloud lands there, and anything you put there from Files is ready to upload. Mounting a cloud as a drive, and creating or extracting archives, are not available on iOS.
```

## Keywords (100 max, comma-separated)

Same conservative set as the Mac listing, and for the same reason: `dropbox`,
`onedrive` and `drive` are third-party trademarks, Apple *has* rejected keyword
sets over them, and a first submission is the wrong place to find out. `rclone`
is deliberately absent — a trademark in the keyword field is the highest-risk
placement, even though the term is central to the description.

```
cloud storage,file manager,sync,backup,file transfer,s3,webdav,sftp,remote files
```

## URLs and version

**Version: 0.6.8** — matching the app and the macOS listing. Three stores
disagreeing about what version Airclone is would be worse than a modest-looking
number.

| Field | Value |
| :--- | :--- |
| Support URL | `https://github.com/GigaionLLC/Airclone` |
| Marketing URL | *(optional — leave blank unless there is a product page)* |

## Copyright

```
2026 Gigaion, LLC
```

## App Review Information

**Sign-in required: NO.** There is no account.

Notes (4,000 max):

```
Airclone is a file manager for cloud storage that the user already owns. There is no Airclone account, no sign-in and no server of ours involved — the app talks directly to whichever storage the user configures, using their own credentials, which stay on the device.

To try it without configuring a real cloud account: tap "On My Device" in the sidebar. That is the app's own Documents folder, which also appears in the Files app under "On My iPhone" as Airclone. Files can be added there from Files and then copied or moved within the app, which exercises the same transfer engine used for cloud remotes.

To try a cloud remote, use the + button beside "Cloud" and pick any provider; the app walks through that provider's normal setup.

On code execution (guidelines 2.5.2 / 4.7): this build spawns no processes and downloads no code. The rclone engine is compiled into the app as a static library and runs in-process, which is why mounting a cloud as a drive and archive create/extract are absent on iOS.

Camera and Face ID: the camera is used only to scan a configuration QR code the user generates themselves, and Face ID only to unlock an encrypted rclone configuration stored on the device. Neither is required to use the app.

WHAT THE APP DOES, AND FOR WHOM (guideline 2.1). Airclone browses, previews, transfers and organises files across more than 70 storage providers (Google Drive, Dropbox, OneDrive, S3, Backblaze B2, WebDAV, SFTP and others) through one interface. The problem it solves: people keep files across several unrelated cloud accounts with no single place to see or move them; the alternatives are single-provider apps or command-line tools. Audience: individuals and small teams using more than one provider - photographers, developers, researchers, anyone migrating between services.

EXTERNAL SERVICES. rclone (MIT licence) is the transfer engine, compiled INTO the app as a static library and run in-process; nothing is downloaded or executed at runtime. Airclone is an independent companion to rclone and is not affiliated with, sponsored by, or endorsed by the rclone project. The only other external parties are the storage providers the user chooses to configure, contacted directly from the device with the user's own credentials. There are no analytics, no telemetry, no crash reporting, no advertising SDKs, no authentication service, no payment processor and no AI services. The app makes no request to any server we operate, because we operate none.

REGIONAL DIFFERENCES. Features and content are identical in every region. France is excluded from availability purely for export-compliance administrative reasons (its separate encryption declaration) and this reflects no difference in the app.

REGULATED INDUSTRY / THIRD-PARTY MATERIAL. The app operates in no regulated industry and provides no regulated service. The only third-party material is the rclone engine, used under its MIT licence, which permits binary redistribution; the licence and attribution ship in the app and the source is public at https://github.com/GigaionLLC/Airclone

ACCOUNTS AND PURCHASES. There is no account registration, login or account deletion, no in-app purchase or subscription, and no user-generated content or social features.
```

⚠️ Do **not** mention the command console in these notes, and do not show it in a
screenshot.

## Related

- [`review-replies.md`](review-replies.md) — the exact App Review reply texts that were sent, and why they are worded that way

## Screenshots

Captured on simulators by
[`ios-screenshots.yml`](../../../.github/workflows/ios-screenshots.yml) —
`xcrun simctl io screenshot` gives native resolution, so no rescaling is involved.
What is banked so far, and how, is in [`ios/MANIFEST.md`](ios/MANIFEST.md).

| Device class | Required? | Size |
| :--- | :--- | :--- |
| iPhone 6.9" | yes | 1320 × 2868 |
| iPad 13" | **yes** — the app ships `TARGETED_DEVICE_FAMILY = "1,2"` | 2064 × 2752 |

⚠️ **No screenshot may show mount, archive, a folder picker, or browsing outside
the app's own folder** — the iOS build has none of those.

⚠️ **Use real media.** Google rejected a screenshot from this project as
*"placeholder images or stock photos"* when it showed gradient tiles named
`IMG_0100.jpg…`. The rig fetches the same CC0 photographs the Play listing uses —
provenance in [`../play/DEMO-MEDIA-PROVENANCE.md`](../play/DEMO-MEDIA-PROVENANCE.md).
