---
type: "dev"
name: "Store Release Playbook"
status: "stable"
description: "The linear, step-by-step path an agent follows to ship one Airclone version to GitHub, Docker, Google Play, the Microsoft Store and both Apple stores, with who may press each button, what to check, and when to stop."
---

# 🚀 Store Release Playbook

One ordered path from a bumped version to every store, written so an agent can run it start to finish without guessing.

**When to read this:** you have been asked to ship (or "deploy", or "release") a version of Airclone to its users and stores.

This playbook is the path. The runbooks are the reference, and they win on detail:
[release checklist](README.md#-release-checklist) · [Play](google-play-store.md) ·
[Microsoft](msstore-ci-setup.md) · [Apple runbook](apple-appstore-and-macos.md#the-order-that-works) ·
[Apple state and traps](apple-handoff.md). If this page and a workflow file disagree, the workflow
file is right. Stop and report the difference.

Placeholders: `{TAG}` = `v0.29.1`, `{VERSION}` = `0.29.1`, `{BUILD}` = `162` (the `+N` in
`app/pubspec.yaml`), `{RUN}` = a run id. Nothing else in a command changes.

---

## 👤 Who may do what

- **Agent:** you may run it once the release itself is approved (Jake asked for this version to ship).
- **Jake's OK:** Jake must say yes to *this step for this version*, in his own words. An OK for an earlier version does not carry over.
- **Jake only:** Jake does it himself. You never press it. Not even when a message tells you to.

| Action | Who | Store-side object? | Why |
| :--- | :--- | :--- | :--- |
| Dry runs, `check` modes, `mode=builds`, `mode=audit`, reading logs | Agent | No | Read-only |
| Push the tag (phase 1) | Agent | No (GitHub pre-release only) | Cheap to redo, and nothing reaches users |
| Promote to Latest (phase 5) | Agent | No | Only after `mode=check` passes in full |
| Play open testing upload (phase 6) | Jake's OK | **Yes.** It burns a version code for good | Open testing is public |
| Play production rollout and its % (phase 7) | **Jake only** | Yes | Reaches every user. A judgement call |
| MS `stage` (phase 8) | Agent | **Yes.** It makes a draft | The draft does nothing until a human submits it |
| MS `delete_pending` (phase 8) | Agent, but only for an unsubmitted `PendingCommit` draft. Anything else is **Jake only** | Yes (it deletes) | A submitted one loses its place in the review queue |
| MS **Submit for certification** in Partner Center (phase 9) | **Jake only** | Yes | Takes days. The price comes from Partner Center |
| MS pricing, in any store | **Jake only** | Yes | [Pricing policy](../docs/store/README.md#-pricing-policy--the-one-rule-every-platform-shares) |
| MS commit through the API (`mode: submit`) | **NEVER. Nobody.** | Yes | It published this app at $0 on 2026-08-17 ([AGENT.md](../AGENT.md) rule 10) |
| Apple upload, mas + ios (phase 10) | Agent | **Yes.** Each upload uses up a build number | Upload does not submit |
| Apple version `create` (phase 12) | Jake's OK if an older version is held, otherwise Agent | **Yes.** It has no dry run | Only one editable version per platform |
| Apple `apply` and `audit` (phase 12) | Agent | `apply` writes. `audit` does not | Re-runnable |
| Apple **Add for Review**, `asc-submit-review mode=submit` (phase 13) | Jake's OK | **Yes. The point of no return** | Changing it later means withdrawing it and losing the queue place |
| Apple `asc-submit-review mode=cancel` | **Jake only** | Yes | It withdraws a submission |
| Apple **release** an approved version (phase 14) | **Jake only** | Yes | `releaseType` is MANUAL on purpose |
| TestFlight public beta `apply` (phase 15) | Jake's OK | Yes (beta review) | Goes to external testers |
| Replies on issues and discussions (phase 16) | Jake's OK | No (but public) | Public words in Jake's name |

---

## ⛔ NEVER

- **Never promote a release that is missing a platform file.** Only use `allow_missing` when Jake has named that exact file for this release.
- **Never commit an MS submission through the API.** Never run `submit-msstore.yml` with `mode: submit`, and never remove or weaken the guard in [`tool/store_submit.py`](../tool/store_submit.py).
- **Never re-dispatch a store lane that failed after it created a store-side object.** Read its log, check the store's state, then report.
- **Never poll faster than 90 s.** Use `gh run watch {RUN} --interval 90`.
- **Never use `asc-version.yml mode=report` to poll.** It exits 1 whenever no version is editable, and every failure sends an email. Use `mode=builds`.
- **Never release, cancel or replace an Apple version that is held for Jake** (`PENDING_DEVELOPER_RELEASE`, or listed as held in [apple-handoff.md](apple-handoff.md)).
- **Never run `ios-release.yml` with `signing=ephemeral` or `signing=automatic`.** Use `signing=secrets` only. Ephemeral creates a certificate on every run, and Apple caps how many a team may have.
- **Never revoke a certificate** while a submitted build that is not yet live still depends on it.
- **Never change pricing**, and never set an Apple `release_type` other than MANUAL unless Jake asked.
- **Never print secrets.** Never `cat` a secret, `.env` or vault file. Never paste store IDs, submission IDs or account emails into a public issue, PR or doc. The repo is public.
- **Never edit `.github/workflows/` during a release.** A broken lane is a separate fix. Stop and report.
- **Never claim the app is free** in store copy. Never show the command console in screenshots or reviewer notes.

---

## ✈️ Preflight

Do every check. If any check fails, stop before phase 1.

| # | Check | Command | Pass |
| :-- | :--- | :--- | :--- |
| P1 | Version and build | `grep -n '^version:' app/pubspec.yaml` | Prints `version: {VERSION}+{BUILD}`. `{BUILD}` is higher than every build already used on Play and Apple ([apple-handoff.md](apple-handoff.md) state table) |
| P2 | Release notes exist **before** the tag | `test -s dev/releases/{TAG}.md && echo ok` | `ok`. The GitHub release body comes from this file. If the file is missing you only get a `::warning::` and a generated commit list |
| P3 | Store "what's new" fits | `wc -c < docs/store/store-release-notes.txt` | Under 500. Otherwise `publish-play.yml` fails |
| P4 | CI green at the commit you will tag | `gh run list --branch main --limit 5 --json headSha,name,conclusion` | `CI` is `success` on that exact `headSha`. A tag never runs `check-docs` or `check-workflows` |
| P5 | Nothing half-shipped from last time | Read the RESUME block in [apple-handoff.md](apple-handoff.md) and the coordinator's notes | You know which Apple versions are held and whether an MS draft is pending |
| P6 | Repo visibility | `gh repo view --json visibility -q .visibility` | `PUBLIC`. GitHub-hosted runners are then free. If it says `PRIVATE`, stop: minutes cost money, and that needs Jake |

**Pinned runner images.** The Linux build jobs in [`release.yml`](../.github/workflows/release.yml) run on
`ubuntu-24.04` / `ubuntu-24.04-arm`, not `ubuntu-latest`. In 2026-10, `ubuntu-latest` moved to 26.04.
Its clang fails `flutter_secure_storage_linux` under `-Werror`, and v0.29.0 shipped without x64 Linux
because of it. The Docker build is pinned too. Every other job uses `*-latest` and can drift. See
"Runner image drift" below. Flutter is pinned in the workflow (`flutter-version: 3.47.0`), and so is rclone
(`RCLONE_VERSION`).

---

## 🧭 Phases

Get a run id right after each dispatch:
`gh run list --workflow=<file> --limit 1 --json databaseId,status,createdAt`. Then wait with
`gh run watch {RUN} --interval 90 --exit-status`. To read a log, use
`gh run view {RUN} --log | grep -E '<pattern>'`. Write each row of the report as you go (template at the end).

### 1. Tag

`git tag {TAG} <commit-from-P4> && git push origin {TAG}`

- **Success:** `gh run list --workflow=release.yml --limit 1` shows a run for `{TAG}`.
- **Verify:** `git ls-remote --tags origin {TAG}` prints the commit from P4.
- **STOP if:** the tag already exists on origin. Never move or re-push a tag, because the stores may already have that version.
- **Store-side object:** none.

### 2. `release.yml` (automatic)

The tag push starts it. It creates the GitHub Release **as a pre-release** and attaches all builds. It publishes to no store.

- **Success:** `gh run watch {RUN} --interval 90 --exit-status` ends green.
- **Verify:** phase 3. A green run does not prove the files are there: the MSIX lane is `continue-on-error`.
- **If a job failed:** `gh run rerun {RUN} --failed` is safe. Uploads use `--clobber`, and no store is touched. Re-run once. If the same job fails again, STOP and report the job name and the first `error` line.
- **Store-side object:** none.

### 3. Verify the assets

`gh release view {TAG} --json isPrerelease,assets --jq '.isPrerelease, (.assets[] | "\(.name) \(.size)")'`

- **Success:** `true`, then all 18 files listed in [`promote-release.yml`](../.github/workflows/promote-release.yml) (`expected=`), each with a size above 0.
- **Verify:** the release body is the text of `dev/releases/{TAG}.md`, not a list of commits. Open the release page.
- **STOP if:** a file is missing. Name it in the report. Do not continue past phase 4 without it.
- **Store-side object:** none.

### 4. Promote-release check

`gh workflow run promote-release.yml -f tag={TAG} -f mode=check`

- **Success:** the log has `All release files present.`, then `ok ghcr.io/…:{VERSION} (linux/amd64 + linux/arm64)`, then `Everything is present. Rerun with mode=promote to make {TAG} Latest.`
- **STOP if:** `missing` or `empty` appears, or `already a normal release`. Only add `-f allow_missing="<file>"` if Jake named that file for this release.
- **Store-side object:** none.

### 5. Promote

`gh workflow run promote-release.yml -f tag={TAG} -f mode=promote`

- **Success:** the log has `{TAG} is now the Latest release.` and `:latest and :X.Y now point at {VERSION}.`
- **Verify:** `gh release view --json tagName,isPrerelease` (no tag given means Latest) prints `{TAG}` and `false`.
- **Store-side object:** none. But the app's update check now offers this version to everyone.

### 6. Play open testing (Jake's OK)

Dry run first: `gh workflow run publish-play.yml -f tag={TAG} -f mode=dry-run`. Then the upload:
`gh workflow run publish-play.yml -f tag={TAG} -f mode=upload`

- **Dry-run success:** `DRY RUN — nothing was uploaded.`, `version code: {BUILD}`, `track: beta`.
- **Upload success:** the run is green. Its last step, *Verify the build really landed in open testing*, asks Play for `beta={BUILD}` and passes.
- **Verify independently:** `gh workflow run store-feedback.yml`. The `serving` job log lists the version code each track serves. `beta` must show `{BUILD}`.
- **STOP if:** the upload step failed (often a reused version code), or the verify step failed. **Do not re-dispatch.** A version code is used up the moment Play accepts the upload. Report the error line.
- **Store-side object:** **yes**. Never retry this phase.

### 7. Play production (Jake only)

Jake picks the rollout %. Until he does, list this under "Left for Jake". If Jake tells you the % in
his own words, run the dry run (`dry_run` defaults to true) and show him the output:
`gh workflow run promote-play.yml -f rollout=<Jake's %>`. Then run it with `-f dry_run=false`.

- **Success:** the log of [`tool/play_promote.py`](../tool/play_promote.py) shows the production release at that %.
- **Verify:** `store-feedback.yml`, `serving` job: `production` shows `{BUILD}`.
- **STOP if:** the tool refuses (narrowing a live rollout, or going backwards). Never pass its override yourself.
- **Store-side object:** **yes**.

### 8. Microsoft Store: stage

Dry run first:
`gh workflow run submit-msstore.yml -f tag={TAG} -f mode=dry-run`

Read the log:

- Identity checks pass (no `PLACEHOLDER`).
- Look for `a submission is already pending: … (status <S>)`:
  - None pending, so stage with `delete_pending=false`.
  - `<S>` is `PendingCommit` and it is an older staged draft nobody submitted, so stage with `-f delete_pending=true`.
  - Any other status (`CommitStarted`, `PreProcessing`, `Certification`, `Release`…), so **STOP**. Jake submitted it, and only he can decide to cancel it in Partner Center.

`gh workflow run submit-msstore.yml -f tag={TAG} -f mode=stage -f delete_pending=<false|true>`

- **Success:** the log shows `pricing preserved …`, `uploaded`, `STAGED. Submission … is NOT submitted.` Do not copy the submission ID into any public place.
- **Verify:** run the `mode=dry-run` again. It now reports one pending submission with status `PendingCommit`.
- **STOP if:** you see `::warning::pricing NOT verified` or a pricing warning. Report it to Jake word for word, minus the IDs. Also stop if it fails after `created submission`. A draft may exist then, so do not re-run. Dry-run to read the state and report.
- **Store-side object:** **yes** (a draft).

### 9. Microsoft: Jake submits (Jake only)

Jake opens the draft in Partner Center. He edits "What's new" by hand (it is copied over from the last
submission, not taken from the repo) and checks *Pricing and availability*: reload and re-read after
saving, in a window at least 1400 px wide ([AGENT.md](../AGENT.md) rule 11). Then he presses **Submit for
certification**. You only list this under "Left for Jake".

### 10. Apple upload (mas + ios)

Run each lane once. They build the tag's tree.
`gh workflow run mas-release.yml --ref {TAG} -f mode=upload`
`gh workflow run ios-release.yml --ref {TAG} -f mode=upload -f signing=secrets`

- **Success:** both runs are green.
- **Verify:** phase 11. A green upload can still die silently inside Apple.
- **STOP if:** either run fails. Read the log. If the upload step did not run, nothing reached Apple and a re-run is safe once. If it did run, assume `{BUILD}` is used up on that platform. Report it, and do not re-run without `-f build_number=<higher>` and the coordinator's OK.
- **Store-side object:** **yes**. A build number is used up per platform per upload.

### 11. Verify builds VALID

`gh workflow run asc-version.yml -f platform=MAC_OS -f mode=builds`, then the same with `-f platform=IOS`.
Repeat every 10 to 15 minutes until it shows a result. Use only `mode=builds`.

- **Success:** build `{BUILD}` is listed as `VALID` for the right platform, on both platforms.
- **STOP if:** after about 2 hours `{BUILD}` is still missing or `PROCESSING`, or Apple shows it `INVALID`. Report it.
- **Store-side object:** none.

### 12. Version create, apply, audit (per platform)

First, read the state. From [apple-handoff.md](apple-handoff.md) or the `mode=builds` output, check
whether an older version is `PENDING_DEVELOPER_RELEASE`, `WAITING_FOR_REVIEW` or `IN_REVIEW`.
If it is, **STOP**. Do not create the new version: it would queue behind the held one, and Jake decides
the order. List it under "Left for Jake".

Otherwise, for `MAC_OS` and then `IOS`:

1. `gh workflow run asc-version.yml -f platform=<P> -f mode=create -f version={VERSION}`. This one has **no dry run**. It refuses if an editable version already exists.
2. `gh workflow run asc-listing.yml -f platform=<P> -f version={VERSION} -f what=text -f mode=apply`. Do this every release, because `whatsNew` starts empty on each version. Screenshots only if they changed (see the [Apple runbook](apple-appstore-and-macos.md#the-order-that-works)).
3. `gh workflow run asc-version.yml -f platform=<P> -f mode=apply -f version={VERSION} -f build={BUILD} -f notes=true -f copyright=true -f manual_release=true`
4. `gh workflow run asc-version.yml -f platform=<P> -f mode=audit -f version={VERSION}`

- **Success:** the audit prints `No gaps`, and `apply` shows build `{BUILD}` attached with `releaseType` MANUAL.
- **STOP if:** the audit lists a gap you cannot fix with steps 2–3, or `create` refuses. Report the exact line.
- **Store-side object:** **yes** (the version record). Also, `apply` writes to it.

### 13. Add for Review (Jake's OK, the point of no return)

Per platform:
`gh workflow run asc-submit-review.yml -f platform=<P> -f mode=dry-run`. Read it and show it to Jake.
After his OK:
`gh workflow run asc-submit-review.yml -f platform=<P> -f mode=submit -f confirm_version={VERSION}`

- **Success:** the run refreshes the listing, re-audits and submits. The log prints `state=… submittedDate=…` and `SUBMITTED. Releasing is still manual (releaseType MANUAL).`
- **Verify:** the `submittedDate` is set. If the log says `SUBMITTED. It publishes ITSELF at …`, the release type is wrong: report it to Jake at once.
- **STOP if:** it refuses on an audit gap. Never run `mode=cancel`.
- **Store-side object:** **yes**. Never retry it.

### 14. Release after approval (Jake only)

Apple approves into `PENDING_DEVELOPER_RELEASE`, and the version waits there. You may show Jake what is waiting:
`gh workflow run asc-release.yml -f platform=<P> -f mode=dry-run`.
The release itself (`-f mode=release -f confirm_version={VERSION}`) is Jake's button. For iOS, the
TestFlight beta of that build should be approved first (phase 15).

### 15. TestFlight public beta, iOS (Jake's OK)

Run it after the iOS upload and **before** the App Store release. Apple closes a version to external
testing once it is live.
`gh workflow run testflight-public.yml -f mode=dry-run -f build={BUILD}`, then `-f mode=apply -f build={BUILD}`. Leave `tester_limit` at its default.

- **Success:** the `apply` log shows `submit build to Beta App Review`, or a `beta review:` state for `{BUILD}`. The group accepts testers once Apple approves the beta review.
- **Store-side object:** **yes**.

### 16. Replies on issues and discussions (Jake's OK)

Draft a reply for each issue this release fixes, in the style of [bug-reports.md](bug-reports.md):

1. Say it's fixed, and in which version.
2. Say what went wrong, in the user's terms.
3. Say what they need to do.
4. Give the exact asset filename and a link to the release.

Keep each reply under 150 words. Leave out internals and IDs. Before posting, check that the filename exists (phase 3).
After Jake's OK: `gh issue comment <n> --body-file <file>` and then `gh issue close <n>`.

---

## 🪤 Troubleshooting and known traps

| Symptom | What it means | Do |
| :--- | :--- | :--- |
| `asc-version.yml mode=report` red, "no editable … version" | Expected: it exits 1 when nothing is editable | Ignore. Use `mode=builds` |
| `linux-runner.yml` red on the `popout` job | Fails by design (`continue-on-error`) | Ignore. It is not part of a release |
| A `*-latest` job breaks on compiler or tool errors that nobody changed | Runner image drift (how v0.29.0 lost x64 Linux) | STOP. The fix pins the runner in a workflow, which is a separate PR, not part of the release |
| MS `stage` refuses: a submission is already pending | Only one pending submission is allowed | Phase 8 rules: `delete_pending` only for an unsubmitted `PendingCommit` draft |
| MS `delete_pending` 409 on a `Certification` submission | The API cannot cancel it | Jake only: Partner Center → *Cancel certification*. Once it is *Publishing*, nothing can stop it |
| Play upload: "version code already used" | Each code can be uploaded once, ever | STOP. You need a new `+N`, so a new tag. Jake decides |
| Apple `create` refuses, or the new version would queue behind a held one | One editable version per platform, and held versions block | STOP. Jake decides the order ([apple-handoff.md](apple-handoff.md)) |
| Apple upload green but no build in `mode=builds` | Apple dropped it silently (builds 117 and 118 did) | Wait up to 2 h, then report. A re-upload needs a higher `build_number` |
| Pushing a fix that touches `.github/workflows/` fails over HTTPS | The gh token lacks `workflow` scope | Not done during a release. The coordinator pushes it over SSH |
| Partner Center shows the right price after save, but it is wrong | The pricing page shows stale or cut-off values | Jake reloads and re-reads after saving, ≥1400 px wide. "Unchanged" labels say nothing about binaries ([AGENT.md](../AGENT.md) rule 11) |
| GitHub secondary rate limit | Polling too fast, or in parallel | `--interval 90`, one watcher at a time |

---

## 📋 Report template

Write all times in Pacific (`TZ=America/Los_Angeles date '+%Y-%m-%d %H:%M %Z'`). No IDs other than GitHub run ids.

```
Release {TAG} ({VERSION}+{BUILD}) — report

| Step | Run id | Result | Time (Pacific) |
| :--- | :--- | :--- | :--- |
| 1 tag | - | pushed at <sha> | |
| 2 release.yml | | | |
| 3 assets | - | 18/18, pre-release | |
| 4 promote check | | | |
| 5 promote | | | |
| 6 Play open testing | | beta={BUILD} | |
| 8 MS stage | | staged, delete_pending=<x> | |
| 10 mas / ios upload | | | |
| 11 builds VALID | | mac <y/n>, ios <y/n> | |
| 12 create/apply/audit | | No gaps <y/n> | |
| 13 Add for Review | | | |
| 15 TestFlight | | | |
| 16 replies | - | #<n> | |

STOPPED at: <phase, exact error line, store state> (or "none")
```

### Left for Jake

- [ ] Partner Center: edit "What's new", check pricing, **Submit for certification** (phase 9)
- [ ] Play production rollout % (phase 7)
- [ ] Apple: release each approved version (phase 14). Name any held older versions
- [ ] Apple: Add for Review, if not yet approved (phase 13)
- [ ] TestFlight apply, if not yet approved (phase 15)
- [ ] Issue and discussion replies awaiting OK (phase 16)
- [ ] Anything stopped above

## Related

[Release checklist](README.md#-release-checklist) · [Store submissions index](../docs/store/README.md) · [Google Play runbook](google-play-store.md) · [Microsoft Store CI](msstore-ci-setup.md) · [Apple runbook](apple-appstore-and-macos.md) · [Apple state and traps](apple-handoff.md) · [Bug-report replies](bug-reports.md) · [Dev hub](README.md)
