#!/usr/bin/env python3
"""Turn raw `adb screencap` PNGs into Google-Play-ready store screenshots.

Play will not accept a raw phone capture: a Pixel screenshot is 1080x2400
(9:20), and Play requires 16:9 or 9:16. So every shot is COMPOSED onto a
brand-blue canvas of the exact required size rather than cropped -- cropping a
9:20 capture down to 9:16 would slice the app's own chrome off.

Layout is reverse-engineered from the assets shipped in 2026-07 so new shots
sit beside the old ones without a visible seam:

    phone   1080x1920   device 702px wide at (189, 265)
    tablet  2560x1440   device 1996px wide at (282, 259)
    7-inch  1920x1080   the 2560x1440 canvas scaled by 0.75

Run from anywhere:  python dev/store/gen_store_shots.py
Add --check to verify the existing outputs without rewriting them.

This script replaces an earlier one that lived in a session scratchpad and was
lost; it lives in the repo now so the next re-shoot is not archaeology.
"""

from __future__ import annotations

import argparse
import os
import sys
from dataclasses import dataclass

from PIL import Image, ImageDraw, ImageFilter, ImageFont

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PLAY = os.path.join(REPO, "docs", "store", "play")
OUT = os.path.join(PLAY, "store-ready")

# Brand gradient, sampled from the 2026-07 assets (top-left -> bottom-right).
GRADIENT_FROM = (35, 140, 228)
GRADIENT_TO = (11, 60, 140)
CAPTION_RGB = (255, 255, 255)

# Play's hard limits, asserted on every output.
MAX_BYTES = 8 * 1024 * 1024
MIN_EDGE = 320
MAX_EDGE = 3840
MIN_EDGE_10IN = 1080

FONT_CANDIDATES = [
    os.path.expanduser(
        "~/flutter/bin/cache/artifacts/material_fonts/roboto-bold.ttf"
    ),
    r"C:\Windows\Fonts\segoeuib.ttf",
    r"C:\Windows\Fonts\arialbd.ttf",
    "/usr/share/fonts/truetype/roboto/Roboto-Bold.ttf",
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
]


@dataclass(frozen=True)
class Layout:
    canvas: tuple[int, int]
    device_width: int
    device_xy: tuple[int, int]
    caption_size: int
    caption_y: int
    corner_radius: int


PHONE = Layout((1080, 1920), 702, (189, 265), 70, 96, 22)
TABLET = Layout((2560, 1440), 1996, (282, 259), 86, 92, 20)

# source basename -> caption. Order here IS the order in the Play listing.
PHONE_SHOTS = [
    ("01-home.png", "Every cloud in your pocket"),
    ("02-browse.png", "Browse remotes like local folders"),
    ("03-gallery.png", "Your cloud photos, in a gallery"),
    ("04-viewer.png", "Full-screen preview, straight from the cloud"),
    ("05-context-menu.png", "Open anything in the app you prefer"),
    ("06-transfers.png", "Watch every transfer in real time"),
    ("07-actions-advanced.png", "Every desktop tool, one tap away"),
    ("08-split.png", "Two folders, side by side"),
]

TABLET_SHOTS = [
    ("01-home.png", "Every cloud in one place"),
    # Caption describes what the capture ACTUALLY shows -- a single browsing
    # pane with the sidebar and transfers dock. An earlier draft said "two
    # panes", which the shot does not show.
    ("02-files.png", "Desktop-class file management on your tablet"),
    ("03-gallery.png", "Your cloud photos, in a gallery"),
    ("04-viewer.png", "Full-screen preview, straight from the cloud"),
    ("05-transfers.png", "Watch every transfer in real time"),
    ("06-transfer-options.png", "Copy, move or sync - with filters and dry-run"),
]


def find_font() -> str:
    for path in FONT_CANDIDATES:
        if os.path.isfile(path):
            return path
    raise SystemExit(
        "No bold sans font found. Tried:\n  " + "\n  ".join(FONT_CANDIDATES)
    )


def gradient(size: tuple[int, int]) -> Image.Image:
    """Diagonal brand gradient: exact GRADIENT_FROM at the top-left pixel and
    GRADIENT_TO at the bottom-right, interpolated along (x/w + y/h)/2."""
    w, h = size
    base = Image.new("RGB", size)
    px = base.load()
    for y in range(h):
        fy = y / max(h - 1, 1)
        for x in range(w):
            t = (x / max(w - 1, 1) + fy) / 2
            px[x, y] = tuple(
                round(a + (b - a) * t)
                for a, b in zip(GRADIENT_FROM, GRADIENT_TO)
            )
    return base


