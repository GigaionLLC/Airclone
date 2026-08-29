#!/usr/bin/env python3
"""Push the Mac App Store listing text from docs/store/apple/listing-en-US.md.

The listing doc is the source of truth - it carries the constraints (no "free"
claim, the rclone non-affiliation line, no console mention) and the reasoning for
each decision. Retyping that into a web form is how copy drifts from the doc that
justifies it, so this reads the doc and PATCHes App Store Connect directly.

Usage:
  python tool/asc_listing.py <key.p8> <keyid> <issuerid> <appid> [options]

Options:
  --platform MAC_OS|IOS   which version's localization to write (default MAC_OS)
  --apply                 actually send it

Without --apply it prints what it WOULD send and changes nothing. The iOS copy is
a SEPARATE document, not a find-and-replace of the Mac one: the iOS build has no
arbitrary filesystem, so its description and review notes describe a different
app.
"""
import base64, io, json, sys, time, urllib.request, urllib.error
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils as au

for _s in (sys.stdout, sys.stderr):
    try: _s.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError): pass

KEY, KID, ISS, APP = sys.argv[1:5]
ARGV = sys.argv[5:]
APPLY = "--apply" in ARGV
PLATFORM = ARGV[ARGV.index("--platform") + 1] if "--platform" in ARGV else "MAC_OS"
DOC = ("docs/store/apple/listing-ios-en-US.md" if PLATFORM == "IOS"
       else "docs/store/apple/listing-en-US.md")
LIMITS = {"description": 4000, "keywords": 100, "promotionalText": 170}


def token():
    def b64u(b): return base64.urlsafe_b64encode(b).rstrip(b"=")
    pk = serialization.load_pem_private_key(open(KEY, "rb").read(), password=None)
    now = int(time.time())
    si = (b64u(json.dumps({"alg": "ES256", "kid": KID, "typ": "JWT"}).encode()) + b"." +
          b64u(json.dumps({"iss": ISS, "iat": now, "exp": now + 600,
                           "aud": "appstoreconnect-v1"}).encode()))
    r, s = au.decode_dss_signature(pk.sign(si, ec.ECDSA(hashes.SHA256())))
    return (si + b"." + b64u(r.to_bytes(32, "big") + s.to_bytes(32, "big"))).decode()


TOK = token()


def call(method, path, body=None):
    req = urllib.request.Request(
        "https://api.appstoreconnect.apple.com" + path,
        data=json.dumps(body).encode() if body else None,
        headers={"Authorization": "Bearer " + TOK, "Content-Type": "application/json"},
        method=method)
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
    """The first ``` block after `header`."""
    i = doc.index(header)
    j = doc.index("```", i) + 3
    return doc[j:doc.index("```", j)].strip("\n")


doc = io.open(DOC, encoding="utf-8").read()
fields = {
    "description": fenced(doc, "## Description"),
    # NOT the first keyword block in the doc - that one is the REJECTED
    # alternative kept for the record. Anchor on the marker instead.
    # The Mac doc keeps a REJECTED keyword alternative for the record, and it
    # comes first, so that one anchors on a marker. The iOS doc has no such
    # alternative and its keywords are simply the block under the heading.
    "keywords": fenced(doc, "**Use this one**" if "**Use this one**" in doc
                       else "## Keywords"),
    "promotionalText": fenced(doc, "## Promotional text"),
    "supportUrl": "https://github.com/GigaionLLC/Airclone",
}

over = [k for k, m in LIMITS.items() if len(fields[k]) > m]
if over:
    sys.exit("refusing: over Apple's limit: %s" % over)

vs = call("GET", "/v1/apps/%s/appStoreVersions?limit=200" % APP)
if not vs:
    sys.exit(1)
ver = next((v for v in vs["data"] if v["attributes"]["platform"] == PLATFORM), None)
if not ver:
    sys.exit("no %s version found" % PLATFORM)
print("%s %s (%s)" % (PLATFORM, ver["attributes"]["versionString"],
                      ver["attributes"]["appStoreState"]))

locs = call("GET", "/v1/appStoreVersions/%s/appStoreVersionLocalizations" % ver["id"])
loc = next((l for l in locs["data"] if l["attributes"]["locale"] == "en-US"), None)
if not loc:
    sys.exit("no en-US localization")

# The privacy-policy URL is APP-level, not per-version, and Apple refuses a
# submission without it. Checked and set here because it is listing metadata like
# everything else in this file, and because "required field nobody filled in" is
# a bad way to discover a blocked submission.
PRIVACY_URL = "https://github.com/GigaionLLC/Airclone/blob/main/PRIVACY.md"
infos = call("GET", "/v1/apps/%s/appInfos" % APP) or {"data": []}
for info in infos["data"]:
    ilocs = call("GET", "/v1/appInfos/%s/appInfoLocalizations" % info["id"])
    iloc = next((l for l in (ilocs or {}).get("data", [])
                 if l["attributes"]["locale"] == "en-US"), None)
    if not iloc:
        continue
    have = iloc["attributes"].get("privacyPolicyUrl") or ""
    print("  privacyPolicyUrl %s" % (have if have else "-- EMPTY --"))
    if have == PRIVACY_URL or not APPLY:
        continue
    r = call("PATCH", "/v1/appInfoLocalizations/%s" % iloc["id"],
             {"data": {"id": iloc["id"], "type": "appInfoLocalizations",
                       "attributes": {"privacyPolicyUrl": PRIVACY_URL}}})
    if r is not None:
        print("  privacyPolicyUrl set")

for k, v in fields.items():
    print("  %-16s %d chars" % (k, len(v)))
if not APPLY:
    print("\ndry run - pass --apply to send")
    sys.exit(0)

res = call("PATCH", "/v1/appStoreVersionLocalizations/%s" % loc["id"],
           {"data": {"id": loc["id"], "type": "appStoreVersionLocalizations",
                     "attributes": fields}})
if not res:
    sys.exit(1)
a = res["data"]["attributes"]
print("\napplied:")
for k in fields:
    got = a.get(k) or ""
    print("  %-16s %s" % (k, "OK (%d chars)" % len(got) if got else "STILL EMPTY"))
