#!/usr/bin/env python3
"""Generate the Android TV banners from the master icon.

There are TWO of these and they are easy to confuse:

  320x180   the LAUNCHER tile, shipped inside the APK as a drawable and named by
            android:banner in the manifest. This is what a TV home screen draws.
  1280x720  the STORE banner, uploaded to the Play listing as the `tvBanner`
            image type. This is what Play shows in its TV storefront.

Both want the app NAME baked into the image - neither surface draws a separate
label, so a banner that is only a logo ships an unnamed tile.

    python dev/brand/make-tv-banner.py

Writes app/android/app/src/main/res/drawable-xhdpi/tv_banner.png and
docs/store/play/tv-banner/. Re-run after any change to the master
icon; the launcher tile is the first thing a TV user sees and a stale one is
easy to miss (the adaptive launcher icon silently shipped near-blank once for
exactly this reason).
"""

from __future__ import annotations

import pathlib
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parents[2]
MASTER = ROOT / "docs/brand/airclone-icon-1024.png"
LAUNCHER = ROOT / "app/android/app/src/main/res/drawable-xhdpi/tv_banner.png"
# Its own folder because tool/play_images.py uploads a DIRECTORY: left
# loose in docs/store/play/ it would be swept up alongside the feature
# graphic and the icon.
STORE = ROOT / "docs/store/play/tv-banner/tv-banner-1280x720.png"


def render(icon: Image.Image, out: pathlib.Path, W: int, H: int) -> int:
    # Everything below is expressed as a fraction of the height, so the same
    # composition holds at both sizes rather than needing two hand-tuned layouts.
    PAD = round(H * 0.10)

    # Brand background straight from the master, so the banner can never drift
    # from the icon. Sample INSIDE the mark's tile rather than at a corner: the
    # corner is the lighter outer field, and using it framed the tile against a
    # second blue instead of letting the white mark sit on one flat colour.
    bg = icon.convert("RGB").getpixel((icon.width // 2, icon.height // 8))

    banner = Image.new("RGB", (W, H), bg)

    # The mark, square. Deliberately NOT full height: the wordmark has to fit
    # beside it, and at full height there was no room left - the first banner
    # generated read "Airclon".
    mark_h = round(H * 0.58)
    mark = icon.resize((mark_h, mark_h), Image.LANCZOS)
    banner.paste(mark, (PAD, (H - mark_h) // 2), mark)

    # The wordmark. Bold, because it is read from three metres away.
    face = next(
        (
            c
            for c in (
                "C:/Windows/Fonts/segoeuib.ttf",
                "C:/Windows/Fonts/arialbd.ttf",
                "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
                "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
            )
            if pathlib.Path(c).exists()
        ),
        None,
    )
    if face is None:
        print("error: no bold font found - banner would ship unnamed", file=sys.stderr)
        return 1

    draw = ImageDraw.Draw(banner)
    text = "Airclone"
    tx = PAD + mark_h + round(H * 0.08)
    avail = W - tx - PAD

    # Fit the wordmark to the space that is actually left, rather than trusting a
    # hard-coded size. A clipped app name is the one defect that survives review
    # and still looks broken on every TV home screen.
    size = round(H * 0.25)
    while size > 8:
        font = ImageFont.truetype(face, size)
        box = draw.textbbox((0, 0), text, font=font)
        if box[2] - box[0] <= avail:
            break
        size -= 1
    else:
        print("error: could not fit the wordmark", file=sys.stderr)
        return 1

    ty = (H - (box[3] + box[1])) // 2
    draw.text((tx, ty), text, font=font, fill=(255, 255, 255))

    out.parent.mkdir(parents=True, exist_ok=True)
    banner.save(out)
    print(f"wrote {out.relative_to(ROOT)}  {W}x{H}  bg=#{bg[0]:02x}{bg[1]:02x}{bg[2]:02x}")
    return 0


def main() -> int:
    if not MASTER.exists():
        print(f"error: master icon missing at {MASTER}", file=sys.stderr)
        return 1
    icon = Image.open(MASTER).convert("RGBA")
    return render(icon, LAUNCHER, 320, 180) or render(icon, STORE, 1280, 720)


if __name__ == "__main__":
    raise SystemExit(main())
