# Microsoft Store CI submission — as-built setup runbook

**Purpose:** reproduce, from nothing, the credential that lets CI submit Airclone's MSIX to the
Microsoft Store — for a new Partner Center account, a rotated secret, or a different app.
**Status:** credential ✅ **proven** end to end (§6). Automated *submission* is ⛔ **blocked** on this
app's pricing model — see the blocker in §0 before building on this. Submitting by hand still works.
**Related:** [`dev/windows-signing-and-store.md`](windows-signing-and-store.md) §2 (the manual
submission runbook + as-built account facts) · [`docs/store/README.md`](../docs/store/README.md) (the
store hub) · [`dev/play-ci-setup.md`](play-ci-setup.md) (the same job for Google Play — read it too,
the shape is nearly identical).

> **This repo is public.** Every account-specific value below is a `<placeholder>`. Never commit the
> tenant id, client id, client secret, Seller ID, Store ID, or the publisher GUID. Real values live
> in GitHub secrets/variables and private notes — nowhere else.

---

## 0. What we are building, and what it cannot do

| Piece | Effect |
| :--- | :--- |
| Entra (Azure AD) app registration + client secret | the identity CI authenticates as |
| That app added in **Partner Center** with the **Manager** role | what lets the identity touch *this* Store account |
| `STORE_*` secrets + `STORE_APP_ID` variable | how CI receives it |
| [`submit-msstore.yml`](../.github/workflows/submit-msstore.yml) | the button that submits, run from the Actions tab |

**Submission is deliberately NOT automatic.** A tag builds, signs and attaches `airclone.msix` to
the GitHub release; a human then runs *Submit to Microsoft Store* against that tag. This mirrors
[`promote-play.yml`](../.github/workflows/promote-play.yml), and matters more here than on Play:
Microsoft certification takes **days**, and a bad submission burns a review cycle — this app has
already lost cycles to package-identity rejections (v0.6.0, 4×) and policy 10.2.5.

The workflow downloads the MSIX **from the release** rather than rebuilding, so what gets certified
is the exact signed package that was tested, and it refuses a missing or zero-byte package before
Partner Center ever sees it.

> The old `STORE_PUBLISH_ENABLED` master switch is **retired**. It existed to keep an
> automatic-on-tag submission dormant; with submission behind a manual dispatch there is nothing to
> gate — the workflow simply refuses to run without credentials.

> ## ⚠️ Why this does not use `msstore publish`
>
> The obvious tool is the Microsoft Store Developer CLI. **It cannot update a paid product.** Proven
> on 2026-08-17 submitting v0.6.7: authentication and identity were fine, the CLI found the app,
> created a submission, retrieved it — and then stopped with
>
> > **App updates are supported only for Free products.**
>
> Airclone is not free; it carries the Store listing price that funds the signing certificates. No
> amount of credential work changes that, and making the app free is a **pricing decision, not an
> engineering one** — it would defund the certs.
>
> Note the ordering trap, because it bites even when you are only experimenting: **the CLI creates a
> submission before it discovers it cannot finish one.** A failed attempt can leave a pending draft,
> and a pending submission blocks the next one. (In the v0.6.7 attempt nothing was actually left
> behind — Partner Center still offered "Start update" — but do check.)
>
> ## ⛔ AND the REST API cannot round-trip this app's pricing either
>
> The obvious next move was the older submission REST API, since the CLI's restriction is a CLI
> restriction. [`tool/store_submit.py`](../tool/store_submit.py) implements it, and everything works —
> auth, package upload, commit, certification — **except pricing**, which is unsolvable as configured:
>
> | Attempt | Result |
> | :--- | :--- |
> | send `pricing` back exactly as received (`priceId: "Base"`) | `'Base' is not a valid PriceId for base price` |
> | drop just `priceId` | accepted, and the price **silently became `Free`** |
> | omit the whole `pricing` object | `Pricing data was not provided in the request` |
>
> The app is on the **advanced pricing model** (`isAdvancedPricingModel: true`), where the real price
> lives outside the submission and `priceId` is the sentinel `"Base"`. The v1 API cannot express that
> value on write, so there is no payload that both satisfies the API and preserves the price.
>
> **This was caught the expensive way.** The `Free` variant was submitted and reached certification on
> 2026-08-17 before a pricing comparison against the live submission revealed it; certification was
> cancelled, the draft deleted, and the live listing was never affected. The script now reads the
> submission back and **refuses to commit** when pricing differs from live — that check must never be
> removed, and it belongs *before* the commit, which is the whole lesson.
>
> **So Store submission stays manual for now.** The realistic options, in order of preference:
>
> 1. **Submit by hand** (~10 minutes per release, and Store review takes days regardless — so the tax
>    is small at this cadence). Everything else built here still pays off: the identity check, the
>    signed MSIX, and the dry run that proves the credential.
> 2. **Move the product off the advanced pricing model** onto a classic price tier. `priceId` would
>    then be a real tier that round-trips, and `store_submit.py` would work unchanged. This is a
>    **pricing decision**, not an engineering one.
> 3. **Make the app free** — then even `msstore publish` works. It also defunds the signing certs.
>
> `STORE_SELLER_ID` is not read by `store_submit.py` (the REST API takes no seller id) but is kept
> set, since it costs nothing and Partner Center tooling asks for it.

