# Google Play — upload-ready assets (`store-ready/`)

Generated from the source captures in `../phone`, `../tablet-7in`, `../tablet-10in`.
Every file below is verified: 24-bit PNG, **no alpha**, 16:9 or 9:16, within Play size limits.
Regenerate with `scratchpad/gen_store_shots.py` (re-runs the same asserts).

## Where each file goes in Play Console → Store listing → Graphics

| Slot | File | Dimensions | Ratio | Alpha | Notes |
| :--- | :--- | :--- | :--- | :--- | :--- |
| Phone screenshot 1 | `phone/01-every-cloud.png` | 1080×1920 | 9:16 | none | already captioned |
| Phone screenshot 2 | `phone/02-browse-remotes.png` | 1080×1920 | 9:16 | none | already captioned |
| 7-inch tablet 1 | `tablet-7in/01-home.png` | 1920×1080 | 16:9 | none | framed + caption |
| 7-inch tablet 2 | `tablet-7in/02-files.png` | 1920×1080 | 16:9 | none | framed + caption |
| 7-inch tablet 3 | `tablet-7in/03-transfers.png` | 1920×1080 | 16:9 | none | framed + caption |
| 10-inch tablet 1 | `tablet-10in/01-home.png` | 2560×1440 | 16:9 | none | framed + caption |
| 10-inch tablet 2 | `tablet-10in/02-files.png` | 2560×1440 | 16:9 | none | framed + caption |
| 10-inch tablet 3 | `tablet-10in/03-transfers.png` | 2560×1440 | 16:9 | none | framed + caption |
| Feature graphic | `feature-1024x500.png` | 1024×500 | — | none | flattened (was RGBA) |
| App icon | `icon-512.png` | 512×512 | 1:1 | kept | Play icon is 32-bit PNG |

## Play requirements these satisfy

- **Phone:** PNG/JPEG · min 2 · 16:9 or 9:16 · each side 320–3840 px · ≤ 8 MB.
- **7-inch tablet:** PNG/JPEG · 16:9 or 9:16 · each side 320–3840 px · ≤ 8 MB.
- **10-inch tablet:** PNG/JPEG · 16:9 or 9:16 · each side **1080**–3840 px · ≤ 8 MB.
- **Feature graphic:** 24-bit PNG (no alpha) or JPEG · 1024×500 · ≤ 15 MB.
- **App icon:** 32-bit PNG · 512×512 · ≤ 1 MB.

## Deliberately excluded

`03-thumbnails.png` (both tablet sizes) is **omitted**. Its grid of gradient tiles
named `IMG_0100.jpg … IMG_0105.jpg` is what Google's reviewer read as
"placeholder images or stock photos." To showcase the thumbnail feature, re-capture
that screen with **real photographs** in the demo remote, then frame it with the same
generator and add it back.
