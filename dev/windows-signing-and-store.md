# Windows code signing + Microsoft Store — activation guide

Both are **pre-wired in `release.yml` but OFF by default**. Nothing runs until you
set the enable **variable** and add the **secrets** below — so releases keep
working unsigned until you're ready. Flip each on independently.

The gating: each block is guarded by `if: ${{ vars.<FLAG> == 'true' }}`, so an
unset flag skips the step entirely (its secrets are never read).

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
   Grant it the **"Trusted Signing Certificate Profile Signer"** role on the
   Trusted Signing account (Access control (IAM) → Add role assignment).
   Note the **tenant id**, **client id**, **client secret**.

### GitHub config (repo → Settings → Secrets and variables → Actions)
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
