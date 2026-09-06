#!/usr/bin/env python3
"""Attach an uploaded build to an App Store version, and set the review notes.

The steps between "a build finished uploading" and "the version goes to
review". All plain App Store Connect API calls, and all the kind of retyping that
lets the console drift from the doc that justifies it - the review notes in
particular carry a constraint that already cost this project review cycles
elsewhere (never point a reviewer at the command console), so this reads them
from the listing document and refuses if they mention it.

It can also SUBMIT (--submit-for-review) and answer export compliance
(--export-compliance), both only under --apply and both described below. Neither
is the day-to-day path: submission goes through asc-submit-review.yml, which
requires a human to name the exact version first, and export compliance is already
answered declaratively by ITSAppUsesNonExemptEncryption=false in both Info.plist
files. The gate that stays human is pressing release - --create-version and
--manual-release both set releaseType MANUAL, so an approved version waits.

Usage:
  python tool/asc_build.py <key.p8> <keyid> <issuerid> <appid> [options]

Options:
  --platform MAC_OS|IOS   which version to work on (default MAC_OS)
  --version 0.6.8         select by version string (default: newest editable)
  --build 117             build number to attach (default: newest VALID)
  --notes                 set the App Review notes from the listing document
  --set-version 0.6.8     rewrite the version string. The iOS record was created
                          with a placeholder 1.0, and Apple requires the
                          submitted version and the build's
                          CFBundleShortVersionString to agree.
  --no-attach             skip attaching a build, for a platform whose build does
                          not exist yet
  --copyright             set the copyright from the listing document
  --manual-release        set the release type to MANUAL, so an approved version
                          waits for a human instead of publishing itself
  --audit                 report EVERYTHING Apple needs before submission and
                          write nothing. The point is to find a missing field
                          from one command rather than from a rejection.
  --apply                 actually send it. Without this nothing is written.
  --builds                just list the builds Apple has registered, and stop.
  --create-version X.Y.Z  create the version record itself (releaseType MANUAL).
  --submit-for-review     add the version to review. Refuses on any audit gap.
                          Needs --apply. This is the point of no return, and
                          asc-submit-review.yml is its only caller.
  --create-encryption-declaration --france yes|no
                          create the App Encryption Declaration that an
                          export-compliance answer of YES requires.
  --export-compliance yes|no
                          answer the US export-control question on a build
                          directly. NOT the normal path: the shipped answer is
                          the declarative ITSAppUsesNonExemptEncryption=false in
                          app/ios|macos/Runner/Info.plist, valid only while
                          France is excluded (the audit's "french store" row
                          guards it). Use this flag only if that key is removed
                          or France is added, and then the answer becomes YES
                          (mass-market 5D992), which needs
                          --create-encryption-declaration first.
                          Needs --apply, like everything else that writes.
                          Works with no editable version, which is exactly when
                          you need it: right after an upload.

Everything printed is ASCII: GitHub's Windows runners give Python a cp1252
stdout and a stray arrow aborts the process mid-run (AGENT.md rule 12).
"""
import base64
import io
import json
import os
import sys
import time
import urllib.error
import urllib.request

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils as au

for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass

if len(sys.argv) < 5:
    print(__doc__)
    sys.exit(2)

KEY, KID, ISS, APP = sys.argv[1:5]
ARGV = sys.argv[5:]
APPLY = "--apply" in ARGV
SET_NOTES = "--notes" in ARGV
ATTACH = "--no-attach" not in ARGV
AUDIT = "--audit" in ARGV
# List the builds Apple has registered, WITHOUT needing an editable version.
# main() otherwise calls pick_version() first, which exits when the only
# versions are in review or live - so right after an upload, when "did it
# actually register?" is the one question worth asking, there was no way to
# ask it. That is not academic: builds 117 and 118 were both accepted at
# upload and then died silently without ever registering, and "UPLOAD
# SUCCEEDED" looked identical both times.
BUILDS = "--builds" in ARGV
# Create the version record itself. Apple allows exactly ONE editable version
# per platform, so this refuses when one already exists rather than making a
# mess that has to be deleted by hand.
CREATE_VERSION = (ARGV[ARGV.index("--create-version") + 1]
                  if "--create-version" in ARGV else None)
