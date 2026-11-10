#!/usr/bin/env python3
"""Tests for tool/carveout_paths.py: which changes may not merge on CI alone.

Its worst failure is silent: a change to the rc allowlist or a price check
reads "none" and merges without the review it needed. So every category and
both diff shapes (git diff, gh pr diff) are covered.

Run from the repo root: python tool/test_carveout_paths.py
"""
from __future__ import annotations

import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import carveout_paths as cp  # noqa: E402


def diff(path: str, *lines: str, old: str | None = None) -> str:
    old = old or path
    body = "\n".join(lines)
    return ("diff --git a/%s b/%s\nindex 1..2 100644\n--- a/%s\n+++ b/%s\n@@ -1 +1 @@\n%s\n"
            % (old, path, old, path, body))


class FindingsTest(unittest.TestCase):
    def cats(self, text: str) -> set[str]:
        return {c for c, _, _ in cp.findings(cp.parse_diff(text))}

    def test_plain_docs_change_is_clean(self) -> None:
        self.assertEqual(self.cats(diff("dev/README.md", "+a line", "-old")), set())

    def test_rc_allowlist_is_security(self) -> None:
        self.assertEqual(self.cats(diff("app/lib/src/webui/webui_rc_policy.dart", "+'x/y',")),
                         {"SECURITY"})

    def test_console_denylist_is_security(self) -> None:
        self.assertIn("SECURITY", self.cats(diff(
            "app/lib/src/state/console/rclone_commands.dart", "-  'index',")))

    def test_price_script_is_money(self) -> None:
        self.assertEqual(self.cats(diff("tool/store_submit.py", "+x = 1")), {"MONEY"})

    def test_price_tier_line_in_other_tool_is_money(self) -> None:
        self.assertIn("MONEY", self.cats(diff("tool/ship_lane.py", '+BASE_PRICE_TIER = "Tier1"')))

    def test_vault_is_signing(self) -> None:
        self.assertEqual(self.cats(diff("dev/vault/notes.md.enc", "+x")), {"SIGNING"})

    def test_workflow_secret_line_is_signing(self) -> None:
        self.assertIn("SIGNING", self.cats(diff(
            ".github/workflows/release.yml", "+        env: { K: ${{ secrets.X }} }")))

    def test_workflow_without_secret_is_clean(self) -> None:
        self.assertEqual(self.cats(diff(".github/workflows/ci.yml", "+      - run: echo hi")), set())

    def test_removed_secret_line_counts_too(self) -> None:
        self.assertIn("SIGNING", self.cats(diff(
            ".github/workflows/ship.yml", "-          KEY: ${{ secrets.ASC_KEY }}")))

    def test_rename_out_of_a_carveout_path_counts(self) -> None:
        self.assertIn("SECURITY", self.cats(diff(
            "app/lib/src/misc/x.dart", "+a", old="app/lib/src/webui/webui_param_guards.dart")))

    def test_header_lines_are_not_content(self) -> None:
        # "+++ b/..." must not be read as an added line that matches a pattern.
        files = cp.parse_diff(diff(".github/workflows/ci.yml", "+ok"))
        self.assertEqual(files[".github/workflows/ci.yml"], ["ok"])

    def test_workflow_comment_is_not_content(self) -> None:
        self.assertEqual(self.cats(diff(".github/workflows/ci.yml",
                                        "+        # checks prices and secrets.X")), set())

    def test_removed_price_step_still_counts(self) -> None:
        self.assertIn("MONEY", self.cats(diff(".github/workflows/ci.yml",
                                              "-        run: python tool/check_price.py")))

    def test_the_checker_itself_is_security(self) -> None:
        self.assertEqual(self.cats(diff("tool/carveout_paths.py", '+    ("MONEY", "x"),')),
                         {"SECURITY"})

    def test_several_files(self) -> None:
        text = diff("dev/README.md", "+a") + diff("tool/msstore_price.py", "+b")
        found = cp.findings(cp.parse_diff(text))
        self.assertEqual([(c, p) for c, p, _ in found], [("MONEY", "tool/msstore_price.py")])


class MainTest(unittest.TestCase):
    def run_on(self, text: str) -> int:
        with tempfile.NamedTemporaryFile("w", suffix=".diff", delete=False) as f:
            f.write(text)
        try:
            return cp.main(["--diff-file", f.name])
        finally:
            os.unlink(f.name)

    def test_exit_0_when_clean(self) -> None:
        self.assertEqual(self.run_on(diff("README.md", "+x")), 0)

    def test_exit_3_on_carveout(self) -> None:
        self.assertEqual(self.run_on(diff("app/lib/src/update/update_trust.dart", "+x")), 3)

    def test_exit_2_on_bad_usage(self) -> None:
        self.assertEqual(cp.main(["--nope"]), 2)

    def test_exit_2_on_missing_file(self) -> None:
        self.assertEqual(cp.main(["--diff-file", "/nonexistent/x.diff"]), 2)


if __name__ == "__main__":
    unittest.main()
