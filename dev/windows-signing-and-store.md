# Windows code signing + Microsoft Store — activation guide

**Windows code signing is LIVE** as of **v0.5.1** — every tagged release signs `airclone.exe` + the
installer + the bundled `rclone.exe` (subject "Gigaion, LLC"), gated on org vars
`AZURE_SIGNING_PROFILE=GigaionLLC-PublicCertProfile` + `WINDOWS_SIGNING_ENABLED=true` (both set).

**The Microsoft Store product is a PACKAGED MSIX** since the 2026-08-08 path reversal (§2) — the
unpackaged EXE/MSI product it replaced is kept below as record, not as instructions. Submission is
the manual [`submit-msstore.yml`](../.github/workflows/submit-msstore.yml) workflow run in
**`mode: stage`**, followed by a human pressing **Submit for certification** in Partner Center.
Committing a submission through the API is permanently forbidden for this product — it republishes
the app at $0 (AGENT.md rule 10). The submission credential and the workflow itself live in
[`dev/msstore-ci-setup.md`](msstore-ci-setup.md); §2 here is the account, the package identity, and
what a human still owns per release.

Historical note: each CI signing block is guarded by `if: ${{ vars.<FLAG> == 'true' }}`, so before
activation an unset flag skipped the step entirely (its secrets were never read).

---

## Tools & auth used (reproduce with the same)

Everything was done from a Windows machine with these tools. All Azure
identity/RBAC operations below are **free** — only the signing account (+ per-use
signing) is billed. Do NOT create any other Azure resources.

- **Azure CLI** — `winget install Microsoft.AzureCLI`. Auth: `az login --use-device-code`
  (headless-friendly: prints a code to enter at <https://microsoft.com/devicelogin>;
  signed in as the subscription owner). The login persists in `%USERPROFILE%\.azure`,
  so later `az` calls reuse it.
