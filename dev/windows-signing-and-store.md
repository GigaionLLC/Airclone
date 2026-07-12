# Windows code signing + Microsoft Store — activation guide

Both are **pre-wired in `release.yml` but OFF by default**. Nothing runs until you
set the enable **variable** and add the **secrets** below — so releases keep
working unsigned until you're ready. Flip each on independently.

The gating: each block is guarded by `if: ${{ vars.<FLAG> == 'true' }}`, so an
unset flag skips the step entirely (its secrets are never read).

---

## As-built record — GigaionLLC / Airclone (started 2026-07-12)

Concrete values for THIS setup (none are secret — the client secret lives only in
the GitHub `AZURE_CLIENT_SECRET` secret, nowhere else):

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

**Still blocked on Microsoft:** submit **Identity validation** (portal) → after
approval create a **Certificate profile** (Public Trust) → set variable
`AZURE_SIGNING_PROFILE=<profile name>` → set `WINDOWS_SIGNING_ENABLED=true` → cut a
release and confirm the installer is signed.

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

# --- 5. AFTER identity validation is approved + a certificate profile exists:
# gh variable set AZURE_SIGNING_PROFILE   --body "<profile name>" --repo $REPO
# gh variable set WINDOWS_SIGNING_ENABLED --body "true"           --repo $REPO
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
2. In that account, create a **Certificate Profile** of type **Public Trust**.
   This triggers **identity validation** (org: D-U-N-S / business docs; individual:
   ID). Note the **profile name** and the **account name**.
3. Create an **Entra ID (Azure AD) app registration** with a **client secret**.
   Grant it the **"Artifact Signing Certificate Profile Signer"** role on the
   signing account (Access control (IAM) → Add role assignment). (The service is
   branded "Artifact Signing"; some older docs say "Trusted Signing …".)
   Note the **tenant id**, **client id**, **client secret**.

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

## 2. Microsoft Store — automated MSIX submission ($19 one-time dev account)

Store apps are signed **by Microsoft**, so Store users get no warning and you need
no signing cert for this path. CI builds `airclone.msix` with `--store` (unsigned,
Store-ready) and submits it.

### One-time setup
1. **Partner Center** account ($19 individual / $99 company). Under **Apps and
   games**, **reserve the app name** ("Airclone"). Open the app → **Product
   management → Product identity** and copy:
   - **Package/Identity Name** (e.g. `1234GigaionLLC.Airclone`)
   - **Publisher** (`CN=<GUID>`)
   - **Publisher display name**
   - the **Store ID** (the app/product id)
2. **Update `app/pubspec.yaml` → `msix_config`** with those three identity values
   (they're currently placeholders `GigaionLLC.Airclone` / `CN=GigaionLLC`). A
   `--store` package only submits once its identity matches the reserved app.
3. Create an **Entra ID app** (can reuse the signing one) and **associate it in
   Partner Center**: Account settings → **User management → Azure AD applications**
   → add it with the **Manager** role (grants Submission-API access). Note the
   tenant id, client id, client secret, and your **Seller ID** (Account settings →
   Legal info / Developer).

### GitHub config
Secrets:
- `STORE_TENANT_ID`
- `STORE_CLIENT_ID`
- `STORE_CLIENT_SECRET`
- `STORE_SELLER_ID`

Variables:
- `STORE_APP_ID` = the Store ID from step 1
- `STORE_PUBLISH_ENABLED` = `true`   ← the master switch (submission runs only on
  tag pushes; it's `continue-on-error` so a Store hiccup never fails the release)

The CI step uses the **Microsoft Store Developer CLI** (`msstore`):
`dotnet tool install --global MSStore.CLI`, then `msstore reconfigure …` +
`msstore publish airclone.msix`. Verify the exact `msstore publish` flags against
`msstore --help` at activation — the CLI evolves. Consider leaving
`STORE_PUBLISH_ENABLED` off and running the submission manually per-release if you
don't want every tag auto-submitted (Store review is slow).

---

## What's already done (no account needed)
- `airclone.iss` (Inno Setup) → `airclone-setup-x64.exe` installer, on every release.
- `msix_config` + `dart run msix:create --store` → `airclone.msix`, on every release
  (non-fatal). Ships unsigned/placeholder-identity until §2 above is completed.
