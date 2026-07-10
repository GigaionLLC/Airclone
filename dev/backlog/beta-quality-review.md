---
type: "backlog"
name: "Beta Quality Review (alpha.86 → beta)"
status: "proposed"
description: "General product-quality findings from the 2026-07-09 beta-readiness review — data-loss guards, error surfaces, docs accuracy, tests."
---

# 🔍 Beta Quality Review — 2026-07-09

General product review run while preparing v0.1.0-beta.1. README staleness (P0 #1) was fixed in the
beta.1 commit itself; everything else is queued here. **#2 is the top candidate for beta.2** and, per
project policy ([avoid `core/command`](../../wiki/core/15-security.md), destructive features get
adversarial safety review), should be built + reviewed as its own change, not rushed.

## Findings

### P0

1. ~~**README advertises the project as pre-code "early bootstrap"**~~ — *fixed in the beta.1 commit*
   (`README.md:32-34,82-86` rewritten to beta status + real roadmap standing).
2. **One-way Sync has no `--max-delete` guard and dry-run is not mandatory** — the backlog's own MUST
   invariant is unfulfilled: `sync/sync` with a wrong/empty source deletes every destination-only
   file, uncapped, no forced preview. `transfer_options.dart:349-397` (`buildRcCall`), `:364`
   (`dryRun` defaults false), `:100-103` (`maxDeletePercent` is bisync-only).
   **Fix:** add `MaxDelete`/`MaxDeleteSize` to the one-way `_config` (sane default, surfaced like the
   bisync slider) + either force dry-run-first for `TransferMode.sync` or an explicit destructive
   confirmation on first real run. Adversarial-review the change (data-loss class).

### P1

3. **File-op failures silently swallowed** — `FileOps.newFolder/rename/deleteEntry/cleanup/copyUrl`
   throw `RcloneException`, but no caller catches: no SnackBar, pane just refreshes.
   `browser_pane.dart:461-504`, `home_screen.dart:236-301`, `file_ops.dart:81-171`.
   **Fix:** shared `runFileOp(context, fn)` helper surfacing the rclone message (pattern exists at
   `home_screen.dart:1569-1571`).
4. **No global crash/uncaught-error handler** — no `FlutterError.onError`, `runZonedGuarded`, or
   `ErrorWidget.builder` (`main.dart:11-26`, `app.dart:31-39`). Uncaught errors vanish in release
   builds.
5. **Engine provisioning not fail-closed on checksum + no version pin** — missing/unfetchable
   `SHA256SUMS` ⇒ proceeds unverified, contradicting the fail-closed claim; `downloadLatest` takes
   whatever `version.txt` says. `rclone_engine.dart:99-127,177-196`.
   **Fix:** hard-fail on missing checksum; enforce the documented min version (≥ 1.73.5).
6. **Engine lifecycle has zero tests** — no tests for `EngineController` (bootstrap → provision →
   password-gate → start → `onDied` → restart) or `RcloneEngine` helpers (target triple, extraction,
   checksum-mismatch, encrypted-header detection). The most likely path to strand a new user.

### P2

7. **Update check never proactively surfaced** — only a manual button in Settings
   (`app_info.dart:40-60`, `settings_screen.dart:760-795`). Add a dismissible launch-time banner
   (respect the future enterprise kill-switch).
8. **`hasUpdate` uses substring matching** — `!tag.contains(current)`: running `0.1.0-alpha.8` vs tag
   `v0.1.0-alpha.86` reports "up to date" (`app_info.dart:52-53`). Compare with `pub_semver`.
9. **No a11y semantics; no arrow-key selection** — Up/Down don't move file selection
   (`home_screen.dart:143-162,602-648`); zero `Semantics` labels on rows/status dots/progress bars.
10. **"i18n-first" is a MUST item with zero l10n infrastructure** — no `flutter_localizations`/arb
    anywhere; either scaffold now (cheaper before more dialogs exist) or demote the backlog claim.
11. **Backlog MoSCoW lists don't reflect shipped reality** — MUST/SHOULD items (dual-pane, drag-drop,
    jobs panel, bisync, crypt, serve, …) shipped but unmarked (`feature-backlog.md:109-185`). Do a
    check-off pass.
12. **Bulk delete/download aborts mid-batch, unreported** — first failure throws out of the loop
    (`home_screen.dart:296-300`, `browser_pane.dart:545-569`). Collect per-item results, report
    "Deleted 4 of 6 — 2 failed".

### P3

13. **No min-version/capability gate on a PATH-located rclone** — an old system rclone is accepted,
    then fails opaquely deep in a feature (`rclone_engine.dart:19-29`, `engine_controller.dart:186-209`).
14. **version-history.md policy section is fictional** — describes a `1.02.003` 3-level scheme that
    isn't the real `0.1.0-<pre>.N` semver flow, and the table is mixed-order (`version-history.md:5-13,48+`).
15. **README build section omits the Rust toolchain requirement** — `super_drag_and_drop` →
    `super_native_extensions` builds a Rust crate via cargokit on desktop (partially addressed in the
    beta.1 commit; verify the dependency is still needed at all).

### Also noted (macOS engine hardening, from the signing audit)

16. **Downloaded rclone engine on macOS: add belt-and-suspenders** — the notarized app spawns a
    runtime-downloaded rclone. Official rclone macOS builds are signed+notarized and Dart socket
    writes don't set the quarantine xattr, so this works today — but nothing *repairs* a quarantined
    or unsigned binary (`killed: 9` on Apple silicon would be opaque). Consider `xattr -d
    com.apple.security.quarantine` + an ad-hoc re-sign fallback after download, or bundling the
    engine like Android does (`rclone_engine.dart`).