- **GitHub CLI (`gh`)** — authenticated in the keyring. **Org** secrets need the
  **`admin:org`** scope (repo scope alone can't write them):
  `gh auth refresh -h github.com -s admin:org` (device-code: one-time code at
  <https://github.com/login/device>).
- **Inno Setup** (installer) — `winget install JRSoftware.InnoSetup`; compiler at
  `%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe`.
- **msix** (Store package) — a dev-dependency in `app/pubspec.yaml`; `dart run msix:create`.

> Handling secrets: the client secret was captured into a shell variable and piped
> straight into GitHub (`gh secret set --body $SECRET`) — never printed to the
> terminal/chat. GitHub secrets are write-only; you cannot read one back (that's why
> moving to org-level re-mints a fresh secret rather than copying the old one).

---

## As-built record — GigaionLLC / Airclone (started 2026-07-12)

> **This repo is PUBLIC.** Identifying values — subscription/tenant/app/validation
> ids, D-U-N-S, physical addresses, personal emails — are **redacted to placeholders**
> here and kept only in PRIVATE project notes. No secret is ever in the repo (the
> client secret lives only in the GitHub `AZURE_CLIENT_SECRET` secret).

Values for THIS setup (identifiers redacted per the note above):

| Thing | Value |
|---|---|
| Trusted/Artifact Signing account | `GigaionLLC` |
| Resource group | `GigaionLLC-ResourceGroup1` |
| Subscription id | `<subscription id>` |
| Entra tenant id | `<tenant id>` |
| Region / endpoint | West US / `https://wus.codesigning.azure.net/` |
| Entra app registration | `GigaionLLC-Signing`, appId `<app id>` |
| RBAC role (data-plane signing) | **`Artifact Signing Certificate Profile Signer`** (the service is branded "Artifact Signing"; the old name was "Trusted Signing …") |
| Certificate profile | **`GigaionLLC-PublicCertProfile`** (type Public Trust, West US, created 2026-07-23) = `vars.AZURE_SIGNING_PROFILE` |
| Client secret | 2-year, minted 2026-07-12 → rotate before **2028-07** |

**Provisioned + wired (done):** app registration + SP, role at the account scope,
client secret, and — at the **GitHub org (GigaionLLC), visibility = Selected
repositories → Airclone** — secrets `AZURE_TENANT_ID` / `AZURE_CLIENT_ID` /
`AZURE_CLIENT_SECRET` and variables `AZURE_SIGNING_ACCOUNT` / `AZURE_SIGNING_ENDPOINT`.
Org-level so every GigaionLLC product shares one signing setup; to add a product,
add its repo to each secret/variable's selected list (see runbook). No repo-level
signing secrets remain on Airclone.

**Identity validation (portal, manual) — COMPLETED 2026-07-23:**
- validation id `<identity validation id>`, org **"Gigaion, LLC"**, type **Public**, US.
- Needed the **`Artifact Signing Identity Verifier`** role on your USER account, assigned at the account
  scope — SEPARATE from the app's Signer role.
- Portal path: the Artifact/Trusted Signing account → **Identity validation** → **New identity** →
  **Organization** → **Public** → fill legal name / address / (D-U-N-S if prompted) → **Submit** →
  status **In Progress → Completed** (days). A **Public Trust** certificate profile requires this
  **Completed** first.

**Certificate profile (portal, manual) — CREATED 2026-07-23:** in the signing account →
**Objects → Certificate profiles → Create → Public Trust** → picked the Completed identity under
"Verified CN and O" → named it **`GigaionLLC-PublicCertProfile`**. Creating a profile needs
**Contributor/Owner** (control-plane); the `GigaionLLC-Signing` SP already held the data-plane
**Signer** role at ACCOUNT scope, which inherits to the new profile. (A **Public Trust *Test*** profile
needs no validation and can smoke-test CI signing early, but its signatures are NOT publicly trusted.)

**Activated (runbook step 5):** set org vars `AZURE_SIGNING_PROFILE=GigaionLLC-PublicCertProfile` +
`WINDOWS_SIGNING_ENABLED=true`. First signed release **v0.5.1** confirmed — `Get-AuthenticodeSignature`
returns **Valid / CN="Gigaion, LLC"**, chain `Microsoft ID Verified CS AOC CA 03`, RFC-3161 timestamped.

## Reproduce — CLI runbook (idempotent-ish)

Everything below is **free** (Entra + RBAC ops); the only paid resource is the
signing account itself. Prereqs: `az` (`winget install Microsoft.AzureCLI`) and
`gh` (authenticated with repo admin). Run in PowerShell.

```powershell
# --- 0. sign in (device code works headless: prints a code to enter in a browser)
az login --use-device-code

# --- parameters (edit for a new org/app) ---
$SUB="<subscription id>"
$RG="GigaionLLC-ResourceGroup1"
$ACCOUNT="GigaionLLC"
$APPNAME="Airclone-Signing"
$REPO="GigaionLLC/Airclone"
$ENDPOINT="https://wus.codesigning.azure.net/"     # from the account's "Account URI"
$acct="/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.CodeSigning/codeSigningAccounts/$ACCOUNT"
$TENANT=(az account show --query tenantId -o tsv)

# --- 1. find the exact signing role name (branding changed: "Artifact Signing …")
az role definition list --scope $acct --query "[?contains(roleName,'Sign')].roleName" -o tsv
$ROLE="Artifact Signing Certificate Profile Signer"

# --- 2. app registration + service principal
$APPID=(az ad app create --display-name $APPNAME --sign-in-audience AzureADMyOrg --query appId -o tsv)
az ad sp create --id $APPID | Out-Null
$SPID=(az ad sp show --id $APPID --query id -o tsv)

# --- 3. assign the signer role at the ACCOUNT scope (retry: new SP may need to replicate)
az role assignment create --assignee-object-id $SPID --assignee-principal-type ServicePrincipal --role $ROLE --scope $acct

# --- 4. client secret (2 yr). Capture it; pipe straight into GitHub — never print it.
$SECRET=(az ad app credential reset --id $APPID --display-name "github-actions-org" --years 2 --query password -o tsv)
# ORG-level (shared across GigaionLLC products — one Artifact Signing account +
# one org-identity cert profile signs them all), scoped to the repos that sign.
# Needs the admin:org scope on gh:  gh auth refresh -h github.com -s admin:org
$ORG="GigaionLLC"
gh secret   set AZURE_TENANT_ID       --org $ORG --visibility selected --repos Airclone --body $TENANT
gh secret   set AZURE_CLIENT_ID        --org $ORG --visibility selected --repos Airclone --body $APPID
gh secret   set AZURE_CLIENT_SECRET    --org $ORG --visibility selected --repos Airclone --body $SECRET
gh variable set AZURE_SIGNING_ACCOUNT  --org $ORG --visibility selected --repos Airclone --body $ACCOUNT
gh variable set AZURE_SIGNING_ENDPOINT --org $ORG --visibility selected --repos Airclone --body $ENDPOINT
# To let ANOTHER org repo sign, add it to every secret/var's selected list, e.g.:
#   gh secret set AZURE_CLIENT_SECRET --org GigaionLLC --visibility selected --repos Airclone,abcli --body $SECRET

# --- 5. DONE 2026-07-23 (profile GigaionLLC-PublicCertProfile) — the two ORG-level vars ARE set
# (same visibility=selected -> Airclone as the rest). Shown for reproduction / to change the profile:
gh variable set AZURE_SIGNING_PROFILE   --org $ORG --visibility selected --repos Airclone --body "GigaionLLC-PublicCertProfile"
gh variable set WINDOWS_SIGNING_ENABLED --org $ORG --visibility selected --repos Airclone --body "true"
```

**Rotate the client secret** (e.g. before it expires): re-run step 4 (it resets the
credential and updates the GitHub secret). **Identity validation + certificate
profile are portal/manual** (identity validation needs Microsoft approval and can't
be scripted meaningfully).

---

## 1. Code signing — Azure Trusted Signing (~$10/month)

Signs `airclone.exe` **and** the installer `airclone-setup-x64.exe` so Windows
shows a real publisher instead of "unknown publisher". A cloud-HSM service —
**no USB token, no physical machine**, works on GitHub-hosted runners. (The
`--store` MSIX is NOT signed here; the Microsoft Store signs that on submission.)

### One-time setup
1. Azure subscription → create a **Trusted Signing account** (Azure portal →
   search "Trusted Signing accounts"). Pick a region — note its **endpoint** URL
   (e.g. `https://eus.codesigning.azure.net/` for East US).
2. **Identity validation FIRST** (the signing account → **Identity validation** →
   **New identity** → Organization → **Public** → legal name/address/D-U-N-S + upload
   formation docs → Submit). This needs **Microsoft approval** — status **In Progress →
   Completed**, ~days — and is REQUIRED before a Public Trust profile. Notes:
   - **Artifact Signing is only available to orgs in the USA / Canada / EU / UK.**
   - Submitting it needs the **`Artifact Signing Identity Verifier`** role on your USER
     (separate from the app's Signer role in step 4).
3. **AFTER validation is Completed**, create a **Certificate Profile** of type **Public
   Trust** (its create form makes you select a **Completed** identity validation — an
   "In Progress" one will NOT appear, so you truly cannot make it early). Note the
   **profile name** + **account name**.
   - The **"Linked certificate profiles"** link on the identity-validation blade is only
     a VIEWER (profiles attached to this identity); it does NOT enable creating a Public
     Trust profile while validation is pending.
   - A **Public Trust *Test*** profile needs NO validation and can smoke-test the whole
     CI signing pipeline early — but its signatures chain to a TEST root (NOT publicly
     trusted), so it's a plumbing check only, not a shippable build.
4. Create an **Entra ID (Azure AD) app registration** with a **client secret**. Grant it
   the **"Artifact Signing Certificate Profile Signer"** role on the signing account
   (Access control (IAM) → Add role assignment). (The service is branded "Artifact
   Signing"; some older docs say "Trusted Signing …".) Note the **tenant id**, **client
   id**, **client secret**.

### GitHub config — ORG-level (Org → Settings → Secrets and variables → Actions → Organization; visibility = Selected repositories → the repos that sign)
Secrets:
- `AZURE_TENANT_ID`
- `AZURE_CLIENT_ID`
- `AZURE_CLIENT_SECRET`

Variables:
- `AZURE_SIGNING_ENDPOINT` = the endpoint URL from step 1
- `AZURE_SIGNING_ACCOUNT`  = the Trusted Signing account name
- `AZURE_SIGNING_PROFILE`  = the certificate profile name
- `WINDOWS_SIGNING_ENABLED` = `true`   ← the master switch

That's it — the next tagged release signs the exe + installer. Note: an **OV**
profile still shows a SmartScreen "unknown publisher" prompt until it earns
download reputation (days–weeks); an **EV** profile is trusted instantly.

---

## 2. Microsoft Store — company account + per-release submission

> **PATH DECISION (2026-08-08): we ship as an MSIX.** This REVERSES the 2026-07-23 EXE/MSI decision
> quoted below. Reason: only a *packaged* product has Store commerce, so the Store collects the
> listing fee and **no payment code ever enters this open-source app**. The EXE/MSI product type
> shows only "Download" and its pricing dropdown is inert metadata. Submissions go to the packaged
> reservation **"Airclone: Cloud File Manager"** (`GigaionLLC.AircloneCloudFileManager`).
>
> **Superseded 2026-08-16:** `STORE_PUBLISH_ENABLED` is **retired**, and submission is no longer
> attached to tagging at all. It is a manual workflow —
> [`submit-msstore.yml`](../.github/workflows/submit-msstore.yml), run from the Actions tab against
> a tag — mirroring the Google Play promote button. Certification takes days and a bad submission
> costs a review cycle, so a human decides when a build is worth one. Setup:
> [`dev/msstore-ci-setup.md`](msstore-ci-setup.md).

<details><summary>Superseded 2026-07-23 decision (EXE/MSI), and the two per-release steps that were only ever its own — kept as record</summary>

We shipped as an UNPACKAGED Win32 EXE app, NOT MSIX. The "Airclone" app in Partner Center was the
EXE/MSI product type — you host your own signed installer at a direct (non-redirecting) URL and the
Store points at it. That reused the `airclone-setup-x64.exe` we already build + sign and needed no
MSIX identity plumbing, which is also why `STORE_PUBLISH_ENABLED` was kept unset: `msstore publish`
would have published the wrong package.

Two per-release steps belonged to that product alone — a packaged submission uploads the package to
Partner Center instead. They are kept because they are the record of how the EXE product was
operated, and of what a self-hosted-installer product costs to run.

**B. Host it at a DIRECT URL** (GitHub release URLs do NOT work — see the EXE gotchas below.) Upload
the verified installer to
**`https://gigaion.com/releases/airclone/vX.Y.Z/airclone-setup-x64.exe`** (our web host). Confirm
`curl -I` → **HTTP 200, no redirect**, `application/octet-stream`, and SHA256 matches the CI
installer.

The host is our 1Panel box, reached over SSH as `<release-ssh-host>` (LAN-only hostname; the account
+ path are in PRIVATE notes — this repo is public). The served tree is
`<release-root>/airclone/vX.Y.Z/airclone-setup-x64.exe`, which 1Panel maps to
`https://gigaion.com/releases/airclone/...`. One version per directory, and **never overwrite a
submitted binary** — Partner Center pins the bytes at the URL. Run from the machine holding the
verified installer:

```powershell
$VER  = "vX.Y.Z"
$SSH  = "<release-ssh-host>"            # e.g. user@host
$ROOT = "<release-root>/airclone"       # 1Panel site path, from private notes

# Pull the CI-built, CI-signed installer rather than a local build.
gh release download $VER --repo GigaionLLC/Airclone --pattern airclone-setup-x64.exe

# Verify BEFORE publishing: signed by us, and ~66 MB (i.e. rclone is bundled).
Get-AuthenticodeSignature .\airclone-setup-x64.exe | Format-List Status, SignerCertificate
(Get-Item .\airclone-setup-x64.exe).Length

ssh $SSH "mkdir -p $ROOT/$VER"
scp .\airclone-setup-x64.exe "${SSH}:$ROOT/$VER/airclone-setup-x64.exe"

# The served bytes must equal the bytes we verified.
(Get-FileHash .\airclone-setup-x64.exe -Algorithm SHA256).Hash.ToLower()
ssh $SSH "sha256sum $ROOT/$VER/airclone-setup-x64.exe"

# And the URL must answer 200 with NO redirect (Partner Center rejects 3xx).
curl.exe -sSI "https://gigaion.com/releases/airclone/$VER/airclone-setup-x64.exe"
```

**C. Partner Center → Packages → Package details** (App type = EXE)

| Field | Value |
|---|---|
| Package URL | `https://gigaion.com/releases/airclone/vX.Y.Z/airclone-setup-x64.exe` (versioned, direct) |
| Architecture | **x64** |
| Installer parameters | **`/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /ALLUSERS`** (leave "silent, no switches" UNCHECKED) |
| Languages | English (United States) |
| App type | **EXE** |
| Installer handling URL | (blank) |
| Install scenarios (Inno exit codes) | successful `0` · cancelled `2` **and** `5` · disk-full `4` · reboot `8` · leave *already exists / in progress / network / rejected* blank |

</details>

## 2-MSIX — the LIVE packaged path (since 2026-08-08)

This IS the path we ship (see the PATH DECISION above). **§2a is the real, as-built account**, and
§§2b–2g are the live one-time setup; the per-release runbook, the EXE-era gotchas and the
certification post-mortems follow them.

### 2a. Register the COMPANY account — the ACTUAL flow (done 2026-07-12)
Microsoft moved onboarding to a new wizard at **<https://storedeveloper.microsoft.com>**,
and in this flow the **company account is FREE** (the old $99 fee is gone — both
Individual and Company show "Free"). Entry point: Partner Center
(<https://partner.microsoft.com/dashboard>) → **Account settings → Programs → Windows →
"Get started"** (redirects to storedeveloper.microsoft.com), or go there directly.

Wizard = 4 steps: **Account type → Business details → Contact details → Account verification.**

1. **Account type** → **Company account** (publishes as "Gigaion, LLC").
2. **Business details** → **Use a D-U-N-S number** (auto-retrieves + validates the
   company instantly), or "Upload a business document". The D-U-N-S lookup auto-fills
   your company name + registered address — verify it matches your records.
   - **Registration number** = OPTIONAL (a state LLC/entity number; NOT the D-U-N-S,
     NOT a Microsoft id — leave blank if unknown).
   - **Company website** (required) = `https://gigaion.com`.
   - **Publisher display name** (required) = **"Gigaion, LLC"** — SAVE THIS EXACTLY; it
     must match `msix_config.publisher_display_name` (§2c) later.
3. **Contact details** → name, phone, and an **org-domain work email** (must be on your
   organization's domain; personal Gmail/Outlook/iCloud are rejected — it's verified
   in-flow). Then **"Contact information shown on your Store page"** (a PUBLIC address).
   - ⚠️ **ADDRESS-VALIDATION GOTCHA (cost us real time).** The public-contact address
     validator can reject a legitimate address as **`PremisesPartial`** — it matched the
     building but not a deliverable *sub-premises* (unit/suite). The backend actually
     returns `"isValid": true` (seen in the browser debug console) but the UI blocks
     Continue and offers no picklist (`suggestions: []`). Our registered legal address
     hit this regardless of ZIP vs ZIP+4.
     **Fixes, in order:** (a) add a real unit to Address Line 2 if one exists; (b)
     **UNCHECK "Use company legal address" and enter a DIFFERENT verifiable address** —
     the legal address is already validated via D-U-N-S, and this field is *meant* to be
     the public contact. **We used a PO Box and it passed.** (c) else escalate via "Get
     support" with the response `correlationId` (backend `isValid:true` is a strong case).
4. **Account verification** → Email ✅ and Employment ✅ verify automatically;
   **Business verification** goes **"Under review" (~5 business days**, via the uploaded
   formation docs / D-U-N-S). "Finish account setup" stays disabled until all three are
   green. **SUBMITTED 2026-07-12, and Completed** — see the as-built table below.

### 2b. Reserve the app + copy its identity (after the dev account is verified)
In the account (Partner Center / Store Developer) → reserve the app name. **It must be a PACKAGED
reservation** — an EXE/MSI product has no package identity to copy, which is why the 2026-08-08
pivot needed a fresh reservation rather than the existing "Airclone" one; ours is **"Airclone: Cloud
File Manager"**. Then open the app → **Product management → Product identity** and copy:
- **Package/Identity Name** (e.g. `1234Gigaion.Airclone`)
- **Publisher** (`CN=<GUID>`)
- **Publisher display name** (e.g. `Gigaion, LLC`)
- the **Store ID** (the product id)

### 2c. Put the real identity in the package  (via REPO VARIABLES, not pubspec)
`Package/Identity/Publisher` is a Partner-Center-assigned GUID and this repo is
public, so the real identity is injected by `release.yml` from repo variables and
`app/pubspec.yaml` keeps inert `PLACEHOLDER.*` values. Set all three:

```powershell
gh variable set MSIX_IDENTITY_NAME --repo GigaionLLC/Airclone --body "<Package/Identity/Name>"
gh variable set MSIX_PUBLISHER     --repo GigaionLLC/Airclone --body "CN=<GUID>"
gh variable set MSIX_DISPLAY_NAME  --repo GigaionLLC/Airclone --body "<a RESERVED app name>"
```

Copy the values verbatim from **Product management → Product identity**. If any
variable is unset the build still runs but emits a `::warning::` and produces a
package Partner Center WILL reject — that silence is exactly how v0.6.0 shipped
with placeholder identity. `publisher_display_name` stays in pubspec (`Gigaion, LLC`):
it is the company name, already public throughout this repo, and is not a GUID.

Four manifest fields are validated on upload, and **the first failure masks the rest** — fix them
as a set, not one round-trip each. The field-by-field table (which variable feeds which field, and
which single one is safe to commit) is owned by [`docs/store/README.md`](../docs/store/README.md),
under "MSIX package identity"; what this runbook adds is where each value is *read from*, all four
on **Product management → Product identity**: `Identity/Name` = the reserved package name,
`Identity/Publisher` = the assigned Publisher ID (`CN=<GUID>`), `Properties/DisplayName` = a
**reserved app name**, `Properties/PublisherDisplayName` = the Store publisher display name.

The **package family name** is not a field — it is derived as
`<Identity/Name>_<base32(SHA-256(Publisher as UTF-16LE)[0..7])>` using the alphabet
`0123456789abcdefghjkmnpqrstvwxyz`. Computing it locally is a fast way to prove a
publisher string is byte-exact before uploading 95 MB.

Gotcha: `msix` drives BOTH `Package/Properties/DisplayName` and the Start-menu tile
(`uap:VisualElements/@DisplayName`) from one `display_name`, so `MSIX_DISPLAY_NAME`
is also what users see on the tile. Reserving a short name (Product management →
**Manage app names**) is the only way to get a short tile.

A `--store` package only uploads once its identity matches the reserved app. Because
`--store` packages are UNSIGNED, a wrong identity can be corrected without rebuilding:
`makeappx unpack` → edit `AppxManifest.xml` → delete `AppxBlockMap.xml` →
`makeappx pack` (it regenerates the block map).

### 2d. API credentials for automated submission
1. Create a **dedicated** Entra app registration — separate from the §1 signing app, so a leaked
   publishing secret cannot sign binaries and either can be rotated without disturbing the other.
   Note tenant id, client id, and a client secret.
2. Partner Center → **Account settings → User management → Microsoft Entra applications** (the menu
   was "Azure AD applications") → add that app with the **Developer** role. Developer is exactly
   "upload packages and submit apps and add-ons", which is all the Submission API needs. **Not
   Manager** — Manager also grants user, role and tenant management, far more authority than a CI
   secret should hold. Verified, not assumed; the sign-in traps on that page are in
   [`dev/msstore-ci-setup.md`](msstore-ci-setup.md) §3.
3. Note your **Seller ID** (Account settings → Legal info / Developer).

### 2e. GitHub config — ORG-level (GigaionLLC, visibility = Selected → Airclone)
Secrets `STORE_TENANT_ID` / `STORE_CLIENT_ID` / `STORE_CLIENT_SECRET` / `STORE_SELLER_ID`; variable
`STORE_APP_ID` (= the Store ID). **There is no master switch to set last.** The old
`STORE_PUBLISH_ENABLED` existed to keep an automatic-on-tag submission dormant and is retired now
that submission is a manual dispatch, so all five values can be set the moment they are known:
[`submit-msstore.yml`](../.github/workflows/submit-msstore.yml) simply refuses to start unless
`STORE_CLIENT_SECRET` and `STORE_APP_ID` are both non-empty.

```powershell
$ORG="GigaionLLC"
gh secret   set STORE_TENANT_ID       --org $ORG --visibility selected --repos Airclone --body "<tenant>"
gh secret   set STORE_CLIENT_ID       --org $ORG --visibility selected --repos Airclone --body "<appId>"
gh secret   set STORE_CLIENT_SECRET   --org $ORG --visibility selected --repos Airclone --body "<secret>"
gh secret   set STORE_SELLER_ID       --org $ORG --visibility selected --repos Airclone --body "<sellerId>"
gh variable set STORE_APP_ID          --org $ORG --visibility selected --repos Airclone --body "<storeId>"
```

### 2f. Store listing (Microsoft won't publish without these)
Prepare once in Partner Center: a **description** + feature list, **screenshots** (use
the screenshot rig from the README process), the **age-rating** questionnaire, a
category + support contact, and a **privacy-policy URL** — the Store REQUIRES one; host
a short page (e.g. in the wiki) and link it.

### 2g. Submit
Submission is a **manual** workflow, not a tag side-effect:
[`submit-msstore.yml`](../.github/workflows/submit-msstore.yml) →
[`tool/store_submit.py`](../tool/store_submit.py), driving the Store submission **REST API**. It
downloads the tag's `airclone.msix`, checks its identity, creates a submission cloned from the last
published one, uploads the package — and in `mode: stage` stops there, leaving an editable draft for
a human to submit in Partner Center. Store review is slow and a bad submission burns a cycle, so
deciding a build is worth one is a human call. Setup, the three modes and the pricing trap that
makes `stage` the only supported route: [`dev/msstore-ci-setup.md`](msstore-ci-setup.md).

> **The `msstore` CLI is a dead end for this product**, if you ever go looking for it. The Microsoft
> Store Developer CLI **cannot update a paid app** — proven on 2026-08-17: it authenticated, found
> the app, created a submission, and only then stopped with *"App updates are supported only for
> Free products."* Note the ordering: it CREATES a submission before discovering it cannot finish
> one, so a failed attempt can leave a pending draft blocking the next. And
> `dotnet tool install --global MSStore.CLI` no longer works either — the package was removed from
> nuget.org (absent from the flat container too, so not merely unlisted); the CLI ships as release
> binaries via Microsoft's own `microsoft/microsoft-store-apppublisher` action.

### As-built — Microsoft Store (started 2026-07-12; account verified, live product)
| Thing | Value |
|---|---|
| Account | **Company** "Gigaion, LLC" via storedeveloper.microsoft.com (FREE) |
| Business verification | **Completed** (submitted 2026-07-12, ~5 business days; Email + Employment verified automatically) — the account has since reserved products, uploaded packages and passed certification, none of which is possible while it is pending |
| D-U-N-S | `<your D-U-N-S>` |
| Publisher display name | **Gigaion, LLC** (must match `msix_config.publisher_display_name`) |
| Public Store-contact address | a **PO Box** (the registered legal address failed with `PremisesPartial`) |
| Company website / support | `https://gigaion.com` |
| Reserved product | **Airclone: Cloud File Manager** (packaged/MSIX reservation, 2026-08-08) |
| Package/Identity Name | `GigaionLLC.AircloneCloudFileManager` |
| Publisher (`CN=<GUID>`) | in repo variable `MSIX_PUBLISHER` — **never commit the GUID** |
| Reserved app names | only the full title so far; "Airclone" alone is NOT reserved, so the Start-menu tile carries the full title unless it is reserved too |
| Store ID | set — org variable `STORE_APP_ID`. Not a secret (it is in the public Store URL), and it is also the `--app-id` default in `tool/store_submit.py` |
| Seller ID | set — the value lives in org secret `STORE_SELLER_ID` |

**v0.6.0 upload (2026-08-08) — rejected 4×, all identity, all from never replacing the
2026-07-12 placeholders.** Partner Center reported only the `PublisherDisplayName`
mismatch first; fixing it revealed the other three. The shipped `airclone.msix` asset on
the v0.6.0 release still carries the placeholder identity — the submitted package was
hand-corrected with `makeappx` (§2c). CI now injects identity from repo variables, so
this cannot recur silently.

### Per-release submission runbook — MSIX (current)

Run [`submit-msstore.yml`](../.github/workflows/submit-msstore.yml) from the Actions tab against the
tag in **`mode: stage`**: it downloads that release's `airclone.msix`, checks its identity, uploads
it and leaves a draft. Then open Partner Center, confirm **Pricing and availability**, and press
**Submit for certification**. Never `mode: submit` (AGENT.md rule 10). Staging every release leaves
a draft in the Store's single pending slot, so the next stage usually also needs
`delete_pending: true` — read [`dev/msstore-ci-setup.md`](msstore-ci-setup.md) §5 before using it on
something that is already in certification.

The steps below are what a human still owns around that button: verify the artifact first, and keep
the listing, the tester notes and the capability justification true for the build being submitted.

**A. Build + VERIFY the package you are about to submit**
1. Cut a release tag `vX.Y.Z` → CI's windows job builds the portable zip, the Inno installer and the
   `--store` MSIX, bundles a SHA256-verified `rclone.exe` into all three, and Artifact-Signs the
   exes (Gigaion, LLC). The MSIX itself is **unsigned by design** — Partner Center signs it.
2. **Verify the artifact — do NOT trust the green check** (a `continue-on-error` bundle
   step once masked a real failure). Download the installer + zip: confirm the installer
   is ~66 MB (rclone bundled), `rclone.exe` is inside the zip, and
   `Get-AuthenticodeSignature` on the installer + `airclone.exe` + `rclone.exe` all return
   **Valid / CN="Gigaion, LLC"**, timestamped. Since v0.5.5 also confirm the zip carries
   **`msvcp140.dll` + `vcruntime140.dll` + `vcruntime140_1.dll`** next to `airclone.exe`
   (the app-local MSVC runtime — policy 10.2.4.1, and without it the app will not start on
   a clean machine). The build step is a hard gate, so this is a re-check, not the gate.
3. Then open the MSIX itself — as a zip, or `makeappx unpack` (§2c) — and confirm what the
   submission is about to promise a reviewer: `AppxManifest.xml` carries the reserved identity and
   not `PLACEHOLDER.*` (the workflow checks this too, but seconds beat days), `rclone.exe` and the
   three MSVC DLLs are inside the package, and **whether `librclone.dll` is there**. The in-process
   engine arrives from a `continue-on-error` artifact download and its absence is only a
   `::warning::` in the release log, so a build genuinely can ship binary-engine-only — and step D2
   names those files to the reviewer.

**D. Store listing** — paste from **`docs/store/windows/listing-en-US.md`** (Description,
What's new, Short description, Product features, Keywords, Copyright, **Applicable license
terms** [required], Developed by). Images from **`docs/store/windows/`**: box art
`store-boxart-1080.png` (1:1 required — use 1080, not the soft 2160), poster
`store-poster-720x1080.png` (2:3), screenshots `screenshots/01–05`. **Privacy-policy URL**
(required): `https://github.com/GigaionLLC/Airclone/blob/main/PRIVACY.md`.
> **PAID release** — the Store version carries the small store-listing fee; the listing
> copy must NOT claim the app is free / no-paywall (only the license-terms field states
> AGPLv3). Direct-download / self-build stays free.

**D2. Notes for certification (testers)** — paste the block below verbatim.

> ⚠️ **This field failed us once — read this before editing it.** The notes used for the
> v0.5.4 submission told the reviewer to run **`config create local local` in the command
> console**. The console *deliberately refuses* `config` (it mutates config / prints
> secrets), so the reviewer hit "Blocked: …", filed **10.1.2.10 Unusable Feature: Create a
> local remote**, and failed the submission. **Never point testers at a console command; the
> console's allowlist is in `app/lib/src/state/console/rclone_commands.dart`.** Since v0.5.5
> the refusal itself also names the in-app alternative, so the same mistake degrades to a
> hint instead of a dead end. Treat **every** sentence in this field as a promise about the build
> being submitted — the file list at the end included, which is what step A3 checks it against.

```
Airclone is a desktop GUI for rclone. No account, sign-in, subscription or cloud
credentials are needed to test it.

BROWSING WORKS WITH NO SETUP
On first launch the left sidebar already lists Home, Desktop, Documents, Downloads,
Pictures, Videos, Music and every local disk. Click any of them to exercise browsing,
previews, right-click actions, and copy/move with the transfer queue (turn on the
dual-pane button in the toolbar to drag between two folders).

TO CREATE A REMOTE WITHOUT ANY CLOUD ACCOUNT
1. In the left sidebar, click the + button next to CLOUD ("Add or encrypt a remote").
2. In the "Search storage types..." box, type: local
3. Select "local - Local Disk", enter a name such as mydisk, and save.
4. Airclone then asks two short setup questions ("nounc", and whether to edit
   advanced config). Accept the defaults - just confirm each one.
   ("alias - Alias for an existing remote" works the same way.)
The remote then appears under CLOUD in the sidebar and browses like any cloud remote.

PLEASE DO NOT CREATE REMOTES FROM THE COMMAND CONSOLE
The console intentionally refuses config, mount, serve and rc commands because they
change the rclone configuration, print stored secrets, or start servers. Remote
creation is done in the UI, as described above. The console is for read-only and
transfer commands, for example:
    ls mydisk:
    size mydisk:

NO OTHER SOFTWARE IS REQUIRED
The app package contains the full rclone engine (rclone.exe, plus librclone.dll for
in-process use when present) and the Microsoft Visual C++ runtime files (msvcp140.dll,
vcruntime140.dll, vcruntime140_1.dll). Nothing is downloaded on first run, and the app
makes no network connection of its own - it only talks to whatever cloud storage the
tester configures.
```

**D3. Restricted capability justification (MSIX only)** — Submission Options → *Restricted
capabilities* asks why the package declares `runFullTrust`. This is a REQUIRED free-text
field on every packaged submission, not an error: `msix` emits
`<rescap:Capability Name="runFullTrust"/>` for any Flutter/Win32 app because the entry
point is `Windows.FullTrustApplication`. Do NOT try to remove it — the app cannot run
without it. Paste verbatim:

```
Airclone is a Win32 desktop application (Flutter + C++) packaged for the Store with the
Desktop Bridge. Its application entry point is Windows.FullTrustApplication, which
requires runFullTrust. The capability is not used to reach anything beyond what the
app's own features need, and the app collects no user data.

1. GENERAL-PURPOSE FILE MANAGEMENT
Airclone is a file manager. It browses, copies, moves, renames and deletes files the
user chooses across their local disks, network locations and connected cloud storage,
including whole-folder transfers between two locations. This needs broad file-system
access; the brokered file-picker model cannot express "list every drive and folder,
then copy this tree to another location".

2. THE BUNDLED RCLONE ENGINE RUNS AS A CHILD PROCESS
Airclone is a graphical front end for the open-source tool rclone. The package ships
its own copy of the engine (rclone.exe, plus librclone.dll for in-process use) and
starts it as a local child process, communicating with it over an HTTP RPC endpoint
bound to 127.0.0.1 only. Creating a child process and loading these native libraries
requires full trust. No executable code is downloaded at runtime - the engine is
bundled in the package and version-pinned.

3. NATIVE MEDIA AND DOCUMENT COMPONENTS
File preview loads native libraries in-process: libmpv for video and audio, PDFium for
PDF, and the Windows shell integration used for drag-and-drop and "open in another app".

Airclone has no accounts, no telemetry and no servers of ours. All processing happens
on the user's device, and cloud credentials stay in the user's own rclone configuration
file on that machine.
```

**E. Properties / Age ratings / Availability** — Category *Utilities & tools › Backup &
manage* (+ secondary *Developer tools*); run the age-ratings questionnaire (utility, no
objectionable content); set pricing + markets. While that module is open, confirm the product is
**discoverable** and not "available but not discoverable" — it was set that way here for a while,
which keeps it out of Store search entirely (`dev/msstore-ci-setup.md` §5).

**F. Submit** — `mode: stage`, then **Submit for certification** in Partner Center (§2g), which is
also what re-derives pricing correctly. Certification then takes days.

> The EXE product had a *package validation* step here instead, runnable only once the hosted URL
> was live: **Malware + Code sign** passed while **Silent install / Add-Remove-Programs /
> Bundleware** showed **"?" (inconclusive → "manually verify") — those are NOT failures, submit
> through them.** The `/ALLUSERS` per-machine install (HKLM ARP entry) + `AppPublisher="Gigaion,
> LLC"` are what made them go green.

### Gotchas from the EXE product (2026-07-23) — kept as record

Three of these are properties of a self-hosted-installer product and cannot bite a packaged
submission; the standalone-installer rule still governs the `airclone-setup-x64.exe` we ship for
direct download.

- **EXE product only.** **GitHub release URLs 302-redirect** to a temporary signed
  `release-assets.githubusercontent.com` URL → Partner Center rejects them ("does not contain, Win32
  Package" when the asset 404s pre-build; "The package URL redirects to another URL" once it
  exists). Self-host a direct URL.
- **Still applies.** **Installer must be standalone** (bundle rclone) — a downloader stub is
  rejected and trips policy 10.2.x. Bundling had silently NEVER worked (a `continue-on-error`
  SHA256SUMS `.Content -split` parse bug); fixed v0.5.3 (file-based parse, FATAL). Store MSIX had
  never been produced as a result — now it is, and it carries the engine too.
- **EXE product only.** **Per-user installs hide the ARP entry** (HKCU) from validation (looks
  machine-wide/HKLM). Fixed v0.5.4: `PrivilegesRequiredOverridesAllowed=commandline dialog` +
  `DefaultDirName={autopf}`; the Store passes `/ALLUSERS` → per-machine HKLM entry. Direct-download
  double-click stays per-user, no UAC. **UAC during a Store install IS allowed** (only the
  installer's own UI must be silent).
- **EXE installer only.** **`AppPublisher`** must match the Store publisher / cert subject →
  `Gigaion, LLC` (was `GigaionLLC`). The packaged equivalent is
  `Package/Properties/PublisherDisplayName` (§2c).

### Certification report 2026-07-29 (v0.5.4) — FAILED "Attention needed", and the fixes

**The canonical index of every Microsoft rejection is the rejection-history table in
[`docs/store/README.md`](../docs/store/README.md)** — one row per failure, including the MSIX-era
one this file has no post-mortem for: **2026-08-10, policy 10.2.5** ("the product updates outside
the Store", raised by Settings → Check for updates → *Open release*), fixed in v0.6.2 by resolving
the install channel at runtime in `install_source.dart` so a store build makes no GitHub request at
all. That failure is why submission is a manual, human-timed workflow. What follows here is the deep
post-mortem detail that has no home elsewhere.

First real certification pass on the EXE product. Product ID `b75d35c4-…`, tested on a
Microsoft Surface Laptop. Three findings; **all three trace back to two real defects**, both
fixed in **v0.5.5**. Keep this list — the same traps re-apply to every future submission.

| Policy | What they said | Root cause | Fix (v0.5.5) |
|---|---|---|---|
| **10.2.4.1** Security – Software Dependencies | "Your product does not disclose dependencies on non-integrated software … **Undisclosed software: VC++**" | Flutter's Windows build links the **dynamic MSVC runtime** (`msvcp140.dll`, `vcruntime140*.dll`), which is NOT part of Windows. We shipped neither the DLLs nor a disclosure, so on a clean device the app can't even start. | **Bundle it app-local**: `windows/CMakeLists.txt` now installs `CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS` (via `InstallRequiredSystemLibraries`) beside `airclone.exe`; release.yml **hard-fails** if `msvcp140.dll` is missing from the Release dir. Plus a disclosure in **the first two lines** of the Store description. |
| **10.1.2.10** Functionality | "**Unusable Feature: Create a local remote.** Error message: `Blocked: "config" is not permitted in the console…`" — steps: launch → open the command console → run `config create local local`. (Observed on an ASUS ExpertBook P5405CSA, OS build 26200.8875.) | **Self-inflicted: our own "Notes for testers" told the reviewer to run `config create local local` in the console**, but the console's allowlist refuses `config` by design (it mutates config / prints secrets). The reviewer followed our instructions into a hard block whose message named no alternative — so a working feature looked broken. NOT a VC++ problem. | **Fix the notes** (see step D2 — they now walk the reviewer through **+ next to CLOUD → search "local" → "local - Local Disk"**, which is the real two-click path), and **fix the message**: `blockedMessage()` in `console/rclone_commands.dart` now names the in-app alternative for every blocked verb, reports an unknown verb as unknown instead of as a secret leak, and blames the *flag* when a safe verb carries a blocked global flag. |
| **10.2.7** Security – Product Removal | "Products need to support a method of clean removal… The files (or folders) were found in: **C:\Program Files\Airclone**" | TWO independent causes. (a) Windows does not kill children with their parent, and nothing stopped `rcd` on window close (`EngineController`'s `ref.onDispose(quit)` never runs — the ProviderScope isn't disposed, the process just ends), so an orphaned `rclone.exe` kept an open handle **on the copy inside the install dir**. (b) **Anything running from `{app}` at uninstall time** — including `airclone.exe` itself, if the reviewer simply doesn't close it first — locks its own file. | `AppLifecycleListener.onExitRequested` in `ui/app.dart` quits the engine on window close; `rclone/windows_child_job.dart` puts every rclone child in a **kill-on-close Job Object** so even a crash can't orphan one; the installer's `InitializeUninstall` **terminates every process running from `{app}`** before deleting (v0.5.7 — see the trap below), plus `[UninstallDelete] Type: filesandordirs; Name: "{app}"` and a `usPostUninstall` re-sweep. The uninstaller also offers to remove app data (never `rclone.conf`). |

**Uninstall traps, both found by actually running install→uninstall on 2026-07-30 (v0.5.7)** — Inno
traps, so they govern the installer we still ship for direct download rather than the packaged
product:
- **`CloseApplications=force` does NOT apply to uninstall.** A full `/LOG` of a silent per-machine
  uninstall shows **zero** Restart Manager activity; a running `airclone.exe` (or any `rclone.exe`
  under `{app}`) just yields `Failed to delete the file; it may be in use (32)` →
  `Failed to delete directory (145)`, and files are left in `C:\Program Files\Airclone`. Neither
  `[UninstallDelete]` nor a `DelTree` helps — a sweep still cannot delete a *locked* file. The only
  fix is to terminate the processes first, which `InitializeUninstall` now does.
- **Never kill "everything under `{app}`" unfiltered.** Inno uninstalls in two phases:
  `{app}\unins000.exe` launches a copy of itself from `%TEMP%` and waits for it. Our code runs in the
  second phase, so an unfiltered kill takes out the first-phase process that is waiting — the
  uninstall still *completes*, but the process tree returns **-1 instead of 0**, which an exit-code
  map reads as failure. Hence the `-and $_.Name -notlike 'unins*'` filter. **Assert the uninstaller
  exit code is 0**, not just that the directory is gone.

Process notes for the next round:
- **Expand every collapsed row** in the certification report before starting work, and grab
  **Supporting files → Download ZIP** — the collapsed summary line ("we found the following
  issues") carries no actionable detail, and the ZIP has the reviewer's logs/screenshots.
  This one cost real work: 10.1.2.10 looked like a symptom of the VC++ finding and was in
  fact unrelated.
- **Walk the tester notes yourself, in the shipping build, before submitting.** Every step in
  that field is a promise about behaviour; one stale instruction fails the whole submission.
- Include the **Product ID** in any message to the Microsoft representative.
- A resubmission needs a **new version**. On the EXE product that also meant a new versioned URL,
  because the binary behind a submitted Package URL must never change. On the packaged product the
  version rides inside the package: `release.yml` derives `Identity/Version` from
  `app/pubspec.yaml` (`--version "$ver.0"`), so cutting a new tag is what produces one.
- Re-test **on a machine with no Visual C++ Redistributable installed** — a dev box always has
  one, which is exactly why this shipped. Verify by artifact, not by the green check.

---

## What's already done (no account needed)
- `airclone.iss` (Inno Setup) → `airclone-setup-x64.exe` installer, on every release.
- `msix_config` + `dart run msix:create --store` → `airclone.msix`, on every release
  (non-fatal). **Unsigned by design** — Partner Center signs the package — and it carries the REAL
  Partner Center identity, injected by `release.yml` from the `MSIX_*` repo variables (§2c). Only a
  LOCAL build keeps the `PLACEHOLDER.*` identity from pubspec, and such a package is deliberately
  not submittable.
- **Every Windows artifact bundles a SHA256-verified `rclone.exe`** (zip, Inno
  installer, AND the Store MSIX): the release windows job downloads + verifies it into
  the Release dir **before signing + packaging**, so the Trusted Signing pass also
  signs `rclone.exe` and all three artifacts are self-contained (no engine download on
  first run). `RcloneEngine.bundledDesktopBinary()` finds it beside the app and uses it
  by default. Whether an in-app engine *update* is allowed is gated by
  `RcloneEngine.isStoreManaged()` (Windows `GetCurrentPackageFullName`): the packaged
  MSIX never downloads executable code (Store policy 10.2.x), while the unpackaged
  zip/installer may still update the engine in-app — a user update lands in the managed
  dir and takes precedence over the bundled one on next launch. That is also what made the
  **standard `airclone-setup-x64.exe` a valid, self-contained Store submission** for the EXE/MSI
  (unpackaged Win32) app type — superseded 2026-08-08, when the product became a packaged MSIX (§2).
