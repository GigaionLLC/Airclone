# 🔁 rclone Bump Playbook

How to take the weekly `rclone-bump.yml` proposal (or a hand-made bump) from "upstream has a new rclone" to a
merged, verified pin. The worked example is PR #65 (v1.75.2 → v1.76.0, app 0.31.1).

**When to read this:** a PR titled "chore(engine): pin rclone v…" (branch `chore/rclone-<version>`) opened by [`rclone-bump.yml`](../.github/workflows/rclone-bump.yml)
(Mondays 07:00 UTC), or Jake asked to move rclone to a given version.

rclone is the engine that moves users' files, and its rc API is what the web UI and the console reach. A bump
is therefore a **security-relevant change**: a DeepSeek coordinator does the work, but the merge waits for the
Opus advisor's review ([coordinator playbook](coordinator-playbook.md#-who-may-do-what)).

---

## 👤 Who may do what

| Action | Who |
| :--- | :--- |
| Read the changelog, download and verify the upstream binary, run the probes | Agent |
| Edit the pin sites, the reasoning comment, denylist, fixtures, notes | Agent |
| Add a new rc call to the allowlist, or relax a web UI guard | **Claude or Jake** (security carve-out) |
| Merge the bump PR | Agent, after green CI **and** the advisor's review with no high findings |
| Tag a release that ships the new rclone | Only when Jake asks for a release ([store playbook](store-release-playbook.md)) |

## ⛔ NEVER

- **Never merge the automatic PR as opened.** It updates the five pins only. The reasoning comment, the checks
  below and the review are the work.
- **Never bump without checking the SHA256** of the upstream zip against upstream `SHA256SUMS`.
- **Never add an rc call to the allowlist** (`app/lib/src/webui/webui_rc_policy.dart`) as part of a bump. A new
  upstream call stays off the list; if Airclone needs it, that is a separate PR with a security review.
- **Never raise `secureRcloneVersion`** (`app/lib/src/rclone/rclone_engine.dart`) unless the release fixes a
  security issue that the app's own checks depend on, and you have checked it against the real binary.
- **Never update one pin site alone.** The bundled binary and the in-process librclone must match.
- **Never run upstream binaries outside a scratch folder** or with your real rclone config. Use a fresh, empty config.

---

## Steps

| # | Do | Command / where | Success | STOP if | Retry-safe |
| :-- | :--- | :--- | :--- | :--- | :--- |
| 1 | Worktree on the bump branch | `git -C ~/git/Airclone fetch origin && git -C ~/git/Airclone worktree add ../Airclone-wt-rclone chore/rclone-<version>` | Folder exists | | Yes |
| 2 | Five pins agree | `grep -rn "v1\.[0-9]*\.[0-9]*" .github/workflows/release.yml dev/android/build-rclone.ps1 dev/desktop/build-librclone.ps1 dev/desktop/build-librclone.sh dev/ios/build-librclone-ios.sh \| grep -i rclone` | All five name the new version; the `rclone-pin` CI check is green | They differ | Yes |
| 3 | Read the changelog | <https://rclone.org/changelog/>, every entry from the old to the new version | Notes in the PR body: security fixes, VFS / mount, `rcd` / rc API, `serve`, config flows, the backends Airclone lists | A removed or renamed rc call or flag Airclone uses: STOP, ask the advisor | Yes |
| 4 | Download and verify | in `~/airclone-scratch/rclone-<ver>/`: the linux-amd64 zip plus `SHA256SUMS` from `https://downloads.rclone.org/<ver>/`; `sha256sum -c --ignore-missing SHA256SUMS` | `OK` | Mismatch | Yes |
| 5 | New commands → console denylist | `rclone help` diff between old and new binary; compare with `app/lib/src/state/console/rclone_commands.dart` | Every new command that writes, serves or runs things is refused there (1.76.0: `rclone index`) | | Yes |
| 6 | New rc calls stay off the allowlist | `rclone rc --loopback rc/list` (old vs new), compare with `webui_rc_policy.dart` | New calls are listed in the PR body as "not on the allowlist" (1.76.0: `operations/getfile`, `operations/index`) | Someone asks to add one: carve-out | Yes |
| 7 | Web UI guards still hold | diff the upstream source between the tags for `exec.Command` and new host-command options; update the comments in `app/lib/src/webui/webui_param_guards.dart` | Comments name the new version and what you checked | A new option that runs a host command: STOP, advisor | Yes |
| 8 | rc behaviour the app depends on | run `rclone rcd` on the new binary with a scratch config and `--rc-user`/`RCLONE_RC_PASS` | `--rc-serve` Range answers 206 with Content-Range and the right bytes; bad auth 401; `config/create` without `parameters` errors; `_async` + `job/status` unchanged; `vfs/stats` options unchanged | Any differs: STOP, advisor | Yes |
| 9 | Refresh fixtures | `python3 dev/plans/fd2-probe/replay_rcd.py <new binary> <ver> app/test/fixtures/config_flows` (run it on the old binary first: it must reproduce the current fixtures) | Old binary reproduces the fixtures; the new diff is explained in the PR body | Old binary does not reproduce them: fix the probe first | Yes |
| 10 | Reasoning comment | the prose above `RCLONE_VERSION` in `.github/workflows/release.yml` | It says why this version and what step 8 verified, for the new version | | Yes |
| 11 | Notes | `dev/releases/vX.Y.Z.md` for the next app version, `docs/store/store-release-notes.txt` (under 500 bytes), `dev/logs/agent-changelog.md`; bump `app/pubspec.yaml` only if a release is planned | `python3 tool/check-docs.py` exits 0 | | Yes |
| 12 | Google sign-in timeline | recheck the forum thread in [google-shared-client-id.md](google-shared-client-id.md), add a dated line | Line added | A 90-day notice: tell Jake | Yes |
| 13 | Push and PR body | push over SSH ([coordinator playbook](coordinator-playbook.md) step 3.6); body sections "Changes", "Verified against the vX binary", "Not verified" (see PR #65) | CI green | Red: fix, never merge red | Yes |
| 14 | Advisor review | brief: PR number, steps 3 to 8 results, the diff of `webui_*` and `rclone_commands.dart` | "No high findings" in writing | High finding: fix first | Yes |
| 15 | Merge and clean up | coordinator playbook steps 3.10 and 3.11 | Merged, worktree gone, scratch folder removed (check the path first) | | Once |

## 🪤 Traps

- **Go version.** New rclone may need a newer Go; the librclone and Android jobs use setup-go `stable`.
  If `librclone.yml` fails on the Go version, that is a workflow fix in a separate PR.
- **Things the agent host cannot check:** a live FUSE mount and a real OAuth sign-in. Say so under "Not verified";
  CI and the next release's testers are the check.
- **Flutter is not on ai-dev1.** Dart tests run in CI only.
- **Upstream fixture drift.** A changed provider `Hide` value after the last capture is not a bug in the probe;
  explain it in the PR body.

## 📋 Report template

```
rclone bump <old> -> <new>, PR #<n>
SHA256: OK
Changelog: <security fixes> / <VFS, rc, serve changes> / <removed calls: none>
Console denylist: <new commands refused>
rc allowlist: <new calls, not added>
rc behaviour (step 8): all unchanged / <diff>
Fixtures: <unchanged / what changed and why>
Not verified: FUSE mount, real OAuth, local Dart tests
Advisor review: <date, result>
Merged: <sha>
```

## Related

[Coordinator playbook](coordinator-playbook.md) · [Store release playbook](store-release-playbook.md) · [Google shared client id](google-shared-client-id.md) · [Dev hub](README.md)
