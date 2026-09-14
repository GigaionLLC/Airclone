"""Build the minisign fixtures the update-verifier tests read.

WHY A GENERATOR AND NOT A HAND-WRITTEN FIXTURE. The Dart verifier and the fixture
must not come from the same understanding of the format, or the tests prove only
that the code agrees with itself. This writes the signature the way minisign's
own spec says to - independently, in Python, with a different Ed25519
implementation - and CI then runs the REAL `minisign -V` against the same files
(.github/workflows/linux-runner.yml). Three separate implementations have to
agree before a test here means anything.

The key here is a TEST key with a fixed seed. It signs nothing anybody installs,
it is committed on purpose, and it must never be confused with the release key -
which is created by a human, kept offline, and never touches this repository.

    python dev/update/make-test-fixture.py

Rewrites app/test/fixtures/update/ in place. Deterministic: run it twice and git
sees no change.
"""

from __future__ import annotations

import base64
import hashlib
import io
import pathlib

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "app" / "test" / "fixtures" / "update"

# Fixed, so the fixture is reproducible and a rerun is a no-op in git.
SEED = bytes.fromhex(
    "a1r0f0n3"[:0].hex() if False else
    "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"
)
KEY_ID = bytes.fromhex("4149524331303031")  # "AIRC1001", so it is obvious in hex

# The manifest a release would publish: one line per asset, sha256sum format
# (hash, two spaces, name). The names are the real ones from release.yml, so a
# test can ask for the asset a given package would want and get a realistic miss
# or hit.
# One entry is a REAL hash of a real (tiny) payload, written alongside as
# asset.bin, so a test can serve it and take the happy path all the way to a
# verified file. The rest are placeholders: what they prove is that a lookup by
# name finds the right line among several.
ASSET_NAME = "Airclone-x86_64.AppImage"
ASSET_BYTES = b"an Airclone build, pretend"
ASSET_SHA256 = hashlib.sha256(ASSET_BYTES).hexdigest()

MANIFEST_LINES = [
    ("1" * 64, "airclone-setup-x64.exe"),
    ("2" * 64, "airclone-windows-x64.zip"),
    ("3" * 64, "airclone-macos.dmg"),
    (ASSET_SHA256, ASSET_NAME),
    ("5" * 64, "airclone-linux-x64.tar.gz"),
    ("6" * 64, "airclone.flatpak"),
]
TRUSTED_COMMENT = "airclone v9.9.9 2026-09-14T00:00:00Z"


def write(path: pathlib.Path, text: str) -> None:
    io.open(path, "w", encoding="utf-8", newline="\n").write(text)
    print("  wrote", path.relative_to(ROOT))


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    key = Ed25519PrivateKey.from_private_bytes(SEED)
    pub = key.public_key().public_bytes_raw()

    manifest = "".join(f"{h}  {name}\n" for h, name in MANIFEST_LINES)
    write(OUT / "SHA256SUMS", manifest)

    # "ED" is the prehashed variant: what is signed is BLAKE2b-512 of the file,
    # so a verifier never has to hold the whole payload in memory. minisign has
    # written this by default since 0.10.
    prehash = hashlib.blake2b(manifest.encode("utf-8"), digest_size=64).digest()
    signature = key.sign(prehash)

    # The trusted comment is only trusted because a SECOND signature covers it,
    # over signature || comment bytes. That is what lets the release tag live in
    # the comment and still be tamper-evident - which is how the app refuses a
    # genuine but older manifest replayed at it.
    global_sig = key.sign(signature + TRUSTED_COMMENT.encode("utf-8"))

    b64 = lambda b: base64.b64encode(b).decode("ascii")  # noqa: E731
    write(
        OUT / "SHA256SUMS.minisig",
        "untrusted comment: signature from airclone TEST key\n"
        f"{b64(b'ED' + KEY_ID + signature)}\n"
        f"trusted comment: {TRUSTED_COMMENT}\n"
        f"{b64(global_sig)}\n",
    )
    write(
        OUT / "minisign.pub",
        "untrusted comment: airclone TEST key - signs nothing anybody installs\n"
        f"{b64(b'Ed' + KEY_ID + pub)}\n",
    )
    # The one line the Dart side actually embeds: the public key, base64, as it
    # appears on line 2 of the .pub file.
    write(OUT / "public_key.txt", b64(b"Ed" + KEY_ID + pub) + "\n")

    # The payload the real hash above belongs to.
    io.open(OUT / "asset.bin", "wb").write(ASSET_BYTES)
    print("  wrote", (OUT / "asset.bin").relative_to(ROOT))

    # A tampered manifest, byte-identical in shape, for the negative tests.
    write(
        OUT / "SHA256SUMS.tampered",
        manifest.replace(ASSET_SHA256, "0" * 63 + "1"),
    )
    print("done")


if __name__ == "__main__":
    main()
