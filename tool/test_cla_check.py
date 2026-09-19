#!/usr/bin/env python3
"""Tests for tool/cla_check.py against an in-memory fake of the GitHub REST API.

The check runs from a pull_request_target workflow with a write token, and its
worst failure is silent: an unsigned author's pull request goes green. So every
path that decides pass or fail is covered here, including the ledger races.

Run from the repo root: python tool/test_cla_check.py
"""
from __future__ import annotations

import base64
import json
import os
import re
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cla_check  # noqa: E402

REPO = "GigaionLLC/Airclone"
MAINTAINER = {"login": "TheJakeBraun", "id": 210177983, "type": "User"}
ALICE = {"login": "alice", "id": 101, "type": "User"}
BOB = {"login": "bob", "id": 102, "type": "User"}
BOT = {"login": "github-actions[bot]", "id": 41898282, "type": "Bot"}


class FakeGitHub:
    """Just enough of the REST API for cla_check, with every write recorded."""

    def __init__(self):
        self.prs: dict[int, dict] = {}
        self.commits: dict[int, list] = {}
        self.comments: dict[int, list] = {}
        self.statuses: list[dict] = []
        self.branch = False
        self.ledger: bytes | None = None
        self.ledger_sha = 0
        self.put_conflicts = 0  # how many PUTs to reject with 409 first
        self.calls: list[tuple[str, str]] = []
        self.next_id = 1000

    def add_pr(self, number, user, commit_authors, state="open", commits=None):
        self.prs[number] = {
            "number": number, "user": user, "state": state,
            "head": {"sha": f"head{number}"},
            "commits": len(commit_authors) if commits is None else commits,
        }
        self.commits[number] = [{"sha": f"{number:03d}{i:037d}", "author": a}
                                for i, a in enumerate(commit_authors)]
        self.comments.setdefault(number, [])
        return self.prs[number]

    def ledger_entries(self):
        return json.loads(self.ledger) if self.ledger else []

    def __call__(self, method, path, body=None):
        self.calls.append((method, path))
        base = f"/repos/{REPO}"
        assert path.startswith(base), path
        p = path[len(base):]
        route = p.split("?")[0]

        if m := re.fullmatch(r"/pulls/(\d+)/commits", route):
            return self._page(self.commits[int(m[1])], p)
        if m := re.fullmatch(r"/pulls/(\d+)", route):
            return self.prs[int(m[1])]
        if m := re.fullmatch(r"/issues/(\d+)/comments", route):
            n = int(m[1])
            if method == "GET":
                return self._page(self.comments[n], p)
            self.next_id += 1
            self.comments[n].append({"id": self.next_id, "body": body["body"], "user": BOT})
            return self.comments[n][-1]
        if m := re.fullmatch(r"/issues/comments/(\d+)", route):
            for cs in self.comments.values():
                for c in cs:
                    if c["id"] == int(m[1]):
                        c["body"] = body["body"]
                        return c
            raise AssertionError("PATCH of an unknown comment")
        if m := re.fullmatch(r"/statuses/(\w+)", route):
            self.statuses.append({"sha": m[1], **body})
            return {}
        if route == f"/git/ref/heads/{cla_check.BRANCH}":
            if not self.branch:
                raise cla_check.ApiError(404, "Not Found")
            return {}
        if route == "/git/trees":
            assert body["tree"][0]["path"] == "README.md"
            return {"sha": "tree1"}
        if route == "/git/commits":
            assert body["parents"] == [], "the ledger branch must be an orphan"
            return {"sha": "commit1"}
        if route == "/git/refs":
            assert body["ref"] == f"refs/heads/{cla_check.BRANCH}"
            self.branch = True
            return {}
        if route == f"/contents/{cla_check.LEDGER}":
            if method == "GET":
                assert f"ref={cla_check.BRANCH}" in p
                if not self.branch or self.ledger is None:
                    raise cla_check.ApiError(404, "Not Found")
                return {"content": base64.b64encode(self.ledger).decode(), "sha": f"s{self.ledger_sha}"}
            assert body["branch"] == cla_check.BRANCH
            if not self.branch:
                raise cla_check.ApiError(404, "Branch not found")
            if self.put_conflicts:
                self.put_conflicts -= 1
                self.ledger_sha += 1  # someone else wrote in between
                raise cla_check.ApiError(409, "conflict")
            if self.ledger is not None and body.get("sha") != f"s{self.ledger_sha}":
                raise cla_check.ApiError(409, "sha mismatch")
            self.ledger = base64.b64decode(body["content"])
            self.ledger_sha += 1
            return {}
        raise AssertionError(f"unexpected call {method} {path}")

    @staticmethod
    def _page(items, p):
        page = int(re.search(r"[?&]page=(\d+)", p)[1])
        return items[(page - 1) * 100: page * 100]


