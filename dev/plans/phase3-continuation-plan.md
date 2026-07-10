---
type: "plan"
name: "Phase 3 Continuation Plan"
status: "active"
description: "Finishing bisync / crypt / scheduling + engine currency: what shipped in the 2026-07-09 safety batch, and the designed path for the big items (background execution, crypt reattach, engine test harness)."
---

# 🧭 Phase 3 Continuation Plan

Grounded in a 4-agent audit (2026-07-09) of the shipped bisync (a55), crypt (a56), scheduling (a50),
and engine-provisioning code. **Bisync/crypt/scheduling are real, working features** — this plan is
about closing their trust gaps and keeping the engine current.

## Shipped in the 2026-07-09 safety & currency batch

| Area | Change |
| :--- | :--- |
| Sync safety | One-way Sync now confirms before a destructive run (Cancel / Dry run first / Run sync) + optional `--max-delete` cap (`MaxDelete` in `_config`) surfaced in the dialog |
| Bisync safety | Ad-hoc Two-way sync no longer fires an unconfirmed `--resync` (baseline confirm dialog) and no longer loops per selected file (dirs-only); saved tasks gain **Re-establish baseline…** recovery |
| Crypt safety | Unmissable "lost password = unrecoverable data" warnings (form + done screen); editing a crypt password now requires an explicit destructive confirm (it orphans all existing data) |
| Scheduler | Last-run display, live next-run countdown, locked-engine skip warning, pure testable `dueTasks` selection |
| Engine currency | Fail-closed SHA-256 (unverifiable download = hard error); min-version gate (≥ 1.73.5) with recovery CTA; **Update engine** in Settings (version row + check + one-click update); Android pin bumped to v1.74.4 (security patch: serve s3/webdav + local symlink CVEs); CI staleness check |

## Big items (each needs its own change, in recommended order)

### 1. Background execution for scheduled tasks — the headline gap
Schedules only fire while the app is open (single `Timer.periodic(30s)`, `scheduler_controller.dart`).
Build order:
1. **Headless entrypoint first** (shared by all desktop platforms): `main(List<String> args)` —
   the Windows runner already forwards args (`main.cpp:22-25`), Dart currently drops them. `--run-task
   <id>` / `--run-due` boots a `ProviderContainer` without `runApp`, spawns rcd on its own free
   loopback port (no collision with a running GUI), runs the task(s) to terminal status, exits with a
   code. ~2–4 days.
2. **Windows**: register via `schtasks` (XML form for run-missed-start catch-up) from the schedule
   editor. ~1–2 days on top of (1).
3. **macOS launchd / Linux systemd-user timers** (`Persistent=true` gives catch-up) — ~1–2 days each.
4. **Android**: `workmanager` plugin + headless isolate; requires moving `nativeLibraryDir` + FGS
   channel from MainActivity to an Application-scoped channel so a background isolate can exec
   `librclone.so`; reuse `TransferService.kt` as the long-running worker; battery-optimization UX.
   ~1–2 weeks.
5. **Cross-cutting prerequisite**: encrypted-config headless unlock — store the config password in the
   OS vault (DPAPI / Keychain / Secret Service) or gate background scheduling on unencrypted configs
   with a clear warning. Without it, unattended runs can't start on locked configs (today the
   scheduler already silently skips; the batch added a visible warning).
6. **Per-run history** on `TransferTask` (last N: timestamp/result/bytes) — prerequisite for trusting
   unattended runs; today a failed scheduled run is indistinguishable from a successful one.

### 2. Crypt: prove it, reattach it, rotate it
- **Round-trip canary verification**: replace `cryptcheck [base, crypt]` (trivially passes on empty
  remotes, false-alarms on populated ones) with write-tiny-blob → read-back → compare → delete via
  `operations/*`. Actually proves the key decrypts.
- **"Connect an existing encrypted remote" wizard**: guided reattach (base + password/salt + matching
  modes) with round-trip verification — today users must hand-recreate via the generic form and any
  mode mismatch yields silent garbage.
- **Live filename-transform preview** (promised in `wiki/core/15-security.md:55`).
- **Safe password rotation**: guided re-wrap (new crypt remote + streamed re-encrypt copy + swap)
  instead of the config/update foot-gun.

### 3. Bisync: reliability surface
- Per-pair state beyond the baseline boolean: last-run result, conflict count, listing age.
- Expose rclone recovery options: `resilient`/`recover`, `force` (past a max-delete abort),
  `checkSync`.
- Move the baseline-flip out of the `_TaskRow` widget listener into the service layer keyed by task
  id (widget-lifecycle flip can silently fail to persist → re-runs the destructive resync).
- Parse the "cannot find prior listing" error into an actionable "Re-establish baseline" CTA on the
  job row.

### 4. Engine test harness (beta-quality-review #6)
Introduce injectable seams (fetch fn + Process/HttpRcloneClient factories) so `RcloneEngine` /
`EngineController` are testable: target-triple, extraction, checksum decisions, encrypted-header
detection, and the full phase state machine (bootstrap → provision → needsPassword → start → onDied →
restart). Land before/with any further engine work.

## Deliberately deferred
- OS-level scheduling UI before the headless entrypoint exists (would over-promise).
- Bisync filters parity and `--max-delete` abort override (`force`) until per-pair state exists.
- Crypt wizard exposure of `no_data_encryption`/`filename_encoding` (quick win, but batch scope was
  safety-first; add with the reattach wizard).
