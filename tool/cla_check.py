#!/usr/bin/env python3
"""Contributor Agreement (CLA) check for pull requests - run by .github/workflows/cla.yml.

Every GitHub account that authored a commit in a pull request, plus the account
that opened it, must have signed CLA.md before the pull request merges. This
script is the whole mechanism: it reads the event GitHub hands the workflow,
works out who still has to sign, records new signatures, and reports the result
as the `Airclone CLA` commit status, which a branch ruleset can require.

Why our own and not a ready-made action: the widely used third-party CLA action
was archived in March 2026, and a pull_request_target workflow holds a write
token - not something to hand to code nobody patches any more. This file uses the standard library only, and it never checks out or
executes anything from the pull request.

THE LEDGER. Signatures live in signatures/cla.json on the `cla-signatures`
branch, an orphan branch that holds nothing else, so recording one never pushes
to main, never triggers CI, and is untouched by any protection on main. Each
entry keeps the login and the numeric account id (a login can be renamed, an id
cannot - the id is what is matched), the pull request and comment that carried
the signature, the comment's timestamp, the CLA version signed, and a permalink
to CLA.md at the default-branch commit the run started from - the exact text in
force when they signed. No email addresses. Bumping CLA_VERSION in the workflow
asks everyone to sign again.

TWO COMMENTS DO ANYTHING. The signing phrase (SIGN_PHRASE) records the
commenter if they are one of the pull request's unsigned authors, then
re-evaluates. `recheck` only re-evaluates, for an author who signed on a
different pull request or has since linked a commit email to their account.
Any other comment is ignored before a single API call.

KNOWN GAP, for reviewers: `Co-authored-by:` trailers are not checked - they
carry an email, not an account. A human co-author named in one has to sign too;
check for them by eye.

Environment: GITHUB_TOKEN, GITHUB_REPOSITORY, GITHUB_EVENT_NAME and
GITHUB_EVENT_PATH and GITHUB_SHA (all set by Actions), CLA_VERSION, and
CLA_EXEMPT - a comma-separated list of numeric account ids that never sign, the
maintainers whose work Gigaion already owns. Ids, not logins: a login someone
renames away from can be registered by anyone, and would inherit the exemption.
Bot accounts are always exempt.

Tests: tool/test_cla_check.py, run by the docs job in ci.yml.
"""
from __future__ import annotations

import base64
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

API = os.environ.get("GITHUB_API_URL", "https://api.github.com")
SERVER = os.environ.get("GITHUB_SERVER_URL", "https://github.com")

BRANCH = "cla-signatures"
LEDGER = "signatures/cla.json"
STATUS_CONTEXT = "Airclone CLA"
MARKER = "<!-- airclone-cla -->"
SIGN_PHRASE = "I have read the Airclone CLA and I hereby sign it."
RECHECK = "recheck"
# GitHub lists at most 250 commits for a pull request. Past that, authors would
# go unseen, so the check fails rather than pass on a partial list.
MAX_COMMITS = 250

BRANCH_README = """# CLA signatures

This branch holds only the signature ledger for the Airclone Contributor
License Agreement (CLA.md on the default branch). `tool/cla_check.py` writes
it from the CLA workflow; do not merge this branch anywhere.
"""

# Set by configure() from the environment; tests set them directly.
REPO = ""
CLA_VERSION = ""
TEXT_SHA = ""  # the default-branch commit whose CLA.md a signature agrees to
EXEMPT: set[int] = set()


class ApiError(Exception):
    def __init__(self, status: int, body: str):
        super().__init__(f"HTTP {status}: {body[:300]}")
        self.status = status


