---
type: "plan"
name: "airclone_rc Progress Log"
status: "active"
description: "Running state of the airclone_rc package split, so any session can resume it."
---

# 🧭 airclone_rc — progress log

Live state for [airclone-rc-package-plan.md](airclone-rc-package-plan.md). **Update this file
at the end of every step and commit it with that step's work.** It exists so a session that
stops mid-way can be replaced by one that reads only this file.

## How to resume

| | |
| :--- | :--- |
| **Worktree** | `D:\git\Airclone-rc` (a second checkout; `D:\git\Airclone` is other sessions' and is never touched) |
| **Branch** | `refactor/airclone-rc-package`, branched from `origin/main` at `4f346b6`, **no upstream on purpose** so a bare `git push` cannot reach `main` |
| **Commits** | small, one per plan step, on the branch only. Nothing is pushed until the A3 checkpoint passes and the user says so |
| **Other sessions** | edit `D:\git\Airclone` at the same time. Stage by explicit path, never `git add -A`, never `checkout`/`restore`/`stash` in the main worktree |
| **Verify** | `cd /d/git/Airclone-rc/app && flutter pub get && dart format --output=none --set-exit-if-changed . && flutter analyze && flutter test` |
| **Issue** | [#6](https://github.com/GigaionLLC/Airclone/issues/6) stays open; reply at each milestone (plan → "Keeping #6 informed"). Draft first, post only after the user approves |

## Status

**Current step: A3 — the proof-of-concept checkpoint.** A1, A2 and most of A4 are done and
green locally. The branch is pushed and **draft [PR #7](https://github.com/GigaionLLC/Airclone/pull/7)**
is open, which is what makes `ci.yml` run (it triggers on `main` and pull requests, not on a
branch push). `librclone.yml` and `mas-verify.yml` were dispatched against the branch;
`ios-verify.yml`, the Linux and macOS runners fired on their own, which is itself evidence the
repointed path filters work.

**Remaining before the branch leaves draft:** CI green, the web build, a desktop smoke test,
and the user's approval to merge. Nothing merges without it.

| Step | State | Notes |
| :--- | :--- | :--- |
| A0 baseline | **DONE** | see below |
| A1.1 log sink | **DONE** `c70497f` | `RcloneLogSink` + `logEngineEvent` bridge; filter stays in the package |
| A1.2 `echoEngineLines` | **DONE** `04558df` | default OFF; app passes `kDebugMode` |
| A1.3 `onUndecryptableName` | **DONE** `04558df` | |
| A1.4 `instanceTag` | **DONE** `07c271d` | required, no default; app passes `'airclone'`; new test that another app's markers are untouched |
| A1.5 package-private platform | **DONE** `d512e03` | `EnginePlatform`, web guard = Flutter's own `kIsWeb` constant |
| A1.6 playlist helper | **DONE** `d512e03` | `rclone/playlist_exts.dart`; `media_formats.dart` imports AND re-exports it (an export alone does not bring names into scope) |
| A1.7 `package:meta` | **DONE** `04558df`, `51e08bc` | `meta` is now a direct dependency; only the lockfile's dependency KIND changed |
| A1.8 redaction test | **DONE** `51e08bc` | `test/engine_log_bridge_test.dart` |
| A2 package + move | **DONE** `94c3915` | scaffold `a1f0e17`-style commit first, then one rename-only move commit |
| A2 gates | **DONE** | lock diff = one path entry; 1685 app + 48 package = 1733; docs gate clean |
| A3 checkpoint | **IN PROGRESS** | PR #7 draft; CI + librclone + mas-verify + ios-verify running |
| A4.1 web build | **DONE** | `flutter build web --no-web-resources-cdn` built clean in 160s — R6 closed |
| A4.2 Flathub note | **DONE** `f72f1bb` | no manifest exists yet, so it is a note for whoever generates one |
| A4.3 boundary docs | **DONE** `2de07e4` | `wiki/core/08` §3.0, AGENT.md, backlog row |
| A4.4 merge | `TODO` | needs the user's approval; expect an AGENT.md conflict with the CLA session's rule |
| A5 release | `TODO` | |

## A0 baseline (2026-09-19)

- **Base commit:** `4f346b6` (`origin/main`). Everything below is measured there, and the A2
  gate compares against it: `git diff 4f346b6 -- app/pubspec.lock` must show only the added
  `airclone_rc` path entry.
- **Local SDK:** Flutter 3.47.0 / Dart 3.13.0 — matches the CI pin, so `dart format` here is
  safe to commit (an older formatter is what broke the v0.6.3 release).
- **`flutter pub get`:** clean, `pubspec.lock` unchanged.
- **Last green runs on `main`:** `librclone` 2026-09-12, `ios-verify` 2026-09-11,
  `mas-verify` 2026-09-14. All `success`, so a failure after the move is attributable.
- **Test baseline:** see "Test counts" below.

### Test counts

| Where | Files | Tests passing |
| :--- | ---: | ---: |
| `app/test` at `4f346b6` | 181 | **1729 passing, 8 skipped** (exit 0) |
| `app/test` after the move | 176 | **1685 passing, 1 skipped** |
| `packages/airclone_rc/test` after the move | 6 | **48 passing, 7 skipped** |

The two after-the-move numbers must add up to the baseline.

## A3 evidence so far (2026-09-19)

- **Live FFI engine, locally:** the package's `librclone_integration_test` run against a real
  `librclone.dll` (the one built in the sibling worktree) — **7 passing**, not skipped. RC
  round-trip, `restart()`, an `_async` `sync/copy` through `job/status`, two engines
  back-to-back in one process, and the object server serving bytes with Range. This is the
  in-process engine working end-to-end from its new home.
- **CI on PR #7:** `package-airclone-rc` (the new job) passed in 38s; `docs`, `cla`,
  `mount-probe` and the Linux `librclone` build-and-verify passed. The last one matters twice
  over: it proves the repointed `paths:` filter fires AND that the integration test runs from
  the package with `dart test`.
- **Web build:** `flutter build web --no-web-resources-cdn` succeeded, so the conditional
  `dart.library.js_interop` exports still keep `dart:ffi` out of the web build.
- **Still to do:** a spawned-`rcd` smoke test needs an `rclone` binary, and there is none on
  this machine. Ask the user before downloading one.

## Decisions taken while implementing

- **2026-09-19 (A1.1):** the sink signature carries `detail`, because
  `_noteTransportFailure` already passed one to `logDiagnostic` and dropping it would have
  lost the underlying error from bug reports.
- **2026-09-19 (A1.4):** `instanceTag` also names the rc username and the multipart
  boundary, so there is one token rather than three literals; an `assert` keeps it
  filename- and header-safe (`^[A-Za-z0-9_-]{1,32}$`).
- **2026-09-19 (A1.6):** `media_formats.dart` both imports and re-exports
  `playlist_exts.dart`. An `export` alone does not bring the names into the exporting
  library's own scope, which `isVideoLikeExt` needs.
- **2026-09-19 (A2):** the package does NOT commit `pubspec.lock` (it is a library; consumers
  resolve their own versions), so `packages/airclone_rc/.gitignore` excludes it.
- **2026-09-19 (A2):** `engine_log_test` split in two. `isEngineFailureLine` went to the
  package; the ingest-redaction assertion stayed in `app/test/engine_log_bridge_test.dart`.
- **2026-09-19 (A2):** `src/platform.dart` is deliberately NOT exported from the barrel — a
  host has its own idea of which OS it is on.
- **2026-09-19 (A1):** two test fakes extend `HttpRcloneClient`
  (`console_controller_test`, `console_pane_focus_test`), so a required constructor
  argument reaches them too. Grep for `super(` as well as `HttpRcloneClient(`.

## Known hazards being closed

- **R2 reaper names:** `instanceTag` is required, with the app passing `'airclone'` so temp
  file names stay byte-identical and a v0.20.0 launch still reaps a v0.13.x orphan.
- **R1 workflow path filters:** `librclone.yml`, `ios-verify.yml`, `mas-verify.yml` must be
  repointed in the same commit as the move.
- **R3 CI gates:** the package needs its own format/analyze/test job.
- **R4 diagnostics:** the sink must stay behind the package's filter, and Airclone must pass
  `logDiagnostic` so redaction still happens at ingest.
