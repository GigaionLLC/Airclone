# Microsoft Store CI submission — as-built setup runbook

**Purpose:** reproduce, from nothing, the credential that lets CI submit Airclone's MSIX to the
Microsoft Store — for a new Partner Center account, a rotated secret, or a different app.
**Status:** IN PROGRESS (2026-08-16). Steps are marked ✅ as they are completed and verified.
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

**What automation does NOT do:**

- **It cannot create the first submission.** The Store submission API updates an app that already has
  a completed submission. Listing copy, screenshots, age rating and the privacy-policy URL must
  already exist, done by hand once.
- **It does not make certification faster.** Play publishes in minutes; Microsoft review takes days,
  and this app has already burned cycles on identity rejections (v0.6.0, 4×) and a policy 10.2.5
  rejection. Automation makes *submitting* cheap — a bad submission still costs a review cycle.

---

## 1. Create the CI identity (Entra app registration)

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
| Created | **2026-08-16** (description `github-actions-long`) |
| Expires | **2028-08-15** (the maximum Entra allows) |

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

## 2. Grant it Store access — Partner Center (browser, no API exists)

Partner Center → **Account settings → User management → Azure AD applications** → add the app from
step 1 with the **Manager** role (that role is what grants Submission-API access).

Capture, while there — both are recorded as `_tbd_` in the as-built table and are needed:

- **Seller ID** — Account settings → Legal info / Developer
- **Store ID** — the app's identity page (this becomes `STORE_APP_ID`)

## 3. GitHub configuration

Org-level (`GigaionLLC`), visibility Selected → Airclone, matching the existing signing secrets:

```powershell
$ORG="GigaionLLC"
gh secret   set STORE_TENANT_ID       --org $ORG --visibility selected --repos Airclone --body "<tenant>"
gh secret   set STORE_CLIENT_ID       --org $ORG --visibility selected --repos Airclone --body "<appId>"
gh secret   set STORE_CLIENT_SECRET   --org $ORG --visibility selected --repos Airclone --body "<secret>"
gh secret   set STORE_SELLER_ID       --org $ORG --visibility selected --repos Airclone --body "<sellerId>"
gh variable set STORE_APP_ID          --org $ORG --visibility selected --repos Airclone --body "<storeId>"
gh variable set STORE_PUBLISH_ENABLED --org $ORG --visibility selected --repos Airclone --body "true"
```

`STORE_PUBLISH_ENABLED` is the last thing to set — with it unset the step is skipped entirely and its
secrets are never read, so everything above can be staged safely.

## 4. What CI runs

Already wired in [`release.yml`](../.github/workflows/release.yml) (windows job, tag pushes only,
`continue-on-error` so a Store hiccup never fails a release):

```powershell
dotnet tool install --global MSStore.CLI
msstore reconfigure --tenantId … --sellerId … --clientId … --clientSecret …
msstore publish airclone.msix --appId <STORE_APP_ID>
```

**Verify the flags against `msstore --help` at activation** — the CLI evolves, and the wiring
predates this setup.

## 5. Verification

*(recorded after the first automated submission)*

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
