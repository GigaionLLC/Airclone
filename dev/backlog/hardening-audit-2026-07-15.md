---
type: "backlog"
name: "Reliability and Product Hardening Audit"
status: "proposed"
description: "Prioritized handoff from the 2026-07-15 Airclone audit: process ownership, transfer safety, config transactions, release integrity, mobile readiness, and test gaps."
audited_commit: "613e262"
---

# Reliability and Product Hardening Audit - 2026-07-15

This is the durable handoff for the multi-lens audit performed against `main` at `613e262`. It records
**candidate work**, not completed fixes. Reproduce each finding against the current branch before
changing code because line numbers and behavior may have moved.

No product code was changed as part of the audit. At the audit baseline:

- `flutter analyze` passed.
- 589 runnable tests passed; 7 environment-dependent FFI tests were skipped.
- Generated line coverage was 31.1% overall. CI uploaded coverage but enforced no floor.
- The worktree was clean.

The recurring design gap is more important than any one item: safety and lifecycle rules currently
live in selected UI entry points. Future work should enforce them at the process, engine, job,
transfer, and config execution boundaries so every current and future UI path gets the same behavior.

## How to use this handoff

1. Reproduce the item and update its checkbox/status before implementation.
2. For a P0 or multi-file P1, create a focused plan under `dev/plans/` and include adversarial tests.
3. Preserve existing behavior unless the acceptance notes explicitly require a product decision.
4. Check an item off only after automated tests and the relevant packaged/platform smoke test pass.
5. Update public capability copy when a fix changes what is genuinely available.

Priority meaning: **P0** = release/data-integrity blocker, **P1** = important reliability, privacy, or
product-trust work, **P2** = quality and maintainability work that should follow the safety pass.

## Existing tracker reconciliation

| Audit result | Existing tracker relationship |
| :--- | :--- |
| **Reopens a claimed fix** | H-01 reopens `feature-backlog.md`'s checked orphan-engine item: the current single raw PID marker is not ownership-safe across GUI/headless instances. H-03 narrows the remaining problem after collision prompts and MaxDelete partially shipped: execution paths still bypass policy, paste fails open, and unattended Sync bypasses the run-now guard. |
| **Already noted, raised or made concrete here** | H-11 expands the cross-process SharedPreferences warning in `phase3-continuation-plan.md`. H-03/H-14/H-15/H-16 overlap older `beta-quality-review.md` findings but record current evidence and acceptance criteria. |
| **Planned feature versus shipped claim** | DocumentsProvider/File Provider and mandatory dry-run preview already appear in `feature-backlog.md`; H-04/H-12/H-17 track the gap between those plans and present-tense README/store claims. |
| **Newly tracked by this audit** | The cancel-before-job-ID race, same-path browser ABA race, tagged debug-sign fallback, preview-temp privacy leak, config transaction gap, tested-engine version drift, and current native biometric setup were not substantively captured elsewhere. |

## P0 - release and data-integrity blockers

### [ ] H-01 - Replace the shared raw engine PID marker

**Finding:** desktop and headless instances use the same `%TEMP%/airclone_rcd.pid`. Startup reads the
number and sends a hard kill without validating process identity or ownership. Concurrent Airclone
instances can kill one another; PID reuse also makes a stale marker unsafe.

**Evidence:** `app/lib/src/rclone/http_rclone_client.dart:53-83,97-103,143-149,289-294`;
`app/lib/src/headless/headless_runner.dart:31-37`.

**Acceptance notes:** use an ownership-validated per-instance lease/mutex/IPC design (or deliberately
share a managed engine); contain owned children at the OS level; test GUI + headless concurrency,
two headless runs, abrupt exit, and stale/reused marker recovery.

### [ ] H-02 - Close the cancel-before-dispatch race

**Finding:** Stop marks a job canceled when no rclone job ID exists. If the async kickoff is already
in flight, it can return afterward and attach a real rclone job to the locally canceled row, leaving
the transfer running invisibly. Stop failures are also treated as successful cancellation.

**Evidence:** `app/lib/src/state/jobs_controller.dart:184-208`;
`app/lib/src/state/transfer_service.dart:96-118`.

