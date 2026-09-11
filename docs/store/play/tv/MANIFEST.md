# Android TV screenshots

Captured from the `airclone_tv` emulator (Android TV 1080p, API 36) by
`dev/android/tv-store-shots.sh`, at 1920x1080 — Play's TV requirement is 16:9
and at least 1280x720, so these need no scaling or padding.

| File | Shows |
| :--- | :--- |
| `01-locations.png` | the side rail and the device's locations, focus on Files |
| `02-focus.png` | the focus ring on a list row — the one thing a TV review checks |
| `03-browsing.png` | a real folder listing with names, sizes and modified times |

Upload them from Actions → **Play Store listing images**
([`play-images.yml`](../../../../.github/workflows/play-images.yml)) with
`type: tvScreenshots`, `dir: docs/store/play/tv`, `replace: true`, and `mode: report`
before `apply`. That route needs no local credentials. The same thing locally, if you
have the service-account key:

```bash
python tool/play_images.py --package com.gigaionllc.airclone \
    --type tvScreenshots --dir docs/store/play/tv --replace --apply
```

`--replace` matters: Play APPENDS an uploaded image to the set rather than
overwriting it, so a second run without it leaves duplicates in the listing. Either
route writes images only, and Play holds the change as a draft until someone sends it.

## The banner, which is not in this folder

A TV listing also needs a **banner** — the tile Play's TV storefront draws — and it
lives one directory across, at
[`../tv-banner/tv-banner-1280x720.png`](../tv-banner/tv-banner-1280x720.png). It is
**exactly 1280x720**, the only size Play accepts for that slot, and
`tool/play_images.py` checks the dimensions before uploading so a wrong file is named
here rather than coming back as an opaque 400.

Generate it from the master icon with `python dev/brand/make-tv-banner.py`, which
writes **both** TV banners: this one, and the 320x180 `drawable-xhdpi/tv_banner.png`
that `android:banner` points at for the TV home screen. They are different images for
different surfaces and neither one complains about being the wrong one — see
[`dev/android-tv.md`](../../../../dev/android-tv.md).

Upload it as its own run, same flags as above: `type: tvBanner`,
`dir: docs/store/play/tv-banner`, `replace: true`, `mode: report` before `apply`.

```bash
python tool/play_images.py --package com.gigaionllc.airclone \
    --type tvBanner --dir docs/store/play/tv-banner --replace --apply
```

## What is deliberately not here

**Transfers and Settings.** Both were captured and both were dropped. The
Transfers tab has nothing in it on a fresh device ("No transfers yet"), and the
Settings page's segmented controls render in Material's default purple, which
appears nowhere else in the app — neither is worth a listing slot. Play needs a
minimum of one TV screenshot and allows eight; three that show the product
working beat four where one is an empty state.

## Two traps, both of which produced a wrong set before this one

**Walking from screen to screen.** Capturing by pressing keys onward from the
previous shot means every press is a guess about where focus already was, and
one wrong guess silently corrupts every frame after it. An early set had three
byte-identical files, all of them pictures of the wrong screen. The rig now
relaunches the app before each screen so the starting point is known.

**Trusting size and uniqueness.** One run wrote the Google Play sign-in screen
as `04-transfers.png` — the app had gone to background. It was 1920x1080, it was
16:9, and its hash differed from every other file, so every cheap check passed.
The rig now reads `dumpsys window` and REFUSES to capture unless Airclone is the
foreground window.
