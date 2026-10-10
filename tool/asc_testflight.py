#!/usr/bin/env python3
"""Public TestFlight beta for iOS: one external group with a public link.

iOS cannot sideload, and the App Store build is paid, so the free way to try
the iPhone/iPad app is TestFlight. This sets up and maintains that: an EXTERNAL
beta group with a public link (capped, default 1000 testers), the beta
information Apple requires before external testing (description, feedback
email, privacy policy, review contact), and the newest iOS build added to the
group and submitted to Beta App Review. macOS is deliberately left out: it is
a free download from GitHub Releases.

Reruns are safe: everything is looked up first and only what is missing or
different is written. Rerun with --limit N to change the tester cap.

Usage:
  python tool/asc_testflight.py <key.p8> <keyid> <issuerid> <appid> [options]

Options:
  --limit N        public-link tester cap (default 1000, Apple's max 10000)
  --build 151      which iOS build number to add (default: newest VALID)
  --apply          actually write. Without it, report what would change.

Environment:
  APPLE_REVIEW_CONTACT  JSON with contactFirstName, contactLastName,
                        contactEmail, contactPhone. Needed for Beta App Review
                        when the app has no beta review contact yet; its email
                        is also the tester feedback address. Never printed.
"""
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request

try:
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.hazmat.primitives.asymmetric import utils as au
except ImportError:
    sys.exit("pip install cryptography")

# GitHub's Windows runners give Python a cp1252 stdout; keep output ASCII and
# reconfigure anyway (AGENT.md rule 12).
try:
    sys.stdout.reconfigure(encoding="utf-8")
except (AttributeError, ValueError):
    pass

if len(sys.argv) < 5:
    print(__doc__)
    sys.exit(2)

KEY, KID, ISS, APP = sys.argv[1:5]
ARGV = sys.argv[5:]
APPLY = "--apply" in ARGV


def opt(name, default=None):
    return ARGV[ARGV.index(name) + 1] if name in ARGV else default


try:
    LIMIT = int(opt("--limit", "1000"))
except ValueError:
    sys.exit("--limit must be a number")
if not 1 <= LIMIT <= 10000:
    sys.exit("--limit must be between 1 and 10000 (Apple's cap)")
WANT_BUILD = opt("--build")

GROUP_NAME = "Public beta"
LOCALE = "en-US"
PRIVACY_URL = "https://github.com/GigaionLLC/Airclone/blob/main/PRIVACY.md"
MARKETING_URL = "https://github.com/GigaionLLC/Airclone"
DESCRIPTION = (
    "Airclone is a free, open-source file manager for rclone: browse, copy, "
    "sync and back up your cloud storage like local folders. This is the public "
    "beta of the iPhone and iPad app. It is the same app as the App Store "
    "version. Please report anything that breaks at "
    "https://github.com/GigaionLLC/Airclone/issues or with TestFlight's "
    "feedback button."
)
WHATS_NEW = (
    "Public beta. Try adding a cloud (Google Drive, OneDrive, Dropbox, S3, "
    "SFTP and more), importing an existing rclone.conf or a QR code from the "
    "desktop app, browsing, copying, and backups. Report bugs at "
    "https://github.com/GigaionLLC/Airclone/issues"
)
CONTACT_KEYS = ("contactFirstName", "contactLastName", "contactEmail",
                "contactPhone")


def token():
    def b64u(b):
        return base64.urlsafe_b64encode(b).rstrip(b"=")

    pk = serialization.load_pem_private_key(open(KEY, "rb").read(), password=None)
    now = int(time.time())
    si = (
        b64u(json.dumps({"alg": "ES256", "kid": KID, "typ": "JWT"}).encode())
        + b"."
        + b64u(json.dumps({"iss": ISS, "iat": now, "exp": now + 1200,
                           "aud": "appstoreconnect-v1"}).encode())
    )
    r, s = au.decode_dss_signature(pk.sign(si, ec.ECDSA(hashes.SHA256())))
    return (si + b"." + b64u(r.to_bytes(32, "big") + s.to_bytes(32, "big"))).decode()


TOK = token()


