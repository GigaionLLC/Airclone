#!/usr/bin/env python3
"""Submit an MSIX to the Microsoft Store via the Store submission REST API.

Why this exists instead of `msstore publish`: the Microsoft Store Developer CLI
refuses to update a **paid** product —

    App updates are supported only for Free products.

— and Airclone carries the small Store listing price that funds its signing
certificates. That restriction lives in the CLI, not in the Store: the REST API
underneath handles paid products fine. See dev/msstore-ci-setup.md.

The flow the API requires, in order (each step depends on the previous one).
Steps 1-5 are what --stage runs; 6 and 7 belong to --commit alone:

    1. token          client-credentials against the devcenter resource
    2. GET app        read state; refuse if a submission is already pending
    3. POST submission    clones the last published submission
    4. PUT submission     mark old packages PendingDelete, add the new one
    5. PUT the zip        to the SAS URL the submission handed back
    6. POST commit        hands it to certification
    7. GET status         bounded poll, only to catch an immediate rejection

Three modes:

  * default   a dry run. It authenticates and reports the app's real state and
              creates nothing, because a bad submission costs a review cycle
              measured in days.
  * --stage   creates the submission, uploads the package and stops, leaving an
              editable draft for a human to check and send with Partner Center's
              "Submit for certification".
  * --commit  the full automatic submission. Allowed only because the price is
              sent as an explicit tier (BASE_PRICE_TIER) and read back before
              commit. Committing with the price left out is how this app once
              published at $0 (2026-08-17): see the pricing notes at step 4 and
              AGENT.md rule 10. The guard refuses before creating anything when
              the live pricing cannot be read, so a refusal leaves no draft.

Step 3 CLONES the last published submission, so everything but the packages,
the price tier and the English release notes carries over. The notes come from
docs/store/store-release-notes.txt, the same file Google Play and Apple read.

Run from CI (see .github/workflows/submit-msstore.yml) or locally:

    STORE_TENANT_ID=... STORE_CLIENT_ID=... STORE_CLIENT_SECRET=... \\
    python tool/store_submit.py --app-id 9PJ6LRTS2B8X --package airclone.msix --commit
"""

from __future__ import annotations

import argparse
import io
import os
import sys
import time
import zipfile

import requests

# GitHub's Windows runners give Python a cp1252 stdout, so a single character
# outside that codepage kills the process mid-run — which it did, after the
# submission had already been created, leaving a draft behind. Em dashes happen
# to be in cp1252 and survive; an arrow is not and does not. Rather than police
# every string, make the stream itself total.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):  # pragma: no cover - older/odd streams
        pass

RESOURCE = "https://manage.devcenter.microsoft.com"
API = f"{RESOURCE}/v1.0/my"

# Certification takes days, so polling to completion is pointless. These states
# mean the commit was accepted and the package is on its way; anything else this
# soon means it was rejected before a human ever looked at it.
ACCEPTED = {"CommitStarted", "PreProcessing", "CertificationInProgress", "Release", "Published"}

# States where Microsoft is actively working on the submission. Superseding one
# of these is allowed — a newer build must not queue behind an older one — but it
# discards review progress, so it is announced rather than done quietly.
IN_FLIGHT = {"PreProcessing", "Certification", "CertificationInProgress", "Release"}

# THE STORE PRICE, as the API's tier name. This is money: change it only when the
# price itself changes, and check the tier in Partner Center (Pricing and
# availability -> view table) first.
#
# A product on the advanced pricing model reads back `priceId: "Base"`, which the
# API refuses on the way in, and a submission with the priceId dropped reads back
# `Free` and commits at $0. Naming the real tier is the one payload that keeps
# the price (Microsoft's own msstore-cli does the same since its PR #175).
# Advanced-model tiers run Tier1012 ($0.99) up in $0.10 steps to Tier1102 ($9.99),
# so $1.49 is Tier1017.
BASE_PRICE_TIER = "Tier1017"  # $1.49 USD
ADVANCED_TIERS = {f"Tier{n}" for n in range(1012, 1425)}


def fail(msg: str) -> None:
    print(f"::error::{msg}", file=sys.stderr)
    sys.exit(1)


def check(resp: requests.Response, what: str) -> dict:
    if not resp.ok:
        # Print the body verbatim. The Store's errors carry a `code` and
        # `message` that name the actual problem, and summarising loses it.
        fail(f"{what} failed [{resp.status_code}]\n{resp.text}")
    return resp.json() if resp.content else {}