**What automation does NOT do:**

- **It cannot create the first submission.** The Store submission API updates an app that already has
  a completed submission. Listing copy, screenshots, age rating and the privacy-policy URL must
  already exist, done by hand once.
- **It does not make certification faster.** Play publishes in minutes; Microsoft review takes days,
  and this app has already burned cycles on identity rejections (v0.6.0, 4×) and a policy 10.2.5
  rejection. Automation makes *submitting* cheap — a bad submission still costs a review cycle.

---

## 1. Create the CI identity (Entra app registration) ✅

A **dedicated** app registration, separate from the code-signing identity: a leaked publishing secret
then cannot sign binaries, and either can be rotated without disturbing the other.

```powershell
az ad app create --display-name "<Org>-StoreSubmit" --sign-in-audience AzureADMyOrg
az ad sp create --id <appId>
az ad app credential reset --id <appId> --years 2   # prints the secret ONCE
```

> **Gotcha — `AADSTS530035: Access has been blocked by security defaults`.** A tenant with Security
> Defaults enabled (the Microsoft-managed baseline) requires a fresh interactive, MFA-backed token
> for Graph admin operations like creating an app registration. A cached `az` session that works
> fine for other commands will fail here. Re-authenticate with the Graph scope:
>
> ```powershell
> az login --use-device-code --tenant <tenant-id> --scope "https://graph.microsoft.com//.default"
> ```
>
> `--use-device-code` matters when the machine is locked or headless: it prints a short code to enter
> at <https://login.microsoft.com/device> from **any** device, including a phone.
>
> **The code is short-lived** — it polls for roughly 15 minutes and then exits 1 with
> `AADSTS70016: ... Authorization is pending`, which reads like a failure but only means nobody
> entered it in time. Start the command when you are actually at a browser, not in advance.

### 1a. The secret expires — there is no "never"

Entra no longer offers a non-expiring client secret, and **Custom does not get you around it**.
Choosing Custom and entering a far-future end date makes the portal state the rule outright:

> The value must be between 8/16/2026 and 8/16/2028.

So the ceiling is exactly **24 months** whichever route you take — presets (90 / 180 / 365 / 545 /
730 days) or Custom. This credential must be rotated; the only question is whether that is a known
date or a surprise.

Two UI quirks in the Custom flow, both of which look like the form is broken:

- **Start is required.** With only End filled, **Add stays greyed out** and nothing says why.
- **Validation is stale until blur.** After correcting the date the error message persists and Add
  stays disabled until you click elsewhere. Click away, then look again.

| | |
| :--- | :--- |
| Created | **2026-08-17** (description `github-actions-ci`) |
| Expires | **2028-08-17** (the maximum Entra allows) |

> **Set it through a pipe, and strip the newline.** The first secret here was pasted through a
> PowerShell stdin pipe, and PowerShell appends `\r\n` — a secret carrying a stray carriage return
> fails authentication *identically* to a wrong one, with no hint that whitespace is the problem.
> Use Git Bash and `tr` so the value goes from Entra to GitHub without ever being displayed:
>
> ```bash
> az ad app credential reset --id <appId> --years 2 --display-name "github-actions-ci" \
>   --query password -o tsv | tr -d '\r\n' | gh secret set STORE_CLIENT_SECRET --org <org> \
>   --visibility selected --repos <repo>
> ```
>
> **`credential reset` replaces every existing secret on the app** — there is no confirmation, and
> `--append` is what you want if you meant to add one alongside. Here replacing was the intent.

