# Windows code signing + Microsoft Store — activation guide

**Windows code signing is LIVE** as of **v0.5.1** — every tagged release signs `airclone.exe` + the
installer + the bundled `rclone.exe` (subject "Gigaion, LLC"), gated on org vars
`AZURE_SIGNING_PROFILE=GigaionLLC-PublicCertProfile` + `WINDOWS_SIGNING_ENABLED=true` (both set). The
**Microsoft Store** is also LIVE but via the **manual EXE path** (§2) — the CI Store-submission
AUTOMATION (the `msstore`/MSIX lane) remains intentionally OFF and must stay that way (see §2).

Historical note: each CI block is guarded by `if: ${{ vars.<FLAG> == 'true' }}`, so before activation an
unset flag skipped the step entirely (its secrets were never read).

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

> **PATH DECISION (2026-07-23): we ship as an UNPACKAGED Win32 EXE app, NOT MSIX.**
> The "Airclone" app in Partner Center is the **EXE/MSI** product type — you host your
> own **signed** installer at a **direct (non-redirecting) URL** and the Store points at
> it. This reuses the `airclone-setup-x64.exe` we already build + sign and needs no MSIX
> identity plumbing. The `--store` MSIX is still built by CI (a possible future pivot /
> winget) but is NOT what we submit. §2a (account) still applies; **§§2b–2g are the
> ORIGINAL, now-SUPERSEDED MSIX plan**, kept only for reference.
>
> **Keep `STORE_PUBLISH_ENABLED` UNSET / false permanently** — the CI "Submit MSIX to Microsoft Store"
> step (`msstore publish`) targets the superseded MSIX and does NOT fit the EXE product type now used
> in Partner Center; turning it on would publish the wrong package.

### Per-release submission runbook (EXE path) — do this for every Store update

The Store requires a **versioned** URL and the binary at it **must not change** after
submission, so bump the app version each release.

**A. Build + VERIFY the signed, self-contained installer**
1. Cut a release tag `vX.Y.Z` → CI's windows job builds `airclone-setup-x64.exe`, bundles
   a SHA256-verified `rclone.exe`, and Trusted-Signs both exes (Gigaion, LLC).
2. **Verify the artifact — do NOT trust the green check** (a `continue-on-error` bundle
   step once masked a real failure). Download the installer + zip: confirm the installer
   is ~66 MB (rclone bundled), `rclone.exe` is inside the zip, and
   `Get-AuthenticodeSignature` on the installer + `airclone.exe` + `rclone.exe` all return
   **Valid / CN="Gigaion, LLC"**, timestamped.

**B. Host it at a DIRECT URL** (GitHub release URLs do NOT work — see gotchas)
3. Upload the verified installer to
   **`https://gigaion.com/releases/airclone/vX.Y.Z/airclone-setup-x64.exe`** (our web
   host). Confirm `curl -I` → **HTTP 200, no redirect**, `application/octet-stream`, and
   SHA256 matches the CI installer.

   The host is our 1Panel box, reached over SSH as `<release-ssh-host>` (LAN-only
   hostname; the account + path are in PRIVATE notes — this repo is public). The
   served tree is `<release-root>/airclone/vX.Y.Z/airclone-setup-x64.exe`, which
   1Panel maps to `https://gigaion.com/releases/airclone/...`. One version per
   directory, and **never overwrite a submitted binary** — Partner Center pins the
   bytes at the URL. Run from the machine holding the verified installer:

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

**D. Store listing** — paste from **`docs/store/windows/listing-en-US.md`** (Description,
What's new, Short description, Product features, Keywords, Copyright, **Applicable license
terms** [required], Developed by). Images from **`docs/store/windows/`**: box art
`store-boxart-1080.png` (1:1 required — use 1080, not the soft 2160), poster
`store-poster-720x1080.png` (2:3), screenshots `screenshots/01–05`. **Privacy-policy URL**
(required): `https://github.com/GigaionLLC/Airclone/blob/main/PRIVACY.md`.
> **PAID release** — the Store version carries the small store-listing fee; the listing
> copy must NOT claim the app is free / no-paywall (only the license-terms field states
> AGPLv3). Direct-download / self-build stays free.

**E. Properties / Age ratings / Availability** — Category *Utilities & tools › Backup &
manage* (+ secondary *Developer tools*); run the age-ratings questionnaire (utility, no
objectionable content); set pricing + markets.

**F. Package validation → Submit** — run validation only AFTER the URL is live.
**Malware + Code sign** pass; **Silent install / Add-Remove-Programs / Bundleware** may
show **"?" (inconclusive → "manually verify") — these are NOT failures, submit-through.**
The `/ALLUSERS` per-machine install (HKLM ARP entry) + `AppPublisher="Gigaion, LLC"` are
what make them go green. Then submit for certification (days).

### Gotchas (learned the hard way, 2026-07-23)
- **GitHub release URLs 302-redirect** to a temporary signed `release-assets.githubusercontent.com`
  URL → Partner Center rejects them ("does not contain, Win32 Package" when the asset 404s
  pre-build; "The package URL redirects to another URL" once it exists). Self-host a direct URL.
