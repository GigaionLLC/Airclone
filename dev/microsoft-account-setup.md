# Microsoft accounts, tenants and Partner Center — as-built, and how to rebuild it

**Purpose:** the map. If the Microsoft side of Airclone had to be rebuilt from nothing — new company,
new tenant, lost access, or somebody simply asking "how is this wired?" — this is the document that
says what exists, in what order it must be created, and which parts cannot be automated.

**Scope:** identities, tenants, Partner Center, and the two Entra app registrations. The per-lane
detail lives in siblings and is not repeated here:

| Doc | Covers |
| :--- | :--- |
| [`windows-signing-and-store.md`](windows-signing-and-store.md) | Azure Artifact Signing, the MSIX build, the Store listing itself |
| [`msstore-ci-setup.md`](msstore-ci-setup.md) | the Store **submission** credential and workflow |
| [`play-ci-setup.md`](play-ci-setup.md) | the Google Play equivalent — different vendor, same shape |

> **This repo is public.** Every identifier below is a `<placeholder>`. Tenant ids, client ids, the
> Seller ID, the publisher GUID and the D-U-N-S are **not committable**. They live in GitHub
> secrets/variables and private notes. Nothing here should ever be filled in with a real value.

**Cost: nothing.** Entra ID Free needs no subscription, associating a tenant is free, and the Partner
Center developer account was a one-off company registration. The Azure subscription exists only to
host code signing. No step in this document requires adding a payment method.

---

## 1. The mental model — read this before clicking anything

Almost every wasted hour in this setup came from one thing: **the same email address can be three
different identities**, and Microsoft's errors never say which one refused you.

| Identity | What it is | Where it bites |
| :--- | :--- | :--- |
| **Microsoft account (MSA)** | a personal Microsoft login that happens to use your company address | it **owns the Partner Center account** |
| **`#EXT#` guest** | that MSA invited into a work tenant | looks like a member, cannot act as an admin of it |
| **native member** | a real user created *inside* the work tenant | the one that actually works |

Once a custom domain is verified in a tenant, `you@yourcompany.com` is ambiguous at every Microsoft
sign-in prompt, and you must consciously choose **"Work or school account"**. Picking the personal
one is the single most common cause of "you don't have permission" here.

Two more distinctions worth having straight:

- **Workforce tenant vs External ID tenant.** Workforce is what you want for staff and admin. An
  External ID (CIAM) tenant is for *your customers* signing into *your product*. Creating the wrong
  one and putting the company domain on it is easy and wastes an afternoon.
- **A custom domain can be verified in exactly one tenant at a time.** If it is on the wrong tenant,
  the fix is to *move* it, not to add it in both.

### Where things actually live

```
Microsoft account (personal)  ──owns──▶  Partner Center account ──associated with──▶ Entra tenant
                                                                                       │
                              Azure subscription ──────────────────────────────────────┤
                                    └── code signing account (Azure Artifact Signing)   │
                                                                                        │
                              App registrations ────────────────────────────────────────┘
                                    ├── <Org>-Signing       → signs the exe/installer
                                    └── <Org>-StoreSubmit   → submits MSIX to the Store
```

**The Partner Center account is owned by an MSA and that cannot be changed by you** — moving
ownership to a work account needs a Microsoft support ticket. It is a cosmetic annoyance, not a
blocker: automation authenticates as an app registration, not as the owner, so everything works with
ownership left where it is.

---

## 2. Order of operations, from nothing

Order matters — several steps are impossible until an earlier one exists.

1. **Entra tenant** (workforce). If you already have one from an Azure subscription, use it. Do not
   create a second; two tenants with similar names is the trap that produced most of §5.
2. **Native admin user** in that tenant — `you@<tenant>.onmicrosoft.com`, Global Administrator. Do
   this even if your MSA is already a guest: the guest cannot do steps 6 and 7.