**Rotation (5 minutes, no CI change):** Entra → the app → *Certificates & secrets* → **New client
secret** → copy the Value → `gh secret set STORE_CLIENT_SECRET --org <org> --visibility selected
--repos <repo>` → delete the old secret. Nothing else moves: the client id, tenant id and Partner
Center grant are unaffected.

**Why not something that never expires:**

- **Federated credentials (GitHub OIDC)** would remove the secret entirely — nothing to rotate, ever.
  Blocked today because `msstore reconfigure` takes `--clientSecret`; the Store CLI cannot consume a
  federated token. Revisit if that changes: it is strictly better than any rotation schedule.
- **A certificate credential** can outlive 2 years, but the CLI wants a secret here too.

The symptom of a lapsed secret is an auth failure at submission time — annoying, but it cannot break
a release: submission is a separate manual workflow, so builds and GitHub releases keep working.

## 2. FIRST: associate an Entra tenant with the Partner Center account ✅

**Do this before anything else in Partner Center.** Azure AD applications can only be added under an
*associated tenant*, so without one there is nothing to grant the CI identity.

**Symptom when it is missing** (this is what we hit, and it reads like a broken login):

> *Account settings → User management* says "You are currently signed in as `<you>`. To manage
> users, sign in with your **associated** Microsoft Entra ID credentials", and the "Sign in with
> Microsoft Entra ID" button loops — you authenticate successfully and land back on the same page,
> forever.

It is not a credential problem. **Check *Account settings → Tenants*: if "Current tenant
associations" is an empty table, that loop can never resolve** — you are being asked to sign in
against an association that does not exist.

Likely root cause: the Partner Center account is signed in with a **Microsoft account (MSA)** while
the Entra work account has the *same email address*. They look identical and are different
identities.

**Fix (free — associating an existing tenant costs nothing, and Entra ID Free needs no
subscription):** *Account settings → Tenants* → the **`...`** overflow next to "Create Microsoft
Entra ID" → **Associate Microsoft Entra ID**, then sign in as a **global admin of that tenant**.

> **Do not click "Create Microsoft Entra ID"** — it sits immediately left of the overflow and makes a
> NEW tenant instead of associating the one your app registration already lives in.

> **Automation note:** these account pages render inside an **iframe**, so DOM queries from the top
> document return nothing and the `...` overflow does not respond to synthetic clicks. This step is
> hand-driven; budget a minute for it rather than scripting it.

Associating a tenant grants its users access to the developer account, and removing it later strips
those users and their permissions — so it is a deliberate, admin-level decision, not a formality.

> **URL gotcha:** the page is `/dashboard/account/v3/**tenantmanagement**`. The obvious
> `/dashboard/account/v3/tenants` renders Partner Center's *"Sorry, we couldn't find that page"*,
> which looks like a permissions problem and is not.

### 2a. What made this hard here — one identity, three meanings

Worth reading before touching any of it, because the same string `jbraun@gigaion.com` named **three
different identities** during this setup and the errors never say which one is being refused:

1. a **Microsoft account (MSA)** — the personal identity that *owns the Partner Center account*;
2. an **`#EXT#` guest** in the work tenant — that MSA invited in, which is what an early attempt
   signed in as, and why the association was refused;
3. a **native member** of the work tenant — what actually works.

Two tenants existed, and the custom domain was initially verified on the wrong one. A custom domain
can be verified in **exactly one tenant at a time**, so the fix is to move the domain, not to
duplicate it. The end state:

- one surviving workforce tenant, holding the custom domain, the Azure subscription, the
  **code-signing** account, and the CI app registration;
- Partner Center associated with **that** tenant;
- the second tenant deleted, having held nothing — verified before deleting, not assumed.

**Check before deleting any tenant:** `az account list --all` shows which tenant the Azure
subscription (and therefore Azure Artifact Signing) lives in. Deleting the tenant that holds it would
take **Windows code signing** down with it, which is a far worse outcome than a Store lane that does
not submit yet.

> **`az account list --all` is not a tenant-emptiness check.** It lists *subscriptions*. App
> registrations, enterprise apps and service principals are not subscriptions and do not appear in
> it, so a tenant can look empty by that command and still hold the identity your CI authenticates
> as — which dies with the tenant, silently, with no warning at delete time.
>
> **Before deleting a tenant, also list its app registrations** (Entra → App registrations → *All
> applications*). And record the tenant id of every registration you create: an app registration and
> the `STORE_TENANT_ID` you authenticate against must be the same directory, and nothing in the
> GitHub secret *names* records which directory that was.
>
> Here the registrations happened to be in the surviving tenant and nothing was lost — but that was
> luck, not verification. Confirm with `az ad app list --all -o table` after signing in to the
> tenant you intend to keep, before deleting the other one.

