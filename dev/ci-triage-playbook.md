# 🚦 CI Triage Playbook

What to do when a check on a pull request or on `main` is red, or green with a warning. Written so a cheaper
model can find the cause without guessing, and knows which reds are expected.

**When to read this:** `gh pr checks <n>` shows a failure, a `CI` run on `main` failed, or a green run shows a
warning ([AGENT.md](../AGENT.md) rule 8: a warning is work).

The workflow table in [dev/README.md](README.md#-ci-workflows) says what every workflow does. This page is about
reading their failures.

---

## 👤 Who may do what

| Action | Who |
| :--- | :--- |
| Read logs, rerun a failed job once when the log shows a network or runner fault | Agent |
| Fix the cause in the PR branch and push again | Agent |
| Change a test's expectation | Agent, only when the PR changed that behaviour on purpose, and the PR body says so |
| Change, skip or weaken a check in `.github/workflows/` | Agent, in its own PR with the reason; never during a ship run. Price checks (`test_store_submit.py`, `test_msstore_price.py`) and the CLA check: **Jake** |
| Rerun or retry a store lane (`ship.yml`, `submit-msstore.yml`, `asc-*`, `publish-play.yml`) | Only as the [store playbook](store-release-playbook.md) says. Never when the lane already created a store-side object |

## ⛔ NEVER

- **Never merge red.** A required check that failed blocks the merge even when "it's unrelated". Prove it is
  unrelated by rerunning it, or fix it.
- **Never make a check pass by deleting or skipping the test**, or by adding `continue-on-error`.
- **Never rerun more than once** without reading the log. A second identical failure is not flaky.
- **Never poll faster than 90 s** (`--interval 90`).
- **Never run `dart format` from the local Docker image** to fix a format failure. Its Flutter lags the CI pin,
  and an older formatter reformats files the gate then rejects. Read the exact diff in the log and fix it by hand.

---

## Steps

| # | Do | Command | Success | STOP if | Retry-safe |
| :-- | :--- | :--- | :--- | :--- | :--- |
| 1 | Which check, which run | `gh pr checks <n>` (or `gh run list --branch main --limit 10 --json name,conclusion,databaseId`) | You have the run id and the failed job name | | Yes |
| 2 | Read only the failed steps | `gh run view <run> --log-failed \| tail -150` | You can quote the first error line | The log is empty: the workflow file may not parse (step 6) | Yes |
| 3 | Match it to the table below | | Cause found | No row fits after reading the full log twice: advisor (coordinator playbook §8) | Yes |
| 4 | Network or runner fault only (`curl: (56)`, `503`, `ETIMEDOUT`, runner lost) | `gh run rerun <run> --failed` | Green on rerun | Red again with the same error: it is real | **Once** |
| 5 | Fix, local checks, push | the fix, then `python3 tool/check-docs.py`, `python3 tool/check-workflows.py` (if workflows changed), `python3 -m unittest discover -s tool -p 'test_*.py'` | Each exits 0, CI green | | Yes |
| 6 | A workflow that fails with no logs | `python3 tool/check-workflows.py` | It names the file and line | | Yes |
| 7 | Write it down | the PR body ("CI: <check> failed because <...>, fixed by <...>") or the state file for a `main` failure | Recorded | | Yes |

## What each required check runs, and what its failures mean

| Check | Runs | Typical failure | Do |
| :--- | :--- | :--- | :--- |
| `analyze-test` | in `app/`: `flutter pub get`, `dart format --set-exit-if-changed`, `flutter analyze`, `flutter test --coverage`, `flutter build web` | **Format:** the log lists the files `dart format` would change | Apply the change the log shows, by hand, exactly as shown |
| | | **Analyze:** `info`, `warning` or `error` with `file:line:col` and a lint name | Fix the line. Don't add `// ignore:` unless the lint is wrong for that line, with a reason in the comment |
| | | **Test:** `Expected: ... Actual: ...` plus the test name | Find the test in `app/test/`, see whether your change caused it. Fix the code, or fix the test if the behaviour change was intended |
| | | **Web build:** a `dart:io` or FFI import reached web code | Use the `_io` / `_web` conditional-import pairs that already exist (`*_io.dart`, `*_web.dart`) |
| `package-airclone-rc` ×3 (Linux, Windows, macOS) | in `packages/airclone_rc/`: format, `dart analyze --fatal-infos`, `dart test`, the spawned-engine test against the pinned real rclone, and "the package never imports the app" | Fails on one OS only | It's a real OS difference (paths, PIDs, line endings, process kill). Don't skip the OS. Read that leg's log |
| | | `airclone_rc must not import the app` | Remove the `package:airclone/` import from the package. The package may import neither the app nor Flutter ([AGENT.md](../AGENT.md) §4) |
| | | `could not read the rclone pin` / `checksum mismatch` | The pin in `release.yml` was edited badly, or upstream changed a published zip. A mismatch on an unchanged pin is a STOP: tell Jake (possible supply-chain problem) |
| `docs` | `tool/check-docs.py`, `compileall tool/`, the CLA, store-price and ship-lane tests, `tool/check-workflows.py` | `BROKEN` link | Fix the link (path relative to the file) |
| | | A test in `test_store_submit.py` or `test_msstore_price.py` | These guard the price customers pay. Find what your change broke; never edit these tests to pass. Not your change? STOP, tell Jake |
| | | `compileall` error | A tool script no longer parses. Often a non-ASCII character (rule 12) |
| `rclone-pin` | compares the five rclone pin sites and the upstream version | **Never fails, only warns.** "pin drift": the five sites differ. "behind the latest upstream": a new rclone exists | Drift: fix in the same PR. Behind: that is the weekly bump ([rclone-bump playbook](rclone-bump-playbook.md)), not your PR |
| `cla` / `Airclone CLA` | `cla.yml` (`pull_request_target`) checks every commit author against the ledger | Red on an outside PR: an author has not signed | Nothing to fix in code. The bot comment tells them how. Don't merge (coordinator playbook §5) |
| | | Red on our own PR | The commit author isn't the expected account. Check `git log --format='%an %ae'`. STOP and tell Jake: don't rewrite the history of a pushed branch on your own |

## 🪤 Expected reds and known traps

| Symptom | Means | Do |
| :--- | :--- | :--- |
| `linux-runner.yml` red on the `popout` job | `continue-on-error` probe, fails by design | Ignore |
| `asc-version.yml mode=report` red "no editable version" | Expected when nothing is editable | Ignore; never use it to poll |
| A green dry-run store workflow | Green while nothing changed | Read the log's answer, not the tick (rule 9) |
| The weekly Monday 06:00 UTC `CI` run red with no repo change | Upstream drift: a new Flutter, pub package or rclone | Treat as work: find what moved. Pins live in `release.yml` and `ci.yml` |
| `HTTP 403 ... secondary rate limit` from `gh` | Too many calls in parallel or too fast | One watcher, 90 s |
| Push rejected for a workflow file over HTTPS | The gh token lacks `workflow` scope | Push over SSH (coordinator playbook step 3.6) |
| An empty `${{ }}` in a workflow comment | Breaks the whole file | `check-workflows.py` names it |

## 📋 Report template

```
CI triage, <date> <time Pacific>
Run <id> (<workflow> on <branch/PR>): <check> failed at <step>
First error: <one line>
Cause: <flaky network | my change | upstream drift | expected red>
Action: <rerun once -> green | fixed in <sha> | handed to <Jake/advisor> because <...>>
```

## Related

[Coordinator playbook](coordinator-playbook.md) · [Code-change guide](code-change-guide.md) · [Store release playbook](store-release-playbook.md) · [Dev hub](README.md)
