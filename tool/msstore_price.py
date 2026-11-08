#!/usr/bin/env python3
"""Read Airclone's live Microsoft Store price and version from the public catalog.

The check after every Microsoft Store publish: an API commit once published this
app at $0 (2026-08-17), and certification can finish within the hour, so this is
what tells us the price customers see. It needs no credentials - it reads the
same public catalog the Store app does.

    python tool/msstore_price.py                   # expects 1.49 USD
    python tool/msstore_price.py --version 0.31.1  # also says whether 0.31.1 is live

Exit codes: 0 the price is as expected, 1 it is not (tell Jake at once if it
reads 0), 2 the catalog could not be read or parsed.
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.request

PRODUCT = "9PJ6LRTS2B8X"
CATALOG = ("https://displaycatalog.mp.microsoft.com/v7.0/products"
           "?bigIds={product}&market={market}&languages=en-US")


def read_catalog(product: str, market: str) -> dict:
    url = CATALOG.format(product=product, market=market)
    with urllib.request.urlopen(url, timeout=60) as r:
        return json.load(r)


def live_state(catalog: dict) -> tuple[float, str, list[str]]:
    """(purchase price, currency, package versions) of the non-trial SKU.

    The catalog also lists a trial SKU and License/Redeem availabilities at 0.0
    on every paid app; only the Purchase action of the non-trial SKU is the
    price a customer pays.
    """
    product = catalog["Products"][0]
    for dsa in product["DisplaySkuAvailabilities"]:
        sku = dsa["Sku"]
        if sku["Properties"].get("IsTrial"):
            continue
        for a in dsa["Availabilities"]:
            if "Purchase" in a.get("Actions", []):
                price = a["OrderManagementData"]["Price"]
                versions = [p.get("PackageFullName", "").split("_")[1]
                            for p in sku["Properties"].get("Packages", [])
                            if p.get("PackageFullName", "").count("_") >= 2]
                return float(price["ListPrice"]), price["CurrencyCode"], versions
    raise ValueError("no Purchase availability on a non-trial SKU (the app reads as free)")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--expect", type=float, default=1.49, help="expected list price (default 1.49)")
    ap.add_argument("--market", default="US")
    ap.add_argument("--version", help="report whether this app version (e.g. 0.31.1) is live")
    args = ap.parse_args()

    try:
        price, currency, versions = live_state(read_catalog(PRODUCT, args.market))
    except ValueError as e:
        print(f"PRICE WRONG: {e}. Tell Jake at once.")
        return 1
    except Exception as e:  # network, JSON or shape
        print(f"could not read the catalog: {e}", file=sys.stderr)
        return 2

    print(f"live price ({args.market}): {price:.2f} {currency}")
    print(f"live package version(s): {', '.join(versions) or 'unknown'}")
    if args.version:
        live = any(v == args.version or v.startswith(args.version + ".") for v in versions)
        print(f"{args.version}: {'live' if live else 'not live yet'}")
    if abs(price - args.expect) > 0.001:
        print(f"PRICE WRONG: expected {args.expect:.2f}. Tell Jake at once; the price is fixed "
              "in Partner Center -> Pricing and availability.")
        return 1
    print("price OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