> **A dead portal session lies about which tenant exists.** After the deletion, the Entra admin
> center failed with `AADSTS90002: Tenant <id> not found` — because the browser session was still
> pinned to the deleted tenant, not because anything was wrong with the surviving one. That error is
> about your *session*, and it is easy to mistake for evidence that resources were destroyed. Sign in
> again against the surviving tenant before drawing any conclusion from it.

**Confirm the association took** without trusting the tenants page alone: *Account settings → Legal
info* lists **Microsoft Entra tenants**, and the tenant table shows the tenant id — it must match
`STORE_TENANT_ID` exactly. A different id means a different directory was associated, and the CI
credential will authenticate fine and then be refused.

## 3. Grant it Store access — Partner Center (browser, no API exists) ✅

Partner Center → **Account settings → User management → Microsoft Entra applications** → add the app
from step 1 with the **Developer** role.

> **Developer, not Manager — verified, and this runbook previously said otherwise.** Microsoft's
> guidance commonly names Manager, but Manager grants "complete access to account features except tax
> and payout… can manage users, roles, and tenants", which is a lot of authority to hand a CI secret.
> Developer is scoped to exactly what publishing needs — "can upload packages and submit apps and
> add-ons" — and `msstore apps list` succeeds with it, returning the real listing. Least privilege
> wins here; escalate only if a future CLI operation genuinely needs more.

> User management demands a *second* sign-in — "You are currently signed in as `<you>`. To manage
> users, sign in with your **associated** Microsoft Entra ID credentials". That is the work account
> from §2a, not the MSA you browsed in with. With a tenant associated this resolves; without one it
> loops forever (§2).

**The same create-vs-select trap as §2.** *Add Microsoft Entra application* opens a dialog offering
**Create Microsoft Entra application** (makes a brand-new registration) and **Add Microsoft Entra
application** (selects an existing one). Pick the second — the first silently gives you a second app
that your `STORE_CLIENT_ID` knows nothing about.

The picker lists every app registration in the associated tenant, which doubles as a check that
Partner Center is reading the directory you think it is: if the app you created in §1 is not in that
list, the tenant association points somewhere else. Tick **only** the StoreSubmit app — leaving the
signing app out is the whole point of having two (§1).

Saving takes ~10s behind a "Saving. Do not close." spinner, then the app appears **twice**, once as
`Microsoft Entra Apps` and once as `Service Principal`. That is normal, not a double-add.

Capture, while there:

- **Seller ID** → *Account settings → Legal info*, under **Publisher IDs** (an 8-digit number,
  listed beside "User Id" and "Windows publisher ID"). This becomes `STORE_SELLER_ID`.
- **Store ID** → the app's identity page. This becomes `STORE_APP_ID`.

## 4. GitHub configuration ✅

Org-level (`GigaionLLC`), visibility Selected → Airclone, matching the existing signing secrets:

```powershell
$ORG="GigaionLLC"
gh secret   set STORE_TENANT_ID       --org $ORG --visibility selected --repos Airclone --body "<tenant>"
gh secret   set STORE_CLIENT_ID       --org $ORG --visibility selected --repos Airclone --body "<appId>"
gh secret   set STORE_CLIENT_SECRET   --org $ORG --visibility selected --repos Airclone --body "<secret>"
gh secret   set STORE_SELLER_ID       --org $ORG --visibility selected --repos Airclone --body "<sellerId>"
gh variable set STORE_APP_ID          --org $ORG --visibility selected --repos Airclone --body "<storeId>"
```

There is no master switch to set last: submission is a manual dispatch, so all five can be staged
whenever they are known. The workflow refuses to start if `STORE_CLIENT_SECRET` or `STORE_APP_ID` is
missing.

## 5. What CI runs ✅

[`submit-msstore.yml`](../.github/workflows/submit-msstore.yml), by hand from the Actions tab. It
downloads the signed MSIX from the chosen release, checks its package identity, then runs
[`tool/store_submit.py`](../tool/store_submit.py) — with `--commit` only when *Dry run* is unchecked.

