#!/usr/bin/env python3
"""Submit an MSIX to the Microsoft Store via the Store submission REST API.

Why this exists instead of `msstore publish`: the Microsoft Store Developer CLI
refuses to update a **paid** product —

    App updates are supported only for Free products.

— and Airclone carries the small Store listing price that funds its signing
certificates. That restriction lives in the CLI, not in the Store: the REST API
underneath handles paid products fine. See dev/msstore-ci-setup.md.

The flow the API requires, in order (each step depends on the previous one):

    1. token          client-credentials against the devcenter resource
    2. GET app        read state; refuse if a submission is already pending
    3. POST submission    clones the last published submission
    4. PUT submission     mark old packages PendingDelete, add the new one
    5. PUT the zip        to the SAS URL the submission handed back
    6. POST commit        hands it to certification
    7. GET status         bounded poll, only to catch an immediate rejection

Nothing is created unless --commit is passed. The default is a dry run that
authenticates and reports the app's real state, because a bad submission costs a
review cycle measured in days.

Run from CI (see .github/workflows/submit-msstore.yml) or locally:

    STORE_TENANT_ID=... STORE_CLIENT_ID=... STORE_CLIENT_SECRET=... \\
    python tool/store_submit.py --app-id 9PJ6LRTS2B8X --package airclone.msix
"""

from __future__ import annotations

import argparse
import io
import os
import sys
import time
import zipfile

import requests

RESOURCE = "https://manage.devcenter.microsoft.com"
API = f"{RESOURCE}/v1.0/my"

# Certification takes days, so polling to completion is pointless. These states
# mean the commit was accepted and the package is on its way; anything else this
# soon means it was rejected before a human ever looked at it.
ACCEPTED = {"CommitStarted", "PreProcessing", "CertificationInProgress", "Release", "Published"}


def fail(msg: str) -> None:
    print(f"::error::{msg}", file=sys.stderr)
    sys.exit(1)


def check(resp: requests.Response, what: str) -> dict:
    if not resp.ok:
        # Print the body verbatim. The Store's errors carry a `code` and
        # `message` that name the actual problem, and summarising loses it.
        fail(f"{what} failed [{resp.status_code}]\n{resp.text}")
    return resp.json() if resp.content else {}


