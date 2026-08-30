# Android TV screenshots

Captured from the `airclone_tv` emulator (Android TV 1080p, API 36) by
`dev/android/tv-store-shots.sh`, at 1920x1080 — Play's TV requirement is 16:9
and at least 1280x720, so these need no scaling or padding.

| File | Shows |
| :--- | :--- |
| `01-locations.png` | the side rail and the device's locations, focus on Files |
| `02-focus.png` | the focus ring on a list row — the one thing a TV review checks |
| `03-browsing.png` | a real folder listing with names, sizes and modified times |

Upload them with:

```bash
python tool/play_images.py --package com.gigaionllc.airclone \
    --type tvScreenshots --dir docs/store/play/tv --replace --apply
```

`--replace` matters: Play APPENDS an uploaded image to the set rather than
overwriting it, so a second run without it leaves duplicates in the listing.

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
