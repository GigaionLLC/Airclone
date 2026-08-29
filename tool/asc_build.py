#!/usr/bin/env python3
"""Attach an uploaded build to an App Store version, and set the review notes.

The steps between "a build finished uploading" and "a human presses Add for
Review". All plain App Store Connect API calls, and all the kind of retyping that
lets the console drift from the doc that justifies it - the review notes in
particular carry a constraint that already cost this project review cycles
elsewhere (never point a reviewer at the command console), so this reads them
from the listing document and refuses if they mention it.

What it deliberately does NOT do:

  * export compliance. `usesNonExemptEncryption` is a US export-control
    declaration about the LLC, and Airclone encrypts the user's rclone config
    with a passphrase, so "no" would probably be false. A human answers it.
  * submit. Adding a version to review is the one action AGENT.md rules 10-13
    exist for: a machine once committed a store submission and published this
    app at $0. There is no code path here that can do it.

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
  --apply                 actually send it. Without this nothing is written.

Everything printed is ASCII: GitHub's Windows runners give Python a cp1252
stdout and a stray arrow aborts the process mid-run (AGENT.md rule 12).
"""
import base64
import io
import json
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
    bs = call("GET", "/v1/builds?filter[app]=%s&limit=50&sort=-uploadedDate"
                     "&include=preReleaseVersion" % APP)
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
                     plat_of.get(pv, "?")))
    print("recent builds:")
    for r in rows[:8]:
        print("  build %-6s %-9s %-12s expired=%-5s %s"
              % (r[1], r[5], r[2], r[3], r[4]))
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


def main():
    ver = pick_version()
    va = ver["attributes"]
    print("%s version %s  state=%s"
          % (PLATFORM, va["versionString"], va["appStoreState"]))

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
            bid, bnum, _, _, when, _bplat = got
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

    if not APPLY:
        print()
        print("dry run - nothing sent. Pass --apply to write.")
        return

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
            if src:
                for k in CONTACT:
                    attrs[k] = src[k]
                print("  review contact: copied from the other platform's "
                      "version (not stored anywhere)")
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
