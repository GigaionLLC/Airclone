# Google Play CI publishing — as-built setup runbook

**Purpose:** reproduce, from nothing, the credentials that let CI upload and promote Airclone on
Google Play — for a new Google account, a rotated key, or a different app.
**Status:** IN PROGRESS (2026-08-16). Steps are marked ✅ as they are completed and verified.
**Related:** [`dev/plans/store-automation-plan.md`](plans/store-automation-plan.md) § Google Play (the
original research) · [`dev/google-play-store.md`](google-play-store.md) (per-release runbook) ·
[`docs/store/README.md`](../docs/store/README.md) (the store hub).

> **This repo is public.** Every account-specific value below is a `<placeholder>`. Never commit the
> service-account JSON, the SA email, the GCP project id, or the Play developer id. Real values live
> in the private notes and in GitHub secrets — nowhere else.

---

## 0. What we are building

| Piece | Effect |
| :--- | :--- |
| Service account + JSON key (Google Cloud) | the credential CI authenticates with |
| That SA granted access in Play Console | what lets the credential touch *this* app |
| `PLAY_SERVICE_ACCOUNT_JSON` GitHub secret | how CI receives it |
| Tag → upload to **open testing** | testers auto-update on every release |
| `workflow_dispatch` promote job | production ships from the Actions tab, no Console login |

**Why the split:** the Play Developer API can upload builds and move version codes between tracks,
but it has **no API for granting a service account access** — that grant is Play Console UI only,
and is the one irreducibly manual step.

---

## 1. Install the Google Cloud SDK ✅

```powershell
winget install --id Google.CloudSDK --accept-source-agreements --accept-package-agreements --silent
```

Installed **580.0.0**. Note the install is **per-user**, not into `Program Files`:

```
%LOCALAPPDATA%\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd
```

It is not on `PATH` for shells that were already open, so every command below prepends it:

```powershell
$env:PATH = "$env:LOCALAPPDATA\Google\Cloud SDK\google-cloud-sdk\bin;$env:PATH"
```

## 2. Authenticate as the human owner

```powershell
gcloud auth login
```

Opens a browser for a normal Google sign-in. Use the account that **owns (or is an admin of) the Play
developer account** — the SA it creates gets its Play access granted by that human in step 5.

> **Gotcha (hit on the first attempt).** `gcloud auth login` spins up a one-shot listener on
> `localhost:8085` and waits for the browser to redirect back with a code. If the sign-in is not
> completed in that window — the browser opened behind other windows, the wrong Chrome profile was
> used, the tab was closed — it dies with:
>
> ```
> ERROR: There was a problem with web authentication. Try running again with --no-browser.
> ERROR: (gcloud.auth.login) (missing_code) Missing code parameter in response.
> ```
>
> It is not a broken install; just run it again and finish the sign-in. Running it from a terminal
> *you* control is the most reliable way, because the flow needs a human at the browser and, in the
> `--no-launch-browser` variant, a code pasted back into the prompt.

## 3. Project + API ✅

A dedicated project keeps the CI identity separate from anything else (and makes it disposable —
delete the project to revoke everything at once). Creating it costs nothing.

```powershell
gcloud projects create <project-id> --name="<Project name>" --organization=<org-id>
gcloud config set project <project-id>
gcloud services enable androidpublisher.googleapis.com --project=<project-id>
```

- `gcloud organizations list` gives `<org-id>` when the account belongs to a Workspace org. Omit
  `--organization` for a personal account.
- **No billing account is attached, and none is needed.** New projects come with a pile of APIs
  enabled by default (BigQuery and friends); they are enabled-but-unused and cannot bill anything
  with no billing account linked. The only API we add deliberately is `androidpublisher`.

## 4. Service account + key ✅

```powershell
gcloud iam service-accounts create play-ci-publisher `
  --display-name="Play CI publisher" `
  --description="Uploads AABs to Google Play from GitHub Actions" `
  --project=<project-id>

gcloud iam service-accounts keys create <path-outside-the-repo>.json `
  --iam-account=play-ci-publisher@<project-id>.iam.gserviceaccount.com `
  --project=<project-id>
