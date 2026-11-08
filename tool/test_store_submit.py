#!/usr/bin/env python3
"""Tests for tool/store_submit.py against an in-memory fake of the Store API.

The commit path sets the price customers pay. Its worst failure is silent: a
submission committed with the wrong pricing block publishes at the wrong price
(it published at $0 once, on 2026-08-17). So every path that decides whether a
commit happens is covered here.

Run from the repo root: python tool/test_store_submit.py
"""
from __future__ import annotations

import copy
import os
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import store_submit  # noqa: E402

APP = "9TEST"
API = store_submit.API
LIVE = {
    "priceId": "Base",
    "isAdvancedPricingModel": True,
    "trialPeriod": "NoFreeTrial",
    "marketSpecificPricings": {"LB": "NotAvailable"},
    "sales": [],
}


class Resp:
    def __init__(self, status: int = 200, body: dict | None = None):
        self.status_code = status
        self.ok = 200 <= status < 300
        self._body = body
        self.content = b"x" if body is not None else b""
        self.text = str(body)

    def json(self) -> dict:
        return self._body or {}


class FakeStore:
    """Just enough of the submission API, with every write recorded."""

    def __init__(self, live_pricing: dict | None = LIVE, live_status: int = 200,
                 readback_price: str | None = None):
        self.live_pricing = live_pricing
        self.live_status = live_status
        # None = the Store keeps whatever priceId was PUT
        self.readback_price = readback_price
        self.created = False
        self.put_payload: dict | None = None
        self.committed = False

    def session(self) -> "FakeStore":
        self.headers: dict = {}
        return self

    def get(self, url: str, timeout: int = 0) -> Resp:
        if url == f"{API}/applications/{APP}":
            return Resp(body={"primaryName": "Airclone",
                              "lastPublishedApplicationSubmission": {"id": "live"}})
        if url == f"{API}/applications/{APP}/submissions/live":
            if self.live_status != 200:
                return Resp(self.live_status, {"code": "x"})
            return Resp(body={"pricing": copy.deepcopy(self.live_pricing)})
        if url == f"{API}/applications/{APP}/submissions/new":
            pricing = copy.deepcopy(self.put_payload["pricing"])
            if self.readback_price is not None:
                pricing["priceId"] = self.readback_price
            return Resp(body={"pricing": pricing})
        if url == f"{API}/applications/{APP}/submissions/new/status":
            return Resp(body={"status": "PreProcessing"})
        raise AssertionError(f"unexpected GET {url}")

    def post(self, url: str, timeout: int = 0) -> Resp:
        if url == f"{API}/applications/{APP}/submissions":
            self.created = True
            return Resp(body={"id": "new", "fileUploadUrl": "https://blob/sas",
                              "applicationPackages": [{"fileName": "old.msix"}],
                              "listings": {"en-us": {"baseListing": {"releaseNotes": "old"}}},
                              "pricing": copy.deepcopy(self.live_pricing)})
        if url == f"{API}/applications/{APP}/submissions/new/commit":
            self.committed = True
            return Resp(body={"status": "CommitStarted"})
        raise AssertionError(f"unexpected POST {url}")

    def put(self, url: str, json: dict, timeout: int = 0) -> Resp:
        assert url == f"{API}/applications/{APP}/submissions/new", url
        self.put_payload = copy.deepcopy(json)
        return Resp(body={})


class StoreSubmitTest(unittest.TestCase):
    def setUp(self) -> None:
        fd, self.pkg = tempfile.mkstemp(suffix=".msix")
        os.write(fd, b"package")
        os.close(fd)
        self.addCleanup(os.remove, self.pkg)
        fd, self.notes = tempfile.mkstemp(suffix=".txt")
        os.write(fd, "New in this release.\n".encode())
        os.close(fd)
        self.addCleanup(os.remove, self.notes)

    def run_tool(self, store: FakeStore, *flags: str) -> int | None:
        argv = ["store_submit.py", "--app-id", APP, "--package", self.pkg,
                "--poll-seconds", "1", "--release-notes", self.notes, *flags]
        env = {"STORE_TENANT_ID": "t", "STORE_CLIENT_ID": "c", "STORE_CLIENT_SECRET": "s"}
        with mock.patch.object(sys, "argv", argv), \
             mock.patch.dict(os.environ, env), \
             mock.patch.object(store_submit, "get_token", return_value="tok"), \
             mock.patch.object(store_submit.requests, "Session", store.session), \
             mock.patch.object(store_submit.requests, "put", return_value=Resp(201)), \
             mock.patch.object(store_submit.time, "sleep"):
            try:
                return store_submit.main()
            except SystemExit as e:
                return e.code

    def test_tier_is_the_listed_price(self) -> None:
        # $0.99 at Tier1012, +$0.10 per tier: $1.49 is the fifth step up.
        self.assertEqual(store_submit.BASE_PRICE_TIER, "Tier1017")
        self.assertIn(store_submit.BASE_PRICE_TIER, store_submit.ADVANCED_TIERS)

    def test_commit_sends_explicit_tier_and_commits(self) -> None:
        store = FakeStore()
        self.assertEqual(self.run_tool(store, "--commit"), 0)
        self.assertEqual(store.put_payload["pricing"]["priceId"], "Tier1017")
        self.assertEqual(store.put_payload["pricing"]["trialPeriod"], "NoFreeTrial")
        self.assertEqual(
            store.put_payload["listings"]["en-us"]["baseListing"]["releaseNotes"],
            "New in this release.")
        self.assertTrue(store.committed)

    def test_commit_refused_without_release_notes(self) -> None:
        store = FakeStore()
        os.truncate(self.notes, 0)
        self.assertEqual(self.run_tool(store, "--commit"), 1)
        self.assertFalse(store.committed)

    def test_commit_refused_when_readback_is_free(self) -> None:
        store = FakeStore(readback_price="Free")
        self.assertEqual(self.run_tool(store, "--commit"), 1)
        self.assertFalse(store.committed)

    def test_commit_refused_when_readback_tier_differs(self) -> None:
        store = FakeStore(readback_price="Tier1012")
        self.assertEqual(self.run_tool(store, "--commit"), 1)
        self.assertFalse(store.committed)

    def test_commit_refused_before_create_when_live_unreadable(self) -> None:
        store = FakeStore(live_status=500)
        self.assertEqual(self.run_tool(store, "--commit"), 1)
        self.assertFalse(store.created)

    def test_commit_refused_before_create_when_not_advanced(self) -> None:
        store = FakeStore(live_pricing={**LIVE, "priceId": "Tier5",
                                        "isAdvancedPricingModel": False})
        self.assertEqual(self.run_tool(store, "--commit"), 1)
        self.assertFalse(store.created)

    def test_commit_refused_when_markets_change(self) -> None:
        store = FakeStore()
        real_put = store.put

        def put(url: str, json: dict, timeout: int = 0) -> Resp:
            r = real_put(url, json, timeout)
            store.put_payload["pricing"]["marketSpecificPricings"] = {}
            return r

        store.put = put
        self.assertEqual(self.run_tool(store, "--commit"), 1)
        self.assertFalse(store.committed)

    def test_stage_never_commits(self) -> None:
        store = FakeStore(readback_price="Free")
        self.assertEqual(self.run_tool(store, "--stage"), 0)
        self.assertEqual(store.put_payload["pricing"]["priceId"], "Tier1017")
        self.assertFalse(store.committed)

    def test_dry_run_creates_nothing(self) -> None:
        store = FakeStore()
        self.assertEqual(self.run_tool(store), 0)
        self.assertFalse(store.created)


if __name__ == "__main__":
    unittest.main()
