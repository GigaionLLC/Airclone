#!/usr/bin/env python3
"""Run one store lane for ship.yml, and decide the next Apple step.

ship.yml ships a tag to every store by dispatching the SAME workflows a person
runs by hand (dev/store-release-playbook.md), so each store keeps exactly one
code path and its own safety checks. This is the glue:

    python tool/ship_lane.py dispatch publish-play.yml -f tag=v0.32.0 -f mode=upload
    python tool/ship_lane.py dispatch mas-release.yml --ref v0.32.0 -f mode=upload --timeout-min 150
    python tool/ship_lane.py apple "STATE target=NONE blocking=0 build=VALID"
    python tool/ship_lane.py apple-ship --platform IOS --version 0.32.0 --build 170 --key key.p8
    python tool/ship_lane.py apple-wait --platform IOS --version 0.32.0 --build 170 --key key.p8

dispatch: starts the workflow, finds the run it started, waits for it (polling
every 90 s - faster trips GitHub's secondary rate limit), and exits non-zero
unless it ended in success. A failed lane is never retried here: lanes that
reach a store create objects there (a version code, a submission, a build
number), and the playbook rule is to read the log before anything is re-run.

apple-ship: playbook phases 11-13 for one platform. Waits for the build to be
VALID, then create, listing text, apply, audit and Add for Review, with
releaseType AFTER_APPROVAL. Needs KEY_ID and ISSUER in the environment and the
key at --key; it reads state itself and leaves every write to the lanes.

apple-wait: only waits for the build to be VALID, and writes nothing. ship.yml
runs it before the TestFlight lane, which needs a processed build, so the beta
is in Beta App Review before the App Store version is submitted.

apple: reads the line `tool/asc_build.py --version-state` prints and says what
to do next - wait, create, update, done or stop - so the decision is code with
tests rather than shell.

Needs `gh` on PATH with GH_TOKEN set (ship.yml passes its own token, which
needs `actions: write`).
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone

POLL_SECONDS = 90
FIND_SECONDS = 15
FIND_TRIES = 16  # about 4 minutes for the run to show up

# Apple states, by what they mean for a version the pipeline is shipping.
# Submitted (or further along): nothing left for the pipeline to do.
SUBMITTED = {
    "WAITING_FOR_REVIEW", "IN_REVIEW", "ACCEPTED",
    "PENDING_DEVELOPER_RELEASE", "PENDING_APPLE_RELEASE",
    "PROCESSING_FOR_APP_STORE", "READY_FOR_SALE", "READY_FOR_DISTRIBUTION",
}
# Apple or a reviewer pushed back. The reason is in Resolution Center, which
# the API cannot read, so a human has to look.
REJECTED = {"REJECTED", "METADATA_REJECTED", "INVALID_BINARY"}
# Editable and normal: being prepared, or withdrawn by us.
PREPARING = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED"}
BUILD_BAD = {"INVALID", "FAILED", "EXPIRED"}


def parse_state(line: str) -> dict[str, str]:
    """`STATE target=X blocking=N build=Y` -> {"target": X, ...}."""
    words = line.split()
    if not words or words[0] != "STATE":
        raise ValueError("not a STATE line: %r" % line)
    out = dict(w.split("=", 1) for w in words[1:] if "=" in w)
    for k in ("target", "blocking", "build"):
        if k not in out:
            raise ValueError("STATE line lacks %s: %r" % (k, line))
    return out


def decide_apple(target: str, blocking: int, build: str) -> tuple[str, str]:
    """(action, why). action is one of wait, create, update, done, stop."""
    if target == "READY_FOR_REVIEW":
        # In a review submission that was never sent: the submit died between
        # adding the item and setting submitted=true. Not done, and not
        # editable either, so asc-submit-review cannot finish it.
        return "stop", ("READY_FOR_REVIEW: added to a review submission that was "
                        "never sent. Jake sends or removes it in App Store Connect.")
    if target in SUBMITTED:
        return "done", "already %s" % target
    if target in REJECTED:
        return "stop", ("%s: the reason is in Resolution Center, which the API "
                        "cannot read. Jake looks first." % target)
    if target not in PREPARING and target != "NONE":
        return "stop", "unknown version state %s" % target
    if blocking:
        return "stop", ("%d older version(s) still hold the platform (in review, "
                        "or approved and waiting). Jake decides the order." % blocking)
    action, why = decide_build(build)
    if action != "ready":
        return action, why
    return ("create" if target == "NONE" else "update"), why


def decide_build(build: str) -> tuple[str, str]:
    """(action, why) for the build alone. action is one of wait, ready, stop."""
    if build in BUILD_BAD:
        return "stop", ("build is %s at Apple. A re-upload needs a higher build "
                        "number, which is a new tag." % build)
    if build != "VALID":
        return "wait", "build is %s" % build
    return "ready", "build VALID"


def pick_run(runs: list[dict], since: datetime, ref: str) -> dict | None:
    """The run our dispatch started: created at or after `since`, on `ref`.

    More than one candidate means someone else dispatched the same workflow at
    the same moment; guessing could watch the wrong run, so that is an error.
    """
    cand = [r for r in runs
            if r.get("headBranch") == ref
            and r.get("event") == "workflow_dispatch"
            and _ts(r["createdAt"]) >= since]
    if len(cand) > 1:
        raise RuntimeError("%d runs match; cannot tell which one this dispatch "
                           "started: %s" % (len(cand), ", ".join(
                               str(r["databaseId"]) for r in cand)))
    return cand[0] if cand else None


def _ts(s: str) -> datetime:
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


def gh(*args: str) -> str:
    return subprocess.run(["gh", *args], check=True, capture_output=True,
                          text=True).stdout


def _out(key: str, value: str) -> None:
    path = os.environ.get("GITHUB_OUTPUT")
    if path:
        with open(path, "a", encoding="utf-8") as f:
            f.write("%s=%s\n" % (key, value))


def _summary(text: str) -> None:
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if path:
        with open(path, "a", encoding="utf-8") as f:
            f.write(text + "\n")


def dispatch(argv: list[str]) -> int:
    if not argv:
        sys.exit("dispatch needs a workflow file")
    workflow, rest = argv[0], argv[1:]
    ref = os.environ.get("SHIP_DEFAULT_REF", "main")
    fields: list[str] = []
    timeout = 120
    i = 0
    while i < len(rest):
        a = rest[i]
        if a == "--ref":
            ref = rest[i + 1]
        elif a == "-f":
            fields += ["-f", rest[i + 1]]
        elif a == "--timeout-min":
            timeout = int(rest[i + 1])
        else:
            sys.exit("unknown argument %r" % a)
        i += 2

    # A little slack for clock skew between this runner and GitHub's API.
    since = datetime.now(timezone.utc) - timedelta(seconds=10)
    print("dispatch %s on %s %s" % (workflow, ref, " ".join(fields[1::2])), flush=True)
    gh("workflow", "run", workflow, "--ref", ref, *fields)

    run = None
    for _ in range(FIND_TRIES):
        time.sleep(FIND_SECONDS)
        runs = json.loads(gh("run", "list", "--workflow", workflow, "--limit", "20",
                             "--json", "databaseId,createdAt,headBranch,event,url"))
        run = pick_run(runs, since, ref)
        if run:
            break
    if not run:
        print("::error::dispatched %s but no run appeared. Check the Actions tab "
              "before dispatching again." % workflow)
        return 1
    rid = str(run["databaseId"])
    print("run %s  %s" % (rid, run["url"]), flush=True)
    _out("run_id", rid)
    _summary("- `%s` %s: [run %s](%s)" % (workflow, " ".join(fields[1::2]), rid, run["url"]))

    deadline = time.monotonic() + timeout * 60
    while True:
        time.sleep(POLL_SECONDS)
        st = json.loads(gh("run", "view", rid, "--json", "status,conclusion"))
        if st["status"] == "completed":
            break
        if time.monotonic() > deadline:
            print("::error::run %s still %s after %d min. It keeps running; watch it "
                  "and re-run this ship job only once it has finished." % (rid, st["status"], timeout))
            return 1
    if st["conclusion"] != "success":
        print("::error::%s run %s ended %s. Do not re-dispatch: read its log and check "
              "the store first (dev/store-release-playbook.md)." % (workflow, rid, st["conclusion"]))
        return 1
    print("%s run %s: success" % (workflow, rid))
    return 0


def apple(argv: list[str]) -> int:
    s = parse_state(" ".join(argv))
    action, why = decide_apple(s["target"], int(s["blocking"]), s["build"])
    print("%s: %s" % (action, why))
    _out("action", action)
    return 0


APP_ID = "6790176897"  # public: it is in every App Store URL for the app
RELEASE_TYPE = "AFTER_APPROVAL"  # Jake 2026-11-08: publish when review passes


def read_state(key: str, platform: str, version: str, build: str) -> dict[str, str]:
    out = subprocess.run(
        [sys.executable, "tool/asc_build.py", key, os.environ["KEY_ID"],
         os.environ["ISSUER"], APP_ID, "--platform", platform,
         "--version-state", version, "--build", build],
        capture_output=True, text=True)
    print(out.stdout, end="", flush=True)
    line = next((ln for ln in out.stdout.splitlines() if ln.startswith("STATE ")), None)
    if out.returncode or not line:
        raise RuntimeError("asc_build.py --version-state failed (exit %d)" % out.returncode)
    return parse_state(line)


def lane(*args: str) -> None:
    if dispatch(list(args)):
        raise SystemExit(1)


def apple_ship(argv: list[str]) -> int:
    """Take one platform from "build uploaded" to "in review", AFTER_APPROVAL.

    The same lanes, in the same order, as playbook phases 11-13. Re-running it is
    safe: a version already submitted is "done", one already created is updated,
    and everything that needs a human (a rejection, an older version still held)
    stops before writing.
    """
    args = dict(zip(argv[::2], argv[1::2]))
    platform, version, build = args["--platform"], args["--version"], args["--build"]
    key, wait_min = args["--key"], int(args.get("--wait-min", "150"))
    deadline = time.monotonic() + wait_min * 60
    while True:
        s = read_state(key, platform, version, build)
        action, why = decide_apple(s["target"], int(s["blocking"]), s["build"])
        print("%s %s: %s (%s)" % (platform, version, action, why), flush=True)
        if action != "wait":
            break
        if time.monotonic() > deadline:
            print("::error::%s build %s still not VALID after %d min. Apple may have "
                  "dropped it (builds 117 and 118 were); report it." % (platform, build, wait_min))
            return 1
        time.sleep(600)
    if action == "done":
        _summary("- Apple %s %s: %s, nothing to do" % (platform, version, why))
        return 0
    if action == "stop":
        print("::error::%s %s: %s" % (platform, version, why))
        return 1
    f = ["-f", "platform=" + platform]
    if action == "create":
        lane("asc-version.yml", *f, "-f", "mode=create", "-f", "version=" + version,
             "-f", "release_type=" + RELEASE_TYPE, "--timeout-min", "20")
        s = read_state(key, platform, version, build)
        action, why = decide_apple(s["target"], int(s["blocking"]), s["build"])
        if action != "update":
            print("::error::after create, %s %s reads %s (%s)" % (platform, version, action, why))
            return 1
    lane("asc-listing.yml", *f, "-f", "version=" + version, "-f", "what=text",
         "-f", "mode=apply", "--timeout-min", "20")
    lane("asc-version.yml", *f, "-f", "mode=apply", "-f", "version=" + version,
         "-f", "build=" + build, "-f", "notes=true", "-f", "copyright=true",
         "-f", "release_type=" + RELEASE_TYPE, "--timeout-min", "20")
    lane("asc-version.yml", *f, "-f", "mode=audit", "-f", "version=" + version,
         "-f", "release_type=" + RELEASE_TYPE, "--timeout-min", "20")
    # The submit re-audits and refuses on any gap, so the audit above is the
    # readable record and this is the gate.
    lane("asc-submit-review.yml", *f, "-f", "mode=submit", "-f", "confirm_version=" + version,
         "-f", "release_type=" + RELEASE_TYPE, "--timeout-min", "20")
    _summary("- Apple %s %s: submitted, publishes itself when review passes" % (platform, version))
    return 0


def apple_wait(argv: list[str]) -> int:
    """Wait until the build is VALID. Read-only; the version state is ignored."""
    args = dict(zip(argv[::2], argv[1::2]))
    platform, version, build = args["--platform"], args["--version"], args["--build"]
    key, wait_min = args["--key"], int(args.get("--wait-min", "150"))
    deadline = time.monotonic() + wait_min * 60
    while True:
        s = read_state(key, platform, version, build)
        action, why = decide_build(s["build"])
        print("%s build %s: %s (%s)" % (platform, build, action, why), flush=True)
        if action == "ready":
            return 0
        if action == "stop":
            print("::error::%s build %s: %s" % (platform, build, why))
            return 1
        if time.monotonic() > deadline:
            print("::error::%s build %s still not VALID after %d min. Apple may have "
                  "dropped it (builds 117 and 118 were); report it." % (platform, build, wait_min))
            return 1
        time.sleep(600)


def main() -> int:
    cmds = {"dispatch": dispatch, "apple": apple, "apple-ship": apple_ship,
            "apple-wait": apple_wait}
    if len(sys.argv) < 2 or sys.argv[1] not in cmds:
        print(__doc__)
        return 2
    return cmds[sys.argv[1]](sys.argv[2:])


if __name__ == "__main__":
    sys.exit(main())
