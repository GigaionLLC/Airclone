#!/usr/bin/env python3
"""Print what each Google Play track is actually serving — and optionally assert it.

Two jobs, both about not trusting a green check:

  # What is live right now?
  python tool/play_tracks.py --package com.example.app

  # CI: fail unless open testing really has the build we just uploaded.
  python tool/play_tracks.py --package com.example.app --expect beta=114

The second matters because an upload step can report success while nothing
lands — a deprecated input silently ignored, an edit committed against the
wrong track. Asking Play what it holds is the only answer that counts.

Credentials come from GOOGLE_APPLICATION_CREDENTIALS (a service-account JSON
with access to the app), same as tool/play_promote.py.
"""

from __future__ import annotations

import argparse
import sys

import google.auth
from google.auth.transport.requests import AuthorizedSession

API = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications"
SCOPE = "https://www.googleapis.com/auth/androidpublisher"
TRACKS = ("internal", "alpha", "beta", "production")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--package", required=True, help="applicationId")
    ap.add_argument(
        "--expect",
        action="append",
        default=[],
        metavar="TRACK=CODE",
        help="fail unless TRACK serves version code CODE (repeatable)",
    )
    args = ap.parse_args()

    expected: dict[str, int] = {}
    for pair in args.expect:
        track, _, code = pair.partition("=")
        if not code.isdigit():
            print(f"error: --expect wants TRACK=CODE, got {pair!r}", file=sys.stderr)
            return 2
        expected[track] = int(code)

    creds, _ = google.auth.default(scopes=[SCOPE])
    http = AuthorizedSession(creds)
    app = f"{API}/{args.package}"

    resp = http.post(f"{app}/edits")
    if not resp.ok:
        print(f"error: edits.insert failed [{resp.status_code}]\n{resp.text}", file=sys.stderr)
        return 1
    edit_id = resp.json()["id"]

    live: dict[str, set[int]] = {}
    try:
        for track in TRACKS:
            r = http.get(f"{app}/edits/{edit_id}/tracks/{track}")
            if not r.ok:
                print(f"{track:11} (unavailable: {r.status_code})")
                continue
            releases = r.json().get("releases") or []
            if not releases:
                print(f"{track:11} —")
            for rel in releases:
                codes = {int(v) for v in (rel.get("versionCodes") or [])}
                live.setdefault(track, set()).update(codes)
                status = rel.get("status", "?")
                # A completed release is at 100%; inProgress carries a fraction.
                share = "100%" if status == "completed" else f"{float(rel.get('userFraction') or 0):.0%}"
                print(
                    f"{track:11} {sorted(codes)} {status} at {share}"
                    f"  {rel.get('name', '')}".rstrip()
                )
    finally:
        # Read-only: never leave a dangling edit behind.
        http.delete(f"{app}/edits/{edit_id}")

    failures = [
        f"{track} does not serve {code} (it has {sorted(live.get(track, set())) or 'nothing'})"
        for track, code in expected.items()
        if code not in live.get(track, set())
    ]
    if failures:
        print("", file=sys.stderr)
        for f in failures:
            print(f"error: {f}", file=sys.stderr)
        return 1
    if expected:
        print("\nall expectations met")
    return 0


if __name__ == "__main__":
    sys.exit(main())