def clear_pending(http: requests.Session, app_id: str, pid: str, state: str) -> None:
    """Remove a pending submission, cancelling certification first if needed.

    A newer release must never be blocked by an older one still in review, so
    "supersede what is in flight" has to be a supported move rather than a trip
    to Partner Center. A draft deletes outright; a submission already in
    certification generally will not, and has to be cancelled first — that is
    what the Cancel certification button in Partner Center does.
    """
    r = http.delete(f"{API}/applications/{app_id}/submissions/{pid}", timeout=120)
    if r.ok:
        return

    print(f"delete refused [{r.status_code}] for status {state}; trying to cancel it first")
    c = http.post(f"{API}/applications/{app_id}/submissions/{pid}/cancel", timeout=120)
    if c.ok:
        r = http.delete(f"{API}/applications/{app_id}/submissions/{pid}", timeout=120)
        if r.ok:
            print("cancelled and deleted")
            return

    fail(
        f"could not clear submission {pid} (status {state}).\n"
        f"  delete: [{r.status_code}] {r.text}\n"
        f"  cancel: [{c.status_code}] {c.text}\n"
        "Cancel it by hand: Partner Center -> the product -> Certification status -> "
        "'Cancel certification', then re-run."
    )


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
    ap.add_argument(
        "--commit",
        action="store_true",
        help="submit for certification. Sends the price as BASE_PRICE_TIER and refuses "
        "unless it reads back exactly (AGENT.md rule 10)",
    )
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
        "--release-notes",
        default="docs/store/store-release-notes.txt",
        help="\"What's new\" text for the English listings (default: %(default)s)",
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
            print(f"clearing pending submission {pid} (status {state})")
            clear_pending(http, args.app_id, pid, state)
            print("cleared. No new submission created.")
            return 0
        if args.commit or args.stage:
            if not args.delete_pending:
                # Clearing an in-progress submission is not this script's call to
                # make silently: it may be a listing edit made by hand, or a
                # build already in certification.
                fail(
                    f"submission {pid} (status {state}) blocks a new one.\n"
                    "Re-run with --delete-pending to supersede it, or finish it in Partner Center."
                )
            if state in IN_FLIGHT:
                # Superseding a release under review is legitimate — a newer
                # build should not wait behind an older one — but say plainly
                # what is being thrown away.
                print(f"::warning::superseding submission {pid}, which is in {state}.")
            print(f"clearing pending submission {pid} (status {state})")
            clear_pending(http, args.app_id, pid, state)

    last = app.get("lastPublishedApplicationSubmission", {}).get("id")
    print(f"last published submission: {last}")
    print(f"package: {args.package} ({size_mb:.1f} MB)")

    live_pricing: dict = {}
    pricing_unknown = "this app has no lastPublishedApplicationSubmission"
    if last:
        _r = http.get(f"{API}/applications/{args.app_id}/submissions/{last}", timeout=60)
        if _r.ok:
            live_pricing = _r.json().get("pricing", {})
            pricing_unknown = ""
        else:
            pricing_unknown = f"GET on submission {last} returned HTTP {_r.status_code}"

    # ── The commit trap — checked BEFORE anything is created ────────────────
    # `commit` applies the submission's pricing block. Proven the hard way on
    # 2026-08-17: v0.6.8 was API-committed with the priceId dropped (the field
    # then reads `Free`), and it published at $0 against a live price of $1.49.
    # A staged PUT alone is harmless - Partner Center re-derives the price when
    # a human submits from there.
    #
    # So a commit must send the real price as an explicit tier (step 4), and the
    # tier constant only means anything on the advanced pricing model, whose
    # tier numbering it uses. Refuse before creating a submission, so a refusal
    # leaves nothing behind.
    #
    # FAIL CLOSED. A 500, a timeout, a throttle, or an app with no
    # lastPublishedApplicationSubmission all leave live_pricing empty; if we
    # cannot read what is live, we cannot prove the model, so refuse.
    if args.commit:
        why = ""
        if not live_pricing:
            why = f"the live pricing could not be read ({pricing_unknown})"
        elif not live_pricing.get("isAdvancedPricingModel"):
            why = (f"the live pricing is not on the advanced model ({live_pricing}), "
                   f"so {BASE_PRICE_TIER} is not a tier it understands")
        elif BASE_PRICE_TIER not in ADVANCED_TIERS:
            why = f"BASE_PRICE_TIER {BASE_PRICE_TIER} is not an advanced-model tier"
        if why:
            fail(
                f"{why}.\nRefusing to commit: a commit with the wrong pricing block "
                "publishes at the wrong price.\nUse mode 'stage' and submit from Partner "
                "Center, or fix BASE_PRICE_TIER. See AGENT.md rule 10."
            )

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
        print(f"--stage uploads it as a draft; --commit submits it at {BASE_PRICE_TIER}.")
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

    # "What's new" is per submission and the clone carries the LAST release's
    # text forward, so set it from the file Play and Apple already read.
    notes = ""
    if os.path.isfile(args.release_notes):
        with open(args.release_notes, encoding="utf-8") as f:
            notes = f.read().strip()
    listings = sub.get("listings") or {}
    if notes:
        for lang, listing in listings.items():
            if lang.lower().startswith("en"):
                listing.setdefault("baseListing", {})["releaseNotes"] = notes
                print(f"release notes for {lang} set from {args.release_notes}")
            else:
                print(f"::warning::listing {lang} keeps its old release notes (the file is English)")
    elif args.commit:
        fail(f"{args.release_notes} is missing or empty - refusing to commit last release's "
             f"notes. Delete draft {sub_id} and add the file.")
    else:
        print(f"::warning::{args.release_notes} is missing or empty; release notes are the "
              "last release's - edit them in Partner Center before submitting.")

    # PRICING — handle with care, this is money.
    #
    # There is exactly one payload this API accepts, and it is not the one you
    # would choose. For a product on the advanced pricing model the API hands
    # back `priceId: "Base"` and then refuses it on the way in ("'Base' is not a
    # valid PriceId for base price"); omitting the whole pricing object is also
    # refused ("Pricing data was not provided in the request"). Dropping just
    # `priceId` is accepted but reads back `Free`, and a COMMIT of that block
    # published the app at $0 (2026-08-17).
    #
    # So name the real price as an explicit tier, then read the submission back
    # and let that decide whether committing is allowed.
    payload = dict(sub)
    pricing_in = dict(payload.get("pricing") or {})
    pricing_in["priceId"] = BASE_PRICE_TIER
    payload["pricing"] = pricing_in
    check(
        http.put(
            f"{API}/applications/{args.app_id}/submissions/{sub_id}", json=payload, timeout=120
        ),
        "update submission",
    )

    # live_pricing was read before the submission was created, so the commit
    # trap could be refused without leaving a draft behind.
    now = check(
        http.get(f"{API}/applications/{args.app_id}/submissions/{sub_id}", timeout=60),
        "read back submission",
    ).get("pricing", {})

    def price_shape(p: dict) -> tuple:
        # EXCLUDES priceId and isAdvancedPricingModel: the live submission reads
        # `Base` / True and ours carries an explicit tier, so those never match
        # and are checked on their own below. Everything else must round-trip.
        return (
            p.get("trialPeriod"),
            tuple(sorted((p.get("marketSpecificPricings") or {}).items())),
            len(p.get("sales") or []),
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
    elif live_pricing:
        print("pricing preserved (markets, trial and sales match the live submission)")
    else:
        # Nothing was compared. Printing "preserved" here claimed a check that
        # had not run, in the same conditions that opened the commit guard.
        print(f"::warning::pricing NOT verified - {pricing_unknown}. Nothing was "
              "compared against a live submission; check Pricing and availability "
              "in Partner Center before submitting.")
    # The price itself. A commit applies this block, so it must hold exactly the
    # tier we sent; anything else (`Free`, a silently remapped tier) is a price
    # change in front of customers.
    print(f"priceId on the new submission: {now.get('priceId')} "
          f"(isAdvancedPricingModel={now.get('isAdvancedPricingModel')}, "
          f"sent {BASE_PRICE_TIER})")
    if now.get("priceId") != BASE_PRICE_TIER:
        detail = f"priceId read back as {now.get('priceId')!r}, not {BASE_PRICE_TIER!r}"
        if args.stage:
            print(f"::warning::{detail}. Check Pricing and availability before submitting.")
        else:
            fail(f"{detail}.\nRefusing to commit. Delete draft {sub_id} and investigate.")

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
    warned: set[str] = set()
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
            # The same warnings come back on every poll (SalesUnsupportedWarning
            # on every commit since sales left the API); print each once.
            if w.get("code") not in warned:
                warned.add(w.get("code"))
                print(f"::warning::{w.get('code')}: {w.get('details')}")
        if status not in {"CommitStarted"}:
            break

    if status not in ACCEPTED:
        fail(f"unexpected status '{status}' — check Partner Center for submission {sub_id}.")

    print(f"\nSubmitted. Status '{status}'. Certification takes days; watch Partner Center.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