**Acceptance notes:** model explicit starting/cancel-requested/canceled states; after kickoff, recheck
terminal state and immediately stop a late job ID; do not report cancellation until termination is
confirmed; ensure owned archive subprocesses are killed and reaped; add deterministic Completer-based
race and stop-failure tests. Also inspect `app/lib/src/state/archive_service.dart:93-99` when scoping.

### [ ] H-03 - Enforce one transfer/conflict/destructive policy at execution time

**Finding:** paste/drop has a collision prompt, but copy/move pickers, uploads, downloads, inspector
downloads, and quick dual-pane transfers call the raw transfer path. Paste also fails open: a failed
destination listing becomes an empty name set and the operation defaults to overwrite. Saved,
scheduled, and headless one-way Sync runs bypass the run-now destructive confirmation; an empty
MaxDelete field means no cap.

**Evidence:** `app/lib/src/ui/browser_pane.dart:737-800,952-977,2012-2025`;
`app/lib/src/ui/inspector_panel.dart:518-543`; `app/lib/src/ui/paste_action.dart:97-143`;
`app/lib/src/ui/transfer_options_dialog.dart:14-19,152-174,473-527`;
`app/lib/src/state/scheduler_controller.dart:121-139`;
`app/lib/src/headless/headless_runner.dart:358-380`.

**Acceptance notes:** introduce a single application-level `TransferCoordinator` used by every
entry point; fail closed when preflight cannot establish safety; enforce overwrite/skip/rename/
immutable semantics in the rclone request rather than only a cached UI listing; require explicit,
persisted approval and conservative delete limits for unattended destructive work; return per-item
batch outcomes.

### [ ] H-04 - Make dry run a reviewable change set

**Finding:** dry run is an ordinary job with `(dry run)` added to its source label. The job model and
jobs panel do not retain or display the planned copies, updates, deletions, or conflicts, despite
public copy describing a preview of exactly what will change.

**Evidence:** `app/lib/src/state/transfer_service.dart:157-215`;
`app/lib/src/rclone/models/job.dart:20-140`; `app/lib/src/ui/jobs_panel.dart:170-343`;
`docs/store/play/listing-en-US.md:44`.

**Acceptance notes:** capture and present a grouped change set; make it reviewable before a real
destructive run; preserve/export technical details; require a successful preview before scheduling
destructive Sync unless the user makes a separately recorded expert override.

### [ ] H-05 - Make config replacement and restore transactional

**Finding:** plaintext replace and backup restore write directly over the live config, then restart
the engine. They do not quiesce rclone first or use atomic replacement, even though the encryption
flow already recognizes rclone as a concurrent config writer. Encrypted replace may also continue
deleting old remotes after a create failure.

**Evidence:** `app/lib/src/state/config_transfer_controller.dart:185-267,523-559,636-674`;
`app/lib/src/state/config_backups.dart:42-100`;
`app/test/config_transfer_test.dart:114-136`.

**Acceptance notes:** block active work; quiesce the engine; take a verified snapshot; write and
flush a sibling temporary file; atomically replace; restart and verify; roll back automatically on
failure. Fetch authoritative remote state before encrypted replace, never prune after a failed
create, and migrate/purge plaintext backups after encryption succeeds. Bound imported file size and
untrusted KDF parameters before allocating/deriving (`config_import_dialog.dart:97-130`,
`config_io.dart:260-268,379-420`) and do expensive derivation off the UI isolate.

### [ ] H-06 - Fail closed on tagged release signing and publication

**Finding:** the Android tag guard checks only the base64 keystore secret. Gradle needs four signing
values and intentionally falls back to the debug key if any are missing. A tagged artifact can
therefore be published with the wrong certificate. The workflow creates a public release before all
platform builds and does not run the normal quality suite itself.

**Evidence:** `.github/workflows/release.yml:39-68,565-585`;
`app/android/app/build.gradle.kts:21-31,83-93`.

