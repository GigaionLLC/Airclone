#!/usr/bin/env python3
"""List the carve-out areas a change touches, before it merges.

    python tool/carveout_paths.py                       # this branch vs origin/main
    python tool/carveout_paths.py --base origin/main
    gh pr diff 123 > /tmp/pr123.diff
    python tool/carveout_paths.py --diff-file /tmp/pr123.diff   # an outside PR, unchecked-out

A carve-out is work that does not merge on CI alone (dev/coordinator-playbook.md,
"Who may do what"):

  SECURITY  needs a written security review before merge: the web UI server and
            its rc allowlist and guards, the console denylist and redaction, the
            updater and its trust checks, how rcd is started, OAuth, log
            redaction, archive extraction, config encryption.
  SIGNING   signing keys, certificates, repository secrets, the vault. Also a
            workflow line that mentions `secrets.` or a signing step.
  MONEY     prices and the price checks: Jake only.

Read-only: it only reads git or the diff file. Exit code: 0 = nothing found,
3 = at least one carve-out (STOP: follow the playbook before merging),
2 = bad usage or git failed. Output is ASCII only (AGENT.md rule 12).

A clean result is not a review. It only says none of the listed paths or
patterns changed; a new file elsewhere that does something risky is still
yours to notice.
"""
from __future__ import annotations

import re
import subprocess
import sys

# (category, path prefix or exact path). A prefix ends with "/".
PATHS: list[tuple[str, str]] = [
    ("SECURITY", "app/lib/src/webui/"),
    ("SECURITY", "app/lib/src/update/"),
    ("SECURITY", "app/lib/src/headless/update_cli.dart"),
    ("SECURITY", "app/lib/src/rclone/rclone_engine.dart"),
    ("SECURITY", "app/lib/src/state/console/rclone_commands.dart"),
    ("SECURITY", "app/lib/src/state/console/console_redaction.dart"),
    ("SECURITY", "app/lib/src/state/console/console_rc_translate.dart"),
    ("SECURITY", "app/lib/src/state/archive_service.dart"),
    ("SECURITY", "app/lib/src/state/archive_command.dart"),
    ("SECURITY", "app/lib/src/state/config_encryption.dart"),
    ("SECURITY", "app/lib/src/state/config_password_vault.dart"),
    ("SECURITY", "app/lib/src/state/cache_crypto.dart"),
    ("SECURITY", "app/lib/src/state/biometric_unlock.dart"),
    ("SECURITY", "app/lib/src/state/engine_flags.dart"),
    ("SECURITY", "packages/airclone_rc/lib/src/http_rclone_client.dart"),
    ("SECURITY", "packages/airclone_rc/lib/src/remote_rclone_client.dart"),
    ("SECURITY", "packages/airclone_rc/lib/src/oauth_flow.dart"),
    ("SECURITY", "packages/airclone_rc/lib/src/log_redaction.dart"),
    ("SECURITY", "packages/airclone_rc/lib/src/librclone_object_server.dart"),
    ("SECURITY", "tool/cla_check.py"),
    # This checker and its tests: weakening them weakens every merge after.
    ("SECURITY", "tool/carveout_paths.py"),
    ("SECURITY", "tool/test_carveout_paths.py"),
    ("SECURITY", ".github/workflows/cla.yml"),
    ("SECURITY", "docker/"),
    ("SIGNING", "dev/secrets/"),
    ("SIGNING", "dev/vault/"),
    ("SIGNING", "dev/update/"),
    ("SIGNING", "tool/vault.py"),
    ("SIGNING", "tool/asc_ios_signing.py"),
    ("SIGNING", ".github/workflows/apple-revoke-cert.yml"),
    ("MONEY", "tool/store_submit.py"),
    ("MONEY", "tool/test_store_submit.py"),
    ("MONEY", "tool/msstore_price.py"),
    ("MONEY", "tool/test_msstore_price.py"),
]