- **Installer must be standalone** (bundle rclone) — a downloader stub is rejected and trips
  policy 10.2.x. Bundling had silently NEVER worked (a `continue-on-error` SHA256SUMS
  `.Content -split` parse bug); fixed v0.5.3 (file-based parse, FATAL). Store MSIX had never
  been produced as a result — now it is.
- **Per-user installs hide the ARP entry** (HKCU) from validation (looks machine-wide/HKLM).
  Fixed v0.5.4: `PrivilegesRequiredOverridesAllowed=commandline dialog` + `DefaultDirName={autopf}`;
  the Store passes `/ALLUSERS` → per-machine HKLM entry. Direct-download double-click stays
  per-user, no UAC. **UAC during a Store install IS allowed** (only the installer's own UI
  must be silent).
- **`AppPublisher`** must match the Store publisher / cert subject → `Gigaion, LLC` (was `GigaionLLC`).

### Certification report 2026-07-29 (v0.5.4) — FAILED "Attention needed", and the fixes

First real certification pass on the EXE product. Product ID `b75d35c4-…`, tested on a
Microsoft Surface Laptop. Three findings; **all three trace back to two real defects**, both
fixed in **v0.5.5**. Keep this list — the same traps re-apply to every future submission.

| Policy | What they said | Root cause | Fix (v0.5.5) |
|---|---|---|---|
| **10.2.4.1** Security – Software Dependencies | "Your product does not disclose dependencies on non-integrated software … **Undisclosed software: VC++**" | Flutter's Windows build links the **dynamic MSVC runtime** (`msvcp140.dll`, `vcruntime140*.dll`), which is NOT part of Windows. We shipped neither the DLLs nor a disclosure, so on a clean device the app can't even start. | **Bundle it app-local**: `windows/CMakeLists.txt` now installs `CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS` (via `InstallRequiredSystemLibraries`) beside `airclone.exe`; release.yml **hard-fails** if `msvcp140.dll` is missing from the Release dir. Plus a disclosure in **the first two lines** of the Store description. |
| **10.1.2.10** Functionality | "While testing the primary functionality of the product, we found the following issues." (row was collapsed in the portal — expand it / read the **Supporting files ZIP** for the specifics) | **Almost certainly the same missing VC++ runtime** — a clean Surface Laptop with no redistributable fails to launch Flutter apps outright. Confirm against the expanded row before assuming. | Same as above. **Re-read the expanded 10.1.2.10 text on the next report** and reopen this if it describes something else. |
| **10.2.7** Security – Product Removal | "Products need to support a method of clean removal… The files (or folders) were found in: **C:\Program Files\Airclone**" | Windows does not kill children with their parent, and nothing stopped `rcd` on window close (`EngineController`'s `ref.onDispose(quit)` never runs — the ProviderScope isn't disposed, the process just ends). The orphaned `rclone.exe` kept an open handle **on the copy inside the install dir**, so the uninstaller couldn't delete it. | Three layers: `AppLifecycleListener.onExitRequested` in `ui/app.dart` quits the engine on window close; `rclone/windows_child_job.dart` puts every rclone child in a **kill-on-close Job Object** so even a crash can't orphan one; the installer adds `CloseApplications=force` + `[UninstallDelete] Type: filesandordirs; Name: "{app}"`, and offers to remove app data (never `rclone.conf`). |

Process notes for the next round:
- **Expand every collapsed row** in the certification report before starting work, and grab
  **Supporting files → Download ZIP** — the collapsed summary line ("we found the following
  issues") carries no actionable detail, and the ZIP has the reviewer's logs/screenshots.
- Include the **Product ID** in any message to the Microsoft representative.
- A resubmission needs a **new version + new versioned URL** (step A→B): the binary behind a
  submitted Package URL must never change.
- Re-test **on a machine with no Visual C++ Redistributable installed** — a dev box always has
  one, which is exactly why this shipped. Verify by artifact, not by the green check.

---

## 2-MSIX (SUPERSEDED — original plan, kept for reference only)

> We did NOT take this path (see the PATH DECISION above). The `--store` MSIX is still
> built by CI, so if we ever pivot to a packaged Store app or winget, §§2c–2g here are the
> starting point. **§2a below (account registration) is STILL the real, as-built account.**

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
- **Every Windows artifact bundles a SHA256-verified `rclone.exe`** (zip, Inno
  installer, AND the Store MSIX): the release windows job downloads + verifies it into
  the Release dir **before signing + packaging**, so the Trusted Signing pass also
  signs `rclone.exe` and all three artifacts are self-contained (no engine download on
  first run). `RcloneEngine.bundledDesktopBinary()` finds it beside the app and uses it
  by default. Whether an in-app engine *update* is allowed is gated by
  `RcloneEngine.isStoreManaged()` (Windows `GetCurrentPackageFullName`): the packaged
  MSIX never downloads executable code (Store policy 10.2.x), while the unpackaged
  zip/installer may still update the engine in-app — a user update lands in the managed
  dir and takes precedence over the bundled one on next launch. This is why the
  **standard `airclone-setup-x64.exe` is a valid, self-contained Store submission** for
  the EXE/MSI (unpackaged Win32) app type — no separate "store installer" needed.