def rounded(im: Image.Image, radius: int) -> Image.Image:
    """Round the device screenshot's corners, matching the shipped assets."""
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [(0, 0), (im.size[0] - 1, im.size[1] - 1)], radius=radius, fill=255
    )
    out = im.convert("RGBA")
    out.putalpha(mask)
    return out


def draw_caption(
    canvas: Image.Image, text: str, layout: Layout, font_path: str
) -> None:
    """Centred white caption, auto-shrunk until it fits 88% of the canvas."""
    draw = ImageDraw.Draw(canvas)
    size = layout.caption_size
    while size > 24:
        font = ImageFont.truetype(font_path, size)
        width = draw.textbbox((0, 0), text, font=font)[2]
        if width <= canvas.size[0] * 0.88:
            break
        size -= 2
    font = ImageFont.truetype(font_path, size)
    box = draw.textbbox((0, 0), text, font=font)
    x = (canvas.size[0] - (box[2] - box[0])) // 2 - box[0]
    draw.text((x, layout.caption_y), text, font=font, fill=CAPTION_RGB)


def compose(src: str, caption: str, layout: Layout, font_path: str) -> Image.Image:
    shot = Image.open(src).convert("RGB")
    scale = layout.device_width / shot.size[0]
    shot = shot.resize(
        (layout.device_width, round(shot.size[1] * scale)), Image.LANCZOS
    )
    shot = rounded(shot, layout.corner_radius)

    canvas = gradient(layout.canvas)

    # Soft drop shadow so the device reads as a separate plane, as in the
    # shipped assets.
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow.paste(
        Image.new("RGBA", shot.size, (0, 0, 0, 90)),
        (layout.device_xy[0], layout.device_xy[1] + 10),
        shot,
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(18))
    canvas = Image.alpha_composite(canvas.convert("RGBA"), shadow)

    canvas.paste(shot, layout.device_xy, shot)
    canvas = canvas.convert("RGB")  # flatten: Play rejects alpha on screenshots
    draw_caption(canvas, caption, layout, font_path)
    return canvas


def verify(path: str, expect: tuple[int, int], min_edge: int) -> None:
    with Image.open(path) as im:
        if im.size != expect:
            raise SystemExit(f"{path}: size {im.size}, expected {expect}")
        if im.mode != "RGB":
            raise SystemExit(f"{path}: mode {im.mode}, expected RGB (no alpha)")
    w, h = expect
    ratio = max(w, h) / min(w, h)
    if abs(ratio - 16 / 9) > 0.01:
        raise SystemExit(f"{path}: ratio {ratio:.3f} is not 16:9 / 9:16")
    if min(w, h) < min_edge or max(w, h) > MAX_EDGE:
        raise SystemExit(f"{path}: {w}x{h} outside Play's edge limits")
    size = os.path.getsize(path)
    if size > MAX_BYTES:
        raise SystemExit(f"{path}: {size} bytes exceeds Play's 8 MB limit")


def build(check_only: bool) -> list[tuple[str, str, str, str]]:
    font_path = find_font()
    rows: list[tuple[str, str, str, str]] = []

    for slot, shots, layout, srcdir in (
        ("phone", PHONE_SHOTS, PHONE, os.path.join(PLAY, "phone")),
        ("tablet", TABLET_SHOTS, TABLET, os.path.join(PLAY, "tablet-10in")),
    ):
        for name, caption in shots:
            src = os.path.join(srcdir, name)
            if not os.path.isfile(src):
                raise SystemExit(f"missing source capture: {src}")

            if slot == "phone":
                dest = os.path.join(OUT, "phone", name)
                if not check_only:
                    os.makedirs(os.path.dirname(dest), exist_ok=True)
                    compose(src, caption, layout, font_path).save(
                        dest, "PNG", optimize=True
                    )
                verify(dest, PHONE.canvas, MIN_EDGE)
                rows.append(("Phone", name, "1080x1920", caption))
            else:
                big = compose(src, caption, layout, font_path)
                d10 = os.path.join(OUT, "tablet-10in", name)
                d7 = os.path.join(OUT, "tablet-7in", name)
                if not check_only:
                    os.makedirs(os.path.dirname(d10), exist_ok=True)
                    os.makedirs(os.path.dirname(d7), exist_ok=True)
                    big.save(d10, "PNG", optimize=True)
                    # 7-inch is the SAME canvas at 0.75 -- identical framing,
                    # which is how the 2026-07 pair was produced.
                    big.resize((1920, 1080), Image.LANCZOS).save(
                        d7, "PNG", optimize=True
                    )
                verify(d10, (2560, 1440), MIN_EDGE_10IN)
                verify(d7, (1920, 1080), MIN_EDGE)
                rows.append(("10-inch", name, "2560x1440", caption))
                rows.append(("7-inch", name, "1920x1080", caption))

    # Prune anything this run did not write. Without this, a renamed shot
    # leaves its predecessor behind in store-ready/ and the next person
    # uploads a screenshot that no longer matches the app.
    if not check_only:
        expected = {
            "phone": {n for n, _ in PHONE_SHOTS},
            "tablet-10in": {n for n, _ in TABLET_SHOTS},
            "tablet-7in": {n for n, _ in TABLET_SHOTS},
        }
        for slot_name, keep in expected.items():
            slot_path = os.path.join(OUT, slot_name)
            if not os.path.isdir(slot_path):
                continue
            for leaf in sorted(os.listdir(slot_path)):
                if leaf.endswith(".png") and leaf not in keep:
                    os.remove(os.path.join(slot_path, leaf))
                    print(f"  pruned stale {slot_name}/{leaf}")

    # Graphics that are not screenshots: verified, never regenerated here.
    for extra, expect, mode in (
        ("feature-1024x500.png", (1024, 500), "RGB"),
        ("icon-512.png", (512, 512), None),
    ):
        path = os.path.join(OUT, extra)
        if os.path.isfile(path):
            with Image.open(path) as im:
                if im.size != expect:
                    raise SystemExit(f"{path}: size {im.size}, expected {expect}")
                if mode and im.mode != mode:
                    raise SystemExit(f"{path}: mode {im.mode}, expected {mode}")
    return rows


