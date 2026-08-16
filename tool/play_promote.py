#!/usr/bin/env python3
"""Promote the build already in one Google Play track to another.

This exists because you cannot promote by re-uploading: Play refuses a version
code it has already seen ("Version code N has already been used"). Promotion is
a *metadata* edit — take the version code sitting in the source track and add a
release for it on the target track — which is what this script does.

Run from CI (see .github/workflows/promote-play.yml) or locally with a service
account key that has "Release apps to production" on the app:

    GOOGLE_APPLICATION_CREDENTIALS=key.json \\
    python tool/play_promote.py --package com.gigaionllc.airclone --rollout 10

Nothing is committed unless --commit is passed: the default is a dry run that
prints exactly what it would do, because the failure mode here is shipping to
every user at once.
"""

from __future__ import annotations

import argparse
import sys

import google.auth
from google.auth.transport.requests import AuthorizedSession

API = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications"
SCOPE = "https://www.googleapis.com/auth/androidpublisher"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--package", required=True, help="applicationId, e.g. com.example.app")
    ap.add_argument("--from-track", default="beta", help="source track (default: beta = Open testing)")
    ap.add_argument("--to-track", default="production", help="target track (default: production)")
    ap.add_argument(
        "--rollout",
        type=float,
        default=10.0,
        help="percent of users, 0 < r <= 100. 100 means a full release (default: 10)",
    )
    ap.add_argument(
        "--version-code",
        type=int,
        default=None,
        help="promote this exact version code instead of what is in --from-track",
    )
    ap.add_argument("--commit", action="store_true", help="actually commit (default: dry run)")
    ap.add_argument(
        "--force",
        action="store_true",
        help="override the safety checks (narrowing a live rollout, or going backwards)",
    )
    args = ap.parse_args()

    if not 0 < args.rollout <= 100:
        print(f"error: --rollout must be in (0, 100], got {args.rollout}", file=sys.stderr)
        return 2

    creds, _ = google.auth.default(scopes=[SCOPE])
    http = AuthorizedSession(creds)
    app = f"{API}/{args.package}"

    def check(resp, what: str):
        if not resp.ok:
            # Play's errors are actually informative; print the body verbatim
            # rather than a tidy summary that loses the reason.
            print(f"error: {what} failed [{resp.status_code}]\n{resp.text}", file=sys.stderr)
            sys.exit(1)
        return resp.json() if resp.content else {}

    edit = check(http.post(f"{app}/edits"), "edits.insert")
    edit_id = edit["id"]
    print(f"edit {edit_id} opened for {args.package}")

    if args.version_code is not None:
        version_codes = [args.version_code]
        print(f"promoting version code {args.version_code} (explicitly given)")
    else:
        src = check(
            http.get(f"{app}/edits/{edit_id}/tracks/{args.from_track}"),
            f"tracks.get({args.from_track})",
        )
        releases = src.get("releases") or []
        version_codes = sorted(
            {int(v) for r in releases for v in (r.get("versionCodes") or [])}
        )
        if not version_codes:
            print(
                f"error: no version codes in track '{args.from_track}' — "
                "has a release been uploaded to it?",
                file=sys.stderr,
            )
            return 1
        # Highest wins: a track can hold several (e.g. a halted rollout).
        version_codes = [version_codes[-1]]
        print(f"found version code {version_codes[0]} in '{args.from_track}'")

    full = args.rollout >= 100
    release: dict = {
        "versionCodes": [str(v) for v in version_codes],
        "status": "completed" if full else "inProgress",
    }
    if not full:
        # The API takes a fraction, the humans running this think in percent.
        release["userFraction"] = round(args.rollout / 100.0, 4)

    # Carry the source release's notes across so the target track is not blank.
    if args.version_code is None:
        for r in releases:
            if str(version_codes[0]) in [str(v) for v in (r.get("versionCodes") or [])]:
                if r.get("name"):
                    release["name"] = r["name"]
                if r.get("releaseNotes"):
                    release["releaseNotes"] = r["releaseNotes"]
                break

    where = "100% (full release)" if full else f"{args.rollout}% staged rollout"

    # ── Look before you leap ────────────────────────────────────────────────
    # `tracks.update` overwrites the target track's releases, so two silent
    # regressions are reachable by ordinary use. They are NOT the same severity,
    # and conflating them is how an operator learns to ignore a red run:
    #
    #   nothing to do   target is already at or beyond what was asked for.
    #                   Production is fine; the request simply achieves nothing.
    #                   -> warn, change nothing, EXIT 0 (a green run with a note)
    #   backwards       target serves a NEWER build than the one being promoted.
    #                   Committing would downgrade users.
    #                   -> error, EXIT 1 (a red run means something is wrong)
    #
    # Reserving red for the genuinely wrong case is the whole point: a failed
    # run in the Actions tab must mean "look at me", not "the guard worked".
    target = check(
        http.get(f"{app}/edits/{edit_id}/tracks/{args.to_track}"),
        f"tracks.get({args.to_track})",
    )
    promoting = version_codes[0]
    requested = 1.0 if full else args.rollout / 100.0
    fatal: list[str] = []
    noop: list[str] = []
    for r in target.get("releases") or []:
        codes = [int(v) for v in (r.get("versionCodes") or [])]
        if not codes:
            continue
        live = max(codes)
        # A completed release is at 100%; an inProgress one carries a fraction.
        fraction = 1.0 if r.get("status") == "completed" else float(r.get("userFraction") or 0)
        if live == promoting:
            print(f"{args.to_track} already serves {live} at {fraction:.0%}")
            if fraction >= requested:
                same = abs(fraction - requested) < 1e-9
                noop.append(
                    f"{args.to_track} already serves {live} at {fraction:.0%}"
                    + (
                        " — exactly what was requested, so there is nothing to do."
                        if same
                        else f", which is wider than the requested {where}. "
                        "Applying it would REDUCE how many users get this build."
                    )
                )
        elif live > promoting:
            fatal.append(
                f"{args.to_track} already serves {live}, which is NEWER than {promoting}. "
                "Promoting would move users backwards."
            )

    if fatal and not args.force:
        for f in fatal:
            print(f"error: {f}", file=sys.stderr)
        print("refusing — pass --force if this is genuinely intended.", file=sys.stderr)
        http.delete(f"{app}/edits/{edit_id}")
        return 1
    if noop and not args.force:
        for n in noop:
            # ::warning:: surfaces on the GitHub run summary without failing it.
            print(f"::warning::{n} Nothing was changed.")
        print(f"\nno change made — {args.to_track} was left exactly as it was.")
        http.delete(f"{app}/edits/{edit_id}")
        return 0
    if fatal or noop:
        print("--force given; proceeding despite the checks above.")

    print(f"→ {args.to_track}: version {version_codes[0]} at {where}")

    if not args.commit:
        print("\nDRY RUN — nothing changed. Re-run with --commit to apply.")
        http.delete(f"{app}/edits/{edit_id}")
        return 0

    check(
        http.put(
            f"{app}/edits/{edit_id}/tracks/{args.to_track}",
            json={"track": args.to_track, "releases": [release]},
        ),
        f"tracks.update({args.to_track})",
    )
    check(http.post(f"{app}/edits/{edit_id}:commit"), "edits.commit")
    print(f"committed — {args.to_track} now serving {version_codes[0]} at {where}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