# Patterns looked for in changed lines (added or removed), per path prefix.
LINE_RULES: list[tuple[str, str, re.Pattern[str]]] = [
    ("SIGNING", ".github/workflows/",
     re.compile(r"secrets\.|codesign|signtool|keychain|provisioning|\.p8\b|\.p12\b|minisign", re.I)),
    ("MONEY", ".github/workflows/", re.compile(r"price|tier\d|BASE_PRICE_TIER", re.I)),
    ("MONEY", "tool/", re.compile(r"BASE_PRICE_TIER|priceId|\bTier\d{3,4}\b")),
]


def parse_diff(text: str) -> dict[str, list[str]]:
    """{path: changed lines} from a unified diff (git diff or gh pr diff)."""
    files: dict[str, list[str]] = {}
    current = None
    for line in text.splitlines():
        if line.startswith("diff --git "):
            m = re.match(r"diff --git a/(\S+) b/(\S+)$", line)
            if m:
                current = m.group(2)
                files.setdefault(current, [])
                if m.group(1) != m.group(2):  # a rename touches both paths
                    files.setdefault(m.group(1), [])
            else:
                # Quoted (non-ASCII) or spaced paths: fail closed, never skip.
                current = UNPARSED + line[len("diff --git "):]
                files.setdefault(current, [])
        elif current is None or line.startswith(("+++", "---")):
            continue
        elif line.startswith(("+", "-")):
            files[current].append(line[1:])
    return files


# Prefix for a file header the parser could not split. Always a finding.
UNPARSED = "?unparsed: "

# Files whose own text is the patterns: they are covered by PATHS instead.
LINE_RULE_EXEMPT = {"tool/carveout_paths.py", "tool/test_carveout_paths.py"}


def _is_comment(path: str, line: str) -> bool:
    """A YAML comment line in a workflow. A removed price check still shows up
    as its original (non-comment) line, so skipping comments loses nothing."""
    return path.startswith(".github/workflows/") and line.lstrip().startswith("#")


def _matches(path: str, rule: str) -> bool:
    return path.startswith(rule) if rule.endswith("/") else path == rule


def findings(files: dict[str, list[str]]) -> list[tuple[str, str, str]]:
    """Sorted, de-duplicated (category, path, why)."""
    out: set[tuple[str, str, str]] = set()
    for path, lines in files.items():
        if path.startswith(UNPARSED):
            out.add(("SECURITY", path, "path not parsed: check it by hand"))
            continue
        for cat, rule in PATHS:
            if _matches(path, rule):
                out.add((cat, path, "path"))
        for cat, prefix, pattern in LINE_RULES:
            if path in LINE_RULE_EXEMPT or not path.startswith(prefix):
                continue
            if any(pattern.search(l) for l in lines if not _is_comment(path, l)):
                out.add((cat, path, "changed line matches " + cat.lower() + " pattern"))
    return sorted(out)


def say(text: str) -> None:
    """print, ASCII only: a path from a PR diff may hold any character (rule 12)."""
    print(text.encode("ascii", "backslashreplace").decode("ascii"))


def git_diff(base: str) -> str:
    out = subprocess.run(["git", "diff", "--no-color", "-M", base + "...HEAD"],
                         capture_output=True, text=True, encoding="utf-8", errors="replace")
    if out.returncode:
        raise RuntimeError("git diff %s...HEAD failed: %s" % (base, out.stderr.strip()))
    return out.stdout


def main(argv: list[str]) -> int:
    base, diff_file = "origin/main", None
    args = list(argv)
    while args:
        a = args.pop(0)
        if a in ("--base", "--diff-file") and args:
            if a == "--base":
                base = args.pop(0)
            else:
                diff_file = args.pop(0)
        else:
            print(__doc__)
            return 2
    try:
        if diff_file:
            with open(diff_file, encoding="utf-8", errors="replace") as f:
                text = f.read()
        else:
            text = git_diff(base)
    except (OSError, RuntimeError) as e:
        say("error: %s" % e)
        return 2
    files = parse_diff(text)
    found = findings(files)
    say("files changed: %d" % len(files))
    if not found:
        say("carve-outs: none (this is not a review; see the docstring)")
        return 0
    for cat, path, why in found:
        say("%-8s %s  (%s)" % (cat, path, why))
    cats = sorted({c for c, _, _ in found})
    say("STOP: carve-out(s) %s. Follow dev/coordinator-playbook.md step 3.9 before merging."
          % ", ".join(cats))
    return 3


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