def api(method: str, path: str, body=None):
    """One GitHub REST call. Returns the parsed JSON, or None for an empty body."""
    headers = {
        "Authorization": "Bearer " + os.environ["GITHUB_TOKEN"],
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "airclone-cla-check",
    }
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(API + path, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read()
    except urllib.error.HTTPError as e:
        raise ApiError(e.code, e.read().decode("utf-8", "replace")) from None
    return json.loads(raw) if raw else None


def paged(path: str) -> list:
    out, page = [], 1
    while True:
        batch = api("GET", f"{path}?per_page=100&page={page}")
        out.extend(batch)
        if len(batch) < 100:
            return out
        page += 1


def normalise(text: str) -> str:
    """Lower-cased, quote markers and backticks dropped, whitespace collapsed, final full stop dropped.

    People copy the phrase out of the bot's comment, so a leading `>` or the
    fence around a code block must not make a genuine signature miss. Anything
    else in the comment still does - the phrase has to stand on its own.
    """
    lines = [re.sub(r"^\s*>\s?", "", ln) for ln in (text or "").splitlines()]
    flat = " ".join(" ".join(lines).replace("`", " ").split()).lower()
    return flat.rstrip(".").strip()


def is_exempt(user: dict) -> bool:
    # A human login cannot contain brackets, so "[bot]" cannot be claimed by a person.
    login = (user.get("login") or "").lower()
    return user.get("type") == "Bot" or login.endswith("[bot]") or user.get("id") in EXEMPT


def authors(pr: dict) -> tuple[dict[int, str], list[str]]:
    """({account id: login} of everyone who must sign, [short SHAs of commits no account authored])."""
    people: dict[int, str] = {}
    unlinked: list[str] = []
    candidates = [pr["user"]]
    for c in paged(f"/repos/{REPO}/pulls/{pr['number']}/commits"):
        if c.get("author"):
            candidates.append(c["author"])
        else:
            unlinked.append(c["sha"][:7])
    for u in candidates:
        if not is_exempt(u):
            people[u["id"]] = u["login"]
    return people, unlinked


def read_ledger() -> tuple[list, str | None]:
    """(entries, blob sha). A missing branch and a missing file both read as empty."""
    try:
        f = api("GET", f"/repos/{REPO}/contents/{LEDGER}?ref={BRANCH}")
    except ApiError as e:
        if e.status == 404:
            return [], None
        raise
    return json.loads(base64.b64decode(f["content"])), f["sha"]


def has_signed(ledger: list, account_id: int) -> bool:
    return any(s.get("id") == account_id and s.get("cla_version") == CLA_VERSION for s in ledger)


def ensure_branch() -> None:
    """Create the orphan ledger branch the first time anyone signs."""
    try:
        api("GET", f"/repos/{REPO}/git/ref/heads/{BRANCH}")
        return
    except ApiError as e:
        if e.status != 404:
            raise
    tree = api("POST", f"/repos/{REPO}/git/trees", {"tree": [
        {"path": "README.md", "mode": "100644", "type": "blob", "content": BRANCH_README}]})
    commit = api("POST", f"/repos/{REPO}/git/commits", {
        "message": "cla: start the signature ledger", "tree": tree["sha"], "parents": []})
    try:
        api("POST", f"/repos/{REPO}/git/refs", {"ref": f"refs/heads/{BRANCH}", "sha": commit["sha"]})
    except ApiError as e:
        if e.status != 422:  # 422: another run created it first, which is fine
            raise


def record(user: dict, pr_number: int, comment: dict) -> None:
    """Append one signature to the ledger, unless it is already there."""
    ensure_branch()
    for attempt in range(5):
        ledger, sha = read_ledger()
        if has_signed(ledger, user["id"]):
            return
        ledger.append({
            "login": user["login"],
            "id": user["id"],
            "cla_version": CLA_VERSION,
            "pull_request": pr_number,
            "comment_id": comment["id"],
            "comment_url": comment["html_url"],
            "signed_at": comment["created_at"],
            "cla_text": f"{SERVER}/{REPO}/blob/{TEXT_SHA}/CLA.md",
        })
        body = {
            "message": f"cla: {user['login']} signs v{CLA_VERSION} (#{pr_number})",
            "content": base64.b64encode((json.dumps(ledger, indent=2) + "\n").encode()).decode(),
            "branch": BRANCH,
        }
        if sha:
            body["sha"] = sha
        try:
            api("PUT", f"/repos/{REPO}/contents/{LEDGER}", body)
            return
        except ApiError as e:
            # 409: the file changed since it was read - a signature landed at the
            # same moment. 422: it was created since, so a sha is now required.
            # Either way, read it again and retry.
            if e.status not in (409, 422):
                raise
            time.sleep(2 * (attempt + 1))
    raise RuntimeError("could not record the signature after 5 attempts")


def set_status(sha: str, ok: bool, description: str, url: str) -> None:
    api("POST", f"/repos/{REPO}/statuses/{sha}", {
        "state": "success" if ok else "failure",
        "context": STATUS_CONTEXT,
        "description": description[:140],
        "target_url": url,
    })


def upsert_comment(pr_number: int, body: str, create: bool) -> None:
    """Keep ONE CLA comment per pull request: edit it in place, or post it if `create`."""
    for c in paged(f"/repos/{REPO}/issues/{pr_number}/comments"):
        if MARKER in (c.get("body") or "") and (c.get("user") or {}).get("type") == "Bot":
            if c["body"] != body:
                api("PATCH", f"/repos/{REPO}/issues/comments/{c['id']}", {"body": body})
            return
    if create:
        api("POST", f"/repos/{REPO}/issues/{pr_number}/comments", {"body": body})


def links_for(event: dict) -> dict[str, str]:
    base = f"{SERVER}/{REPO}/blob/{event['repository']['default_branch']}"
    return {
        "cla": f"{base}/CLA.md",
        "corporate": f"{base}/CLA-CORPORATE.md",
        "why": f"{base}/CONTRIBUTING.md#the-contributor-agreement",
    }


def unsigned_body(missing: list[str], unlinked: list[str], links: dict[str, str]) -> str:
    # Only logins (GitHub restricts them to letters, digits and hyphens) and
    # SHAs go into this comment - never a commit author's free-text name.
    parts = [
        MARKER,
        "### Airclone Contributor Agreement",
        "",
        "Thank you for the pull request. Before it can be merged, everyone who wrote a commit in "
        f"it needs to sign the [Airclone Contributor Agreement]({links['cla']}) (version "
        f"{CLA_VERSION}). It transfers the copyright in your contribution to Gigaion, LLC, and "
        "gives you back a license to use your own work however you like. You sign once, and it "
        f"covers every pull request after this one. [Why we ask]({links['why']}).",
    ]
    if missing:
        parts += [
            "",
            "**Still to sign:** " + ", ".join("@" + m for m in missing),
            "",
            "To sign, post this as a comment on this pull request, on its own:",
            "",
            "```",
            SIGN_PHRASE,
            "```",
        ]
    if unlinked:
        parts += [
            "",
            "**Commits with no GitHub account behind them:** "
            + ", ".join(f"`{s}`" for s in unlinked),
            "",
            "Their author email is not linked to any GitHub account, so nobody can sign for them. "
            "Add that email to your account (Settings > Emails) and comment `recheck`, or rewrite "
            "the commits with an email that is linked and push them again.",
        ]
    parts += [
        "",
        "Contributing as part of your job? Your employer may need to sign the "
        f"[corporate agreement]({links['corporate']}) too. If this comment looks out of date, "
        f"comment `{RECHECK}`.",
    ]
    return "\n".join(parts)


def signed_body(links: dict[str, str]) -> str:
    return "\n".join([
        MARKER,
        "### Airclone Contributor Agreement",
        "",
        f"Everyone who wrote a commit in this pull request has signed the [Airclone CLA]({links['cla']}). "
        "Thank you.",
    ])


def evaluate(pr: dict, links: dict[str, str], sign_comment: dict | None = None) -> None:
    number, sha = pr["number"], pr["head"]["sha"]
    if pr.get("commits", 0) > MAX_COMMITS:
        set_status(sha, False, f"Over {MAX_COMMITS} commits, too many to check - please squash", links["cla"])
        return
    people, unlinked = authors(pr)
    if sign_comment and sign_comment["user"]["id"] in people:
        record(sign_comment["user"], number, sign_comment)
    ledger, _ = read_ledger()
    missing = sorted((login for uid, login in people.items() if not has_signed(ledger, uid)),
                     key=str.lower)
    if not missing and not unlinked:
        set_status(sha, True, "Every author has signed the CLA", links["cla"])
        upsert_comment(number, signed_body(links), create=False)
        return
    if missing:
        what = f"Waiting on {len(missing)} author(s) to sign the CLA"
    else:
        what = f"{len(unlinked)} commit(s) have no GitHub account to sign for them"
    set_status(sha, False, what, links["cla"])
    upsert_comment(number, unsigned_body(missing, unlinked, links), create=True)


def run(event_name: str, event: dict) -> None:
    links = links_for(event)
    if event_name == "pull_request_target":
        evaluate(event["pull_request"], links)
        return
    if event_name != "issue_comment" or not event.get("issue", {}).get("pull_request"):
        return
    comment = event["comment"]
    said = normalise(comment.get("body") or "")
    signing = said == normalise(SIGN_PHRASE)
    if not signing and said != RECHECK:
        return
    pr = api("GET", f"/repos/{REPO}/pulls/{event['issue']['number']}")
    if pr["state"] != "open":
        return
    evaluate(pr, links, comment if signing else None)


def configure() -> None:
    global REPO, CLA_VERSION, TEXT_SHA, EXEMPT
    REPO = os.environ["GITHUB_REPOSITORY"]
    TEXT_SHA = os.environ["GITHUB_SHA"]
    CLA_VERSION = os.environ["CLA_VERSION"].strip()
    if not CLA_VERSION:
        raise SystemExit("CLA_VERSION is empty")
    # int() raises on a login pasted in by mistake, which fails the run loudly
    # instead of silently exempting nobody.
    EXEMPT = {int(s) for s in os.environ.get("CLA_EXEMPT", "").split(",") if s.strip()}


def main() -> int:
    configure()
    with open(os.environ["GITHUB_EVENT_PATH"], encoding="utf-8") as f:
        event = json.load(f)
    run(os.environ["GITHUB_EVENT_NAME"], event)
    return 0


if __name__ == "__main__":
    sys.exit(main())
