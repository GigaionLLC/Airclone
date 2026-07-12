# Windows code signing + Microsoft Store — activation guide

Both are **pre-wired in `release.yml` but OFF by default**. Nothing runs until you
set the enable **variable** and add the **secrets** below — so releases keep
working unsigned until you're ready. Flip each on independently.

The gating: each block is guarded by `if: ${{ vars.<FLAG> == 'true' }}`, so an
unset flag skips the step entirely (its secrets are never read).

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
| Client secret | 2-year, minted 2026-07-12 → rotate before **2028-07** |

**Provisioned + wired (done):** app registration + SP, role at the account scope,
client secret, and — at the **GitHub org (GigaionLLC), visibility = Selected
repositories → Airclone** — secrets `AZURE_TENANT_ID` / `AZURE_CLIENT_ID` /
`AZURE_CLIENT_SECRET` and variables `AZURE_SIGNING_ACCOUNT` / `AZURE_SIGNING_ENDPOINT`.
Org-level so every GigaionLLC product shares one signing setup; to add a product,
add its repo to each secret/variable's selected list (see runbook). No repo-level
signing secrets remain on Airclone.

**Identity validation (portal, manual) — SUBMITTED 2026-07-12, status In Progress:**
- validation id `<identity validation id>`, org **"Gigaion, LLC"**, type
  **Public**, US.
- Needed the **`Artifact Signing Identity Verifier`** role on your USER account,
  assigned at the account scope — SEPARATE from the app's Signer role.
- Portal path: the Artifact/Trusted Signing account → **Identity validation** → **New
  identity** → **Organization** → **Public** → fill legal name / address / (D-U-N-S if
  prompted) → **Submit** → status goes **In Progress** → wait for Microsoft (days). A
  **Public Trust** certificate profile requires this **Completed/Approved** first.

**Still blocked on Microsoft (after the validation is Approved):** create a
**Certificate profile** of type **Public Trust** → note its name → do runbook **step 5**
(flip the two ORG vars) → cut a release and confirm the exe + installer are signed. (A
**Public Trust Test** profile needs no validation and can smoke-test the CI signing
early, but its signatures are NOT publicly trusted — plumbing check only.)

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

# --- 5. AFTER identity validation is approved + a certificate profile exists,
# flip the two ORG-level variables on (same visibility=selected -> Airclone as the rest):
# gh variable set AZURE_SIGNING_PROFILE   --org $ORG --visibility selected --repos Airclone --body "<profile name>"
# gh variable set WINDOWS_SIGNING_ENABLED --org $ORG --visibility selected --repos Airclone --body "true"
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

## 2. Microsoft Store — company account + automated MSIX submission (FREE via the new flow)

Store apps are signed **by Microsoft**, so Store users get no warning and this path
needs no signing cert of ours. It is **independent of §1** — NOT blocked on the Azure
identity validation, so it proceeds in parallel. CI already builds `airclone.msix`
with `--store` (unsigned, Store-ready) **and bundles a SHA256-verified `rclone.exe`
inside it** (commit `dda4c7c`), so the packaged app never downloads executable code at
runtime — clear of Store policy 10.2.x.

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
   green. **SUBMITTED 2026-07-12 — awaiting review.**

### 2b. Reserve the app + copy its identity (after the dev account is verified)
In the account (Partner Center / Store Developer) → reserve the app name **"Airclone"**,
then open the app → **Product management → Product identity** and copy:
- **Package/Identity Name** (e.g. `1234Gigaion.Airclone`)
- **Publisher** (`CN=<GUID>`)
- **Publisher display name** (e.g. `Gigaion, LLC`)
- the **Store ID** (the product id)

### 2c. Put the real identity in the package
Edit `app/pubspec.yaml` → `msix_config` (today placeholders
`identity_name: GigaionLLC.Airclone` / `publisher: CN=GigaionLLC`):
- `identity_name`          = the reserved **Package/Identity Name**
- `publisher`              = the assigned **Publisher** (`CN=<GUID>`)
- `publisher_display_name` = must match the Store **publisher display name**

A `--store` package only uploads once its identity matches the reserved app.

