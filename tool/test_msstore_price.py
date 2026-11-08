#!/usr/bin/env python3
"""Tests for tool/msstore_price.py on catalog shapes seen live (2026-11-08).

Run from the repo root: python tool/test_msstore_price.py
"""
from __future__ import annotations

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import msstore_price  # noqa: E402


def avail(actions: list[str], price: float) -> dict:
    return {"Actions": actions,
            "OrderManagementData": {"Price": {"ListPrice": price, "CurrencyCode": "USD"}}}


def catalog(purchase_price: float | None) -> dict:
    paid = [avail(["Details", "License"], 0.0)]
    if purchase_price is not None:
        paid.insert(0, avail(["Details", "Fulfill", "Purchase"], purchase_price))
    return {"Products": [{"DisplaySkuAvailabilities": [
        {"Sku": {"Properties": {"IsTrial": True}},
         "Availabilities": [avail(["Details", "Purchase"], 0.0)]},
        {"Sku": {"Properties": {"IsTrial": False, "Packages": [
            {"PackageFullName": "Pub.App_0.31.1.0_x64__abc"}]}},
         "Availabilities": paid},
    ]}]}


class LiveStateTest(unittest.TestCase):
    def test_reads_purchase_price_of_non_trial_sku(self) -> None:
        self.assertEqual(msstore_price.live_state(catalog(1.49)), (1.49, "USD", ["0.31.1.0"]))

    def test_free_listing_reads_zero(self) -> None:
        self.assertEqual(msstore_price.live_state(catalog(0.0))[0], 0.0)

    def test_no_purchase_action_is_an_error(self) -> None:
        with self.assertRaises(ValueError):
            msstore_price.live_state(catalog(None))


if __name__ == "__main__":
    unittest.main()