SET_COPYRIGHT = "--copyright" in ARGV
MANUAL_RELEASE = "--manual-release" in ARGV
# Add the version to review - the same act as pressing "Add for Review" in the
# console. Gated on the audit and on --apply, and reached only through
# asc-submit-review.yml, which requires the operator to name the exact version;
# that string is passed here as --version, so the notes it refreshes and the
# version it submits cannot be different ones.
SUBMIT_FOR_REVIEW = "--submit-for-review" in ARGV
# Create the App Encryption Declaration - the resource that makes an export
# compliance answer of YES possible at all. Without one, PATCHing
# usesNonExemptEncryption=true is accepted, echoed back, and stored as nothing.
#
# Four of its five required fields are settled by the analysis in
# dev/plans/apple-appstore-plan.md and are hard-coded below. The fifth,
# availableOnFrenchStore, is a commercial decision with a legal tail (yes means
# Apple requires an ANSSI declaration, uploaded and approved before shipping) and
# so has to be passed in explicitly. It is never defaulted.
CREATE_DECLARATION = "--create-encryption-declaration" in ARGV
FRANCE = (ARGV[ARGV.index("--france") + 1] if "--france" in ARGV else None)
# The US export-control declaration, carried on the BUILD rather than the
# version - and NOT how this app answers it. The shipped answer is the
# declarative ITSAppUsesNonExemptEncryption=false in both Info.plist files, so
# Apple never asks per build. Apple itself drew that line: it refuses to create
# an App Encryption Declaration unless the app uses proprietary cryptography, or
# third-party cryptography AND is sold in France. Airclone is neither, which is
# Apple saying the use is exempt. It holds only while France stays excluded - the
# audit's "french store" row watches exactly that. If the plist key is ever
# removed, or France is added, the answer becomes YES (mass-market 5D992) and
# needs an App Encryption Declaration to attach to first.
# Kept an explicit flag, never implied by --apply: it is a legal statement
# and it should be visible in the command that makes it.
EXPORT_COMPLIANCE = (ARGV[ARGV.index("--export-compliance") + 1]
                     if "--export-compliance" in ARGV else None)


def opt(name, default=None):
    return ARGV[ARGV.index(name) + 1] if name in ARGV else default


PLATFORM = opt("--platform", "MAC_OS")
WANT_VERSION = opt("--version")
WANT_BUILD = opt("--build")
SET_VERSION = opt("--set-version")
DOC = ("docs/store/apple/listing-ios-en-US.md" if PLATFORM == "IOS"
       else "docs/store/apple/listing-en-US.md")

# States a version can still be edited in. Anything else means it is in review or
# already shipped, and writing to it is either refused by Apple or a mistake.
EDITABLE = {
    "PREPARE_FOR_SUBMISSION",
    "DEVELOPER_REJECTED",
    "REJECTED",
    "METADATA_REJECTED",
    "INVALID_BINARY",
}

# Editable, but only because something went WRONG. Apple or a reviewer pushed
# back and the reason lives in Resolution Center, which the App Store Connect
# API does not expose - so the most this tool can do is refuse to call it fine.
# DEVELOPER_REJECTED is absent on purpose: that one is you withdrawing your own
# submission, which is a normal thing to do.
NEEDS_ATTENTION = {
    "REJECTED",
    "METADATA_REJECTED",
    "INVALID_BINARY",
}


def token():
    def b64u(b):
        return base64.urlsafe_b64encode(b).rstrip(b"=")

    pk = serialization.load_pem_private_key(open(KEY, "rb").read(), password=None)
    now = int(time.time())
    si = (
        b64u(json.dumps({"alg": "ES256", "kid": KID, "typ": "JWT"}).encode())
        + b"."
        + b64u(
            json.dumps(
                {"iss": ISS, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}
            ).encode()
        )
    )
    r, s = au.decode_dss_signature(pk.sign(si, ec.ECDSA(hashes.SHA256())))
    return (si + b"." + b64u(r.to_bytes(32, "big") + s.to_bytes(32, "big"))).decode()


TOK = token()