3. **Custom domain** (optional) — verify `yourcompany.com` in that tenant via DNS TXT.
4. **Partner Center account** — company registration at partner.microsoft.com. Needs a D-U-N-S and
   business verification (days, not minutes). Signed in with the MSA.
5. **App registrations** — one per job (§3).
6. **Associate the tenant with Partner Center** — *Account settings → Tenants*. **Do this before
   anything else in Partner Center**, because app grants are impossible without it (§4).
7. **Grant the CI app a role** — *Account settings → User management → Microsoft Entra applications*
   (§4).
8. **GitHub secrets and variables** (§6).
9. **Prove it** — dry-run the workflows before trusting anything (§7).

---

## 3. The two app registrations

**Keep them separate.** A leaked publishing secret then cannot sign binaries, and either can be
rotated without disturbing the other.

| Registration | Used by | Lives where |
| :--- | :--- | :--- |
| `<Org>-Signing` | Azure Artifact Signing — signs `.exe` / `.msi` | needs a **role assignment on the Azure signing account** |
| `<Org>-StoreSubmit` | Store submission API | needs a **Partner Center role** (§4) |

```powershell
az ad app create --display-name "<Org>-StoreSubmit" --sign-in-audience AzureADMyOrg
az ad sp create --id <appId>
```

**Secrets expire — there is no "never".** Entra caps client secrets at **24 months**, and choosing
*Custom* does not get you around it; the portal states the rule outright ("The value must be between
`<today>` and `<today + 2 years>`"). Plan on a known rotation date rather than a surprise. Rotation
is 5 minutes and needs no CI change — see [`msstore-ci-setup.md`](msstore-ci-setup.md) §1a.

**Set the secret through a pipe so it is never displayed.** Use Git Bash, and strip the newline —
PowerShell appends `\r\n`, and a secret with a stray carriage return fails authentication
*identically* to a wrong one:

```bash
az ad app credential reset --id <appId> --years 2 --display-name "github-actions-ci" \
  --query password -o tsv | tr -d '\r\n' | gh secret set STORE_CLIENT_SECRET --org <org> \
  --visibility selected --repos <repo>
```

`credential reset` **replaces every existing secret** on the app; `--append` adds one alongside.

---

## 4. Partner Center — the two steps with no API

Both are hand-driven. Budget ten minutes, not a script.

### 4a. Associate the tenant

*Account settings → **Tenants*** → **Associate Microsoft Entra ID** → sign in as a **global admin of
that tenant**.

- The page is `/dashboard/account/v3/**tenantmanagement**`. The obvious `.../tenants` returns Partner
  Center's "Sorry, we couldn't find that page", which looks like a permissions problem and is not.
- **Do not click "Create Microsoft Entra ID"** — it sits right beside Associate and makes a *new*
  tenant instead of associating yours.
- Confirm it took by checking that the tenant id shown matches the one CI authenticates against.
  *Account settings → Legal info* also lists **Microsoft Entra tenants**.

### 4b. Grant the CI app a role

*Account settings → **User management** → **Microsoft Entra applications*** → **Add Microsoft Entra
application** → select the existing app → role **Developer**.

- The dialog again offers **Create** (new app) beside **Add** (select existing). Pick **Add**.
- **Developer, not Manager.** Manager grants "complete access… can manage users, roles, and tenants",
  which is far too much authority for a CI secret. Developer is exactly "upload packages and submit
  apps", and it is sufficient — verified, not assumed.
- Saving takes ~10s, then the app appears **twice** (as *Microsoft Entra Apps* and as *Service
  Principal*). That is normal.
- Tick only the submission app. Leaving the signing app out is the entire point of having two.

**Symptom that 4a was skipped:** User management says "sign in with your **associated** Microsoft
Entra ID credentials" and the sign-in **loops forever**. It is not a credential problem — check
whether "Current tenant associations" is an empty table.

---

## 5. Things that will bite you

Every one of these actually happened.

**`AADSTS530035` on `az login --use-device-code`.** Security Defaults blocks the device-code flow —
it is phishable, so Microsoft disables it by default. The sign-in genuinely succeeds and the *token*
is refused, which reads like a permissions problem. **Use plain `az login`** (authorization-code flow
in a browser); it is permitted. A device code also only polls ~15 minutes before exiting with
`AADSTS70016 Authorization is pending`, which looks like failure but means nobody typed it in time.

**`AADSTS90002: Tenant <id> not found` is about your session, not your resources.** After deleting a
tenant, a portal tab still pinned to it fails this way. It is *not* evidence that anything was
destroyed. Sign in again against the surviving tenant before concluding anything — this error
produced a completely wrong diagnosis here, and nearly a needless credential rebuild.

**`az account list --all` is not an emptiness check.** It lists **subscriptions**. App registrations
and service principals are not subscriptions and will not appear, so a tenant can look empty and
still hold the identity CI authenticates as. **Before deleting a tenant, also run `az ad app list
--all -o table`** against it.

**Deleting a tenant would take code signing with it** if the Azure subscription lives there. Check
`az account list --all` *for that reason* — it is the right tool for that question, just not for the
one above.

**Never enumerate DOM inputs on a credentials page.** Entra keeps a client secret in a hidden
copy-to-clipboard input long after the visible table truncates it, so a generic "list every input"
query prints the whole secret. That happened here and cost a freshly-created secret, which had to be
deleted and replaced. Query the one field you need, by label — or do the secret step by hand.

**Partner Center account pages render in an iframe**, so DOM queries from the top document return
nothing and overflow menus ignore synthetic clicks. Widen the window instead of fighting it; a
too-narrow window is what hid the Associate button behind an unresponsive `...`.

**Partner Center makes you sign in twice** — once as the MSA to browse, again as the work account for
User management. Expect it; it is not a bug.

---

## 6. What CI actually holds

Org-level in GitHub (`--visibility selected`, scoped to the one repo):

| Name | Kind | Feeds |
| :--- | :--- | :--- |
| `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET` | secret | code signing |
| `AZURE_SIGNING_ACCOUNT`, `AZURE_SIGNING_ENDPOINT`, `AZURE_SIGNING_PROFILE` | variable | code signing |
| `WINDOWS_SIGNING_ENABLED` | variable | master switch for signing |
| `STORE_TENANT_ID`, `STORE_CLIENT_ID`, `STORE_CLIENT_SECRET` | secret | Store submission |
| `STORE_SELLER_ID` | secret | kept for reference; the REST API takes no seller id |
| `STORE_APP_ID` | variable | the Store ID of the product |
| `MSIX_IDENTITY_NAME`, `MSIX_PUBLISHER`, `MSIX_DISPLAY_NAME` | repo variable | injected into the MSIX at build; **placeholders in pubspec** so local builds still work |

**The `STORE_TENANT_ID` and the tenant holding `STORE_CLIENT_ID` must be the same directory**, and
nothing in the names records which directory that was. Write it down somewhere private.

---

## 7. Prove it, don't assume it

Both publishing lanes have a dry run that authenticates for real and changes nothing. Use them:

```bash
gh workflow run submit-msstore.yml --repo <org>/<repo> -f tag=<tag> -f dry_run=true
```

And read the log rather than the green tick — this repo has shipped three Windows releases with no
bundled rclone because `continue-on-error` hid a failure (AGENT.md §9).

**`Failed to auth` is not a diagnosis.** It covers a missing app registration, a wrong tenant, an
unauthorised app, and a malformed secret, with no way to tell them apart. Work the list in order of
what you can *prove*:

1. `az ad app list --display-name "<Org>-StoreSubmit"` — does the app exist, in this tenant?
2. Partner Center → User management → Microsoft Entra applications — is it granted?
3. Legal info → Microsoft Entra tenants — is the associated tenant the one you are authenticating
   against?
4. Only then rotate the secret — it is the one input you cannot inspect, so it is the last thing to
   suspect, not the first.
