# 🧭 Coordinator Playbook

The recurring work of whoever runs Airclone day to day: start cold, check what came in, turn a change into a
merged pull request, and watch a release land. Written so a cheaper model can do it without guessing.

**When to read this:** you are the Airclone coordinator (or standing in for it) and you are starting a session,
doing the daily check, or about to merge something.

Releases have their own playbook: [store-release-playbook.md](store-release-playbook.md). The weekly rclone
update has [rclone-bump-playbook.md](rclone-bump-playbook.md). Repo rules are in [AGENT.md](../AGENT.md); when
this page and AGENT.md disagree, AGENT.md wins. Stop and report the difference.

---

## 👤 Who may do what

| Action | Who | Why |
| :--- | :--- | :--- |
| Read issues, discussions, PRs, CI logs, store-feedback runs | Agent | Read-only |
| Open a branch and PR for docs, tests, tooling or app code | Agent | Nothing ships until merge |
| Merge your own PR once every check is green | Agent | CI is the gate. Not for carve-outs (below) |
| Merge a Dependabot actions PR | Agent, after the checks in step 6 | It changes workflows, so read the diff |
| Merge an outside contributor's PR | Agent, only after the CLA check in step 5 | Gigaion must own every line |
| Post any reply on an issue or discussion | **Jake's OK** for that reply | Public words in Jake's name |
| Close an issue without a reply, label, or transfer | Agent | Housekeeping, but say why in your notes |
| Anything in a carve-out: signing, secrets, security review, money | **Claude or Jake** | A DeepSeek coordinator writes a brief for the Opus advisor and stops |
| Pricing, `BASE_PRICE_TIER`, anything that costs money | **Jake only** | Cost rule |

**Carve-outs in detail.** Signing (certificates, profiles, `apple-revoke-cert.yml`, Windows signing, the update
key), repository secrets, and the security review of any diff that touches auth, tokens, `rcd` start flags,
the rc allowlist (`app/lib/src/webui/webui_rc_policy.dart`), the web UI guards
(`app/lib/src/webui/webui_param_guards.dart`), the console denylist
(`app/lib/src/state/console/rclone_commands.dart`), file extraction, or the network. A DeepSeek coordinator may
write such a change, but it does not merge until the advisor's review says so. No advisor available means it
does not merge.

---

## ⛔ NEVER

