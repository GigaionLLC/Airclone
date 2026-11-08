#!/usr/bin/env python3
"""Tests for tool/ship_lane.py: which run a dispatch started, and the Apple step.

Both decide what ship.yml does next without a human watching. Watching the
wrong run reports someone else's result as ours; a wrong Apple step creates or
submits a version that should have waited for Jake.

Run from the repo root: python tool/test_ship_lane.py
"""
from __future__ import annotations

import os
import sys
import unittest
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ship_lane  # noqa: E402

T0 = datetime(2026, 11, 8, 20, 0, tzinfo=timezone.utc)


def run(rid: int, at: str, ref: str = "main", event: str = "workflow_dispatch") -> dict:
    return {"databaseId": rid, "createdAt": at, "headBranch": ref, "event": event,
            "url": "https://example/%d" % rid}


class PickRunTest(unittest.TestCase):
    def test_picks_the_new_run_on_the_ref(self) -> None:
        runs = [run(3, "2026-11-08T20:00:05Z", "v0.32.0"),
                run(2, "2026-11-08T19:59:00Z", "v0.32.0"),
                run(1, "2026-11-08T20:00:06Z", "main")]
        self.assertEqual(ship_lane.pick_run(runs, T0, "v0.32.0")["databaseId"], 3)

    def test_none_until_it_appears(self) -> None:
        self.assertIsNone(ship_lane.pick_run([run(2, "2026-11-08T19:59:00Z")], T0, "main"))

    def test_ignores_other_events(self) -> None:
        runs = [run(4, "2026-11-08T20:01:00Z", event="push")]
        self.assertIsNone(ship_lane.pick_run(runs, T0, "main"))

    def test_two_candidates_is_an_error(self) -> None:
        runs = [run(5, "2026-11-08T20:00:01Z"), run(6, "2026-11-08T20:00:02Z")]
        with self.assertRaises(RuntimeError):
            ship_lane.pick_run(runs, T0, "main")


class DecideAppleTest(unittest.TestCase):
    def d(self, target: str, blocking: int = 0, build: str = "VALID") -> str:
        return ship_lane.decide_apple(target, blocking, build)[0]

    def test_new_version_with_valid_build_is_created(self) -> None:
        self.assertEqual(self.d("NONE"), "create")

    def test_prepared_version_is_updated(self) -> None:
        self.assertEqual(self.d("PREPARE_FOR_SUBMISSION"), "update")
        self.assertEqual(self.d("DEVELOPER_REJECTED"), "update")

    def test_waits_while_build_processes(self) -> None:
        self.assertEqual(self.d("NONE", build="PROCESSING"), "wait")
        self.assertEqual(self.d("NONE", build="NONE"), "wait")

    def test_bad_build_stops(self) -> None:
        for b in ("INVALID", "FAILED", "EXPIRED"):
            self.assertEqual(self.d("NONE", build=b), "stop", b)

    def test_older_held_version_stops(self) -> None:
        self.assertEqual(self.d("NONE", blocking=1), "stop")
        self.assertEqual(self.d("PREPARE_FOR_SUBMISSION", blocking=1), "stop")

    def test_already_submitted_is_done_even_if_others_block(self) -> None:
        for t in ("WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE",
                  "READY_FOR_SALE"):
            self.assertEqual(self.d(t, blocking=1, build="PROCESSING"), "done", t)

    def test_rejected_stops_for_jake(self) -> None:
        for t in ("REJECTED", "METADATA_REJECTED", "INVALID_BINARY"):
            self.assertEqual(self.d(t), "stop", t)

    def test_unknown_state_stops(self) -> None:
        self.assertEqual(self.d("SOMETHING_NEW"), "stop")

    def test_parse_state(self) -> None:
        s = ship_lane.parse_state("STATE target=NONE blocking=0 build=VALID")
        self.assertEqual(s, {"target": "NONE", "blocking": "0", "build": "VALID"})
        with self.assertRaises(ValueError):
            ship_lane.parse_state("no gaps")
        with self.assertRaises(ValueError):
            ship_lane.parse_state("STATE target=NONE")


if __name__ == "__main__":
    unittest.main()