def event_pr(pr):
    return {"pull_request": pr, "repository": {"default_branch": "main"}}


def event_comment(number, user, body, is_pr=True):
    issue = {"number": number}
    if is_pr:
        issue["pull_request"] = {"url": "x"}
    return {
        "issue": issue,
        "comment": {"id": 5000 + number, "user": user, "body": body,
                    "html_url": f"https://github.com/{REPO}/pull/{number}#c",
                    "created_at": "2026-09-19T12:00:00Z"},
        "repository": {"default_branch": "main"},
    }


class ClaCheckTest(unittest.TestCase):
    def setUp(self):
        self.gh = FakeGitHub()
        self._saved = (cla_check.api, cla_check.REPO, cla_check.CLA_VERSION, cla_check.EXEMPT,
                       cla_check.TEXT_SHA, cla_check.time.sleep)
        cla_check.api = self.gh
        cla_check.REPO = REPO
        cla_check.CLA_VERSION = "1.0"
        cla_check.TEXT_SHA = "c0ffee"
        cla_check.EXEMPT = {210177983}
        cla_check.time.sleep = lambda s: None

    def tearDown(self):
        (cla_check.api, cla_check.REPO, cla_check.CLA_VERSION, cla_check.EXEMPT,
         cla_check.TEXT_SHA, cla_check.time.sleep) = self._saved

    def last_status(self):
        return self.gh.statuses[-1]

    def cla_comments(self, n):
        return [c for c in self.gh.comments[n] if cla_check.MARKER in c["body"]]

    # -- the phrase ---------------------------------------------------------

    def test_phrase_matches_how_people_actually_paste_it(self):
        want = cla_check.normalise(cla_check.SIGN_PHRASE)
        for body in [
            cla_check.SIGN_PHRASE,
            "  I have read the Airclone CLA and I hereby sign it.  \n",
            "i have read the airclone cla and i hereby sign it",
            "> I have read the Airclone CLA and I hereby sign it.",
            "```\nI have read the Airclone CLA and I hereby sign it.\n```",
            "I have read the Airclone CLA\nand I hereby sign it.",
        ]:
            self.assertEqual(cla_check.normalise(body), want, body)

    def test_phrase_must_stand_on_its_own(self):
        want = cla_check.normalise(cla_check.SIGN_PHRASE)
        for body in [
            "",
            "I have read the Airclone CLA and I hereby sign it. Also, when is the next release?",
            "I have not read the Airclone CLA and I hereby sign it.",
            "Should I say 'I have read the Airclone CLA and I hereby sign it'?",
        ]:
            self.assertNotEqual(cla_check.normalise(body), want, body)

    # -- who has to sign ----------------------------------------------------

    def test_unsigned_contributor_fails_and_is_told_how_to_sign(self):
        pr = self.gh.add_pr(7, ALICE, [ALICE])
        cla_check.run("pull_request_target", event_pr(pr))
        st = self.last_status()
        self.assertEqual((st["sha"], st["state"], st["context"]), ("head7", "failure", "Airclone CLA"))
        [c] = self.cla_comments(7)
        self.assertIn("@alice", c["body"])
        self.assertIn(cla_check.SIGN_PHRASE, c["body"])
        self.assertIsNone(self.gh.ledger, "evaluating must not write the ledger")
        self.assertFalse(self.gh.branch)

    def test_signing_records_the_signature_and_turns_the_check_green(self):
        pr = self.gh.add_pr(7, ALICE, [ALICE])
        cla_check.run("pull_request_target", event_pr(pr))
        cla_check.run("issue_comment", event_comment(7, ALICE, cla_check.SIGN_PHRASE))

        [entry] = self.gh.ledger_entries()
        self.assertEqual((entry["id"], entry["login"], entry["cla_version"], entry["pull_request"]),
                         (101, "alice", "1.0", 7))
        self.assertEqual(entry["signed_at"], "2026-09-19T12:00:00Z")
        self.assertEqual(entry["cla_text"], f"https://github.com/{REPO}/blob/c0ffee/CLA.md",
                         "the ledger pins the exact text that was signed")
        self.assertNotIn("email", json.dumps(entry))
        self.assertEqual(self.last_status()["state"], "success")
        [c] = self.cla_comments(7)
        self.assertIn("has signed", c["body"], "the one comment is edited, not joined by a second")

    def test_a_signature_carries_over_to_later_pull_requests_without_a_comment(self):
        self.gh.add_pr(7, ALICE, [ALICE])
        cla_check.run("issue_comment", event_comment(7, ALICE, cla_check.SIGN_PHRASE))
        pr = self.gh.add_pr(8, ALICE, [ALICE, ALICE])
        cla_check.run("pull_request_target", event_pr(pr))
        self.assertEqual(self.last_status()["state"], "success")
        self.assertEqual(self.cla_comments(8), [], "nothing to say to someone already signed")

    def test_every_commit_author_signs_not_just_the_opener(self):
        self.gh.add_pr(7, ALICE, [ALICE])
        cla_check.run("issue_comment", event_comment(7, ALICE, cla_check.SIGN_PHRASE))
        pr = self.gh.add_pr(9, ALICE, [ALICE, BOB])
        cla_check.run("pull_request_target", event_pr(pr))
        self.assertEqual(self.last_status()["state"], "failure")
        [c] = self.cla_comments(9)
        self.assertIn("@bob", c["body"])
        self.assertNotIn("@alice", c["body"])

    def test_an_outside_commit_in_a_maintainers_pull_request_still_needs_signing(self):
        pr = self.gh.add_pr(10, MAINTAINER, [MAINTAINER, BOB])
        cla_check.run("pull_request_target", event_pr(pr))
        self.assertEqual(self.last_status()["state"], "failure")
        self.assertIn("@bob", self.cla_comments(10)[0]["body"])

    def test_maintainers_and_bots_pass_silently(self):
        for n, (opener, authors) in enumerate([(MAINTAINER, [MAINTAINER]), (BOT, [BOT])], start=20):
            pr = self.gh.add_pr(n, opener, authors)
            cla_check.run("pull_request_target", event_pr(pr))
            self.assertEqual(self.last_status()["state"], "success")
            self.assertEqual(self.cla_comments(n), [])

    def test_the_exemption_follows_the_account_not_the_login(self):
        squatter = {"login": "TheJakeBraun", "id": 999, "type": "User"}
        renamed = {"login": "TheJakeBraun-renamed", "id": 210177983, "type": "User"}
        pr = self.gh.add_pr(30, squatter, [squatter])
        cla_check.run("pull_request_target", event_pr(pr))
        self.assertEqual(self.last_status()["state"], "failure",
                         "a new account on a vacated login must not inherit the exemption")
        pr = self.gh.add_pr(31, renamed, [renamed])
        cla_check.run("pull_request_target", event_pr(pr))
        self.assertEqual(self.last_status()["state"], "success")

    def test_a_commit_with_no_account_behind_it_fails_even_when_everyone_signed(self):
        pr = self.gh.add_pr(11, MAINTAINER, [MAINTAINER, None])
        cla_check.run("pull_request_target", event_pr(pr))
        self.assertEqual(self.last_status()["state"], "failure")
        [c] = self.cla_comments(11)
        self.assertIn("`0110000`", c["body"])
        self.assertIn("no GitHub account", self.last_status()["description"])

    def test_too_many_commits_to_see_fails_closed(self):
        pr = self.gh.add_pr(12, ALICE, [ALICE], commits=251)
        cla_check.run("pull_request_target", event_pr(pr))
        self.assertEqual(self.last_status()["state"], "failure")
        self.assertIn("squash", self.last_status()["description"])
        self.assertNotIn(("GET", f"/repos/{REPO}/pulls/12/commits?per_page=100&page=1"), self.gh.calls)

    def test_authors_past_the_first_page_of_commits_are_seen(self):
        pr = self.gh.add_pr(13, MAINTAINER, [MAINTAINER] * 100 + [BOB])
        cla_check.run("pull_request_target", event_pr(pr))
        self.assertIn("@bob", self.cla_comments(13)[0]["body"])

    def test_a_new_cla_version_asks_everyone_to_sign_again(self):
        self.gh.add_pr(7, ALICE, [ALICE])
        cla_check.run("issue_comment", event_comment(7, ALICE, cla_check.SIGN_PHRASE))
        cla_check.CLA_VERSION = "2.0"
        pr = self.gh.add_pr(14, ALICE, [ALICE])
        cla_check.run("pull_request_target", event_pr(pr))
        self.assertEqual(self.last_status()["state"], "failure")
        cla_check.run("issue_comment", event_comment(14, ALICE, cla_check.SIGN_PHRASE))
        self.assertEqual([e["cla_version"] for e in self.gh.ledger_entries()], ["1.0", "2.0"])
        self.assertEqual(self.last_status()["state"], "success")

    # -- comments that must not sign ----------------------------------------

    def test_only_an_author_of_the_pull_request_can_sign_on_it(self):
        self.gh.add_pr(7, ALICE, [ALICE])
        cla_check.run("issue_comment", event_comment(7, BOB, cla_check.SIGN_PHRASE))
        self.assertIsNone(self.gh.ledger)
        self.assertEqual(self.last_status()["state"], "failure")

    def test_other_comments_cost_no_api_calls(self):
        self.gh.add_pr(7, ALICE, [ALICE])
        cla_check.run("issue_comment", event_comment(7, ALICE, "Thanks! I will sign it tomorrow."))
        cla_check.run("issue_comment", event_comment(7, ALICE, cla_check.SIGN_PHRASE, is_pr=False))
        self.assertEqual(self.gh.calls, [])

    def test_a_closed_pull_request_is_left_alone(self):
        self.gh.add_pr(7, ALICE, [ALICE], state="closed")
        cla_check.run("issue_comment", event_comment(7, ALICE, cla_check.SIGN_PHRASE))
        self.assertIsNone(self.gh.ledger)
        self.assertEqual(self.gh.statuses, [])

    def test_recheck_picks_up_a_signature_made_elsewhere(self):
        pr = self.gh.add_pr(8, ALICE, [ALICE])
        cla_check.run("pull_request_target", event_pr(pr))
        self.assertEqual(self.last_status()["state"], "failure")
        self.gh.add_pr(7, ALICE, [ALICE])
        cla_check.run("issue_comment", event_comment(7, ALICE, cla_check.SIGN_PHRASE))
        cla_check.run("issue_comment", event_comment(8, ALICE, "recheck"))
        self.assertEqual([s["state"] for s in self.gh.statuses if s["sha"] == "head8"],
                         ["failure", "success"])
        self.assertEqual(len(self.gh.ledger_entries()), 1, "recheck never signs")

    # -- the ledger ---------------------------------------------------------

    def test_signing_twice_records_once(self):
        self.gh.add_pr(7, ALICE, [ALICE])
        cla_check.run("issue_comment", event_comment(7, ALICE, cla_check.SIGN_PHRASE))
        cla_check.run("issue_comment", event_comment(7, ALICE, cla_check.SIGN_PHRASE))
        self.assertEqual(len(self.gh.ledger_entries()), 1)

    def test_a_concurrent_write_is_retried_not_lost(self):
        self.gh.add_pr(7, ALICE, [ALICE])
        self.gh.add_pr(9, BOB, [BOB])
        cla_check.run("issue_comment", event_comment(7, ALICE, cla_check.SIGN_PHRASE))
        self.gh.put_conflicts = 2
        cla_check.run("issue_comment", event_comment(9, BOB, cla_check.SIGN_PHRASE))
        self.assertEqual([e["login"] for e in self.gh.ledger_entries()], ["alice", "bob"])
        self.assertEqual(self.last_status()["state"], "success")

    def test_the_ledger_branch_is_created_once(self):
        self.gh.add_pr(7, ALICE, [ALICE])
        self.gh.add_pr(9, BOB, [BOB])
        cla_check.run("issue_comment", event_comment(7, ALICE, cla_check.SIGN_PHRASE))
        cla_check.run("issue_comment", event_comment(9, BOB, cla_check.SIGN_PHRASE))
        self.assertEqual(self.gh.calls.count(("POST", f"/repos/{REPO}/git/refs")), 1)

    def test_an_unexpected_api_error_fails_the_run_instead_of_passing(self):
        pr = self.gh.add_pr(7, ALICE, [ALICE])

        def broken(method, path, body=None):
            if "/contents/" in path:
                raise cla_check.ApiError(500, "boom")
            return self.gh(method, path, body)

        cla_check.api = broken
        with self.assertRaises(cla_check.ApiError):
            cla_check.run("pull_request_target", event_pr(pr))
        self.assertEqual(self.gh.statuses, [], "no status at all beats a wrong one")


