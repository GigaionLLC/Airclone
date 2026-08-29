#!/usr/bin/env python3
"""Create the iOS App Store signing assets, the same way the Mac pair was made.

The Mac certificates (3rd Party Mac Developer Application / Installer) do NOT
cover iOS, so ios-release.yml needs its own Apple Distribution certificate and an
iOS App Store provisioning profile. Xcode's CLOUD signing cannot mint a
distribution certificate with an App Manager key - that is what "Cloud signing
permission error" means - but the Certificates API can, which is why this exists
and why the CI key stays at App Manager rather than Admin.

What it does, in order:
  1. generate an EC/RSA private key and a CSR with openssl (locally, never sent
     anywhere except the CSR itself)
  2. POST it to /v1/certificates as DISTRIBUTION
  3. fetch Apple's WWDR G3 intermediate, without which the p12 chain is
     incomplete and codesign refuses the identity
  4. build a .p12 bundling key + certificate + intermediate
  5. find the bundle ID resource and create an IOS_APP_STORE profile for it
  6. print the three GitHub secret values as base64, to files - never to stdout

Usage:
  python tool/asc_ios_signing.py <key.p8> <keyid> <issuerid> [--apply]
  python tool/asc_ios_signing.py <key.p8> <keyid> <issuerid> --revoke <cert-id>

`--revoke` exists for the EPHEMERAL flow: a CI job creates a certificate, uses it
within that one job, and revokes it on the way out, so no long-lived distribution
private key is stored anywhere. It revokes exactly the id it is given and never
searches for one to clean up - Apple's certificate `name` is derived from the
team, so an ephemeral certificate is indistinguishable from one a human made by
hand, and guessing wrong would revoke something somebody depends on.

Without --apply it reports what already exists and what it WOULD create, and
touches nothing. Output lands in dev/secrets/apple-ios/ (gitignored).

Everything printed is ASCII: GitHub's Windows runners give Python a cp1252
stdout, and a stray arrow raises UnicodeEncodeError mid-run (AGENT.md rule 12).
"""
import base64
import json
import os
import subprocess
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

if len(sys.argv) < 4:
    print(__doc__)
    sys.exit(2)

KEY, KID, ISS = sys.argv[1:4]
APPLY = "--apply" in sys.argv
REVOKE = (sys.argv[sys.argv.index("--revoke") + 1]
          if "--revoke" in sys.argv else None)
OUT_OVERRIDE = (sys.argv[sys.argv.index("--out-dir") + 1]
                if "--out-dir" in sys.argv else None)
# The ephemeral flow generates a FRESH private key every run, so reusing an
# existing certificate would pair our new key with someone else's certificate and
# produce an identity codesign rejects. --force-new says "mint one for this key".
FORCE_NEW = "--force-new" in sys.argv
BUNDLE_ID = "com.gigaionllc.airclone"
PROFILE_NAME = "Airclone iOS App Store"
OUT = os.path.join("dev", "secrets", "apple-ios")
WWDR_URL = "https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer"


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


def run(*args, **kw):
    """openssl, with its output suppressed unless it fails."""
    p = subprocess.run(args, capture_output=True, text=True, **kw)
    if p.returncode != 0:
        print("  command failed:", " ".join(args))
        print("  ", (p.stderr or p.stdout or "").strip()[:400])
        sys.exit(1)
    return p.stdout


