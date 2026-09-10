#!/usr/bin/env python3
"""Print recent Google Play reviews, newest first — the only user feedback channel we have.

Airclone's GitHub repo has no watchers and effectively no issues; the people
running the app are on the stores. A Google TV user's three-bug report on
2026-09-09 arrived out of band, and there was no way to have seen it coming or
to check whether anyone else had said the same thing. This is that way.

  # Everything Play has (it keeps roughly a week of reviews)
  python tool/play_reviews.py --package com.gigaionllc.airclone

  # CI-friendly: exit 1 if any review is at or below a star threshold, so a
  # scheduled run can shout rather than be read.
  python tool/play_reviews.py --package com.gigaionllc.airclone --fail-at-or-below 3

**Play only keeps about a week of reviews on this endpoint.** That is not a
limit worth working around here, but it does mean an unscheduled run is not a
substitute for a scheduled one: nobody reads a review that expired.

Credentials come from GOOGLE_APPLICATION_CREDENTIALS (a service-account JSON
with access to the app), same as tool/play_tracks.py and tool/play_promote.py.
"""

from __future__ import annotations

import argparse
import sys

# Windows runners default stdout to cp1252, and a character outside it kills the
# script mid-run - store_submit.py died that way once and left a half-created
# Store submission behind. Every other script in tool/ carries this. Review text
# is written by strangers, so this one needs it more than most.
for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass

import google.auth
from google.auth.transport.requests import AuthorizedSession

API = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications"
SCOPE = "https://www.googleapis.com/auth/androidpublisher"


def _stars(n: int) -> str:
    """A star rating that survives a cp1252 console."""
    if not isinstance(n, int) or not 1 <= n <= 5:
        return "?"
    return "*" * n + "." * (5 - n)


def _flatten(review: dict) -> list[dict]:
    """One row per user comment on a review.

    A Play review is a thread: the user's comment plus any developer reply. Only
    the user's half is feedback, so the reply is folded in as context rather than
    listed as its own entry.
    """
    rows = []
    for c in review.get("comments", []):
        user = c.get("userComment")
        if not user:
            continue
        rows.append(
            {
                "id": review.get("reviewId", ""),
                "author": review.get("authorName") or "(anonymous)",
                "stars": user.get("starRating", 0),
                "text": (user.get("text") or "").strip(),
                "when": (user.get("lastModified") or {}).get("seconds", "0"),
                "version": (user.get("appVersionName") or "?"),
                "device": user.get("deviceMetadata", {}).get(
                    "productName", user.get("device", "?")
                ),
                "android": user.get("androidOsVersion", "?"),
                "replied": any(
                    "developerComment" in x for x in review.get("comments", [])
                ),
            }
        )
    return rows


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--package", required=True, help="applicationId")
    ap.add_argument(
        "--fail-at-or-below",
        type=int,
        default=0,
        help="exit 1 if any review has this star rating or lower (0 = never fail)",
    )
    ap.add_argument(
        "--max",
        type=int,
        default=100,
        help="stop after this many reviews (default 100)",
    )
    args = ap.parse_args()

    creds, _ = google.auth.default(scopes=[SCOPE])
    http = AuthorizedSession(creds)

    rows: list[dict] = []
    token = None
    while len(rows) < args.max:
        params = {"maxResults": 100}
        if token:
            params["token"] = token
        r = http.get(f"{API}/{args.package}/reviews", params=params, timeout=60)
        if r.status_code != 200:
            # A 401/403 here is almost always the service account lacking the
            # "Reply to reviews" permission, which is separate from release
            # access - say so rather than printing a bare status code.
            print(f"reviews request failed: HTTP {r.status_code}", file=sys.stderr)
            print(r.text[:800], file=sys.stderr)
            if r.status_code in (401, 403):
                print(
                    "\nThe service account needs the 'Reply to reviews' "
                    "permission in Play Console; release access alone is not "
                    "enough to READ them.",
                    file=sys.stderr,
                )
            return 2
        body = r.json()
        for review in body.get("reviews", []):
            rows.extend(_flatten(review))
        token = (body.get("tokenPagination") or {}).get("nextPageToken")
        if not token:
            break

    rows.sort(key=lambda x: int(x["when"] or 0), reverse=True)
    rows = rows[: args.max]

    if not rows:
        print("No reviews. (Play serves roughly the last week on this endpoint.)")
        return 0

    print(f"{len(rows)} review(s), newest first:\n")
    worst = 5
    for row in rows:
        worst = min(worst, row["stars"] if isinstance(row["stars"], int) else 5)
        head = (
            f"{_stars(row['stars'])}  {row['author']}  "
            f"v{row['version']}  {row['device']} (Android {row['android']})"
        )
        print(head)
        print(f"  {row['text'] or '(no text - rating only)'}")
        if row["replied"]:
            print("  [already replied to]")
        print()

    if args.fail_at_or_below and worst <= args.fail_at_or_below:
        print(
            f"FAIL: at least one review is {worst} star(s), "
            f"at or below the {args.fail_at_or_below} threshold.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
