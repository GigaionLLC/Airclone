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

**Current step: A1 — decouple in place.**

| Step | State | Notes |
| :--- | :--- | :--- |
| A0 baseline | **DONE** | see below |
| A1.1 log sink | `TODO` | |
| A1.2 `echoEngineLines` | `TODO` | |
| A1.3 `onUndecryptableName` | `TODO` | |
| A1.4 `instanceTag` | `TODO` | |
| A1.5 package-private platform | `TODO` | |
| A1.6 playlist helper | `TODO` | |
| A1.7 `package:meta` | `TODO` | |
| A1.8 redaction test | `TODO` | |
| A2 package + move | `TODO` | |
| A3 checkpoint | `TODO` | |
| A4 docs + merge | `TODO` | |
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
| `app/test` at `4f346b6` | 181 | _pending_ |
| `app/test` after the move | | |
| `packages/airclone_rc/test` after the move | | |

The two after-the-move numbers must add up to the baseline.

## Decisions taken while implementing

_(append here; each entry dated, so the plan can be corrected at wrap-up)_

## Known hazards being closed

- **R2 reaper names:** `instanceTag` is required, with the app passing `'airclone'` so temp
  file names stay byte-identical and a v0.20.0 launch still reaps a v0.13.x orphan.
- **R1 workflow path filters:** `librclone.yml`, `ios-verify.yml`, `mas-verify.yml` must be
  repointed in the same commit as the move.
- **R3 CI gates:** the package needs its own format/analyze/test job.
- **R4 diagnostics:** the sink must stay behind the package's filter, and Airclone must pass
  `logDiagnostic` so redaction still happens at ingest.
