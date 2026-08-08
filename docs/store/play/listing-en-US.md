# Google Play — default store listing (en-US)

Paste-ready copy for the Play Console "Create default store listing" form.
Feature-first so it matches the screenshots; includes an rclone non-affiliation
line to avoid trademark/impersonation rejections.

---

## App name  (max 30 chars)

```
Airclone
```

Optional, more discoverable (29 chars — accurate keywords, not stuffing):

```
Airclone – Cloud File Manager
```

## Short description  (max 80 chars)

```
Browse, sync and move files across your clouds — a friendly GUI for rclone.
```

(75 chars. Leads with what the user does, not the app name.)

## Full description  (max 4000 chars)

```
Airclone is a modern, easy-to-use file manager for rclone.

rclone is a powerful open-source tool that can move and sync files across 70+ cloud
storage services — Google Drive, Dropbox, OneDrive, Amazon S3, SFTP, WebDAV and many
more. Airclone gives it a clean, touch-friendly interface, so you can manage all of your
clouds from one app without ever touching the command line.

WHAT YOU CAN DO
• Browse every cloud like a local folder. Your phone's storage and all of your cloud
  remotes appear side by side in one simple list, with the same rows and gestures.
• Move and copy files between clouds. Send a file straight from one cloud to another —
  the transfer runs as a background job you can watch, pause, or cancel.
• Sync and back up folders. Mirror, copy, move, or two-way sync, with a dry-run preview
  that shows exactly what will change before anything happens.
• See your photos and videos. Image and video thumbnails load right in the app for any
  remote, cached and encrypted on your device.
• Stay in control. Nothing is overwritten silently — every file collision asks first:
  skip, replace, or keep both.
• Open anything in another app. Hand any file straight to the app you'd rather use —
  a video player, a photo viewer, an editor — or send it on with the share sheet.

PRIVATE BY DESIGN
Airclone runs entirely on your device. There are no accounts, no tracking, and no
telemetry. Your files and your cloud credentials never pass through our servers —
because we don't have any.

OPEN SOURCE
Airclone is open-source software (AGPLv3). It runs entirely on your device, with no ads and no
tracking.

BUILT ON RCLONE
The full rclone engine ships inside the app, so there is nothing else to install.
Airclone is an independent companion to rclone and is not affiliated with, sponsored by,
or endorsed by the rclone project.

FOR TEAMS AND IT (OPTIONAL)
Airclone can also be deployed and managed by IT — MDM configuration, policy controls,
OS-keychain secret storage, and local audit logging — all without phoning home.
```

---

## Screenshot checklist (the actual blocker for the rejection)

- [x] Thumbnail/gallery screenshots are BACK. The gradient swatches that read as placeholder
      images are gone — `IMG_0100–0105.jpg` are now real CC0 photographs (provenance in
      `../DEMO-MEDIA-PROVENANCE.md`), so the gallery shot ships on phone and both tablet sizes.
- [x] Tablet screenshots are framed + captioned exactly like the phone ones — same generator
      (`dev/store/gen_store_shots.py`), same gradient, same caption band.
- [x] The set grew from 2 phone / 3 per tablet to **8 phone / 6 per tablet**.
- [ ] **STILL OPEN — demo remotes all read "webdav".** A remote NAMED "Google-Drive" whose
      subtitle says `webdav` looks fabricated, which is the same credibility smell as the
      placeholder images. The backing HAS to be webdav (the emulator reaches a host
      `rclone serve webdav`), so the fix is to rename the demo remotes to something the type
      is plausible for — "Home NAS", "Studio Drive", "Backups" — rather than borrowing real
      provider names. Requires a full re-shoot of all 14 screenshots.
- [ ] Resubmit via "Update default store listing" → replace assets → Save.
