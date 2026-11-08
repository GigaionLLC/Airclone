#!/usr/bin/env python3
"""Watch one workflow run (usually ship.yml) and log each job's state as it changes.

    python tool/ship_watch.py                      # the newest ship.yml run
    python tool/ship_watch.py 42521804507          # a given run id
    python tool/ship_watch.py 42521804507 --out ~/airclone-scratch/ship-v0.32.0.txt

Read-only: it only calls `gh run view`. It polls every 90 s (faster trips
GitHub's secondary rate limit) and prints a block, with the time in Pacific,
only when some job's state changed. The same lines go to --out when given,
so a background watcher leaves its result on disk. Exit code: 0 when the run
ends in success, 1 for any other conclusion, 2 on bad usage.

Output is ASCII only (AGENT.md rule 12). Needs `gh` logged in.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from datetime import datetime
from zoneinfo import ZoneInfo

POLL_SECONDS = 90
PACIFIC = ZoneInfo("America/Los_Angeles")


def gh_json(args: list[str]) -> object:
    out = subprocess.run(["gh", *args], capture_output=True, text=True)
    if out.returncode:
        raise RuntimeError("gh %s failed: %s" % (" ".join(args), out.stderr.strip()))
    return json.loads(out.stdout)


def newest_ship_run() -> str:
    runs = gh_json(["run", "list", "--workflow", "ship.yml", "--limit", "1",
                    "--json", "databaseId"])
    if not runs:
        raise RuntimeError("no ship.yml runs found")
    return str(runs[0]["databaseId"])


def snapshot(run_id: str) -> tuple[str, str, list[str]]:
    """(status, conclusion, one line per job that has started)."""
    r = gh_json(["run", "view", run_id, "--json", "status,conclusion,jobs"])
    jobs = ["%s: %s %s" % (j["name"], j["status"], j.get("conclusion") or "")
            for j in r["jobs"] if j["status"] != "queued"]
    return r["status"], r.get("conclusion") or "", [j.rstrip() for j in jobs]


def main(argv: list[str]) -> int:
    out_path = None
    if "--out" in argv:
        i = argv.index("--out")
        if i + 1 >= len(argv):
            print(__doc__)
            return 2
        out_path = os.path.expanduser(argv[i + 1])
        os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
        argv = argv[:i] + argv[i + 2:]
    if len(argv) > 1 or (argv and not argv[0].isdigit()):
        print(__doc__)
        return 2
    run_id = argv[0] if argv else newest_ship_run()

    def emit(lines: list[str]) -> None:
        text = "\n".join(lines) + "\n"
        print(text, end="", flush=True)
        if out_path:
            with open(out_path, "a", encoding="ascii", errors="replace") as f:
                f.write(text)

    emit(["watching run %s" % run_id])
    last: list[str] | None = None
    while True:
        try:
            status, conclusion, jobs = snapshot(run_id)
        except RuntimeError as e:
            # A transient gh/API error is not the run's result: log it and keep polling.
            emit(["!! %s" % e])
            time.sleep(POLL_SECONDS)
            continue
        state = ["RUN %s %s" % (status, conclusion)] + jobs
        if state != last:
            now = datetime.now(PACIFIC).strftime("%Y-%m-%d %H:%M %Z")
            emit(["== " + now] + state)
            last = state
        if status == "completed":
            emit(["DONE %s" % (conclusion or "unknown")])
            return 0 if conclusion == "success" else 1
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