def call(method, path, body=None):
    req = urllib.request.Request(
        "https://api.appstoreconnect.apple.com" + path,
        data=json.dumps(body).encode() if body else None,
        headers={"Authorization": "Bearer " + TOK, "Content-Type": "application/json"},
        method=method,
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.load(r) if r.status != 204 else {}
    except urllib.error.HTTPError as e:
        print("  HTTP %s on %s" % (e.code, path))
        try:
            for x in json.load(e).get("errors", []):
                print("   ", x.get("title"), "|", x.get("detail"))
        except Exception:
            print("   ", e.read()[:300])
        return None


def fenced(doc, header):
    """The first fenced block after `header`."""
    i = doc.index(header)
    j = doc.index("```", i) + 3
    return doc[j:doc.index("```", j)].strip("\n")


def pick_version():
    vs = call("GET", "/v1/apps/%s/appStoreVersions?limit=200" % APP)
    if not vs:
        sys.exit(1)
    cand = [v for v in vs["data"] if v["attributes"]["platform"] == PLATFORM]
    if WANT_VERSION:
        cand = [v for v in cand if v["attributes"]["versionString"] == WANT_VERSION]
    if not cand:
        sys.exit("no %s version found" % PLATFORM)
    editable = [v for v in cand if v["attributes"]["appStoreState"] in EDITABLE]
    if not editable:
        for v in cand:
            print("  %s is %s" % (v["attributes"]["versionString"],
                                  v["attributes"]["appStoreState"]))
        sys.exit("no editable %s version - refusing to touch one in review" % PLATFORM)
    return editable[0]


def pick_build():
    # A build is only attachable once processingState is VALID. PROCESSING means
    # Apple is still working on it and the attach fails with a confusing 409.
    # include=preReleaseVersion because a build's PLATFORM lives there, not on
    # the build itself - and macOS and iOS builds of the same release share a
    # build NUMBER, so the number alone cannot tell them apart.
    # fields[builds] is REQUIRED for usesNonExemptEncryption: the list endpoint
    # omits it from its default attribute set, so a build that HAS been answered
    # reads back as unanswered and the listing quietly lies about the one thing
    # it is most useful for.
    bs = call("GET", "/v1/builds?filter[app]=%s&limit=50&sort=-uploadedDate"
                     "&include=preReleaseVersion"
                     "&fields[builds]=version,processingState,expired,"
                     "uploadedDate,usesNonExemptEncryption,preReleaseVersion"
                     % APP)
    if not bs:
        sys.exit(1)
    plat_of = {}
    for inc in bs.get("included", []):
        if inc.get("type") == "preReleaseVersions":
            plat_of[inc["id"]] = inc["attributes"].get("platform")
    # Distinguish "Apple has not registered it yet" from "the filter is wrong".
    # An empty list here after a successful upload is normal for a while: a build
    # takes minutes to appear and longer to finish PROCESSING.
    print("builds visible to this key: %d" % len(bs["data"]))
    if not bs["data"]:
        pre = call("GET", "/v1/apps/%s/preReleaseVersions?limit=10" % APP)
        n = len((pre or {}).get("data", []))
        print("pre-release versions on the app: %d" % n)
        for v in (pre or {}).get("data", []):
            a = v["attributes"]
            print("  %s (%s)" % (a.get("version"), a.get("platform")))
        # Unfiltered, to tell "Apple has not created the build record yet" apart
        # from "this key cannot see builds at all". Same question the app-scoped
        # query asks, minus the filter that could be the thing that is wrong.
        allb = call("GET", "/v1/builds?limit=10")
        print("builds across the whole team: %d"
              % len((allb or {}).get("data", [])))
        for b in (allb or {}).get("data", [])[:5]:
            a = b["attributes"]
            print("  build %s  %s  %s"
                  % (a.get("version"), a.get("processingState"),
                     (a.get("uploadedDate") or "")[:19]))
    rows = []
    for b in bs["data"]:
        a = b["attributes"]
        rel = ((b.get("relationships") or {}).get("preReleaseVersion") or {})
        pv = (rel.get("data") or {}).get("id")
        rows.append((b["id"], a.get("version"), a.get("processingState"),
                     a.get("expired"), (a.get("uploadedDate") or "")[:19],
                     plat_of.get(pv, "?"), a.get("usesNonExemptEncryption")))
    # Export compliance "yes" is NOT a boolean write - it needs an App Encryption
    # Declaration to point at. List them, because without one a PATCH setting
    # usesNonExemptEncryption=true is accepted, echoed back as true, and stored
    # as nothing.
    decls = call("GET", "/v1/appEncryptionDeclarations?filter[app]=%s&limit=20" % APP)
    dd = (decls or {}).get("data", [])
    print("app encryption declarations: %d" % len(dd))
    for d in dd:
        a = d["attributes"]
        print("  %s  state=%s  exempt=%s  france=%s  code=%s"
              % (d["id"][:12], a.get("appEncryptionDeclarationState"),
                 a.get("exempt"), a.get("availableOnFrenchStore"),
                 a.get("codeValue") or "-"))
    print("recent builds:")
    for r in rows[:8]:
        # usesNonExemptEncryption is the EXPORT COMPLIANCE answer, carried on the
        # build. None means Apple has not been told yet and will ask before the
        # build can be submitted. Printed because "what did we answer last time"
        # is otherwise only discoverable by clicking through App Store Connect.
        enc = {True: "yes", False: "no", None: "UNANSWERED"}.get(r[6], str(r[6]))
        print("  build %-6s %-9s %-12s expired=%-5s %s  export=%s"
              % (r[1], r[5], r[2], r[3], r[4], enc))
    # Platform matters: attaching an iOS build to a macOS version is rejected,
    # and both platforms of one release carry the same build number.
    usable = [r for r in rows
              if r[2] == "VALID" and not r[3] and r[5] in (PLATFORM, "?")]
    if WANT_BUILD:
        usable = [r for r in usable if r[1] == WANT_BUILD]
    if not usable:
        print()
        print("no VALID unexpired build to attach yet.")
        print("PROCESSING means Apple is still working - wait and re-run.")
        # In report mode this is information, not a failure: the whole point of
        # running it is to find out. Only --apply, which was asked to attach
        # something, has nothing to do and should say so loudly.
        if not APPLY:
            return None
        sys.exit(1)
    return usable[0]


def audit(ver):
    """Everything Apple checks at submission, in one place.

    Written because "is it ready?" was six console pages, and a missing field
    surfaces as a rejected submission rather than as a warning.
    """
    vid = ver["id"]
    va = ver["attributes"]
    rows = []

    def row(name, ok, detail=""):
        rows.append((name, ok, detail))

    # EDITABLE answers "can this version be worked on", and a REJECTED version
    # very much can - you fix it and resubmit. But an AUDIT asks "is this ready
    # to submit", and reporting REJECTED as OK is how a rejection reads like a
    # clean bill of health. It printed exactly that for iOS 0.6.8: "version
    # state  OK  REJECTED", directly above "No gaps."
    state = va["appStoreState"]
    row(
        "version state",
        state not in NEEDS_ATTENTION,
        state + (" <- a reviewer pushed back; read Resolution Center"
                 if state in NEEDS_ATTENTION else ""),
    )
    # Copyright and the release type live on the VERSION, not the localization,
    # which is why an audit built around localization fields missed both. The
    # copyright was empty on a version that otherwise reported no gaps, and the
    # release type was still AFTER_APPROVAL - the setting that makes approval and
    # publication the same event.
    row("copyright", bool(va.get("copyright")), va.get("copyright") or "EMPTY")
    rel = va.get("releaseType") or "?"
    row("release type", rel == "MANUAL",
        rel + (" - approval and publication are the SAME event"
               if rel != "MANUAL" else ""))
    b = call("GET", "/v1/appStoreVersions/%s/build" % vid)
    row("build attached", bool((b or {}).get("data")),
        (b or {}).get("data", {}).get("id", "none") if (b or {}).get("data") else "none")

    locs = call("GET", "/v1/appStoreVersions/%s/appStoreVersionLocalizations" % vid)
    loc = next((l for l in (locs or {}).get("data", [])
                if l["attributes"]["locale"] == "en-US"), None)
    if loc:
        a = loc["attributes"]
        # whatsNew is REQUIRED on an update and was missing from this list, so
        # the audit reported "no gaps" on a version App Store Connect refused
        # with "English (U.S.) - What's New in This Version - This field is
        # required". An audit that misses a blocker is worse than no audit: it
        # is a green light for a wall. It is per-VERSION, not per-listing, so
        # renaming a version does not carry it over.
        for f in ("description", "keywords", "promotionalText", "supportUrl",
                  "whatsNew"):
            v = a.get(f) or ""
            row(f, bool(v), "%d chars" % len(v) if v else "EMPTY")
        sets = call("GET",
                    "/v1/appStoreVersionLocalizations/%s/appScreenshotSets" % loc["id"])
        found = []
        for st in (sets or {}).get("data", []):
            dt = st["attributes"]["screenshotDisplayType"]
            shots = call("GET", "/v1/appScreenshotSets/%s/appScreenshots" % st["id"])
            n = len((shots or {}).get("data", []))
            done = sum(1 for x in (shots or {}).get("data", [])
                       if (x["attributes"].get("assetDeliveryState") or {})
                       .get("state") == "COMPLETE")
            found.append("%s %d/%d complete" % (dt, done, n))
        row("screenshot sets", bool(found), "; ".join(found) or "NONE")
    else:
        row("en-US localization", False, "missing")

    det = call("GET", "/v1/appStoreVersions/%s/appStoreReviewDetail" % vid)
    da = ((det or {}).get("data") or {}).get("attributes", {})
    row("review notes", bool(da.get("notes")),
        "%d chars" % len(da.get("notes") or "") if da.get("notes") else "EMPTY")
    row("review contact", all(da.get(k) for k in
                              ("contactFirstName", "contactLastName",
                               "contactEmail", "contactPhone")),
        "present" if da.get("contactEmail") else "MISSING")
    row("sign-in required", da.get("demoAccountRequired") is False,
        str(da.get("demoAccountRequired")))

    infos = call("GET", "/v1/apps/%s/appInfos" % APP) or {"data": []}
    purl = ""
    for info in infos["data"]:
        il = call("GET", "/v1/appInfos/%s/appInfoLocalizations" % info["id"])
        e = next((l for l in (il or {}).get("data", [])
                  if l["attributes"]["locale"] == "en-US"), None)
        if e and e["attributes"].get("privacyPolicyUrl"):
            purl = e["attributes"]["privacyPolicyUrl"]
    row("privacy policy URL", bool(purl), purl or "EMPTY")

    # Export compliance is answered declaratively by ITSAppUsesNonExemptEncryption
    # in Info.plist, and that answer is only correct while France stays excluded:
    # Apple refuses to create an App Encryption Declaration unless the app uses
    # proprietary cryptography, or third-party cryptography AND is sold in France.
    # Adding France therefore turns the shipped key into a FALSE declaration, and
    # nothing about the build would change to say so. Check it here, where
    # somebody is already asking whether this version can ship.
    fr_available = None
    av = call("GET", "/v1/apps/%s/appAvailabilityV2" % APP)
    if (av or {}).get("data"):
        terr = call("GET", "/v2/appAvailabilities/%s/territoryAvailabilities"
                           "?limit=200&include=territory" % av["data"]["id"])
        for t in (terr or {}).get("data", []):
            tid = ((t.get("relationships") or {}).get("territory") or {})
            if (tid.get("data") or {}).get("id") == "FRA":
                fr_available = bool(t["attributes"].get("available"))
    if fr_available is None:
        rows.append(("french store", True, "could not read - check by hand"))
    else:
        rows.append((
            "french store", not fr_available,
            "excluded, so the exempt export answer holds" if not fr_available
            else "AVAILABLE - ITSAppUsesNonExemptEncryption=false is now a FALSE "
                 "declaration, see dev/plans/apple-appstore-plan.md"))

    print()
    print("== submission audit: %s %s ==" % (PLATFORM, va["versionString"]))
    bad = 0
    for name, ok, detail in rows:
        if not ok:
            bad += 1
        print("  %-20s %-4s %s" % (name, "OK" if ok else "GAP", detail))
    print()
    if bad:
        print("%d gap(s). Apple will refuse the submission until they are closed."
              % bad)
    else:
        print("No gaps. Export compliance is answered in Info.plist. What")
        print("remains is human: Add for")
        print("Review, and 'Manually release this version'.")
    return bad
    return bad


def submit_for_review():
    """Add the editable version to review - the point of no return.

    Gated on the audit rather than on the caller's confidence. Everything the
    audit checks is something Apple refuses a submission for, so submitting with
    a known gap only converts a fixable problem into a rejection and a lost
    review cycle. It has caught an empty copyright and a releaseType silently set
    to AFTER_APPROVAL before.
    """
    ver = pick_version()
    va = ver["attributes"]
    print("%s version %s  state=%s"
          % (PLATFORM, va["versionString"], va["appStoreState"]))
    if va["appStoreState"] in NEEDS_ATTENTION:
        print("This version is editable only because something went WRONG "
              "(%s)." % va["appStoreState"])
        print("The reason lives in Resolution Center, which the API cannot read.")
        sys.exit(1)

    gaps = audit(ver)
    if gaps:
        print()
        print("REFUSING to submit with %d open gap(s)." % gaps)
        sys.exit(1)

    # Reuse an in-flight submission for this platform rather than making a
    # second one; Apple treats them as a queue and two is confusing at best.
    subs = call("GET", "/v1/reviewSubmissions?filter[app]=%s&limit=50" % APP)
    live = [x for x in (subs or {}).get("data", [])
            if x["attributes"].get("platform") == PLATFORM
            and x["attributes"].get("state") not in ("COMPLETE", "CANCELING")]
    print()
    if not APPLY:
        print("dry run - nothing submitted. Pass --apply to send it to Apple.")
        return

    if live:
        sub_id = live[0]["id"]
        print("reusing review submission %s (state=%s)"
              % (sub_id, live[0]["attributes"].get("state")))
    else:
        r = call("POST", "/v1/reviewSubmissions", {
            "data": {
                "type": "reviewSubmissions",
                "attributes": {"platform": PLATFORM},
                "relationships": {"app": {"data": {"type": "apps", "id": APP}}},
            },
        })
        if not r:
            sys.exit(1)
        sub_id = r["data"]["id"]
        print("created review submission %s" % sub_id)

    r = call("POST", "/v1/reviewSubmissionItems", {
        "data": {
            "type": "reviewSubmissionItems",
            "relationships": {
                "reviewSubmission": {
                    "data": {"type": "reviewSubmissions", "id": sub_id}},
                "appStoreVersion": {
                    "data": {"type": "appStoreVersions", "id": ver["id"]}},
            },
        },
    })
    if not r:
        sys.exit(1)
    print("added version %s to the submission" % va["versionString"])

    r = call("PATCH", "/v1/reviewSubmissions/%s" % sub_id,
             {"data": {"id": sub_id, "type": "reviewSubmissions",
                       "attributes": {"submitted": True}}})
    if not r:
        sys.exit(1)
    # Read it back: a submitted flag that did not take is the difference between
    # "in review" and "sitting there while you think it is".
    back = call("GET", "/v1/reviewSubmissions/%s" % sub_id)
    a = ((back or {}).get("data") or {}).get("attributes", {})
    print()
    print("state=%s  submittedDate=%s"
          % (a.get("state"), a.get("submittedDate") or "NOT SUBMITTED"))
    if not a.get("submittedDate"):
        print("::error::Apple did not record a submittedDate - not submitted.")
        sys.exit(1)
    print("SUBMITTED. Releasing is still manual (releaseType MANUAL).")


def create_encryption_declaration():
    """POST an App Encryption Declaration. NOT the shipped answer - see below.

    This path exists but is not the one Airclone uses. The shipped answer is
    declarative: ITSAppUsesNonExemptEncryption=false in both Info.plists, valid
    only while France stays excluded from availability. `--audit` checks that
    precondition as its "french store" row.

    The reasoning that got here, kept because it is the part that is easy to get
    wrong twice: the app does implement standard confidentiality encryption of
    its own, so the "HTTPS only" and "only Apple's OS crypto" exemptions do not
    apply. But Apple refuses to create a declaration for an app in this position
    at all - a declaration is for proprietary crypto, or for third-party crypto
    sold in France - so YES is unrecordable rather than merely unrecorded, and
    the exemption is the accurate answer, not a convenient one. If France is
    ever added, this changes and the US BIS 5D992 self-classification (a
    separate, already-live obligation) is not a substitute for it.

    dev/plans/apple-appstore-plan.md owns this decision; state it in one clause
    elsewhere and link there rather than re-arguing it.
    """
    if FRANCE not in ("yes", "no"):
        sys.exit("--france yes|no is required and is never defaulted: YES makes "
                 "Apple require an ANSSI declaration approved before shipping.")
    france = FRANCE == "yes"

    existing = call("GET",
                    "/v1/appEncryptionDeclarations?filter[app]=%s&limit=20" % APP)
    for d in (existing or {}).get("data", []):
        a = d["attributes"]
        print("declaration %s already exists, state=%s"
              % (d["id"], a.get("appEncryptionDeclarationState")))
        return

    attrs = {
        # Every algorithm Airclone uses is a published standard - rclone's crypt
        # backend, the config encryption, the notes vault, Argon2id for the
        # offline QR - so nothing here is proprietary.
        "containsProprietaryCryptography": False,
        # TRUE: the engine is statically linked Go and brings its own TLS and
        # ciphers rather than calling Apple's Security framework.
        "containsThirdPartyCryptography": True,
        "availableOnFrenchStore": france,
        # Apple caps this at 300 characters.
        "appDescription":
            "Standard, published cryptography for data confidentiality: TLS "
            "from the statically linked rclone engine rather than the OS, "
            "rclone's crypt backend for encrypted remotes (NaCl secretbox / "
            "AES), passphrase encryption of the user's own config file, and "
            "Argon2id key derivation. No proprietary algorithms.",
    }
    # Apple REFUSES to create a declaration unless proprietary cryptography is
    # involved, or third-party cryptography AND French availability both are:
    #
    #   Cannot create appEncryptionDeclarations unless either
    #   containsProprietaryCryptography is True or containsThirdPartyCryptography
    #   and availableOnFrenchStore are both True
    #
    # So for an app using only standard algorithms and NOT sold in France, there
    # is no declaration to make - which is Apple saying the use is exempt. The
    # export answer for that app is usesNonExemptEncryption=false, and that IS a
    # plain boolean this tool can set. Say so instead of forwarding a 409.
    if not attrs["containsProprietaryCryptography"] and not france:
        print()
        print("Apple will refuse this: a declaration exists for proprietary")
        print("cryptography, or for third-party cryptography sold in France.")
        print("Neither applies here, which means the encryption is EXEMPT and")
        print("there is nothing to declare. Use:")
        print("  --export-compliance no")
        print("See dev/plans/apple-appstore-plan.md.")
        sys.exit(1)
    print("app encryption declaration to create:")
    for k, v in attrs.items():
        print("  %-32s %s" % (k, v if not isinstance(v, str) else v[:60] + "..."))
    if not france:
        print()
        print("  availableOnFrenchStore=false. Verified consistent: the app's")
        print("  territory availability already excludes France.")
    if not APPLY:
        print()
        print("dry run - nothing sent. Pass --apply to write.")
        return
    r = call("POST", "/v1/appEncryptionDeclarations", {
        "data": {
            "type": "appEncryptionDeclarations",
            "attributes": attrs,
            "relationships": {"app": {"data": {"type": "apps", "id": APP}}},
        },
    })
    if not r:
        sys.exit(1)
    a = r["data"]["attributes"]
    print()
    print("created declaration %s  state=%s"
          % (r["data"]["id"], a.get("appEncryptionDeclarationState")))


def create_version(version_string):
    """POST a new appStoreVersion. There was no way to do this before.

    Every other mode starts at pick_version(), which finds an EDITABLE version or
    exits - so the moment the only versions were live or in review, the whole tool
    was blocked behind a human clicking "+ Version or Platform" in App Store
    Connect. The API has always allowed this; the tool simply never asked.

    releaseType is set to MANUAL at creation rather than patched afterwards.
    AFTER_APPROVAL makes approval and publication the same event, and it was found
    silently set that way once, AFTER an audit had twice reported no gaps.
    """
    vs = call("GET", "/v1/apps/%s/appStoreVersions?limit=200" % APP)
    if vs is None:
        sys.exit(1)
    mine = [v for v in vs["data"] if v["attributes"]["platform"] == PLATFORM]
    for v in mine:
        a = v["attributes"]
        if a["versionString"] == version_string:
            print("%s version %s already exists, state=%s - nothing to do"
                  % (PLATFORM, version_string, a["appStoreState"]))
            return
    editable = [v for v in mine if v["attributes"]["appStoreState"] in EDITABLE]
    if editable:
        # Apple permits one editable version per platform. Creating a second is
        # rejected, and asking for it usually means the intent was to RENAME the
        # one already sitting there.
        a = editable[0]["attributes"]
        print("%s already has an editable version %s (%s)."
              % (PLATFORM, a["versionString"], a["appStoreState"]))
        print("Apple allows only one. Rename it instead:")
        print("  --set-version %s" % version_string)
        sys.exit(1)

    print("%s: would create version %s, releaseType MANUAL" % (PLATFORM, version_string))
    if not APPLY:
        print()
        print("dry run - nothing sent. Pass --apply to write.")
        return
    r = call("POST", "/v1/appStoreVersions", {
        "data": {
            "type": "appStoreVersions",
            "attributes": {
                "platform": PLATFORM,
                "versionString": version_string,
                "releaseType": "MANUAL",
            },
            "relationships": {
                "app": {"data": {"type": "apps", "id": APP}},
            },
        },
    })
    if not r:
        sys.exit(1)
    a = r["data"]["attributes"]
    print("created %s version %s  state=%s  releaseType=%s"
          % (PLATFORM, a["versionString"], a["appStoreState"], a.get("releaseType")))
    print()
    print("Next: attach the build and set the notes, then audit:")
    print("  mode=apply   (attaches the newest VALID build)")
    print("  mode=audit   (what Apple will still refuse)")


def main():
    if SUBMIT_FOR_REVIEW:
        submit_for_review()
        return
    if CREATE_DECLARATION:
        create_encryption_declaration()
        return
    if CREATE_VERSION:
        create_version(CREATE_VERSION)
        return
    if BUILDS:
        # Deliberately before pick_version(): the whole point is to work when no
        # editable version exists yet. pick_build() already prints the listing
        # and, outside --apply, returns quietly when nothing is attachable.
        pick_build()
        return
    ver = pick_version()
    va = ver["attributes"]
    print("%s version %s  state=%s"
          % (PLATFORM, va["versionString"], va["appStoreState"]))

    if AUDIT:
        audit(ver)
        return

    cur = call("GET", "/v1/appStoreVersions/%s/build" % ver["id"])
    attached = (cur or {}).get("data")
    print("  build attached: %s" % (attached["id"] if attached else "-- NONE --"))

    rename = bool(SET_VERSION and SET_VERSION != va["versionString"])
    if rename:
        print("  version string: %s to %s" % (va["versionString"], SET_VERSION))

    bid = bnum = when = None
    if ATTACH:
        got = pick_build()
        if got:
            bid, bnum, _, _, when, _bplat, _benc = got
            print("  will attach:    build %s (uploaded %s)" % (bnum, when))

    notes = None
    if SET_NOTES:
        doc = io.open(DOC, encoding="utf-8").read()
        notes = fenced(doc, "Notes (4,000 max):")
        if "console" in notes.lower():
            sys.exit("refusing: the review notes mention the console. "
                     "That cost Microsoft review cycles - see " + DOC)
        print("  review notes:   %d chars from %s" % (len(notes), DOC))
        print("                  demoAccountRequired = false")

    # Both of these live on the VERSION rather than the localization, which is
    # how an audit built around localization fields missed them.
    attrs = {}
    if SET_COPYRIGHT:
        doc = io.open(DOC, encoding="utf-8").read()
        attrs["copyright"] = fenced(doc, "## Copyright")
        print("  copyright:      %s" % attrs["copyright"])
    if MANUAL_RELEASE and va.get("releaseType") != "MANUAL":
        attrs["releaseType"] = "MANUAL"
        print("  release type:   %s -> MANUAL" % va.get("releaseType"))

    if not APPLY:
        print()
        print("dry run - nothing sent. Pass --apply to write.")
        return

    if attrs:
        r = call("PATCH", "/v1/appStoreVersions/%s" % ver["id"],
                 {"data": {"id": ver["id"], "type": "appStoreVersions",
                           "attributes": attrs}})
        if r is None:
            sys.exit(1)
        got = r["data"]["attributes"]
        for k in attrs:
            print("set %s = %s" % (k, got.get(k)))

    if rename:
        r = call("PATCH", "/v1/appStoreVersions/%s" % ver["id"],
                 {"data": {"id": ver["id"], "type": "appStoreVersions",
                           "attributes": {"versionString": SET_VERSION}}})
        if r is None:
            sys.exit(1)
        print()
        print("version string set to %s" % SET_VERSION)

    if not ATTACH or bid is None:
        print("--no-attach: left the build relationship alone"
              if not ATTACH else "no build to attach; left the relationship alone")
    elif attached and attached["id"] == bid:
        print("already attached; nothing to do")
    else:
        r = call("PATCH", "/v1/appStoreVersions/%s/relationships/build" % ver["id"],
                 {"data": {"type": "builds", "id": bid}})
        if r is None:
            sys.exit(1)
        print("attached build %s" % bnum)

    if EXPORT_COMPLIANCE:
        # On the build, not the version, so it survives being re-attached and has
        # to be set once per uploaded build.
        target = bid or (attached or {}).get("id")
        if not target:
            print("export compliance: no build to set it on")
        else:
            want = EXPORT_COMPLIANCE.lower() in ("yes", "true", "1")
            r = call("PATCH", "/v1/builds/%s" % target,
                     {"data": {"id": target, "type": "builds",
                               "attributes": {"usesNonExemptEncryption": want}}})
            if r is None:
                sys.exit(1)
            # READ IT BACK. Apple accepts this PATCH, echoes the value in the
            # response, and stores NOTHING when the answer is `true` and the app
            # has no App Encryption Declaration to attach it to. The echo is not
            # the artifact - that mistake was made here first, on build 122, and
            # would otherwise have shipped as "export compliance: True".
            back = call("GET", "/v1/builds/%s?fields[builds]=usesNonExemptEncryption"
                        % target)
            stored = ((back or {}).get("data", {})
                      .get("attributes", {}).get("usesNonExemptEncryption"))
            if stored != want:
                print("::error::export compliance did NOT stick: asked for %s, "
                      "Apple still reports %s" % (want, stored))
                if want:
                    decls = call(
                        "GET",
                        "/v1/appEncryptionDeclarations?filter[app]=%s&limit=1" % APP)
                    if not (decls or {}).get("data"):
                        print("The app has NO App Encryption Declaration. Answering")
                        print("YES needs one - it carries the documentation, the")
                        print("France/ANSSI answer and the compliance code, and Apple")
                        print("reviews it. Answering NO is a plain boolean and needs")
                        print("nothing. See dev/plans/apple-appstore-plan.md.")
                sys.exit(1)
            print("export compliance: usesNonExemptEncryption = %s (read back)" % stored)

    if notes is not None:
        det = call("GET", "/v1/appStoreVersions/%s/appStoreReviewDetail" % ver["id"])
        existing = (det or {}).get("data")
        attrs = {"notes": notes, "demoAccountRequired": False}
        # Apple requires the review CONTACT on this resource, and refuses the
        # whole PATCH without it:
        #   409 You must provide a value for the attribute 'contactFirstName'
        # Those are personal details. They are not invented here and never touch
        # the repo - they are read back from whichever platform's review detail
        # already has them, because the human entered them once for this app and
        # copying them across platforms is not new information.
        CONTACT = ("contactFirstName", "contactLastName",
                   "contactEmail", "contactPhone")
        have = (existing or {}).get("attributes", {})
        if not all(have.get(k) for k in CONTACT):
            # An explicitly supplied contact wins: APPLE_REVIEW_CONTACT holds the
            # four fields as JSON and comes from a GitHub secret, so the values
            # reach Apple without ever being written to this repo or printed.
            env_json = os.environ.get("APPLE_REVIEW_CONTACT", "").strip()
            if env_json:
                try:
                    supplied = json.loads(env_json)
                except ValueError:
                    sys.exit("APPLE_REVIEW_CONTACT is not valid JSON")
                missing = [k for k in CONTACT if not supplied.get(k)]
                if missing:
                    sys.exit("APPLE_REVIEW_CONTACT is missing: %s" % ", ".join(missing))
                for k in CONTACT:
                    attrs[k] = supplied[k]
                print("  review contact: supplied (kept out of the repo and the log)")
                have = {k: attrs[k] for k in CONTACT}
            src = None
            allv = call("GET", "/v1/apps/%s/appStoreVersions?limit=200" % APP) or {}
            for v in allv.get("data", []):
                if v["id"] == ver["id"]:
                    continue
                d2 = call("GET",
                          "/v1/appStoreVersions/%s/appStoreReviewDetail" % v["id"])
                a2 = ((d2 or {}).get("data") or {}).get("attributes", {})
                if all(a2.get(k) for k in CONTACT):
                    src = a2
                    break
            if all(attrs.get(k) for k in CONTACT):
                src = True
            if src and src is not True:
                for k in CONTACT:
                    attrs[k] = src[k]
                print("  review contact: copied from the other platform's "
                      "version (not stored anywhere)")
            elif src is True:
                pass
            else:
                print("::error::this version needs a review contact "
                      "(first/last name, email, phone) and no other version has "
                      "one to copy. Enter it once in App Store Connect - it is "
                      "personal data and does not belong in this repo.")
                sys.exit(1)
        if existing:
            r = call("PATCH", "/v1/appStoreReviewDetails/%s" % existing["id"],
                     {"data": {"id": existing["id"],
                               "type": "appStoreReviewDetails",
                               "attributes": attrs}})
        else:
            r = call("POST", "/v1/appStoreReviewDetails",
                     {"data": {"type": "appStoreReviewDetails",
                               "attributes": attrs,
                               "relationships": {"appStoreVersion": {
                                   "data": {"type": "appStoreVersions",
                                            "id": ver["id"]}}}}})
        if r is None:
            sys.exit(1)
        print("review notes set, sign-in required = NO")

    print()
    print("STILL YOURS, and deliberately not automatable here:")
    print("  1. export compliance on the build (a legal declaration)")
    print("  2. Add for Review")
    print("  3. choose 'Manually release this version'")


main()