class DocsAgreeTest(unittest.TestCase):
    """The phrase, the version and the exemption live in four files; drift between them breaks signing."""

    ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    def read(self, *parts):
        with open(os.path.join(self.ROOT, *parts), encoding="utf-8") as f:
            return f.read()

    def test_the_bot_links_to_headings_that_exist(self):
        links = cla_check.links_for({"repository": {"default_branch": "main"}})
        anchor = links["why"].split("#", 1)[1]
        headings = re.findall(r"^##+ (.+)$", self.read("CONTRIBUTING.md"), re.M)
        slugs = {re.sub(r"[^a-z0-9 -]", "", h.lower()).strip().replace(" ", "-") for h in headings}
        self.assertIn(anchor, slugs)

    def test_the_signing_phrase_is_the_one_the_docs_print(self):
        for doc in ("CLA.md", "CONTRIBUTING.md"):
            self.assertIn(cla_check.SIGN_PHRASE, self.read(doc), doc)

    def test_the_workflow_version_is_the_version_cla_md_states(self):
        wf = self.read(".github", "workflows", "cla.yml")
        version = re.search(r"CLA_VERSION: '([^']+)'", wf)[1]
        for doc in ("CLA.md", "CLA-CORPORATE.md"):
            self.assertEqual(re.search(r"Version (\S+)\*\*", self.read(doc))[1], version, doc)

    def test_the_workflow_exempts_account_ids_not_logins(self):
        wf = self.read(".github", "workflows", "cla.yml")
        exempt = re.search(r"CLA_EXEMPT: '?([^'\n#]+)", wf)[1].strip()
        self.assertTrue(all(s.strip().isdigit() for s in exempt.split(",")), exempt)


if __name__ == "__main__":
    unittest.main(verbosity=2)