**Acceptance notes:** validate every signing input, verify the output certificate fingerprint with
`apksigner`, require signing for all tagged production artifacts, validate tag/package versions, run
format/analyze/tests/builds first, publish a draft only after all required assets and checksums pass,
then atomically promote it. Apply equivalent fail-closed signing to tagged Windows artifacts; pin
third-party Actions by commit SHA with job-level least privilege; generate an SBOM/provenance artifact
before advertising signed/SBOM'd builds.

## P1 - runtime reliability, privacy, and product trust

### [ ] H-07 - Coordinate engine restarts with active and queued jobs

**Finding:** config/path/flag/update actions can quit the engine without coordinating with jobs.
Queued closures can retain an obsolete client, old job IDs survive into a new engine session, and
release-mode rclone stdout is not drained while stderr is drained only in debug. Shutdown can clear
state after a soft-kill timeout without force-killing and reaping the child.

**Evidence:** `app/lib/src/state/engine_controller.dart:235-321`;
`app/lib/src/state/jobs_controller.dart:218-273`;
`app/lib/src/rclone/http_rclone_client.dart:137-173,270-294`;
`app/lib/src/state/transfer_service.dart:27-90,157-215`.

**Acceptance notes:** gate or explicitly reconcile restarts; resolve the live client at dispatch;
attach an engine-session generation to every job; mark interrupted work terminal; always drain both
process streams into a bounded/redacted diagnostic tail; force-kill and await exit after a bounded
graceful shutdown.

### [ ] H-08 - Finish browser stale-response protection

**Finding:** the v0.5 guard snapshots only remote and path. Same-path overlapping refreshes can commit
out of order, A-to-B-to-A navigation can admit an old A response, and tabs at the same location lack
request/session identity.

**Evidence:** `app/lib/src/state/browser_controller.dart:190-194,255-273,344-372,420-450`.

**Acceptance notes:** capture tab/session identity plus a monotonically increasing load generation;
only the latest matching request may commit. Add deterministic tests for concurrent refresh, A-to-B,
A-to-B-to-A, error ordering, and same-path tab switching.

### [ ] H-09 - Bring preview caching under the privacy and cache policy

**Finding:** the FFI object server materializes the full cloud object into a general plaintext temp
file before serving ranges. It ignores the memory-only preference, uses only filesystem + path as its
cache identity, can reuse stale content, and has no owned size/TTL/LRU cleanup policy.

**Evidence:** `app/lib/src/rclone/librclone_object_server.dart:15-19,51-66,123-198`;
`app/lib/src/state/engine_controller.dart:500-509`;
`app/lib/src/state/cache_crypto.dart:85-168`.

**Acceptance notes:** prefer true ranged streaming; otherwise use a dedicated account/session-aware
cache with version metadata, size/TTL/LRU limits, secure cleanup, and explicit memory-only behavior.

### [ ] H-10 - Use one tested rclone version policy

**Finding:** release builds pin rclone v1.74.4, while the runtime minimum is 1.73.5 and the portable
desktop updater discovers whatever `version.txt` currently advertises. This can accept an older
security baseline or run a newer engine that was not covered by Airclone's release tests.

**Evidence:** `.github/workflows/release.yml:25-32,611`;
`app/lib/src/rclone/rclone_engine.dart:116-156,238-274`;
`.github/workflows/ci.yml:47-74`.

**Acceptance notes:** define the tested version and security floor once; pass it explicitly to every
build; fail CI on drift; stage, verify, atomically swap, and roll back engine updates. Treat a PATH
override below the floor as an explicit recovery choice, not a warning-only normal path.
On Windows, download to a versioned staging path before stopping/swapping the running executable;
the current update path writes to the managed binary before `quit()` (`rclone_engine.dart:190-205`,
`engine_controller.dart:313-321`).

### [ ] H-11 - Make scheduled-task persistence cross-process safe and durable

**Finding:** GUI and headless processes rewrite SharedPreferences with last-writer-wins semantics.
Task persistence is fire-and-forget, and headless execution can exit before run history/lastRun is
durably flushed. Concurrent writes can lose task edits, history, or unrelated preference state.

**Evidence:** `app/lib/src/headless/headless_runner.dart:31-37,193-206,358-380`;
`app/lib/src/state/tasks_controller.dart:199-274`;
`dev/plans/phase3-continuation-plan.md` under "Cross-process SharedPreferences whole-file clobber".