def get_token(tenant: str, client_id: str, secret: str) -> str:
    resp = requests.post(
        f"https://login.microsoftonline.com/{tenant}/oauth2/token",
        data={
            "grant_type": "client_credentials",
            "client_id": client_id,
            "client_secret": secret,
            "resource": RESOURCE,
        },
        timeout=60,
    )
    if not resp.ok:
        # The four ways this fails are indistinguishable from the message alone
        # (wrong tenant, missing app, unauthorised app, malformed secret), so
        # point at the runbook that lists them in order of what you can prove.
        fail(
            f"token request failed [{resp.status_code}]\n{resp.text}\n"
            "See dev/msstore-ci-setup.md §6 — work through the causes in order."
        )
    return resp.json()["access_token"]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--app-id", required=True, help="Store ID, e.g. 9PJ6LRTS2B8X")
    ap.add_argument("--package", required=True, help="path to the .msix")
    ap.add_argument("--commit", action="store_true", help="actually submit (default: dry run)")
    ap.add_argument(
        "--delete-pending",
        action="store_true",
        help="delete an existing pending submission instead of refusing",
    )
    ap.add_argument(
        "--poll-seconds",
        type=int,
        default=180,
        help="how long to watch for an immediate rejection after commit (default: 180)",
    )
    args = ap.parse_args()

    tenant = os.environ.get("STORE_TENANT_ID", "")
    client_id = os.environ.get("STORE_CLIENT_ID", "")
    secret = os.environ.get("STORE_CLIENT_SECRET", "")
    if not (tenant and client_id and secret):
        fail("STORE_TENANT_ID, STORE_CLIENT_ID and STORE_CLIENT_SECRET must all be set.")

    if not os.path.isfile(args.package) or os.path.getsize(args.package) == 0:
        fail(f"{args.package} is missing or empty — refusing to submit nothing.")
    size_mb = os.path.getsize(args.package) / (1024 * 1024)

    token = get_token(tenant, client_id, secret)
    http = requests.Session()
    http.headers.update({"Authorization": f"Bearer {token}", "Content-Type": "application/json"})

    app = check(http.get(f"{API}/applications/{args.app_id}", timeout=60), "get application")
    print(f"app: {app.get('primaryName')} ({args.app_id})")

    pending = app.get("pendingApplicationSubmission")
    if pending:
        pid = pending.get("id")
        if not args.delete_pending:
            # Deleting someone else's in-progress draft is not this script's call
            # to make silently — it could be a listing edit made by hand.
            fail(
                f"submission {pid} is already pending. A pending submission blocks a new one.\n"
                "Finish or delete it in Partner Center, or re-run with --delete-pending."
            )
        print(f"deleting pending submission {pid}")
        r = http.delete(f"{API}/applications/{args.app_id}/submissions/{pid}", timeout=120)
        if not r.ok:
            fail(f"could not delete pending submission [{r.status_code}]\n{r.text}")

    last = app.get("lastPublishedApplicationSubmission", {}).get("id")
    print(f"last published submission: {last}")
    print(f"package: {args.package} ({size_mb:.1f} MB)")

    if not args.commit:
        print("\nDRY RUN — authenticated, app reachable, no submission created.")
        print("Re-run with --commit to submit for certification.")
        return 0

    # ── 3. Create ───────────────────────────────────────────────────────────
    # This clones the last published submission, so listing copy, screenshots,
    # age rating and pricing all carry over untouched. Only the packages change.
    sub = check(
        http.post(f"{API}/applications/{args.app_id}/submissions", timeout=120),
        "create submission",
    )
    sub_id = sub["id"]
    upload_url = sub["fileUploadUrl"]
    print(f"created submission {sub_id}")

    # ── 4. Point it at the new package ──────────────────────────────────────
    # Existing packages must be explicitly retired; leaving them Pending means
    # the old build stays alongside the new one.
    for pkg in sub.get("applicationPackages", []):
        pkg["fileStatus"] = "PendingDelete"
    sub["applicationPackages"].append(
        {"fileName": os.path.basename(args.package), "fileStatus": "PendingUpload"}
    )
    check(
        http.put(f"{API}/applications/{args.app_id}/submissions/{sub_id}", json=sub, timeout=120),
        "update submission",
    )

    # ── 5. Upload ───────────────────────────────────────────────────────────
    # The API takes a ZIP whose entry names match the fileName values above.
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        z.write(args.package, os.path.basename(args.package))
    blob = buf.getvalue()
    print(f"uploading {len(blob) / (1024 * 1024):.1f} MB ...")
    r = requests.put(
        upload_url,
        data=blob,
        headers={"x-ms-blob-type": "BlockBlob"},
        timeout=1800,
    )
    if not r.ok:
        fail(f"package upload failed [{r.status_code}]\n{r.text}")
    print("uploaded")

    # ── 6. Commit ───────────────────────────────────────────────────────────
    check(
        http.post(f"{API}/applications/{args.app_id}/submissions/{sub_id}/commit", timeout=120),
        "commit submission",
    )
    print(f"committed submission {sub_id}")

    # ── 7. Watch briefly ────────────────────────────────────────────────────
    # Certification takes days; this only catches the failures that arrive in
    # seconds, so a broken package does not look like a success in the log.
    deadline = time.time() + args.poll_seconds
    status = "CommitStarted"
    while time.time() < deadline:
        time.sleep(15)
        st = check(
            http.get(
                f"{API}/applications/{args.app_id}/submissions/{sub_id}/status",
                timeout=60,
            ),
            "submission status",
        )
        status = st.get("status", "")
        print(f"  status: {status}")
        details = st.get("statusDetails") or {}
        errors = details.get("errors") or []
        if errors:
            for e in errors:
                print(f"::error::{e.get('code')}: {e.get('details')}", file=sys.stderr)
            fail(f"submission {sub_id} was rejected before certification.")
        for w in details.get("warnings") or []:
            print(f"::warning::{w.get('code')}: {w.get('details')}")
        if status not in {"CommitStarted"}:
            break

    if status not in ACCEPTED:
        fail(f"unexpected status '{status}' — check Partner Center for submission {sub_id}.")

    print(f"\nSubmitted. Status '{status}'. Certification takes days; watch Partner Center.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
