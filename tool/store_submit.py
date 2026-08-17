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
        "--stage",
        action="store_true",
        help="create the submission and upload the package, but stop before commit "
        "so a human can check it in Partner Center and submit from there",
    )
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
        # A pending submission only *blocks* a new one. On a dry run it is
        # something to report, not a reason to fail — refusing there made it
        # impossible to inspect the very submission you were asking about.
        st = http.get(f"{API}/applications/{args.app_id}/submissions/{pid}/status", timeout=60)
        state = st.json().get("status", "unknown") if st.ok else "unknown"
        print(f"a submission is already pending: {pid} (status {state})")
        # --delete-pending on its own (no --commit) is the cleanup path: a failed
        # attempt leaves a draft, and something has to be able to remove it
        # without also starting a new submission.
        if args.delete_pending and not (args.commit or args.stage):
            print(f"deleting pending submission {pid} (status {state})")
            r = http.delete(f"{API}/applications/{args.app_id}/submissions/{pid}", timeout=120)
            if not r.ok:
                fail(f"could not delete pending submission [{r.status_code}]\n{r.text}")
            print("deleted. No new submission created.")
            return 0
        if args.commit or args.stage:
            if not args.delete_pending:
                # Deleting an in-progress submission is not this script's call to
                # make silently: it may be a listing edit made by hand, or — as
                # happened here — a build already in certification.
                fail(
                    f"submission {pid} (status {state}) blocks a new one.\n"
                    "Finish or delete it in Partner Center, or re-run with --delete-pending."
                )
            print(f"deleting pending submission {pid} (status {state})")
            r = http.delete(f"{API}/applications/{args.app_id}/submissions/{pid}", timeout=120)
            if not r.ok:
                fail(f"could not delete pending submission [{r.status_code}]\n{r.text}")

    last = app.get("lastPublishedApplicationSubmission", {}).get("id")
    print(f"last published submission: {last}")
    print(f"package: {args.package} ({size_mb:.1f} MB)")

    if not (args.commit or args.stage):
        # Report the pricing of whatever submission is current. This script has
        # to touch the pricing block (see step 4), and pricing on a paid product
        # is money — so make it inspectable rather than assumed.
        # Print BOTH when both exist. A single reading is uninterpretable — the
        # question is never "what does pricing say" but "does the submission we
        # built still price the same as the one that is live".
        for which, sid in (("last published", last), ("pending", (pending or {}).get("id"))):
            if not sid:
                continue
            st = http.get(f"{API}/applications/{args.app_id}/submissions/{sid}", timeout=60)
            if not st.ok:
                continue
            pricing = st.json().get("pricing", {})
            markets = pricing.get("marketSpecificPricings") or {}
            print(f"\npricing on the {which} submission {sid}:")
            print(f"  priceId                = {pricing.get('priceId')}")
            print(f"  isAdvancedPricingModel = {pricing.get('isAdvancedPricingModel')}")
            print(f"  trialPeriod            = {pricing.get('trialPeriod')}")
            print(f"  marketSpecificPricings = {markets}")
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

    # PRICING — handle with care, this is money.
    #
    # There is exactly one payload this API accepts, and it is not the one you
    # would choose. For a product on the advanced pricing model the API hands
    # back `priceId: "Base"` and then refuses it on the way in ("'Base' is not a
    # valid PriceId for base price"); omitting the whole pricing object is also
    # refused ("Pricing data was not provided in the request"). That leaves
    # sending pricing with `priceId` dropped — after which the field reads back
    # as `Free`.
    #
    # So the write is forced, and safety has to come from verifying the result
    # instead: read the submission back, compare against what is live, and let
    # that decide whether committing is allowed.
    payload = dict(sub)
    pricing_in = dict(payload.get("pricing") or {})
    pricing_in.pop("priceId", None)
    payload["pricing"] = pricing_in
    check(
        http.put(
            f"{API}/applications/{args.app_id}/submissions/{sub_id}", json=payload, timeout=120
        ),
        "update submission",
    )

    live_pricing = {}
    if last:
        r = http.get(f"{API}/applications/{args.app_id}/submissions/{last}", timeout=60)
        if r.ok:
            live_pricing = r.json().get("pricing", {})
    now = check(
        http.get(f"{API}/applications/{args.app_id}/submissions/{sub_id}", timeout=60),
        "read back submission",
    ).get("pricing", {})

    def price_shape(p: dict) -> tuple:
        return (
            p.get("priceId"),
            p.get("isAdvancedPricingModel"),
            p.get("trialPeriod"),
            tuple(sorted((p.get("marketSpecificPricings") or {}).items())),
        )

    mismatch = bool(live_pricing) and price_shape(now) != price_shape(live_pricing)
    if mismatch:
        detail = (
            "pricing on the new submission does not match what is live:\n"
            f"  live: {live_pricing}\n"
            f"  new:  {now}"
        )
        if args.stage:
            # Staging exists precisely to look at this, so report and continue.
            # The draft is editable in Partner Center — pricing can be corrected
            # there before anyone submits it.
            print(f"::warning::{detail}\nCheck Pricing and availability before submitting.")
        else:
            # Refuse BEFORE commit. An uncommitted submission is a draft nobody
            # sees; a committed one is a price change in front of customers.
            fail(f"{detail}\nRefusing to commit. Delete draft {sub_id} and investigate.")
    else:
        print(f"pricing preserved: priceId={now.get('priceId')} (matches the live submission)")

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

    if args.stage:
        print(f"\nSTAGED. Submission {sub_id} holds the new package and is NOT submitted.")
        print("Open it in Partner Center: check 'Pricing and availability', correct it there if")
        print("needed (a draft is editable), then click 'Submit for certification'.")
        return 0

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
