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
| **Verify (app)** | `cd /d/git/Airclone-rc/app && flutter pub get && dart format --output=none --set-exit-if-changed lib test && flutter analyze && flutter test` |
| **Verify (package)** | `cd /d/git/Airclone-rc/packages/airclone_rc && dart pub get && dart format --output=none --set-exit-if-changed . && dart analyze --fatal-infos && dart test` |
| **Format gotcha** | format `lib test`, not `.`, once you have built locally: `build/` holds generated Dart (cargokit) that is not formatted, and `dart format` does not honour the analyzer's `exclude`. CI checks out clean, so it never sees this |
| **Live engines** | both smoke tests are opt-in env vars: `AIRCLONE_RCLONE="C:/Program Files/Airclone/rclone.exe"` (v1.75.1, the pin) and `AIRCLONE_LIBRCLONE=<built librclone.dll>`. Binaries exist on this machine already — do not go looking for a download |
| **Issue** | [#6](https://github.com/GigaionLLC/Airclone/issues/6) stays open; reply at each milestone (plan → "Keeping #6 informed"). Draft first, post only after the user approves |

## Status

**Current step: B5 `operations`, on the typed-API branch. B1-B4 are done, and B5 has
migrated `job`, `mount`, `serve`, `vfs`, `core` and `config` - every namespace except
`operations`.** Each migration ran the whole app suite: 1685 passing / 1 skipped before and
after every one of them, which is what the golden tests exist to guarantee.

Previous state of this line: The merge (A4.4) is deliberately NOT happening
— the maintainer said so on 2026-09-20: keep working, do not merge.** A1, A2, A3 and the rest
of A4 are done and green, and the spawned-`rcd` smoke test is now done too (see A3 evidence),
so nothing in Milestone A is outstanding except the merge itself and the #6 updates, which
wait on the maintainer's wording approval.

Previous state of this line, kept because it says what A3 was: A1, A2 and most of A4 are done and
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
| B1 typed API | **DONE** `bb2f6f4` (branch `feat/airclone-rc-typed-api`) | `RcApi` over `rpc`, golden param tests; kept OFF PR #7 |
| A3 checkpoint | **PASSED** | every check green except the pre-existing `popout`; macOS flake cleared by a re-run |
| A4.1 web build | **DONE** | `flutter build web --no-web-resources-cdn` built clean in 160s — R6 closed |
| A4.2 Flathub note | **DONE** `f72f1bb` | no manifest exists yet, so it is a note for whoever generates one |
| A4.3 boundary docs | **DONE** `2de07e4` | `wiki/core/08` §3.0, AGENT.md, backlog row |
| A4.4 merge | **WAITING ON THE USER** | expect an AGENT.md conflict with the CLA session's rule; `main` was still at `4f346b6` at the last check |
| A5 notes | **DRAFTED** `1434ed0` | `dev/releases/v0.20.0.md`; the version bump and the release itself wait on the user |
| A4.5 rcd smoke test | **DONE** `52bd8ab` | live `HttpRcloneClient` against the pinned rclone v1.75.1, 10 passing; the same test now runs in CI's `package-airclone-rc` job against a checksum-verified download |
| B2 golden params | **DONE** | every typed method pins its method string and params map in `test/rc_api_test.dart` (15 tests) |
| B3 namespaces | **DONE** | `core`, `config`, `operations`, `job`, `sync`, `mount`, `serve`, `vfs`. Chosen from what the app calls, not from what rclone offers |
| B4 gotchas encoded | **DONE** | `config/create`'s `parameters`, serve's snake_case `read_only`/`vfs_cache_mode`, mount's Go field names, `vfs/refresh`'s string `'true'`, bisync's `path1`/`path2`, check's five bucket flags |
| B5 job | **DONE** | 7 call sites |
| B5 mount/serve/vfs | **DONE** | the controllers lost their response parsing; serve/start's hand-kept whitelist is now a signature |
| B5 core/config | **DONE** | 12 call sites, 11 files |
| B5 operations | NEXT | `operations/list` LAST: 9 call sites and the browser's hot path |

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

The two after-the-move numbers must add up to the baseline. **They no longer do, on purpose:**
`415cefc` added 2 package tests (`instance_tag_test.dart`) and `52bd8ab` added 10 more
(`rcd_integration_test.dart`, skipped unless `AIRCLONE_RCLONE` is set), so the package now
reports **50 passing, 17 skipped**. The identity 1685 + 48 = 1733 holds at the move commit
`94c3915`, which is where the gate applies.

## A3: PASSED (2026-09-20)

Final run on the pushed head `6fa818e`: `analyze-test` pass, **`package-airclone-rc` pass**,
`docs` pass, `compile` pass, `mount-probe` pass, `window-behaviour` **pass**, `cla` pass,
`Airclone CLA` pass, `rclone-pin` pass, `flatpak` skipped. `popout` fails, as it does on
`main`. The `librclone` (all three platforms), `ios-verify` and `mas-verify` runs passed on
the identical `lib/src` — the only package change after them was formatting `example.dart`,
which is outside their path filters.

## A3 evidence (2026-09-19)

- **Live FFI engine, locally:** the package's `librclone_integration_test` run against a real
  `librclone.dll` (the one built in the sibling worktree) — **7 passing**, not skipped. RC
  round-trip, `restart()`, an `_async` `sync/copy` through `job/status`, two engines
  back-to-back in one process, and the object server serving bytes with Range. This is the
  in-process engine working end-to-end from its new home.
- **CI on PR #7:** passing — `package-airclone-rc` (the new job, 38s), `analyze-test`,
  `docs`, `cla`, `mount-probe`, Linux `compile`, **all three `librclone` build-and-verify
  matrix legs** (Linux, macOS, Windows) and the MAS `sandbox-verify`. The librclone legs
  matter twice over: they prove the repointed `paths:` filter fires AND that the integration
  test now runs from the package with `dart test`. `ios-verify` and the Linux/macOS runners
  fired on their own, which is more evidence the filters are right.
- **`window-behaviour` (macOS): CLEARED — it was a runner flake.** The first branch run
  segfaulted on the plain launch (`plain launch: 0 window(s)`) while `main` passed the same
  job in the same hour. Re-running the job on the SAME commit passed
  (`plain launch: 1 window(s)`), so the crash was the runner, not the split. Worth knowing
  that this job can fail this way: re-run it once before bisecting anything.
- **`ios-verify` (simulator): passed** on the branch.
- **The example runs standalone:** `dart run example/example.dart --librclone …` printed
  `rclone v1.74.4` and a real listing, with no Airclone involved.
- **Local Windows build + run:** `flutter build windows --release` succeeded (387s) and the
  built `airclone.exe --version` printed `Airclone 0.13.9` and exited 0 — the real desktop
  binary, built against the package, running its headless path.
- **Web build:** `flutter build web --no-web-resources-cdn` succeeded, so the conditional
  `dart.library.js_interop` exports still keep `dart:ffi` out of the web build.
- **`popout` fails, and it is NOT ours.** The Linux runner's pop-out probe fails on `main`
  too (three runs running back to 2026-09-15) and is `continue-on-error: true`, so the
  workflow still reports success. It is the known Flutter/Linux multi-window experiment:
  "the patched plugin does not survive either". Do not chase it.
- **Live spawned engine (`rcd`), locally: DONE 2026-09-20.** `test/rcd_integration_test.dart`
  run against `C:/Program Files/Airclone/rclone.exe` (**v1.75.1 — the pin**): **10 passing**,
  not skipped. It spawns the child, proves it received our `--config` (an empty config, so a
  run cannot see the caller's remotes), round-trips `core/version` and `rc/noop`, maps a bad
  method to `RcloneException`, restarts, drives an `_async sync/copy` to `success` through
  `job/status`, serves object bytes over loopback with Range **and 401s without the session
  credentials**, uploads through the hand-built multipart body, reads `core/command` as lines,
  and shows `quit()` leaving neither a reap marker nor a live PID. `example.dart --rclone …`
  also printed `rclone v1.75.1` and a real listing. **Both engines are now proven standalone.**
- **Correction to an earlier note here:** it said there was no `rclone` binary on this machine.
  There are several — `C:/Program Files/Airclone/rclone.exe` (v1.75.1),
  `%APPDATA%/app.airclone/airclone/engine/rclone.exe` (v1.74.3) and two WinGet copies. Only
  `PATH` and the Go module cache had been checked. No download was needed, and the failed
  offline `go build` was never necessary.

## B5: where to start migrating call sites (not done — one namespace per PR)

`job/*` is the cleanest first namespace: five call sites, each an exact 1:1 with a typed
method, all already covered by tests.

| Call site | Becomes |
| :--- | :--- |
| `state/file_ops.dart:44` `rpc('job/stop', {'jobid': j})` | `api.job.stop(j)` |
| `state/file_ops.dart:203` `rpc('job/status', …)` | `api.job.status(jobid)` |
| `state/jobs_controller.dart:203` | `api.job.stop(jobid)` |
| `state/jobs_controller.dart:259` | `api.job.status(jobid)` |
| `state/scheduler_controller.dart:377` | `api.job.status(rcJobid)` |

Hold ONE `RcApi` per client rather than building one per call — the jobs poller runs at 1 Hz.
`operations/list` is deliberately NOT first: its params come from `Remote.listParams`, which
carries the v0.13.2 `copy_links` fix, so that migration wants its own careful pass.

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
- **2026-09-19 (A3):** `dart format --output=none` REPORTS a file as changed but does not
  write it. Seeing "1 changed" and moving on is how an unformatted example reached CI. Run
  `dart format .` (no `--output=none`) to fix, then the checking form to verify.
- **2026-09-19 (A2):** the package does NOT commit `pubspec.lock` (it is a library; consumers
  resolve their own versions), so `packages/airclone_rc/.gitignore` excludes it.
- **2026-09-19 (A2):** `engine_log_test` split in two. `isEngineFailureLine` went to the
  package; the ingest-redaction assertion stayed in `app/test/engine_log_bridge_test.dart`.
- **2026-09-19 (A2):** `src/platform.dart` is deliberately NOT exported from the barrel — a
  host has its own idea of which OS it is on.
- **2026-09-19 (A1):** two test fakes extend `HttpRcloneClient`
  (`console_controller_test`, `console_pane_focus_test`), so a required constructor
  argument reaches them too. Grep for `super(` as well as `HttpRcloneClient(`.

## Hazards found while migrating (B5)

- **`return someFuture()` inside a `try` is not caught.** `mountTypesProvider` became
  `return RcApi(client).mount.types();`, which returns the future OUT of the try block, so
  the empty-list fallback for "WinFsp is not installed" would have stopped running and the
  provider would have thrown instead. `flutter analyze` caught it
  (`unawaited_return_in_try_block`) - it is `return await` now. Expect this on every
  single-expression `try { return await client.rpc(...) }` that gets migrated.
- **Writing Windows paths into a doc through a script's string escapes** turned `\a` and
  `\r` into real BEL and CR bytes in this very file, and `tool/check-docs.py` failed the
  `docs` job for it. Use forward slashes in docs, or write the file with a tool that does
  not process escapes.
- **Two `config/create` callers carry an `opt` that decides whether rclone obscures
  passwords** (`obscure` when they come from a dialog, `noObscure` when they came out of
  `config/get` already obscured). Neither is part of the typed signature, so both go through
  `extra` - the reason `extra` exists.

## Known hazards being closed

- **R2 reaper names:** `instanceTag` is required, with the app passing `'airclone'` so temp
  file names stay byte-identical and a v0.20.0 launch still reaps a v0.13.x orphan.
- **R1 workflow path filters:** `librclone.yml`, `ios-verify.yml`, `mas-verify.yml` must be
  repointed in the same commit as the move.
- **R3 CI gates:** the package needs its own format/analyze/test job.
- **R4 diagnostics:** the sink must stay behind the package's filter, and Airclone must pass
  `logDiagnostic` so redaction still happens at ingest.