def call(method, path, body=None, quiet=False):
    req = urllib.request.Request(
        "https://api.appstoreconnect.apple.com" + path,
        data=json.dumps(body).encode() if body else None,
        headers={"Authorization": "Bearer " + TOK,
                 "Content-Type": "application/json"},
        method=method,
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.load(r) if r.status != 204 else {}
    except urllib.error.HTTPError as e:
        if not quiet:
            print("  HTTP %s on %s %s" % (e.code, method, path.split("?")[0]))
            try:
                for x in json.load(e).get("errors", []):
                    print("   ", x.get("title"), "|", x.get("detail"))
            except Exception:
                pass
        return None


def write(what, method, path, body):
    """Writes under --apply; otherwise says what it would have written."""
    if not APPLY:
        print("  would %s" % what)
        return {}
    print("  %s" % what)
    res = call(method, path, body)
    if res is None:
        sys.exit("FAILED: %s" % what)
    return res


def review_contact():
    raw = os.environ.get("APPLE_REVIEW_CONTACT", "").strip()
    if not raw:
        return None
    try:
        c = json.loads(raw)
    except ValueError:
        sys.exit("APPLE_REVIEW_CONTACT is not valid JSON")
    missing = [k for k in CONTACT_KEYS if not c.get(k)]
    if missing:
        sys.exit("APPLE_REVIEW_CONTACT is missing: %s" % ", ".join(missing))
    return c


def pick_build():
    q = ("/v1/builds?filter[app]=%s&filter[preReleaseVersion.platform]=IOS"
         "&filter[processingState]=VALID&filter[expired]=false"
         "&sort=-uploadedDate&limit=50&include=preReleaseVersion" % APP)
    res = call("GET", q) or {}
    vers = {x["id"]: x["attributes"].get("version")
            for x in res.get("included", []) if x["type"] == "preReleaseVersions"}
    for b in res.get("data", []):
        num = b["attributes"]["version"]
        if WANT_BUILD and num != WANT_BUILD:
            continue
        pv = (b["relationships"].get("preReleaseVersion", {}).get("data") or {})
        return b, vers.get(pv.get("id"), "?")
    sys.exit("No VALID, unexpired iOS build%s found."
             % (" numbered %s" % WANT_BUILD if WANT_BUILD else ""))


def ensure_beta_localization(contact):
    res = call("GET", "/v1/apps/%s/betaAppLocalizations" % APP) or {}
    mine = [x for x in res.get("data", []) if x["attributes"]["locale"] == LOCALE]
    email = contact["contactEmail"] if contact else None
    want = {"description": DESCRIPTION, "privacyPolicyUrl": PRIVACY_URL,
            "marketingUrl": MARKETING_URL}
    if mine:
        have = mine[0]["attributes"]
        if email is None and not have.get("feedbackEmail"):
            sys.exit("No feedback email set and APPLE_REVIEW_CONTACT not given.")
        if email:
            want["feedbackEmail"] = email
        diff = {k: v for k, v in want.items() if have.get(k) != v}
        if not diff:
            print("  beta app information: up to date")
            return
        write("update beta app information (%s)" % ", ".join(sorted(diff)),
              "PATCH", "/v1/betaAppLocalizations/%s" % mine[0]["id"],
              {"data": {"type": "betaAppLocalizations", "id": mine[0]["id"],
                        "attributes": diff}})
    else:
        if email is None:
            sys.exit("No feedback email set and APPLE_REVIEW_CONTACT not given.")
        want.update(locale=LOCALE, feedbackEmail=email)
        write("create beta app information (%s)" % LOCALE, "POST",
              "/v1/betaAppLocalizations",
              {"data": {"type": "betaAppLocalizations", "attributes": want,
                        "relationships": {"app": {"data": {"type": "apps",
                                                           "id": APP}}}}})


def ensure_review_detail(contact):
    res = call("GET", "/v1/apps/%s/betaAppReviewDetail" % APP) or {}
    d = res.get("data")
    if not d:
        sys.exit("App has no betaAppReviewDetail record.")
    have = d["attributes"]
    if all(have.get(k) for k in CONTACT_KEYS):
        print("  beta review contact: set")
        return
    if not contact:
        sys.exit("Beta review contact is empty and APPLE_REVIEW_CONTACT not given.")
    attrs = {k: contact[k] for k in CONTACT_KEYS}
    attrs["demoAccountRequired"] = False
    write("set beta review contact (values not shown)", "PATCH",
          "/v1/betaAppReviewDetails/%s" % d["id"],
          {"data": {"type": "betaAppReviewDetails", "id": d["id"],
                    "attributes": attrs}})


def ensure_whats_new(build):
    res = call("GET", "/v1/builds/%s/betaBuildLocalizations" % build["id"]) or {}
    mine = [x for x in res.get("data", []) if x["attributes"]["locale"] == LOCALE]
    if mine and mine[0]["attributes"].get("whatsNew"):
        print("  what to test: set")
        return
    if mine:
        write("set what to test", "PATCH",
              "/v1/betaBuildLocalizations/%s" % mine[0]["id"],
              {"data": {"type": "betaBuildLocalizations", "id": mine[0]["id"],
                        "attributes": {"whatsNew": WHATS_NEW}}})
    else:
        write("set what to test", "POST", "/v1/betaBuildLocalizations",
              {"data": {"type": "betaBuildLocalizations",
                        "attributes": {"locale": LOCALE, "whatsNew": WHATS_NEW},
                        "relationships": {"build": {"data": {
                            "type": "builds", "id": build["id"]}}}}})


def ensure_group():
    res = call("GET", "/v1/apps/%s/betaGroups?limit=200" % APP) or {}
    for g in res.get("data", []):
        if g["attributes"]["name"] == GROUP_NAME:
            print("  group \"%s\": exists" % GROUP_NAME)
            return g
    out = write("create external group \"%s\"" % GROUP_NAME, "POST",
                "/v1/betaGroups",
                {"data": {"type": "betaGroups",
                          "attributes": {"name": GROUP_NAME,
                                         "feedbackEnabled": True},
                          "relationships": {"app": {"data": {"type": "apps",
                                                             "id": APP}}}}})
    return out.get("data")


def ensure_build_in_group(group, build):
    if group is None:
        print("  would add the build to the group")
        return
    res = call("GET", "/v1/betaGroups/%s/relationships/builds?limit=200"
               % group["id"]) or {}
    if any(x["id"] == build["id"] for x in res.get("data", [])):
        print("  build in group: yes")
        return
    write("add build to group", "POST",
          "/v1/betaGroups/%s/relationships/builds" % group["id"],
          {"data": [{"type": "builds", "id": build["id"]}]})


def ensure_submitted(build):
    res = call("GET", "/v1/builds/%s/betaAppReviewSubmission" % build["id"],
               quiet=True) or {}
    d = res.get("data")
    if d:
        print("  beta review: %s" % d["attributes"].get("betaReviewState"))
        return
    body = {"data": {"type": "betaAppReviewSubmissions",
                     "relationships": {"build": {"data": {
                         "type": "builds", "id": build["id"]}}}}}
    if not APPLY:
        print("  would submit build to Beta App Review")
        return
    print("  submit build to Beta App Review")
    if call("POST", "/v1/betaAppReviewSubmissions", body) is None:
        # Apple closes a version to external testing once it is live on the
        # App Store (HTTP 422 "closed for beta review submission"). Not fatal:
        # the group and link are still set up, and the next upload with a
        # higher version number is the build testers get.
        print("  NOT SUBMITTED. If Apple says the version is closed, upload a "
              "build with a higher version and rerun.")


def ensure_public_link(group):
    if group is None:
        print("  would enable the public link, capped at %d testers" % LIMIT)
        return None
    a = group["attributes"]
    want = {"publicLinkEnabled": True, "publicLinkLimitEnabled": True,
            "publicLinkLimit": LIMIT}
    diff = {k: v for k, v in want.items() if a.get(k) != v}
    if diff:
        res = write("set public link: on, capped at %d testers" % LIMIT,
                    "PATCH", "/v1/betaGroups/%s" % group["id"],
                    {"data": {"type": "betaGroups", "id": group["id"],
                              "attributes": diff}})
        a = (res.get("data") or {}).get("attributes", a)
    else:
        print("  public link: on, capped at %d testers" % LIMIT)
    return a.get("publicLink")


def main():
    print("Mode: %s" % ("APPLY" if APPLY else "dry-run (nothing is written)"))
    contact = review_contact()
    build, version = pick_build()
    print("Build: iOS %s (%s)" % (version, build["attributes"]["version"]))
    ensure_beta_localization(contact)
    ensure_review_detail(contact)
    ensure_whats_new(build)
    group = ensure_group()
    ensure_build_in_group(group, build)
    ensure_submitted(build)
    link = ensure_public_link(group)
    print()
    if link:
        print("PUBLIC LINK: %s" % link)
        print("It accepts testers once Apple approves the beta review "
              "(usually about a day for the first build).")
    elif APPLY:
        print("No public link returned yet; rerun after the build is approved.")


main()