### 2d. API credentials for automated submission
1. Create (or reuse the §1 signing) **Entra app registration**; note tenant id, client
   id, and a client secret.
2. Partner Center → **Account settings → User management → Azure AD applications** →
   add that app with the **Manager** role (grants Submission-API access).
3. Note your **Seller ID** (Account settings → Legal info / Developer).

### 2e. GitHub config — ORG-level (GigaionLLC, visibility = Selected → Airclone)
Secrets `STORE_TENANT_ID` / `STORE_CLIENT_ID` / `STORE_CLIENT_SECRET` /
`STORE_SELLER_ID`; variables `STORE_APP_ID` (= the Store ID) and
`STORE_PUBLISH_ENABLED` (= `true`, the master switch — submission runs only on tag
pushes and is `continue-on-error`, so a Store hiccup never fails a release).

```powershell
$ORG="GigaionLLC"
gh secret   set STORE_TENANT_ID       --org $ORG --visibility selected --repos Airclone --body "<tenant>"
gh secret   set STORE_CLIENT_ID       --org $ORG --visibility selected --repos Airclone --body "<appId>"
gh secret   set STORE_CLIENT_SECRET   --org $ORG --visibility selected --repos Airclone --body "<secret>"
gh secret   set STORE_SELLER_ID       --org $ORG --visibility selected --repos Airclone --body "<sellerId>"
gh variable set STORE_APP_ID          --org $ORG --visibility selected --repos Airclone --body "<storeId>"
gh variable set STORE_PUBLISH_ENABLED --org $ORG --visibility selected --repos Airclone --body "true"
```

### 2f. Store listing (Microsoft won't publish without these)
Prepare once in Partner Center: a **description** + feature list, **screenshots** (use
the screenshot rig from the README process), the **age-rating** questionnaire, a
category + support contact, and a **privacy-policy URL** — the Store REQUIRES one; host
a short page (e.g. in the wiki) and link it.

### 2g. Submit
CI uses the **Microsoft Store Developer CLI** (`msstore`):
`dotnet tool install --global MSStore.CLI` → `msstore reconfigure …` → `msstore publish
airclone.msix --appId <STORE_APP_ID>`. Verify exact flags against `msstore --help` at
activation (the CLI evolves). **Recommendation:** keep `STORE_PUBLISH_ENABLED` OFF and
run the FIRST submission manually (Store review is slow and the listing must be
complete); turn it on later for tag-triggered updates.

### As-built — Microsoft Store (started 2026-07-12; verification pending)
| Thing | Value |
|---|---|
| Account | **Company** "Gigaion, LLC" via storedeveloper.microsoft.com (FREE) |
| Business verification | **Under review** (submitted 2026-07-12, ~5 business days); Email + Employment already verified |
| D-U-N-S | `<your D-U-N-S>` |
| Publisher display name | **Gigaion, LLC** (must match `msix_config.publisher_display_name`) |
| Public Store-contact address | a **PO Box** (the registered legal address failed with `PremisesPartial`) |
| Company website / support | `https://gigaion.com` |
| Package/Identity Name | _tbd — after verification + app reservation_ |
| Publisher (`CN=<GUID>`) | _tbd_ |
| Store ID | _tbd_ |
| Seller ID | _tbd_ |

---

## What's already done (no account needed)
- `airclone.iss` (Inno Setup) → `airclone-setup-x64.exe` installer, on every release.
- `msix_config` + `dart run msix:create --store` → `airclone.msix`, on every release
  (non-fatal). Ships unsigned/placeholder-identity until §2 above is completed.
- The Store MSIX **bundles a SHA256-verified `rclone.exe`** (commit `dda4c7c`): the
  release windows job downloads + verifies it into the Release dir AFTER the zip +
  installer are built (so ONLY the MSIX carries it), and the "Build MSIX" step refuses
  to package an engine-less one. `RcloneEngine.bundledDesktopBinary()` finds it beside
  the app, and `downloadLatest()` refuses on a bundled build — so the Store flavour
  never downloads executable code at runtime. Portable zip / installer are unchanged
  (download-on-first-run + in-app engine update).
