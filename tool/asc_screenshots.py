#!/usr/bin/env python3
"""Upload Mac App Store screenshots from docs/store/apple/mac/store-ready/.

Apple's screenshot upload is a three-step dance, not a POST:
  1. reserve  - POST /v1/appScreenshots with the file name and size; Apple replies
                with uploadOperations telling you exactly how to send the bytes
  2. upload   - PUT the bytes to each operation's URL with its headers
  3. commit   - PATCH uploaded=true with an MD5 of the file, which Apple verifies

Skipping step 3 leaves a screenshot that exists and never appears. The MD5 is a
transport checksum Apple requires, not a security claim.

Usage:
  python tool/asc_screenshots.py <key.p8> <keyid> <issuerid> <appid> [options]

Options:
  --device mac|iphone|ipad   which screenshot SET to fill (default mac)
  --replace                  delete the set's existing screenshots first. Apple
                             does not overwrite by filename, so without this an
                             improved set lands BESIDE the old one.
  --dir <path>               override the directory for that device
  --apply                    actually upload

Apple wants one set per display type, and iPhone and iPad are SEPARATE sets on
the same iOS version - not one set holding both sizes. Without --apply it lists
what it would upload and changes nothing.
"""
import base64, hashlib, json, os, sys, time, urllib.request, urllib.error
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils as au

for _s in (sys.stdout, sys.stderr):
    try: _s.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError): pass

KEY, KID, ISS, APP = sys.argv[1:5]
ARGV = sys.argv[5:]
APPLY = "--apply" in ARGV


def _opt(name, default):
    return ARGV[ARGV.index(name) + 1] if name in ARGV else default


# Apple wants one screenshot SET per display type, and iPhone and iPad are
# separate sets on the same iOS version - not one set with mixed sizes. Mac has
# exactly one. `--device` picks which; the directory follows from it, so the
# shots for each device live somewhere obvious rather than in one soup.
DEVICES = {
    "mac": ("MAC_OS", "APP_DESKTOP", "docs/store/apple/mac/store-ready"),
    "iphone": ("IOS", "APP_IPHONE_67", "docs/store/apple/ios/iphone"),
    "ipad": ("IOS", "APP_IPAD_PRO_3GEN_129", "docs/store/apple/ios/ipad"),
}
DEVICE = _opt("--device", "mac")
if DEVICE not in DEVICES:
    sys.exit("--device must be one of: %s" % ", ".join(DEVICES))
PLATFORM, DISPLAY_TYPE, SHOTS = DEVICES[DEVICE]
SHOTS = _opt("--dir", SHOTS)


def token():
    def b64u(b): return base64.urlsafe_b64encode(b).rstrip(b"=")
    pk = serialization.load_pem_private_key(open(KEY, "rb").read(), password=None)
    now = int(time.time())
    si = (b64u(json.dumps({"alg": "ES256", "kid": KID, "typ": "JWT"}).encode()) + b"." +
          b64u(json.dumps({"iss": ISS, "iat": now, "exp": now + 900,
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
        with urllib.request.urlopen(req, timeout=90) as r:
            return json.load(r) if r.status not in (204,) else {}
    except urllib.error.HTTPError as e:
        print("  HTTP %s %s" % (e.code, path))
        try:
            for x in json.load(e).get("errors", []):
                print("   ", x.get("title"), "|", x.get("detail"))
        except Exception:
            print("   ", e.read()[:400])
        return None


files = sorted(f for f in os.listdir(SHOTS) if f.endswith(".png"))
if not files:
    sys.exit("no screenshots in " + SHOTS)
print("found %d screenshots" % len(files))
for f in files:
    print("   %-32s %d bytes" % (f, os.path.getsize(os.path.join(SHOTS, f))))
if not APPLY:
    print("\ndry run - pass --apply to upload")
    sys.exit(0)

vs = call("GET", "/v1/apps/%s/appStoreVersions?limit=200" % APP)
ver = next((v for v in vs["data"] if v["attributes"]["platform"] == PLATFORM), None)
if not ver:
    sys.exit("no %s version found" % PLATFORM)
locs = call("GET", "/v1/appStoreVersions/%s/appStoreVersionLocalizations" % ver["id"])
loc = next(l for l in locs["data"] if l["attributes"]["locale"] == "en-US")

# Reuse the set if one exists; creating a second would silently split the shots.
sets = call("GET", "/v1/appStoreVersionLocalizations/%s/appScreenshotSets" % loc["id"])
sset = next((s for s in sets["data"]
             if s["attributes"]["screenshotDisplayType"] == DISPLAY_TYPE), None)
if sset:
    print("reusing existing %s set" % DISPLAY_TYPE)
else:
    sset = call("POST", "/v1/appScreenshotSets", {"data": {
        "type": "appScreenshotSets",
        "attributes": {"screenshotDisplayType": DISPLAY_TYPE},
        "relationships": {"appStoreVersionLocalization": {"data": {
            "type": "appStoreVersionLocalizations", "id": loc["id"]}}}}})
    if not sset:
        sys.exit(1)
    sset = sset["data"]
    print("created %s set" % DISPLAY_TYPE)

# Clear the set first when asked. Apple does not overwrite by filename - it
# creates a second asset - so re-uploading an improved set without this leaves
# the old shots on the product page beside the new ones.
if "--replace" in ARGV:
    existing = call("GET", "/v1/appScreenshotSets/%s/appScreenshots" % sset["id"])
    for old_shot in (existing or {}).get("data", []):
        nm = old_shot["attributes"].get("fileName", old_shot["id"])
        if call("DELETE", "/v1/appScreenshots/%s" % old_shot["id"]) is None:
            sys.exit("could not delete %s" % nm)
        print("  removed %s" % nm)

for name in files:
    path = os.path.join(SHOTS, name)
    blob = open(path, "rb").read()
    print("\n%s" % name)

    res = call("POST", "/v1/appScreenshots", {"data": {
        "type": "appScreenshots",
        "attributes": {"fileName": name, "fileSize": len(blob)},
        "relationships": {"appScreenshotSet": {"data": {
            "type": "appScreenshotSets", "id": sset["id"]}}}}})
    if not res:
        continue
    shot = res["data"]

    for op in shot["attributes"]["uploadOperations"]:
        chunk = blob[op["offset"]:op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], data=chunk, method=op["method"])
        for h in op["requestHeaders"]:
            req.add_header(h["name"], h["value"])
        try:
            urllib.request.urlopen(req, timeout=180)
        except urllib.error.HTTPError as e:
            print("  upload failed: HTTP %s" % e.code)
            break
    else:
        done = call("PATCH", "/v1/appScreenshots/%s" % shot["id"], {"data": {
            "id": shot["id"], "type": "appScreenshots",
            "attributes": {"uploaded": True,
                           "sourceFileChecksum": hashlib.md5(blob).hexdigest()}}})
        state = ((done or {}).get("data", {}).get("attributes", {})
                 .get("assetDeliveryState", {}) or {}).get("state")
        print("  committed, state=%s" % state)

print("\n--- final set ---")
final = call("GET", "/v1/appScreenshotSets/%s/appScreenshots" % sset["id"])
for s in (final or {}).get("data", []):
    a = s["attributes"]
    print("  %-32s %s" % (a.get("fileName"),
                          (a.get("assetDeliveryState") or {}).get("state")))
