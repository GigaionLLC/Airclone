#!/usr/bin/env python3
"""Upload Play Store listing images - including the Android TV set.

The repo already holds the screenshots and graphics under docs/store/play/, and
they were being retyped into the Console by hand. The API takes them directly,
so the documents stay the source of truth.

    # What is up there now?
    python tool/play_images.py --package com.example.app --report

    # Send the TV set (replacing whatever is there - Play APPENDS otherwise)
    python tool/play_images.py --package com.example.app \
        --type tvScreenshots --dir docs/store/play/tv --replace --apply

Image types Play accepts: phoneScreenshots, sevenInchScreenshots,
tenInchScreenshots, tvScreenshots, wearScreenshots, tvBanner, icon,
featureGraphic.

--replace matters. Play ADDS an uploaded image to the set rather than
overwriting it, so running this twice without --replace leaves duplicates in the
listing - the same trap the App Store screenshot tool has.

Credentials come from GOOGLE_APPLICATION_CREDENTIALS (a service-account JSON
with access to the app), same as tool/play_tracks.py.
"""

from __future__ import annotations

import argparse
import pathlib
import sys

import google.auth
from google.auth.transport.requests import AuthorizedSession

API = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications"
UPLOAD = "https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications"
SCOPE = "https://www.googleapis.com/auth/androidpublisher"

TYPES = (
    "phoneScreenshots",
    "sevenInchScreenshots",
    "tenInchScreenshots",
    "tvScreenshots",
    "wearScreenshots",
    "tvBanner",
    "icon",
    "featureGraphic",
)

# What Play will reject, checked here so the failure names the file rather than
# arriving as an opaque 400 halfway through a batch.
RULES = {
    "tvScreenshots": ("16:9", 1280, 720, 3840, 2160),
    "tvBanner": ("16:9", 1280, 720, 1280, 720),
}


def fail(msg: str) -> None:
    print(f"error: {msg}", file=sys.stderr)
    raise SystemExit(1)


def check(resp, what: str) -> dict:
    if not resp.ok:
        fail(f"{what} failed [{resp.status_code}]\n{resp.text}")
    return resp.json() if resp.text else {}


def image_size(path: pathlib.Path) -> tuple[int, int]:
    """Width/height of a PNG or JPEG, without a Pillow dependency in CI."""
    data = path.read_bytes()
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return int.from_bytes(data[16:20], "big"), int.from_bytes(data[20:24], "big")
    if data[:2] == b"\xff\xd8":  # JPEG: walk the segments to SOFn
        i = 2
        while i < len(data) - 9:
            if data[i] != 0xFF:
                i += 1
                continue
            marker = data[i + 1]
            if marker in (0xC0, 0xC1, 0xC2, 0xC3):
                return (
                    int.from_bytes(data[i + 7 : i + 9], "big"),
                    int.from_bytes(data[i + 5 : i + 7], "big"),
                )
            i += 2 + int.from_bytes(data[i + 2 : i + 4], "big")
    fail(f"{path.name}: not a PNG or JPEG Play will accept")
    raise AssertionError("unreachable")


def verify(path: pathlib.Path, image_type: str) -> str:
    rule = RULES.get(image_type)
    w, h = image_size(path)
    note = f"{w}x{h}"
    if rule is None:
        return note
    ratio, min_w, min_h, max_w, max_h = rule
    # 16:9 to within a pixel of rounding.
    if abs(w * 9 - h * 16) > 16:
        fail(f"{path.name} is {w}x{h}; {image_type} must be {ratio}")
    if w < min_w or h < min_h:
        fail(f"{path.name} is {w}x{h}; {image_type} minimum is {min_w}x{min_h}")
    if w > max_w or h > max_h:
        fail(f"{path.name} is {w}x{h}; {image_type} maximum is {max_w}x{max_h}")
    return note


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--package", required=True, help="applicationId")
    ap.add_argument("--language", default="en-US")
    ap.add_argument("--type", dest="image_type", choices=TYPES)
    ap.add_argument("--dir", help="directory of images, uploaded in sorted order")
    ap.add_argument("--replace", action="store_true", help="clear the set first")
    ap.add_argument("--apply", action="store_true", help="without this, dry run")
    ap.add_argument("--report", action="store_true", help="list what is live")
    args = ap.parse_args()

    if not args.report and not (args.image_type and args.dir):
        fail("need --type and --dir (or --report)")

    creds, _ = google.auth.default(scopes=[SCOPE])
    http = AuthorizedSession(creds)
    app = f"{API}/{args.package}"

    edit = check(http.post(f"{app}/edits"), "edits.insert")["id"]
    try:
        if args.report:
            for t in TYPES:
                r = http.get(f"{app}/edits/{edit}/listings/{args.language}/{t}")
                n = len(r.json().get("images", [])) if r.ok else 0
                print(f"  {t:22} {n}")
            return 0

        files = sorted(p for p in pathlib.Path(args.dir).iterdir()
                       if p.suffix.lower() in (".png", ".jpg", ".jpeg"))
        if not files:
            fail(f"no images in {args.dir}")

        print(f"{args.image_type} <- {args.dir}")
        for p in files:
            print(f"  {p.name:34} {verify(p, args.image_type)}")

        if not args.apply:
            print(f"\ndry run - {len(files)} image(s) would be uploaded"
                  f"{' after clearing the set' if args.replace else ''}."
                  " Pass --apply to send.")
            return 0

        base = f"{app}/edits/{edit}/listings/{args.language}/{args.image_type}"
        if args.replace:
            check(http.delete(base), "images.deleteall")
            print("  cleared the existing set")

        for p in files:
            mime = "image/png" if p.suffix.lower() == ".png" else "image/jpeg"
            check(
                http.post(
                    f"{UPLOAD}/{args.package}/edits/{edit}/listings/"
                    f"{args.language}/{args.image_type}?uploadType=media",
                    data=p.read_bytes(),
                    headers={"Content-Type": mime},
                ),
                f"images.upload {p.name}",
            )
            print(f"  uploaded {p.name}")

        check(http.post(f"{app}/edits/{edit}:commit"), "edits.commit")
        print("committed")
        edit = None
        return 0
    finally:
        if edit:
            http.delete(f"{app}/edits/{edit}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
