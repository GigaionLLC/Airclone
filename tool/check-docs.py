#!/usr/bin/env python3
"""Documentation linter for the Airclone doc library.

Checks the three failure modes that are invisible to someone who only opens the hub:

  1. BROKEN LINKS  - a relative markdown link whose target does not exist on disk.
                     Includes links into app/ source, which rot when files move.
  2. ORPHANS       - a doc no other doc links to. Unreachable by navigation, so a
                     low-context agent can only find it by grep.
  3. DOC SHAPE     - a wiki/core/ doc missing the shape required by
                     wiki/core/17-docs-blueprint.md section 3 (H1, purpose,
                     "When to read this", "Related").

Unlike the inline snippets this replaces, fenced code blocks are stripped first, so
link *examples* inside a doc are not reported as broken.

Usage (from the repo root):
    python tool/check-docs.py            # report; exit 1 only on broken links
    python tool/check-docs.py --strict   # exit 1 on any finding (orphans, shape too)
    python tool/check-docs.py --quiet    # totals only

Exit codes: 0 clean, 1 findings. Safe to wire into CI later; nothing here is
platform-specific and it needs no third-party packages.
"""
from __future__ import annotations

import os
import re
import sys
from urllib.parse import unquote

# Roots scanned for docs, plus individual root-level files.
DOC_ROOTS = ("wiki", "dev", "docs")
ROOT_FILES = ("AGENT.md", "README.md", "DESIGN.md", "HOW-TO.md", "PRIVACY.md")

# Excluded from the ORPHAN check only: these are addressed by tag or by directory,
# not linked individually, so "nothing links to it" is expected and fine.
ORPHAN_EXEMPT = (
    "dev/releases/",
    "dev/archive-plans/",
    "docs/store/play/whats-new-",
)

# Docs required to follow the blueprint shape.
SHAPE_SCOPE = "wiki/core/"

LINK = re.compile(r"\[([^\]]*)\]\(([^)]+)\)")
FENCE = re.compile(r"```.*?```", re.S)
INLINE_CODE = re.compile(r"`[^`\n]*`")
RELATED_HEADING = re.compile(r"^#{2,3}\s.*Related", re.M)
H1 = re.compile(r"^#\s+\S", re.M)


def strip_code(text: str) -> str:
    """Remove fenced blocks and inline code so examples are not linted as links."""
    return INLINE_CODE.sub("", FENCE.sub("", text))


def collect(repo: str) -> list[str]:
    found: list[str] = []
    for root in DOC_ROOTS:
        base = os.path.join(repo, root)
        if not os.path.isdir(base):
            continue
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = [d for d in dirnames if d not in (".git", "node_modules")]
            for fn in filenames:
                if fn.endswith(".md"):
                    rel = os.path.relpath(os.path.join(dirpath, fn), repo)
                    found.append(rel.replace("\\", "/"))
    for fn in ROOT_FILES:
        if os.path.isfile(os.path.join(repo, fn)):
            found.append(fn)
    return sorted(set(found))


def main() -> int:
    strict = "--strict" in sys.argv
    quiet = "--quiet" in sys.argv
    repo = os.path.abspath(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

    docs = collect(repo)
    broken: list[tuple[str, str, str]] = []
    inbound: dict[str, set[str]] = {}
    shape: list[tuple[str, list[str]]] = []

    for rel in docs:
        path = os.path.join(repo, rel)
        try:
            raw = open(path, encoding="utf-8").read()
        except OSError as exc:
            broken.append((rel, "<unreadable>", str(exc)))
            continue

        body = strip_code(raw)
        for label, target in LINK.findall(body):
            t = target.strip()
            if t.startswith(("http://", "https://", "mailto:", "#")):
                continue
            t = unquote(t.split("#")[0].split("?")[0]).strip()
            if not t:
                continue
            resolved = os.path.normpath(os.path.join(os.path.dirname(path), t))
            key = os.path.relpath(resolved, repo).replace("\\", "/")
            inbound.setdefault(key, set()).add(rel)
            if not os.path.exists(resolved):
                broken.append((rel, t, label[:40]))

        if rel.startswith(SHAPE_SCOPE):
            missing = []
            if not H1.search(raw):
                missing.append("H1 title")
            if "When to read this" not in raw:
                missing.append('"When to read this"')
            if not RELATED_HEADING.search(raw):
                missing.append("Related section")
            if missing:
                shape.append((rel, missing))

    orphans = [
        d for d in docs
        if d not in inbound
        and not d.startswith(ORPHAN_EXEMPT)
        and d not in ROOT_FILES
    ]

    if not quiet:
        print("=== BROKEN LINKS ===")
        print("  none" if not broken else "")
        for src, target, label in broken:
            print(f"  {src}  ->  {target}   [{label}]")

        print("\n=== ORPHANS (no doc links to these) ===")
        print("  none" if not orphans else "")
        for o in orphans:
            print(f"  {o}")

        print(f"\n=== DOC SHAPE ({SHAPE_SCOPE}, see 17-docs-blueprint.md section 3) ===")
        print("  all conform" if not shape else "")
        for rel, missing in shape:
            print(f"  {rel}  missing: {', '.join(missing)}")

    print(
        f"\ndocs {len(docs)} | broken {len(broken)} | orphans {len(orphans)} "
        f"| shape violations {len(shape)}"
    )

    if broken:
        return 1
    if strict and (orphans or shape):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
