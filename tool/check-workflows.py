#!/usr/bin/env python3
"""Validate .github/workflows/*.yml for the things GitHub rejects and nothing else catches.

GitHub's own parser is the only authority on a workflow file, and it reports a
bad one badly: the run shows up on the push that introduced it, triggered by
`push` even when the workflow is dispatch-only, named after the file PATH rather
than its `name:`, with no logs and no annotations reachable by API. Meanwhile
`yaml.safe_load` says the file is fine - it is valid YAML, just not a valid
workflow. So a local YAML parse proves nothing, and the feedback loop is a push.

Two checks, both for defects this repo has actually shipped:

1. EMPTY EXPRESSION - `${{ }}` with nothing in it. GitHub template-expands a
   `run:` block BEFORE any shell sees it, so the sequence is parsed wherever it
   appears, comments included, and an empty one invalidates the whole file.
   This happened three times in one day, twice inside a comment explaining why
   a free-form input must not be interpolated.

2. RAW INTERPOLATION OF A FREE-FORM INPUT into a `run:` block. `${{ inputs.x }}`
   splices the dispatch value into the shell verbatim, so a value like
   `1.2.3"; curl ... | sh; #` executes on the runner. Values from `choice` and
   `boolean` inputs cannot carry a payload and are allowed; `string` inputs must
   travel through `env:` and be quoted.

Exit 1 on any finding. Dependency-free apart from PyYAML, which CI already has.
"""
from __future__ import annotations

import glob
import io
import os
import re
import sys

import yaml

WF = os.path.join(".github", "workflows", "*.yml")
EXPR = re.compile(r"\$\{\{(.*?)\}\}", re.S)
INPUT_REF = re.compile(r"\$\{\{\s*inputs\.([A-Za-z0-9_-]+)[^}]*\}\}")


def free_form_inputs(doc) -> set[str]:
    """Input names whose value is an arbitrary string the dispatcher controls."""
    try:
        # PyYAML turns the `on:` key into the boolean True.
        on = doc.get(True, doc.get("on", {})) or {}
        inputs = (on.get("workflow_dispatch") or {}).get("inputs") or {}
    except AttributeError:
        return set()
    return {n for n, spec in inputs.items()
            if (spec or {}).get("type", "string") not in ("choice", "boolean")}


def run_blocks(text: str):
    """(line, body) for each `run:` block scalar, by indentation."""
    lines = text.split("\n")
    for i, line in enumerate(lines):
        m = re.match(r"^(\s*)-?\s*run:\s*[|>][-+]?\s*$", line)
        if not m:
            continue
        indent = len(m.group(1))
        body = []
        for nxt in lines[i + 1:]:
            if nxt.strip() and len(nxt) - len(nxt.lstrip()) <= indent:
                break
            body.append(nxt)
        yield i + 1, "\n".join(body)


def main() -> int:
    findings = []
    files = sorted(glob.glob(WF))
    for f in files:
        text = io.open(f, encoding="utf-8").read()
        for m in EXPR.finditer(text):
            if not m.group(1).strip():
                findings.append((f, text[:m.start()].count("\n") + 1,
                                 "empty ${{ }} expression - invalidates the whole file"))
        try:
            doc = yaml.safe_load(text)
        except yaml.YAMLError as exc:
            findings.append((f, 0, f"not valid YAML: {exc}"))
            continue
        loose = free_form_inputs(doc)
        if not loose:
            continue
        for start, body in run_blocks(text):
            for m in INPUT_REF.finditer(body):
                if m.group(1) in loose:
                    findings.append((
                        f, start + body[:m.start()].count("\n"),
                        f"free-form input `{m.group(1)}` interpolated into a run: block "
                        f"- pass it through env: and quote it"))

    for f, line, msg in findings:
        loc = f"{f}:{line}" if line else f
        print(f"  {loc}  {msg}")
    print(f"\nworkflows {len(files)} | findings {len(findings)}")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