**Acceptance notes:** use a transactional, cross-process-safe store (for example SQLite or locked
per-task atomic records); separate task definitions from append-only run results; serialize writes;
expose and await `flush()` before headless shutdown; test simultaneous GUI/headless mutation.

### [ ] H-12 - Complete Android/iOS platform wiring before store claims

**Finding:** Android biometric code uses `FlutterActivity` although `local_auth` requires
`FlutterFragmentActivity`; the manifest lacks the biometric permission and the launch theme is not
AppCompat. The iOS plist lacks Face ID and camera usage descriptions. Android has no
DocumentsProvider and iOS has no File Provider extension despite "Show in Files" claims. Foreground
service startup failures are swallowed on both sides of the platform channel, and broad all-files
access is requested without a scoped system-picker-first flow.

**Evidence:** `app/android/app/src/main/kotlin/app/airclone/airclone/MainActivity.kt:9-13`;
`app/android/app/src/main/AndroidManifest.xml`; `app/android/app/src/main/res/values/styles.xml`;
`app/ios/Runner/Info.plist`; `README.md:32,69-72,98-105`.
Foreground-service evidence: `MainActivity.kt:44-54` and
`app/lib/src/state/android_transfer_service.dart:52-62`; storage UX:
`app/lib/src/ui/engine_gate.dart:200-260`, `app/lib/src/ui/mobile_action_sheets.dart:100-159`.

**Acceptance notes:** correct the native setup and add real-device/emulator smoke tests for biometric,
camera, foreground-service, and storage permission flows. Either implement each OS integration and
test it or clearly mark it planned/unsupported in every public surface. Return real foreground-service
success/failure, latch only after confirmation, warn if background protection is lost, and prefer
scoped system file/photo pickers before optional all-files access.

### [ ] H-13 - Harden FFI worker and recurring pollers

**Finding:** FFI startup and pending RPCs have no bounded timeout/on-exit failure path. Several
one-second timers can overlap, while the FFI worker is intentionally serialized; preview polling can
run every 150 ms. Slow calls can build queues and apply stale snapshots.

**Evidence:** `app/lib/src/rclone/librclone_ffi.dart:24-30,118-175,216-240`;
`app/lib/src/state/jobs_controller.dart:38-45,218-273`;
`app/lib/src/state/stats_controller.dart:41-61`;
`app/lib/src/rclone/librclone_object_server.dart:154-165`.

**Acceptance notes:** add dedicated isolate error/exit ports, bounded startup/RPC deadlines, and a
single failure path for pending completers. Replace overlapping timers with non-overlapping,
self-scheduling loops or in-flight guards; coalesce stats calls and discard stale generations.

### [ ] H-14 - Surface failures consistently and add privacy-safe diagnostics

**Finding:** desktop mutation paths often let errors escape, mobile bulk operations reduce failures to
a count, some remote operations silently catch errors, and startup has no global release error hook.

**Evidence:** `app/lib/src/ui/browser_pane.dart:720-735,1956-2009`;
`app/lib/src/ui/selection_actions.dart:37-67`;
`app/lib/src/ui/mobile_action_sheets.dart:431-437`; `app/lib/main.dart:13-55`.

**Acceptance notes:** route user mutations through one typed operation runner with progress,
per-item outcomes, friendly error, technical details, retry, and partial-success reporting. Add
global recovery handling plus a local-only, rotating, redacted diagnostic log and "Copy diagnostics"
action; telemetry need not be introduced.

## P2 - testing, UX, and maintainability

### [ ] H-15 - Test real journeys and enforce risk-based coverage

**Finding:** test count is healthy, but critical runtime files have very low coverage and there is no
normal end-to-end suite for real transfers, cancellation, restart, config rollback, or packaged
platform behavior. CI uploads LCOV without a threshold; release is the first full platform build.

**Evidence:** `.github/workflows/ci.yml:37-45`; `app/test/`; absence of `app/integration_test/` at the
audited commit.

