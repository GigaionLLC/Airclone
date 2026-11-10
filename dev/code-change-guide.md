# 🛠️ Code-Change Guide

How to make a change to the app, the `airclone_rc` package or the `tool/` scripts, from "I know what to change"
to a pull request someone can merge with confidence. Written for an agent that is careful but new to this code.

**When to read this:** before you edit anything under `app/`, `packages/` or `tool/`. The process around it
(worktree, push, PR, merge) is in [coordinator-playbook.md](coordinator-playbook.md) §3. A red check is
[ci-triage-playbook.md](ci-triage-playbook.md).

---

## 👤 Who may do what

| Action | Who |
| :--- | :--- |
| Fix a bug, add a test, refactor, improve a tool script, update docs | Agent |
| A change that `tool/carveout_paths.py` flags as SECURITY or SIGNING | Agent may write it; it merges only after a written security review (coordinator playbook §3.9) |
| A change it flags as MONEY (prices, price checks) | **Jake only** |
| A new feature that changes what users see on more than one platform | Agent proposes it in a plan; the design choice goes to the advisor or Jake first |

## ⛔ NEVER

- **Never call rclone a second way.** Everything goes through the one `RcloneClient` interface
  ([AGENT.md](../AGENT.md) rule 1).
- **Never put a secret in argv, a log line, a URL or a test fixture** (rule 16). Passwords go in env vars or stdin.
  New log output passes through the existing redaction (`log_redaction.dart`, `console_redaction.dart`).
- **Never add a delete, purge, overwrite or one-way sync without a confirmation** (rule 4).
- **Never hard-code colours, sizes or spacing.** Use the design tokens ([wiki/core/06-design-system.md](../wiki/core/06-design-system.md), rule 2).
- **Never make `packages/airclone_rc` import the app or Flutter.** `RcloneClient` never grows a member.
- **Never weaken a guard to make a test pass**: an allowlist, a param guard, a denylist entry, a trust check.
- **Never print non-ASCII from a `tool/` script** (rule 12).

---

## 1. Find the code

| You are changing… | Look in | Read first |
| :--- | :--- | :--- |
| A screen, dialog or widget | `app/lib/src/ui/` | [06-design-system](../wiki/core/06-design-system.md), [wiki/features/](../wiki/features/features-index.md) |
| App state, a controller, settings | `app/lib/src/state/` | [07-state-context](../wiki/core/07-state-context.md) |
| How rclone is started or driven | `app/lib/src/state/engine_*.dart`, `app/lib/src/rclone/`, `packages/airclone_rc/lib/src/` | [08-core-architecture](../wiki/core/08-core-architecture.md) (all of it) |
| The browser web UI and its server | `app/lib/src/webui/` | [15-security](../wiki/core/15-security.md): this is a carve-out |
| The console | `app/lib/src/state/console/`, `app/lib/src/ui/console_pane.dart` | [11-validation-standards](../wiki/core/11-validation-standards.md), [15-security](../wiki/core/15-security.md) |
| In-app updating | `app/lib/src/update/` | [15-security](../wiki/core/15-security.md): this is a carve-out |
| Media playback | `app/lib/src/native/`, `app/lib/src/ui/media_*` | [media-support-matrix.md](media-support-matrix.md) |
| Release, store or CI glue | `tool/*.py`, `.github/workflows/` | [store-release-playbook.md](store-release-playbook.md); never during a ship run |

The full file map is [wiki/core/04-directory-structure.md](../wiki/core/04-directory-structure.md). Search before you
add: `grep -rn "<name>" app/lib packages/airclone_rc/lib` often finds a helper that already does it.

## 2. Make the change

1. **Smallest change that fixes the cause.** Don't refactor nearby code in the same PR.
2. **Platforms.** Ask for each of Windows, macOS, Linux, Android, iOS: does it apply, and does it still work? Code that
   uses `dart:io` or FFI needs the existing `_io` / `_web` conditional-import pattern, or the web build fails.
   If what a platform can do changes, update [docs/guide/platforms.md](../docs/guide/platforms.md) in the same commit (rule 20).
3. **Tests.** Every bug fix gets a test that failed before the fix. App tests live in `app/test/<area>_test.dart`, package
   tests in `packages/airclone_rc/test/`, tool tests in `tool/test_<script>.py` (run directly, `unittest`). Copy the
   style of the nearest existing test.
4. **Comments say why, not what.** A comment that states an invariant needs a test or an assert that enforces it (rule 15).

## 3. Check it locally

| Check | Command | Notes |
| :--- | :--- | :--- |
| Tool scripts | `python3 -m unittest discover -s tool -p 'test_*.py'` | Must exit 0 |
| Docs | `python3 tool/check-docs.py` | 0 broken links |
| Workflows (if touched) | `python3 tool/check-workflows.py` | |
| Carve-outs | `python3 tool/carveout_paths.py --base origin/main` | Exit 3 = STOP, see §5 |
| Dart analyze / tests (optional) | `docker compose run --rm -T flutter flutter analyze` and `... flutter test test/<file>_test.dart` | The local image's Flutter **lags the CI pin**, so CI is the real gate. **Don't run `dart format` from it.** It leaves root-owned files in the worktree (the cleanup is in the coordinator playbook's traps) |
| Invisible characters | `grep -nP '[^\x00-\x7F]' <changed files>` | Review every hit in code you generated (rule 18). Emoji in docs are fine |

## 4. Self-review checklist (put the answers in the PR body)

- [ ] What was the cause, in one sentence? Does the change fix the cause or hide the symptom?
- [ ] Any secret, token or password: never in argv, logs, URLs, fixtures, errors shown to users?
- [ ] Any input from a user, a remote file name or a server: validated before use (paths, `..`, option strings)?
- [ ] Any file written or extracted: stays inside the folder the user picked?
- [ ] Any new listener, port or `serve`: bound to loopback, authenticated?
- [ ] Any destructive action: confirmed first?
- [ ] Failure path: does it fail closed, with a plain message to the user and detail only in the log?
- [ ] All five platforms considered; `platforms.md` updated if a capability changed?
- [ ] Tests added; local checks above exit 0?
- [ ] `tool/carveout_paths.py` result pasted into the PR body?

## 5. Carve-outs

If `tool/carveout_paths.py` exits 3:
- **SECURITY / SIGNING:** finish the change, open the PR, and write the review brief (what changed, why, the checklist
  answers, what you're unsure about). It merges only after a written review with no high findings. No reviewer
  available means it waits. Note it where the coordinator tracks open items, then move on to other work.
- **MONEY:** stop, don't push. Write down what you wanted to change and why, for Jake.

## 6. PR body template

```
## What and why
<one paragraph: the user-visible problem and its cause>

## Changes
- <file>: <what>

## Verified
- <tests added, local checks, CI>

## Not verified
- <e.g. a real FUSE mount, a real OAuth sign-in, iOS on a device>

## Self-review
<the §4 checklist with answers>

## Carve-outs
<tool/carveout_paths.py output>
```

## Related

[Coordinator playbook](coordinator-playbook.md) · [CI triage playbook](ci-triage-playbook.md) · [rclone bump playbook](rclone-bump-playbook.md) · [AGENT.md](../AGENT.md) · [Dev hub](README.md)