MANIFEST_HEAD = """# Google Play - upload-ready assets (`store-ready/`)

Generated by `dev/store/gen_store_shots.py` from the raw captures in
`../phone` and `../tablet-10in`. Every file below is verified on write:
24-bit PNG, no alpha, exactly 16:9 or 9:16, inside Play's size limits.
Re-run the generator (or `--check`) to re-assert all of it.

The 7-inch set is the 10-inch canvas scaled to 0.75, so both tablet slots show
identical framing.

## Where each file goes in Play Console -> Store listing -> Graphics

| Slot | File | Dimensions | Caption |
| :--- | :--- | :--- | :--- |
"""

MANIFEST_TAIL = """
| Feature graphic | `feature-1024x500.png` | 1024x500 | - |
| App icon | `icon-512.png` | 512x512 | - |

## Play requirements these satisfy

- **Phone:** PNG/JPEG - min 2, max 8 - 16:9 or 9:16 - each side 320-3840 px - <= 8 MB.
- **7-inch tablet:** PNG/JPEG - 16:9 or 9:16 - each side 320-3840 px - <= 8 MB.
- **10-inch tablet:** PNG/JPEG - 16:9 or 9:16 - each side **1080**-3840 px - <= 8 MB.
- **Feature graphic:** 24-bit PNG (no alpha) or JPEG - 1024x500 - <= 15 MB.
- **App icon:** 32-bit PNG - 512x512 - <= 1 MB.

## Demo content

The photos in these shots are real CC0 photographs, not the synthetic gradient
tiles a reviewer previously read as "placeholder images or stock photos". See
[`../DEMO-MEDIA-PROVENANCE.md`](../DEMO-MEDIA-PROVENANCE.md).

## Deliberately omitted

**No "video playing" screenshot.** The Android emulator cannot render video at
all - media_kit forces software rendering there and `eglCreateContext` fails
with `EGL_BAD_ATTRIBUTE` - and video thumbnails go through the same libmpv
path. With no physical device available, capturing the loading or error state
and presenting it as the video feature would misrepresent the app. Add this
shot when hardware is available.
"""


def write_manifest(rows: list[tuple[str, str, str, str]]) -> None:
    lines = [
        f"| {slot} | `{slot_dir(slot)}/{name}` | {dims} | {caption} |"
        for slot, name, dims, caption in rows
    ]
    # newline="\n": Python's default text mode writes CRLF on Windows, which
    # git normalises to LF on commit — so every re-run would leave the file
    # "modified" against a clean tree for no reason.
    with open(
        os.path.join(OUT, "MANIFEST.md"), "w", encoding="utf-8", newline="\n"
    ) as fh:
        fh.write(MANIFEST_HEAD + "\n".join(lines) + MANIFEST_TAIL)


def slot_dir(slot: str) -> str:
    return {
        "Phone": "phone",
        "10-inch": "tablet-10in",
        "7-inch": "tablet-7in",
    }[slot]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--check",
        action="store_true",
        help="verify existing outputs without rewriting them",
    )
    args = ap.parse_args()
    rows = build(args.check)
    if not args.check:
        write_manifest(rows)
    print(f"{'checked' if args.check else 'wrote'} {len(rows)} assets")
    for slot, name, dims, _ in rows:
        print(f"  {slot:<8} {name:<26} {dims}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
