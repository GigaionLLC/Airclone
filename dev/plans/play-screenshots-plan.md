# Google Play screenshot expansion — plan

**Status:** planned, not yet executed. Written 2026-08-07.

**Why:** the Play listing ships only **2 phone screenshots** and 3 per tablet size, and none of
them show the photo/video features. A Play review ("the preview function for video files stored in
the cloud often doesn't work") pushed those features to the front of the roadmap, so the listing
should demonstrate them.

## The constraint that shapes everything

`docs/store/play/store-ready/MANIFEST.md` records that the thumbnail screenshot was **pulled from
the listing** because:

> Its grid of gradient tiles named `IMG_0100.jpg … IMG_0105.jpg` is what Google's reviewer read as
> "placeholder images or stock photos."

`D:\AircloneDemo` is entirely synthetic — gradient JPGs, and (added 2026-08-07) gradient MP4s. So
**every screenshot worth adding is one Google already rejected the ingredients for.** Real media in
the demo remote is a prerequisite for this plan, not a nice-to-have.

Residual risk worth naming: the finding said "placeholder images **or stock photos**." Sourced
stock is a large improvement over solid gradients but is not zero-risk; prefer ordinary-looking
photographs over glossy stock compositions.

## Step 1 — restock the demo remote with real media — **DONE 2026-08-07**

Six CC0 photographs from Wikimedia Commons now back `google-drive/Photos/2026 Summer/`
(`IMG_0100–0105.jpg`), verified rendering in the app's gallery. Full record, including the
personality-rights screening that rejected the first candidate, is in
[`docs/store/play/DEMO-MEDIA-PROVENANCE.md`](../../docs/store/play/DEMO-MEDIA-PROVENANCE.md).
Video stays synthetic — see "Deliberately omitted" below.

Original requirements, kept for future re-stocks:

Source openly-licensed (CC0 / public-domain) photographs and short clips, and record **every**
asset's source URL, author, and licence in `docs/store/play/DEMO-MEDIA-PROVENANCE.md`.

- Replace `google-drive/Photos/2026 Summer/IMG_0100–0105.jpg` with real photographs.
- Replace `google-drive/Videos/*.mp4` with 2–3 real short clips.
- Keep the existing convention: plausible filenames, back-dated mtimes (directories too).
- **Do not commit the media itself.** `D:\AircloneDemo` is outside the repo and stays that way;
  only the derived screenshots plus the provenance file are committed. That avoids redistributing
  third-party assets under the repo's AGPLv3.

## Step 2 — rebuild the capture→store pipeline — **DONE 2026-08-07**

Lives at [`dev/store/gen_store_shots.py`](../store/gen_store_shots.py) this time, not a scratchpad.
`python dev/store/gen_store_shots.py` regenerates everything; `--check` re-asserts the outputs
without rewriting them. It also **prunes** any store-ready PNG it didn't write, so a renamed shot
can't leave its predecessor behind for someone to upload later.

Original requirements, kept for reference:

The generator referenced by MANIFEST.md (`scratchpad/gen_store_shots.py`) was written in a session
scratchpad and **no longer exists**. Rebuild it at `dev/store/gen_store_shots.py` this time so it
survives. Python 3 + Pillow 12.3 are installed.

It must:
1. Take raw `adb screencap` PNGs (phone 1080×2400, tablet 2560×1440).
2. Produce exact Play ratios — **scale-to-fit + pad on a brand background**, never crop (cropping a
   1080×2400 phone shot to 9:16 would cut the app chrome).
3. Flatten alpha → 24-bit PNG (Play rejects RGBA for screenshots).
4. Optionally draw the caption band the existing assets use.
5. Assert dimensions / ratio / file size, then regenerate `MANIFEST.md`.

Play requirements (already documented in MANIFEST.md): 16:9 or 9:16; phone & 7-inch each side
320–3840 px; 10-inch min side 1080 px; ≤ 8 MB; max 8 screenshots per slot.

## Step 3 — capture — **DONE 2026-08-07**

Captured on `airclone_pixel` (1080×2400) and `airclone_tab` (2560×1440), demo-mode status bar,
against the WebDAV demo remote. **8 phone + 6 per tablet size** are staged in `docs/store/play/`
and generated into `store-ready/`. The 7-inch source folder was deleted — 7-inch is now derived
from the 10-inch canvas, and a second set of sources would only drift.

**Bug found and fixed during the shoot.** The first tablet pass showed the desktop shell drawing
its top bar *under* the system status bar — the clock landed on the Airclone wordmark and the
wifi/battery icons sat on the toolbar's own buttons. The shell had no inset handling at all
(`mobile_home.dart` has always had a `SafeArea`; the desktop shell never did, because desktop
platforms have a real title bar and this only bites on Android tablets ≥700px). Fixed by wrapping
the shell's `Column` in a `SafeArea` in `ui/home_screen.dart`, and the tablet set was re-shot
against the fixed build. `SafeArea` is inert where view padding is zero, so desktop is untouched.

Original notes, kept for reference:

Emulators: `airclone_pixel` (1080×2400) and `airclone_tab` (Pixel Tablet, 2560×1440 — natively 16:9,
matches the 10-inch slot exactly and downscales cleanly to 1920×1080 for 7-inch).

Setup per the existing rig: host `rclone serve webdav D:\AircloneDemo --addr 127.0.0.1:8090`,
webdav remotes pointing at `10.0.2.2:8090`, config injected via `adb root` into
`/data/data/com.gigaionllc.airclone/files/rclone.conf`, then
`adb shell appops set com.gigaionllc.airclone MANAGE_EXTERNAL_STORAGE allow`.

Clean the status bar with the `com.android.systemui.demo` broadcasts before capturing.

### Phone (9:16 · 1080×1920 · up to 8)

| # | Shot | Status |
| :--- | :--- | :--- |
| 1 | Cloud remotes / home | exists — `01-every-cloud.png` |
| 2 | Browsing a remote, list view | exists — `02-browse-remotes.png` |
| 3 | Gallery view, date-grouped photo thumbnails | NEW — needs real photos |
| 4 | Fullscreen photo viewer (edge-to-edge) | NEW — needs real photos |
| 5 | Actions sheet (`⋯`) incl. the Advanced group | NEW |
| 6 | Transfers screen mid-copy with progress | NEW |
| 7 | "Open in another app" / Share sheet | NEW |
| 8 | Split view (stacked panes) | NEW |

### Tablet 7-inch (1920×1080) and 10-inch (2560×1440) · up to 8 each

| # | Shot | Status |
| :--- | :--- | :--- |
| 1 | Home / remotes | exists |
| 2 | Files, dual-pane | exists |
| 3 | Transfers | exists |
| 4 | Gallery with real photo thumbnails | NEW — restores the pulled `03-thumbnails` |
| 5 | Fullscreen photo viewer | NEW |
| 6 | Transfer options (filters · dry-run) | NEW |

### Deliberately omitted: "video playing"

There is **no physical Android device available**, and the emulator cannot render video at all —
media_kit forces software rendering on an emulator and `eglCreateContext` fails with
`EGL_BAD_ATTRIBUTE`, so no frame is ever produced (see the Android dev notes). Capturing the
loading or error state and presenting it as the video feature would misrepresent the app, so the
slot stays empty until hardware is available.

## Step 4 — publish — **YOURS TO DO**

Everything is upload-ready in `docs/store/play/store-ready/`; `MANIFEST.md` says which file goes
in which slot. Publishing to a live store listing is a manual, outward-facing step — sign in to
Play Console → Store listing → Graphics and replace the phone / 7-inch / 10-inch sets.

Listing edits do not require a new AAB (see `dev/google-play-store.md`), so this ships
independently of a release.
