# Google Play — default store listing (en-US)

Paste-ready copy for the Play Console "Create default store listing" form.
Feature-first so it matches the screenshots; includes an rclone non-affiliation
line to avoid trademark/impersonation rejections.

⚠️ **Nothing pushes this text.** [`play-images.yml`](../../../.github/workflows/play-images.yml)
writes **images only** — it cannot change a word of the listing. Editing this file
therefore does not change the live listing; someone has to paste the block into
Play Console → Store listing. Assume the live text is whatever was last pasted, not
what is written here, and re-paste after any correction.

**Two corrections were made here on 2026-09-06 and are almost certainly still wrong
in the live listing until someone pastes:**

- A *FOR TEAMS AND IT* paragraph claiming MDM configuration, policy controls and
  local audit logging. None of the three exists — there is no `app_restrictions` /
  `RestrictionsManager` integration in the Android app and no audit log anywhere;
  `mount_policy.dart` and `serve_policy.dart` are internal build-flavour gates with a
  managed-config *seam* and no managed-config *source*. Only the keychain half was
  real, and it survives below as SECRETS STAY IN THE OS. This is precisely the class
  of claim that earns an "Unusable Feature" finding — `hardening-audit-2026-07-15.md`
  H-17 cited this paragraph by line number. Do not restore the enterprise story until
  H-17's capability matrix exists and marks those features available.
- "watch, pause, or cancel" a transfer. The only pause control pauses the **queue**
  (`jobs_panel.dart`: *"queued transfers wait; running ones finish"*); a running
  transfer cannot be paused.

**And one addition on 2026-09-10, also pending a paste:** camera-roll backup and
scheduled folder backups, both shipped in v0.8 and never claimed here. Two things
go with that edit:

- Check Play Console → **Data safety** against the new copy before pasting. The app
  now reads the camera roll and copies it off the device, to storage the user chose,
  which is what that form asks about. The form itself belongs to
  [`dev/google-play-store.md`](../../../dev/google-play-store.md), not to this file.
- **No new Android permission was added for any of it** — photo backup rides the
  All-files-access grant the app already asks for. Nothing here may imply otherwise.

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
  the transfer runs as a background job you can watch or cancel, and you can pause the
  queue so nothing new starts.
• Sync and back up folders. Mirror, copy, move, or two-way sync, with a dry-run preview
  that shows exactly what will change before anything happens.
• Back up your camera roll. Point it at a cloud you already own and your photos copy
  themselves across in the background — on Wi-Fi unless you say otherwise, videos
  included or not, as often as you choose. Copy only: nothing on the phone is moved or
  deleted.
• Back up a folder, on a schedule. Pick what, where and how often. A file the backup
  replaces is kept beside the new one, so an earlier version is still there to copy back.
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

SECRETS STAY IN THE OS
If you let Airclone remember an encrypted rclone configuration's password, it goes into your device's
own credential store — never into a file of ours, and never off the device. Nothing phones home.
```

---

## Screenshot checklist (the actual blocker for the rejection)

- [x] Thumbnail/gallery screenshots are BACK. The gradient swatches that read as placeholder
      images are gone — `IMG_0100–0105.jpg` are now real CC0 photographs (provenance in
      `../DEMO-MEDIA-PROVENANCE.md`), so the gallery shot ships on phone and both tablet sizes.
- [x] Tablet screenshots are framed + captioned exactly like the phone ones — same generator
      (`dev/store/gen_store_shots.py`), same gradient, same caption band.
- [x] The set grew from 2 phone / 3 per tablet to **8 phone / 6 per tablet**.
- [x] **Demo remotes no longer look fabricated.** They were named after real providers while
      their subtitle read `webdav` — "Google-Drive · webdav" — the same credibility smell as the
      placeholder images. The backing has to be webdav (the emulator reaches a host
      `rclone serve webdav`), so the remotes are now named for something that type is plausible
      for: **Home-NAS**, **Studio-Drive**, **Archive-Backups**. All 14 screenshots re-shot.
- [x] Assets are uploaded from this repo, not through the Console's "Add assets"
      button (which opens a native file dialog nothing but a human at that machine can
      drive). Run Actions → **Play Store listing images**
      ([`play-images.yml`](../../../.github/workflows/play-images.yml)), one run per
      image type, with `replace: true` — Play **appends** otherwise and leaves
      duplicates — and `mode: report` before `mode: apply`. Slot-to-folder pairs are in
      [`store-ready/MANIFEST.md`](store-ready/MANIFEST.md).
- [ ] Send the draft. The workflow writes **images only** and Play holds the change as
      a draft until someone reviews and sends it — and the text above still has to be
      pasted into the Console by hand.