- **Never check out, build or run an outside PR's code on this machine** ([AGENT.md](../AGENT.md) rule 19). Read it on GitHub.
- **Never merge on the colour of the `Airclone CLA` check alone.** Read the bot comment and the `cla-signatures` ledger (rule 19).
- **Never post a public reply without Jake's OK** for that reply.
- **Never paste store IDs, submission IDs, account emails or secret values** into an issue, PR, commit or doc. The repo is public. Run ids are fine.
- **Never read `.env`, `dev/secrets/dev-profile.env` or vault notes** unless the task needs one named value, and never copy it anywhere.
- **Never use bare `git stash`**, and never delete a directory without checking the path is the one you mean.
- **Never push a final `vX.Y.Z` tag** unless Jake asked for that release. It ships to every store.
- **Never edit `.github/workflows/` while a ship run is in progress.**
- **Never poll faster than 90 s** (GitHub's secondary rate limit).
- **Never delete or rewrite the `cla-signatures` branch** (protected by a ruleset).

---

## 1. Cold start (every session)

| # | Do | Command | Success |
| :-- | :--- | :--- | :--- |
| 1.1 | Read the state file | the coordinator's state file (named in its resume pointer) | You know the store state, open items and what waits for Jake |
| 1.2 | Update main | `git -C ~/git/Airclone pull --ff-only` | Fast-forward or "Already up to date". Anything else: STOP, the main clone has local changes. Leave them |
| 1.3 | Last 3 changelog entries | `sed -n 1,80p dev/logs/agent-changelog.md` | AGENT.md rule 5 |
| 1.4 | Open PRs and their checks | `gh pr list --state open` then `gh pr checks <n>` | You know what is waiting |
| 1.5 | Runs that failed on main | `gh run list --branch main --limit 15 --json name,conclusion,databaseId` | Each `failure` is explained (step 7 traps) or becomes work |
| 1.6 | Any ship run in flight | `gh run list --workflow=ship.yml --limit 1` | If `in_progress`: watch it ([store playbook](store-release-playbook.md) automatic path, step 4) |

Retry-safe: all read-only.

## 2. Daily check

| # | Check | Command | Do |
| :-- | :--- | :--- | :--- |
| 2.1 | New or updated issues | `gh issue list --state open --limit 20` | New bug: reproduce from the report, then step 3. Draft a reply per [bug-reports.md](bug-reports.md), save it to a file, and ask Jake |
| 2.2 | Discussions | `gh api graphql -f query='{repository(owner:"GigaionLLC",name:"Airclone"){discussions(first:5,orderBy:{field:UPDATED_AT,direction:DESC}){nodes{number title updatedAt comments{totalCount}}}}}'` | A new one or a new comment: read it on GitHub, draft a reply if needed, ask Jake |
| 2.3 | Play reviews | `gh run list --workflow=store-feedback.yml --limit 1`, then `gh run view <id> --log` | Runs daily 08:00 UTC. A new review that reports a bug becomes an issue-style task |
| 2.4 | Dependabot / rclone-bump PRs | `gh pr list --author app/dependabot` · `gh pr list --search "pin rclone in:title"` | Step 6, or the [rclone-bump playbook](rclone-bump-playbook.md) |
| 2.5 | CI warnings on main | open the newest green `CI` run's summary | A warning is work (AGENT.md rule 8) |
| 2.6 | Post-release watch, if a release is not fully live | [store playbook phase 17](store-release-playbook.md#17-post-release-watch-agent) | Note the result in the state file |

Retry-safe: all read-only. Write what you found into the state file before you start fixing anything.

## 3. Change → PR → merge

1. **Worktree.** `git -C ~/git/Airclone worktree add ../Airclone-wt-<slug> -b <branch> origin/main`.
   Success: the new folder exists. Never work in the main clone.
2. **Plan** if it is more than ~3 steps: `dev/plans/` from `plans/template-plan.md` (AGENT.md rule 6).
3. **Change it.** Follow AGENT.md rules. Tool output ASCII only (rule 12).
4. **Local checks.** `python3 tool/check-docs.py` and, if workflows changed, `python3 tool/check-workflows.py`.
   For tool scripts: `python3 -m unittest discover -s tool -p 'test_*.py'`. Success: each exits 0.
   Flutter is not on ai-dev1; Dart tests run in CI.
5. **Wrap-up in the same PR** (AGENT.md wrap-up protocol): an entry in `dev/logs/agent-changelog.md`, `wiki/`
   and `docs/guide/` synced, `docs/guide/platforms.md` if a platform's features changed (rule 20).
6. **Commit and push.** Push over SSH (the gh token lacks `workflow` scope):
   `git push git@github.com:GigaionLLC/Airclone.git <branch>`.
7. **Open the PR.** `gh pr create --base main --head <branch> --title "..." --body-file <file>`.
   Body: what changed, what was verified and how, what was **not** verified. It ends with the generated-by line.
8. **Wait for checks.** `gh pr checks <n> --watch --interval 90`. Needed: `analyze-test`, `docs`, `rclone-pin`,
   `cla`, `Airclone CLA`, the three `package-airclone-rc` jobs. Red: read the log, fix, push again. Never merge red.
9. **Carve-out?** If the diff touches anything in the carve-out list, a DeepSeek coordinator stops here and
   asks the advisor for a review (brief: PR number, the files, what to check). Merge only after "no high findings".
10. **Merge.** `gh pr merge <n> --squash --delete-branch`. Success: `gh pr view <n> --json state` says `MERGED`.
11. **Clean up.** `git -C ~/git/Airclone worktree remove ../Airclone-wt-<slug>`. If it says "not a working tree",
    `--delete-branch` already removed it: check `git -C ~/git/Airclone worktree list`. Then
    `git -C ~/git/Airclone pull --ff-only`.

Retry-safe: steps 1 to 8 yes. Step 10 only once (check the state first).

## 4. Bug reports

Read [bug-reports.md](bug-reports.md) first. Fix it (step 3), then draft the reply in a file. The reply waits
until the fix is in a release users can download. Show Jake the draft; post only after his OK:
`gh issue comment <n> --body-file <file>` then `gh issue close <n>`.

## 5. Outside pull requests

1. Read the diff on GitHub (`gh pr diff <n>`). Do not check it out (rule 19).
2. Let hosted CI run it. A first-time contributor's run may need approval in the Actions tab: that is Jake's click.
3. CLA: read the bot's sticky comment, then check the ledger (`signatures/cla.json` on branch `cla-signatures`,
   matched by GitHub account id and CLA version, see `tool/cla_check.py`):
   `gh api "repos/GigaionLLC/Airclone/contents/signatures/cla.json?ref=cla-signatures" -q .content | base64 -d`
   and `gh api users/<login> -q .id`. A 404 means the branch does not exist yet: nobody has signed, so it
   cannot merge.
4. Review it like your own change. Anything in the carve-outs: advisor review first.
5. Merge (step 3.10). Thank the contributor only with Jake's OK on the words.

## 6. Dependabot actions PRs

Monthly, grouped, prefix `ci`. Actions are pinned by full SHA with a `# version` comment.

1. `gh pr diff <n>`: every change is a SHA swap with a matching `# vX.Y.Z` comment. Anything else: STOP.
2. Each new SHA belongs to the tag in its comment: `gh api repos/<owner>/<repo>/commits/<tag> --jq .sha`.
3. Read each action's release notes for breaking changes (new Node version, renamed inputs).
4. Not while a ship run is in progress. Checks green, then merge (step 3.10).
5. After merge, the next `CI` run on main is green with no new warnings (rule 8).

## 7. Known traps

| Symptom | Means | Do |
| :--- | :--- | :--- |
| `linux-runner.yml` red on the `popout` job | `continue-on-error` probe, fails by design | Ignore |
| `asc-version.yml mode=report` red "no editable version" | Expected when nothing is editable | Ignore; never use it to poll |
| `git worktree remove` fails: permission denied on build files | A Docker build left root-owned files | Check the path is the worktree, then `docker run --rm -v "$PWD/../Airclone-wt-<slug>":/w alpine find /w -mindepth 1 -delete`, then `git worktree prune`. Never with an empty or wrong path |
| Push rejected over HTTPS for a workflow file | gh token lacks `workflow` scope | Push over SSH (step 3.6) |
| GitHub secondary rate limit | Parallel or fast polling | One watcher, 90 s |
| `check-workflows.py` fails on a comment | An empty `${{ }}` anywhere, comments included, breaks the file | Remove it |

## 8. When to ask the Opus advisor

A DeepSeek coordinator writes a brief file and asks (it does not wait idle; it moves to other work):
- any carve-out item (above);
- a CI failure it cannot explain after reading the full log twice;
- a store returning something no playbook covers;
- a design choice that changes what users see on more than one platform;
- any time a doc and the code disagree and the fix is not obvious.

## 📋 Report template

```
Airclone coordinator, <date> <time Pacific>
Issues: <n new> (#.. drafted, waiting for Jake's OK)
Discussions: <changes>
PRs: #.. merged (<title>), #.. waiting on <check/advisor/Jake>
CI on main: green / <run id> red because <...>
Stores: <one line per store, from phase 17>
Waiting for Jake: <list>
```

## Related

[Store release playbook](store-release-playbook.md) · [rclone bump playbook](rclone-bump-playbook.md) · [Bug-report replies](bug-reports.md) · [AGENT.md](../AGENT.md) · [Dev hub](README.md)