def survey():
    """What already exists. Run first, so --apply never duplicates a resource."""
    print("== what the account already has ==")
    certs = call("GET", "/v1/certificates?limit=200") or {"data": []}
    ios = [
        c
        for c in certs["data"]
        if c["attributes"].get("certificateType") in ("DISTRIBUTION", "IOS_DISTRIBUTION")
    ]
    for c in ios:
        a = c["attributes"]
        print(
            "  cert  %-18s %s  expires %s"
            % (a.get("certificateType"), a.get("name"), a.get("expirationDate", "")[:10])
        )
    if not ios:
        print("  cert  (no iOS distribution certificate)")

    profs = call("GET", "/v1/profiles?limit=200") or {"data": []}
    app_store = [
        p for p in profs["data"] if p["attributes"].get("profileType") == "IOS_APP_STORE"
    ]
    for p in app_store:
        a = p["attributes"]
        print(
            "  prof  %-28s %s  expires %s"
            % (a.get("name"), a.get("profileState"), a.get("expirationDate", "")[:10])
        )
    if not app_store:
        print("  prof  (no IOS_APP_STORE profile)")
    return ios, app_store


def bundle_resource_id():
    r = call("GET", "/v1/bundleIds?limit=200&filter[identifier]=" + BUNDLE_ID)
    for b in (r or {}).get("data", []):
        if b["attributes"].get("identifier") == BUNDLE_ID:
            return b["id"]
    return None