**Acceptance notes:** add deterministic state/race tests, local-rclone integration journeys,
Android emulator and packaged-desktop smoke tests, and golden/accessibility checks. Start with a
ratcheting changed-lines threshold plus higher floors for engine, transfer, config, persistence, and
platform bridges rather than chasing a single vanity percentage.

### [ ] H-16 - Build dedicated mobile and accessibility behavior

**Finding:** mobile reuses desktop table/job layouts, causing narrow filenames and fixed metadata
columns. Touch rows can be 36 px although the design calls for 56 px; long press opens a menu before
selection; no explicit Semantics foundation or semantics tests were found. Keyboard selection lacks
Up/Down/Home/End/Shift-range and macOS Command parity.

**Evidence:** `app/lib/src/ui/browser_pane.dart:2174-2268`;
`app/lib/src/ui/column_header.dart:61-110,180-233`;
`app/lib/src/ui/mobile_home.dart:824-867`;
`app/lib/src/ui/theme/tokens.dart:361-403`;
`app/lib/src/ui/home_screen.dart:116-203`; `wiki/core/06-design-system.md:101-132`.

**Acceptance notes:** create touch-native file and transfer cards with stacked metadata; use 48/56 px
targets; long press should enter selection; restrict narrow split view until responsive panes exist;
add semantic roles/states/live progress, focus traversal, 200% text-scale, contrast, reduced-motion,
and screen-reader smoke tests. Honor `MediaQuery.disableAnimations`; animated multi-part QR should
start paused or use slower/manual paging (`offline_qr_dialog.dart:70-105`). Reorganize the long flat
Settings screen and add a connection-test/Open-remote completion step to remote creation only after
the foundational interaction work is complete.

### [ ] H-17 - Keep README/store claims generated from shipped capability state

**Finding:** README and Play copy describe mobile Files integration, two-way sync/dry-run preview,
active-transfer pause, MDM/policy/audit/SIEM/SBOM, and other capabilities that are absent, partial, or
desktop-only. The mobile UI exposes Files/Transfers/Settings rather than saved tasks/sync surfaces.

**Evidence:** `README.md:32-37,69-72,98-105`;
`docs/store/play/listing-en-US.md:39-69`;
`app/lib/src/ui/mobile_home.dart:142-160`;
`app/lib/src/ui/jobs_panel.dart:114-120`;
`app/lib/src/state/mount_policy.dart`; `app/lib/src/state/serve_policy.dart`.

**Acceptance notes:** maintain one machine-readable capability matrix with available/experimental/
planned and per-platform states; generate or validate README/store copy from it; do a truth audit
before every store submission. Do not use implementation plans as present-tense marketing claims.
Add a public privacy policy plus an in-app link and complete the store data/permission declarations
before a production submission.

### [ ] H-18 - Reduce resource and dependency risk after the safety pass

**Finding:** large UI/controller files duplicate policies, thumbnail downloads buffer full bodies and
do not dispose native decode resources, and several direct dependencies need planned upgrades
(`flutter_markdown` was reported discontinued at the audit baseline). The app update comparison also
uses substring matching, which can confuse similarly prefixed versions.

**Evidence:** `app/lib/src/ui/browser_pane.dart`; `app/lib/src/ui/settings_screen.dart`;
`app/lib/src/state/thumbnail_service.dart:75-79,165-176,213-223`; `app/pubspec.yaml`;
`app/lib/src/state/app_info.dart:52-53`.

**Acceptance notes:** extract use-case coordinators before mechanically splitting widgets; stream
thumbnail responses with hard byte limits and dispose codecs/images; add a scheduled dependency lane
and upgrade in tested groups rather than mixing major upgrades into safety fixes. Use semantic-version
comparison for application updates.

## Recommended implementation order

1. **Process/job safety:** H-01, H-02, H-07.
2. **Data-operation safety:** H-03, H-04, H-05.
3. **Release integrity:** H-06, H-10, the Android portion of H-12.
4. **Trust and resilience:** H-08, H-09, H-11, H-13, H-14.
5. **Quality/product alignment:** H-15 through H-18.

Do not start by adding another native skin or splitting files solely by line count. The highest-leverage
change is to centralize invariants so one implementation protects desktop, mobile, interactive,
scheduled, and headless paths together.
