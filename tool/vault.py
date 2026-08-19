#!/usr/bin/env python3
"""Encrypted notes vault - commercially sensitive working notes, versioned in git.

WHY THIS EXISTS
    Some notes belong in the repository's history but not in public view: store
    account state, pricing and positioning, unreleased planning, competitive
    analysis. Airclone's repo is PUBLIC, so those cannot simply be committed.

    The obvious alternative - gitignore them - means they live on exactly one
    machine and disappear with it. That has already cost this project context.

    So: `dev/vault/vault.enc` IS committed. The decrypted `dev/vault/notes/`
    directory is gitignored, as is the passphrase. The notes are versioned,
    backed up and reviewable, just not readable by anyone who clones the repo.

WHAT MUST NOT GO IN HERE
    Anything that must never exist in git - credentials, signing keys, API
    private keys, customer data. Those belong in `dev/secrets/` (gitignored,
    never committed in any form) or in a secret manager. A vault in a PUBLIC
    repository is only as strong as its passphrase, and a leaked passphrase
    exposes every historical revision, not just the current one. See
    `dev/vault/README.md` and `dev/secrets/README.md` - the split between the
    two is deliberate and is the whole security argument.

CRYPTO
    scrypt (N=2^16, r=8, p=1) derives a 256-bit key from the passphrase, then
    AES-256-GCM with a fresh random salt and IV on every lock. The GCM tag is
    verified on unlock, so a modified vault.enc fails loudly rather than
    producing plausible-looking garbage. A failure means either the wrong
    passphrase or a tampered blob; GCM cannot distinguish those, and treating
    both as "do not trust" is the correct response.

    The work factor is deliberately high. The blob is public, so the passphrase
    is the only barrier and an offline attacker has unlimited attempts.

USE
    python tool/vault.py init      # generate a passphrase (once, ever)
    python tool/vault.py status    # what is in the vault, WITHOUT decrypting
    python tool/vault.py unlock    # vault.enc -> notes/
    python tool/vault.py lock      # notes/ -> vault.enc, then commit vault.enc

    Edit under notes/, run lock, commit vault.enc. The plaintext never enters
    git. An unlocked edit that is never re-locked is simply lost - the commit
    will not contain it.

Requires `cryptography` (pip install cryptography). Everything else is stdlib.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import secrets
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

# GitHub's Windows runners hand Python a cp1252 stdout, where a stray non-ASCII
# character raises UnicodeEncodeError and kills the process mid-operation. That
# has bitten this repo before (AGENT.md rule 12), so: reconfigure defensively
# AND keep every printed string ASCII.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass

try:
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
except ImportError:  # pragma: no cover - environment problem, not logic
    sys.exit("vault: needs the 'cryptography' package (pip install cryptography)")

REPO = Path(__file__).resolve().parent.parent
VAULT_DIR = REPO / "dev" / "vault"
NOTES_DIR = VAULT_DIR / "notes"
BLOB = VAULT_DIR / "vault.enc"
PASSPHRASE_FILE = REPO / "dev" / "secrets" / ".vault-passphrase"
PASSPHRASE_ENV = "AIRCLONE_VAULT_PASSPHRASE"

MAGIC = b"ACVAULT1"
SALT_BYTES = 16
IV_BYTES = 12
TAG_BYTES = 16
KEY_BYTES = 32

# N=2^16 costs ~64 MiB and a noticeable fraction of a second. That is the point.
SCRYPT_N = 1 << 16
SCRYPT_R = 8
SCRYPT_P = 1
SCRYPT_MAXMEM = 256 * 1024 * 1024


def die(message: str) -> "NoReturn":  # type: ignore[valid-type]
    sys.exit(f"vault: {message}")


def rel(path: Path) -> str:
    """Repo-relative, POSIX-separated - stable in output across platforms."""
    try:
        return path.resolve().relative_to(REPO).as_posix()
    except ValueError:
        return str(path)


def passphrase() -> str:
    """Env var wins, then the gitignored file. Never prompts.

    A prompt would be worse than useless here: it invites someone to paste a
    passphrase into a shared terminal transcript.
    """
    from_env = os.environ.get(PASSPHRASE_ENV, "").strip()
    if from_env:
        return from_env
    if PASSPHRASE_FILE.exists():
        value = PASSPHRASE_FILE.read_text(encoding="utf-8").strip()
        if value:
            return value
    die(
        f"no passphrase. Set {PASSPHRASE_ENV}, or create {rel(PASSPHRASE_FILE)}.\n"
        "  Run 'python tool/vault.py init' if this vault does not exist yet.\n"
        "  If it DOES exist, get the passphrase from the password manager - there\n"
        "  is no recovery path, and any recovery path would also be a bypass."
    )


def derive(secret: str, salt: bytes) -> bytes:
    return hashlib.scrypt(
        secret.encode("utf-8"),
        salt=salt,
        n=SCRYPT_N,
        r=SCRYPT_R,
        p=SCRYPT_P,
        dklen=KEY_BYTES,
        maxmem=SCRYPT_MAXMEM,
    )


def note_files() -> list[Path]:
    """Every file under notes/, sorted, skipping junk that should never lock."""
    if not NOTES_DIR.exists():
        return []
    skip = {".DS_Store", "Thumbs.db"}
    return sorted(
        p
        for p in NOTES_DIR.rglob("*")
        if p.is_file() and p.name not in skip and ".git" not in p.parts
    )


def cmd_init(_: argparse.Namespace) -> None:
    """Generate the passphrase. Refuses to overwrite - that would orphan the vault."""
    if PASSPHRASE_FILE.exists() and PASSPHRASE_FILE.read_text(encoding="utf-8").strip():
        die(
            f"a passphrase already exists at {rel(PASSPHRASE_FILE)}.\n"
            "  Refusing to overwrite it: doing so would make the current vault\n"
            "  permanently unreadable."
        )
    # 32 bytes of entropy, base64url. Long enough that scrypt is not the last
    # line of defence.
    value = base64.urlsafe_b64encode(secrets.token_bytes(32)).decode("ascii").rstrip("=")
    PASSPHRASE_FILE.parent.mkdir(parents=True, exist_ok=True)
    PASSPHRASE_FILE.write_text(value + "\n", encoding="utf-8")
    print(f"wrote a new 256-bit passphrase to {rel(PASSPHRASE_FILE)}")
    print("")
    print("  PUT A COPY IN THE PASSWORD MANAGER NOW, and share it with")
    print("  collaborators the same way. There is no recovery path.")


def cmd_lock(_: argparse.Namespace) -> None:
    files = note_files()
    if not files:
        die(f"nothing to lock: {rel(NOTES_DIR)} is empty or missing")

    manifest = {
        p.relative_to(NOTES_DIR).as_posix(): base64.b64encode(p.read_bytes()).decode("ascii")
        for p in files
    }
    payload = json.dumps(
        {"files": manifest, "lockedAt": datetime.now(timezone.utc).isoformat()},
        separators=(",", ":"),
    ).encode("utf-8")

    salt = secrets.token_bytes(SALT_BYTES)
    iv = secrets.token_bytes(IV_BYTES)
    sealed = AESGCM(derive(passphrase(), salt)).encrypt(iv, payload, None)
    # cryptography appends the tag; split it out so the layout matches the
    # header-then-tag-then-body shape the reader expects.
    body, tag = sealed[:-TAG_BYTES], sealed[-TAG_BYTES:]

    # The header is authenticated implicitly: a changed salt or IV yields a
    # failed tag check, because the key and nonce would both be wrong.
    VAULT_DIR.mkdir(parents=True, exist_ok=True)
    BLOB.write_bytes(MAGIC + salt + iv + tag + body)

    print(f"locked {len(files)} file(s)")
    for name in sorted(manifest):
        print(f"    {name}")
    size = BLOB.stat().st_size / 1024
    print(f"  {rel(BLOB)}  ({size:.1f} KiB) - COMMIT THIS")


def cmd_unlock(_: argparse.Namespace) -> None:
    if not BLOB.exists():
        die(f"no vault at {rel(BLOB)}")
    blob = BLOB.read_bytes()
    if blob[: len(MAGIC)] != MAGIC:
        die("not a vault file, or a newer format")

    at = len(MAGIC)
    salt = blob[at : at + SALT_BYTES]
    at += SALT_BYTES
    iv = blob[at : at + IV_BYTES]
    at += IV_BYTES
    tag = blob[at : at + TAG_BYTES]
    at += TAG_BYTES
    body = blob[at:]

    try:
        plain = AESGCM(derive(passphrase(), salt)).decrypt(iv, body + tag, None)
    except Exception:
        die(
            "could not decrypt. Either the passphrase is wrong or vault.enc was\n"
            "  modified. AES-GCM cannot tell you which, and both mean do not trust it."
        )

    data = json.loads(plain.decode("utf-8"))
    files = data.get("files", {})

    # Replace wholesale: a stale file left behind from a previous unlock would
    # silently get re-locked into the vault as if it were current.
    if NOTES_DIR.exists():
        shutil.rmtree(NOTES_DIR)
    for name, b64 in files.items():
        target = (NOTES_DIR / name).resolve()
        # A crafted manifest must not be able to write outside notes/.
        if not str(target).startswith(str(NOTES_DIR.resolve())):
            die(f"refusing path outside the vault: {name}")
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(base64.b64decode(b64))

    print(f"unlocked {len(files)} file(s) to {rel(NOTES_DIR)}")
    print(f"  locked at {data.get('lockedAt', 'unknown')}")
    print("")
    print("  Edit, then 'python tool/vault.py lock' and commit vault.enc.")
    print("  An unlocked edit that is never re-locked is lost.")


def cmd_status(_: argparse.Namespace) -> None:
    """Peek without decrypting - safe to run with no passphrase at all."""
    if BLOB.exists():
        size = BLOB.stat().st_size / 1024
        print(f"vault:  {rel(BLOB)}  ({size:.1f} KiB)")
        header_ok = BLOB.read_bytes()[: len(MAGIC)] == MAGIC
        print(f"format: {'ok' if header_ok else 'UNRECOGNISED - wrong file?'}")
    else:
        print(f"vault:  absent ({rel(BLOB)})")

    have_env = bool(os.environ.get(PASSPHRASE_ENV, "").strip())
    have_file = PASSPHRASE_FILE.exists() and bool(
        PASSPHRASE_FILE.read_text(encoding="utf-8").strip()
    )
    source = (
        f"{PASSPHRASE_ENV} (env)"
        if have_env
        else rel(PASSPHRASE_FILE) if have_file else "NONE - cannot unlock"
    )
    print(f"passphrase: {source}")

    files = note_files()
    if files:
        print(f"unlocked:   {len(files)} file(s) in {rel(NOTES_DIR)}")
        for p in files:
            print(f"    {p.relative_to(NOTES_DIR).as_posix()}")
        print("")
        print("  Re-lock before committing, or these edits are not in the vault.")
    else:
        print(f"unlocked:   none ({rel(NOTES_DIR)} empty or missing)")


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="vault.py", description="Encrypted notes vault for sensitive working notes."
    )
    sub = parser.add_subparsers(dest="command", required=True)
    for name, fn, help_text in (
        ("init", cmd_init, "generate the passphrase (once, ever)"),
        ("status", cmd_status, "what is in the vault, without decrypting"),
        ("unlock", cmd_unlock, "vault.enc -> notes/"),
        ("lock", cmd_lock, "notes/ -> vault.enc"),
    ):
        sub.add_parser(name, help=help_text).set_defaults(func=fn)
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