The script walks the REST flow, each step depending on the last:

| Step | Why it matters |
| :--- | :--- |
| token (client credentials, `resource=…devcenter…`) | the only place a wrong tenant/app/secret shows up |
| `GET /applications/{id}` | reads real state; **refuses if a submission is already pending** |
| `POST /submissions` | clones the last published submission — listing copy, screenshots, age rating and **pricing** carry over untouched |
| `PUT /submissions/{id}` | old packages → `PendingDelete`, new one → `PendingUpload` |
| `PUT` the zip to the SAS URL | `x-ms-blob-type: BlockBlob` |
| `POST /commit` | hands it to certification |
| `GET /status`, bounded poll | catches an immediate rejection; certification itself takes **days**, so polling to completion is pointless |

**A pending submission blocks a new one**, and the script refuses rather than deleting it, because a
draft may be a listing edit somebody made by hand. `--delete-pending` overrides that deliberately.

**Identity is checked before any of it** (`AppxManifest.xml` vs the `MSIX_*` repo variables), because
Partner Center validates the four identity fields in a fixed order and **the first failure masks the
rest** — fix one, resubmit, wait days, discover the next. That is how v0.6.0 burned four cycles.

> **`dotnet tool install --global MSStore.CLI` is dead**, if you ever go looking for the CLI path:
> the package is gone from nuget.org (absent from the flat container too, so removed rather than
> unlisted). The CLI itself still ships as release binaries via
> `microsoft/microsoft-store-apppublisher@v1.4` — but see the paid-product blocker in §0 before
> reaching for it.

## 6. Verification ✅

First green dry run: **2026-08-17**, `submit-msstore.yml` against `v0.6.7`. Verified by reading the
log, not by the green check (AGENT.md §9) — `airclone.msix` downloaded at 98,156,524 bytes,
`reconfigure` passed its own auth test, and `msstore apps list` returned the real listing with
ProductId matching `STORE_APP_ID`.

**Two independent faults had to be fixed, and each masked the other:**

| Fault | Symptom | Fix |
| :--- | :--- | :--- |
| The Entra app was never added in Partner Center | `Really failed to auth` | §3 — the applications tab read "You have not added any Microsoft Entra applications yet" |
| The stored client secret was unusable | `Really failed to auth` — *identical* | §1a — rotated through a pipe with the newline stripped |

The lesson worth keeping: **`Failed to auth` is not a diagnosis.** It covers a missing app
registration, a wrong tenant, an unauthorised app, and a malformed secret, with no way to tell them
apart from the message. Work through the four candidates in order of what you can *prove* — `az ad
app list` proves the app exists, the Partner Center applications tab proves the grant, and only the
secret cannot be inspected, so rotate that last rather than first.

---

## Gotchas collected while doing this

- **Security Defaults blocks app registration from a cached token** (step 1) — the error names
  Graph, not the Store, which makes it look unrelated.
- **`az login` may be refused entirely.** On this tenant both `az login --use-device-code` and the
  scoped variant returned *"Your sign-in was successful but you don't have permission to access this
  resource"* — the sign-in works, the resource is refused. The whole of step 1 was therefore done in
  the **Entra portal UI** instead, which worked first time. If the CLI fights you, stop fighting it.
- **Partner Center has two identities.** *Account settings → User management* refuses the Microsoft
  account you browse with and demands "Sign in with Microsoft Entra ID" — the work account. Expect a
  second sign-in specifically for the user-management pages.
- PowerShell mangles `az` failures: piping `2>&1 | ConvertFrom-Json` turns a readable `ERROR:` line
  into `Invalid JSON primitive`. Run the command plainly and read the error first.

### Handling the secret itself — a rule learned the hard way

**On a credentials page, never enumerate DOM inputs.** Avoiding a screenshot of the secret is not
enough: Entra keeps the real value in a hidden copy-to-clipboard input long after the visible table
truncates it, so a generic "list every input's value" query prints the full secret. That happened
during this setup and cost a freshly-created secret, which had to be deleted and replaced.

Query only the specific field you need, by label — or better, do the secret step by hand:

1. The person at the keyboard clicks **Add**, copies the Value, and runs
   `gh secret set STORE_CLIENT_SECRET --org <org> --visibility selected --repos <repo>` (it reads
   stdin, so the value never appears in a command line, a log, or an agent transcript).
2. Delete any superseded secret immediately — a secret that leaked anywhere is burned even if it was
   never used.