def main():
    if REVOKE:
        # DELETE on a certificate is how the API revokes it. Narrow on purpose:
        # this id and nothing else.
        r = call("DELETE", "/v1/certificates/%s" % REVOKE)
        if r is None:
            sys.exit(1)
        print("revoked certificate %s" % REVOKE)
        return

    ios_certs, profiles = survey()
    bid = bundle_resource_id()
    print("  bundle id resource:", "found" if bid else "MISSING - register it first")

    if not APPLY:
        print()
        print("== dry run, nothing created ==")
        print("Re-run with --apply to create:")
        if not ios_certs:
            print("  - an Apple Distribution certificate (DISTRIBUTION)")
        if not any(p["attributes"]["name"] == PROFILE_NAME for p in profiles):
            print("  - the '%s' profile (IOS_APP_STORE)" % PROFILE_NAME)
        if ios_certs and any(p["attributes"]["name"] == PROFILE_NAME for p in profiles):
            print("  - nothing; both already exist")
        return

    if not bid:
        print("::error:: bundle id %s is not registered" % BUNDLE_ID)
        sys.exit(1)

    out_dir = OUT_OVERRIDE or OUT
    globals()["OUT"] = out_dir
    os.makedirs(out_dir, exist_ok=True)
    key_path = os.path.join(OUT, "ios-dist.key")
    csr_path = os.path.join(OUT, "ios-dist.csr")
    cer_path = os.path.join(OUT, "ios-dist.cer")
    pem_path = os.path.join(OUT, "ios-dist.pem")
    p12_path = os.path.join(OUT, "ios-dist.p12")
    wwdr_path = os.path.join(OUT, "wwdr.pem")

    if not os.path.exists(csr_path):
        print("== generating a private key and CSR ==")
        run("openssl", "genrsa", "-out", key_path, "2048")
        run(
            "openssl", "req", "-new", "-key", key_path, "-out", csr_path,
            "-subj", "/CN=Airclone iOS Distribution/O=Gigaion, LLC/C=US",
        )
    csr = open(csr_path).read()

    cert_id = None
    if ios_certs and not FORCE_NEW:
        print("== reusing the existing distribution certificate ==")
        cert_id = ios_certs[0]["id"]
        content = ios_certs[0]["attributes"]["certificateContent"]
    else:
        print("== creating the distribution certificate ==")
        r = call(
            "POST",
            "/v1/certificates",
            {
                "data": {
                    "type": "certificates",
                    "attributes": {"certificateType": "DISTRIBUTION", "csrContent": csr},
                }
            },
        )
        if not r:
            sys.exit(1)
        cert_id = r["data"]["id"]
        content = r["data"]["attributes"]["certificateContent"]
        print("  created:", r["data"]["attributes"].get("name"))

    open(os.path.join(OUT, "cert-id.txt"), "w").write(cert_id)
    open(cer_path, "wb").write(base64.b64decode(content))
    run("openssl", "x509", "-inform", "DER", "-in", cer_path, "-out", pem_path)

    # Without the WWDR intermediate the p12 chain is incomplete and codesign
    # will not accept the identity. That cost a run on the Mac lane.
    print("== fetching the Apple WWDR G3 intermediate ==")
    with urllib.request.urlopen(WWDR_URL, timeout=60) as r:
        open(os.path.join(OUT, "wwdr.cer"), "wb").write(r.read())
    run(
        "openssl", "x509", "-inform", "DER",
        "-in", os.path.join(OUT, "wwdr.cer"), "-out", wwdr_path,
    )

    pw = base64.urlsafe_b64encode(os.urandom(24)).decode().rstrip("=")
    run(
        "openssl", "pkcs12", "-export",
        "-inkey", key_path, "-in", pem_path, "-certfile", wwdr_path,
        "-out", p12_path, "-passout", "pass:" + pw, "-legacy",
    )
    open(os.path.join(OUT, "p12.password"), "w").write(pw)
    print("  p12 written (password in dev/secrets/apple-ios/p12.password)")

    existing = [p for p in profiles if p["attributes"]["name"] == PROFILE_NAME]
    if existing and FORCE_NEW:
        # A profile embeds the certificates it was built for. The ephemeral flow
        # revokes its certificate on the way out, so any profile left over from a
        # previous run references a dead one and would export an unsignable app.
        # Delete it and rebuild against the certificate minted just now.
        print("== replacing the stale profile (its certificate was revoked) ==")
        if call("DELETE", "/v1/profiles/%s" % existing[0]["id"]) is None:
            sys.exit(1)
        existing = []
    if existing:
        print("== reusing the existing profile ==")
        prof = existing[0]["attributes"]["profileContent"]
    else:
        print("== creating the provisioning profile ==")
        r = call(
            "POST",
            "/v1/profiles",
            {
                "data": {
                    "type": "profiles",
                    "attributes": {
                        "name": PROFILE_NAME,
                        "profileType": "IOS_APP_STORE",
                    },
                    "relationships": {
                        "bundleId": {"data": {"type": "bundleIds", "id": bid}},
                        "certificates": {
                            "data": [{"type": "certificates", "id": cert_id}]
                        },
                    },
                }
            },
        )
        if not r:
            sys.exit(1)
        prof = r["data"]["attributes"]["profileContent"]
        print("  created:", PROFILE_NAME)

    open(os.path.join(OUT, "Airclone_iOS.mobileprovision"), "wb").write(
        base64.b64decode(prof)
    )
    open(os.path.join(OUT, "profile-name.txt"), "w").write(PROFILE_NAME)

    # Base64 to FILES, never to stdout: a secret that reaches a transcript is a
    # secret that has to be rotated.
    with open(os.path.join(OUT, "APPLE_IOS_DIST_P12_BASE64.txt"), "wb") as f:
        f.write(base64.b64encode(open(p12_path, "rb").read()))
    with open(os.path.join(OUT, "APPLE_IOS_PROVISIONING_PROFILE_BASE64.txt"), "wb") as f:
        f.write(base64.b64encode(base64.b64decode(prof)))

    print()
    print("== done. Set these, reading from the files so nothing is echoed ==")
    print("  gh secret set APPLE_IOS_DIST_P12_BASE64 --org GigaionLLC --visibility all \\")
    print("    < dev/secrets/apple-ios/APPLE_IOS_DIST_P12_BASE64.txt")
    print("  gh secret set APPLE_IOS_PROVISIONING_PROFILE_BASE64 --org GigaionLLC --visibility all \\")
    print("    < dev/secrets/apple-ios/APPLE_IOS_PROVISIONING_PROFILE_BASE64.txt")
    print("  gh secret set APPLE_IOS_P12_PASSWORD --org GigaionLLC --visibility all \\")
    print("    < dev/secrets/apple-ios/p12.password")
    print()
    print("Then: gh workflow run ios-release.yml --ref main -f mode=validate")


main()