```

**No GCP IAM roles are granted to this SA** — it needs none. Its authority comes entirely from the
Play Console grant in step 5. The JSON key is the only credential; treat it like a password, write it
somewhere outside the repo, and delete it once it is in the GitHub secret.

## 5. Grant the SA access — Play Console (browser, no API exists) ✅

Play Console → **Users and permissions → Invite new user**:

1. **Email** = the SA address from step 4. Service accounts do not accept invitations; access applies
   the moment you save.
2. **App permissions → add the app**, then grant (least privilege — not account-wide Admin):
   - *View app information and download bulk reports*
   - *Release to testing tracks and manage testing track configuration* — the automated uploads
   - *Release apps to production, exclude devices, and use Play App Signing* — **required for the
     promote-to-production workflow**; without it the promote job 403s while uploads still work,
     which is a confusing failure to debug later.
3. New access can take minutes to propagate. A first-run 403 usually means "wait and retry", not
   "misconfigured".

While in the Console, record two things that decide whether automated production is even possible:

- **Account type** (Settings → Developer account → Account details). A *personal* account created
  after Nov 2023 must run 12 testers for 14 days before production unlocks. Organization accounts are
  exempt.
- **Whether the Open testing track exists and is configured** (countries/testers). The API can create
  a release on a track, but it cannot do a track's first-time setup.

## 6. GitHub secret ✅

`--body` mangles multi-line JSON in PowerShell (it word-splits into 5 args). Pipe the file on stdin
instead — from git-bash:

```bash
gh secret set PLAY_SERVICE_ACCOUNT_JSON < <path-outside-the-repo>.json
```

Then **delete the local key file**. It is a live credential and there is no reason for a second copy
to exist once GitHub holds it.

## 7. CI wiring ✅

Two lanes, deliberately split:

| Lane | Trigger | Track | File |
| :--- | :--- | :--- | :--- |
| Upload | every `v*` tag | **open testing** (`beta`) | `.github/workflows/release.yml` (android job) |
| Promote | **manual** — Actions → *Promote on Google Play* → Run workflow | production, staged | `.github/workflows/promote-play.yml` + [`tool/play_promote.py`](../tool/play_promote.py) |

**Track names differ between the Console and the API** — the single most confusing thing here:

| Play Console | API |
| :--- | :--- |
| Internal testing | `internal` |
| Closed testing | `alpha` (or a custom track name) |
| **Open testing** | **`beta`** |
| Production | `production` |

**Promotion cannot re-upload.** Play refuses a version code it has already accepted, so the promote
job reads the version code sitting in open testing and adds a release for *that same code* on
production (`edits.insert` → `tracks.get` → `tracks.update` → `edits.commit`). Re-run it with a
larger percentage to widen a staged rollout (10 → 50 → 100); it defaults to a **dry run**, because
the failure mode is shipping to everyone at once.

**Promotion can hurt users in two silent ways, so the script checks first** (`--force` overrides).
The two are NOT the same severity, and the exit codes say so — because an operator who sees red for
a working guard learns to ignore red:

| Situation | Result | Exit |
| :--- | :--- | :--- |
| Target is already at or beyond what was asked (same version, same-or-wider fraction) | `::warning::` on the run, **nothing changed** — production is fine, the request just achieves nothing | **0** (green) |
| Target already serves a **newer** version code | refuses: promoting an older build downgrades users | **1** (red) |

A red *Promote on Google Play* run therefore always means something is actually wrong. This was
learned the hard way: the first version failed the run for every refusal, and the Actions tab filled
with red X's that were the guard doing its job — indistinguishable, at a glance, from a broken
pipeline. It also mislabelled the equal case ("would reduce it") when asking for the state that
already exists reduces nothing.

## 8. Verification ✅ (2026-08-16)

The grant propagated **immediately** — the 403 became a working call on the next run, so "wait
hours" is a worst case, not the norm.

Reading every track at once is the fastest way to know where you stand (and the check the promote
script now does for you):

```
internal     codes=['100'] status=completed          name=100 (0.4.0)
beta         codes=['113'] status=completed          name=113 (0.6.4)
production   codes=['113'] status=completed          name=113 (0.6.4)
```

**This is exactly the state that makes a naive promote harmful**, and finding it is why the safety
checks below exist: production was already serving 113 at 100%, so a `--rollout 10` promote would
have taken a fully-live release and pinned it back to a 10% staged rollout.

Local dry run with the key (no changes, opens and discards an edit):

```bash
GOOGLE_APPLICATION_CREDENTIALS=<key>.json \
python tool/play_promote.py --package <applicationId> --rollout 10
```

- **403 `The caller does not have permission`** → step 5 has not been done, or has not propagated.
  This is the expected result *before* the Console grant, and a useful checkpoint: it proves the key
  authenticates and the API is reachable, and that only the grant is missing.
- Success prints the version code found in open testing and what it would do.

Then the real end-to-end: push a tag, confirm the android job's upload step succeeds, confirm the
build appears in the Console's open testing track, and run the promote workflow with
**Dry run = true** before ever running it for real.

### First full run through the pipeline — v0.6.5, 2026-08-16 ✅

Every component exercised against the live account, in this order:

| Step | Command / trigger | Observed |
| :--- | :--- | :--- |
| Tag → build + upload | `git push origin v0.6.5` | 8/8 jobs green; upload step logged `Validating tracks: 'beta'` → `Successfully committed` |
| Promote — dry run | `gh workflow run promote-play.yml -f rollout=10 -f dry_run=true` | `found version code 114 in 'beta'` → planned 10%, changed nothing |
| Promote — staged | `... -f rollout=10 -f dry_run=false` | `committed — production now serving 114 at 10.0% staged rollout` |
| Promote — widen | `... -f rollout=100 -f dry_run=false` | `production already serves 114 at 10%` → `now serving 114 at 100%` |
| Guard — narrowing | `... -f rollout=10 -f dry_run=true` (after 100%) | refused, nothing changed |
| Guard — no-op | `... -f rollout=100` (when already at 100%) | warning, nothing changed, **exit 0** |
| Guard — backwards | `--version-code 100` while 114 is live | **exit 1** — the only red case |

Three behaviours worth keeping: widening a rollout does **not** trip the guard (10 → 100 proceeds),
narrowing or repeating it changes nothing but stays green with a warning, and only a genuine
downgrade fails the run.

### Second run — v0.6.6, proving the pipeline changes themselves ✅

The Play steps only execute on a tag, so `tracks:` (plural), the new verification step, and the
Node-24 action bumps all shipped **unproven** by v0.6.5. v0.6.6 was cut with no app changes purely
to exercise them, and all three held:

```
Validating tracks: 'beta'                     ← the plural input is honoured
Successfully committed
expecting version code 115 in open testing
beta        [115] completed at 100%  v0.6.6
all expectations met                          ← Play confirms it landed
```

Then dry run → promote at 100% → `committed — production now serving 115 at 100%`, with no Node-20
warnings anywhere. **Cutting a throwaway patch release to prove a change to the release machinery is
cheaper than discovering months later that publishing quietly stopped.**

**Deprecation caught in this run:** the upload action warned that `track:` (singular) "is deprecated
and will be removed in a future release". Migrated to `tracks:` immediately, because the failure mode
is a lane that silently stops publishing on some future action bump.

---

## Billing posture — why there is nothing to alert on

Verified 2026-08-16. **Three independent reasons this setup cannot be charged**, and they are
stronger than any budget alert:

| Layer | State | Why it matters |
| :--- | :--- | :--- |
| Billing account on the project | none (`billingEnabled: false`) | GCP **refuses** to create billable resources without one. A refusal, not a notification. |
| The account's only billing account | closed (`OPEN: False`) | not a live payment instrument even if attached |
| The CI service account's GCP roles | **none** | it cannot create a resource in the project at all; its only authority is the Play Console grant |

The Google Play Developer API is free, and the repo is public so Actions minutes are free too.

**Do not "add a $1 budget alert" here — it is not possible and not useful:**

- Budgets attach to **billing accounts**, not projects. With no billing account there is nothing to
  attach one to.
- **A GCP budget is an alert, not a cap.** It emails after spend happens; it does not stop it. The
  only true hard stop is budget → Pub/Sub → a Cloud Function that disables billing — which needs
  billing enabled and a running function, so it costs more than it protects at this scale.

```powershell
# The checks that establish the above — safe to re-run any time.
gcloud billing projects describe <project-id>        # expect billingEnabled: false
gcloud billing accounts list                         # expect no OPEN account, or none at all
gcloud projects get-iam-policy <project-id>          # expect only your own user, no SA binding
```

**If billing is ever attached** (someone reopens the account, or reuses this project for something
paid), then a budget becomes both possible and worth having:

```powershell
gcloud billing budgets create --billing-account=<billing-account-id> `
  --display-name="Airclone Play CI" --budget-amount=1USD `
  --threshold-rule=percent=0.5 --threshold-rule=percent=1.0
```

Treat that as an alarm on an unexpected state, not as protection.

---

## Gotchas collected while doing this

- `gcloud auth login` needs a human at the browser **on this machine** while it runs; it fails with
  `(missing_code) Missing code parameter in response` otherwise (see step 2).
- The SDK installs **per-user** under `%LOCALAPPDATA%`, not `Program Files`, and is not on `PATH` in
  already-open shells.
- gcloud writes progress to **stderr**, so PowerShell reports `NativeCommandError` / exit 255 for
  commands that actually succeeded. Check the operation output, not the exit code.
- `gh secret set --body` word-splits multi-line JSON in PowerShell — pipe the file on stdin instead.
- On this machine `pip` is not on `PATH`; use `python -m pip`.
- A new GCP project auto-enables a pile of unrelated APIs (BigQuery and friends). They are unused,
  and with no billing account attached nothing can be charged. Do not "clean them up" — disabling
  Google's defaults occasionally breaks project tooling for no benefit.
- **Production may not be reachable at all** for a personal Play account created after Nov 2023
  until 12 testers have run the app for 14 days. Check the account type before promising automated
  production releases.
