# Google Play — per-release submission runbook

Companion to `dev/windows-signing-and-store.md` (Microsoft Store) — same house style. This covers the
**recurring, per-release** Play steps. The **one-time** service-account / CI setup lives in
`dev/plans/store-automation-plan.md` (§ Google Play) and is NOT repeated here.

> **Status (2026-07-23):** the Play listing is live and updated manually / via the internal track. CI
> (`release.yml` android job) is fully wired to auto-push the AAB to the **internal** track via
> `r0adkll/upload-google-play@v1`, but is **dormant** — it runs only when the repo secret
> `PLAY_SERVICE_ACCOUNT_JSON` is set, and it is **not set yet**. So every release today is a manual
> upload. Production-track promotion is manual/future (CI never touches production).

> **PAID listing** — the Play version carries the small store-listing fee; listing copy must NOT claim
> the app is free / no-paywall (see `docs/store/README.md`). Direct-download / self-build stays free.

## Facts you'll reuse

| Thing | Value |
| :--- | :--- |
| Package name | `com.gigaionllc.airclone` |
| Listing copy | `docs/store/play/listing-en-US.md` |
| Upload-ready screenshots | `docs/store/play/store-ready/` (+ `MANIFEST.md`) |
| Privacy policy (required) | `https://github.com/GigaionLLC/Airclone/blob/main/PRIVACY.md` |
| CI upload action | `r0adkll/upload-google-play@v1`, track `internal`, status `completed` |
| What's-new source | `dev/releases/<tag>.md` → distilled to `distribution/whatsnew/whatsnew-en-US` (≤480 chars) |
| versionCode | the pubspec build number (`version: X.Y.Z+N`) — must strictly increase every upload |

## Per-release runbook — do this for every Play update

**A. Pre-release verification**
1. Confirm the pubspec **build number bumped** (`+N`). Play rejects a versionCode ≤ any previously
   uploaded one — this is the single most common upload failure.
2. Cut the release tag `vX.Y.Z` → the android job builds per-ABI + universal APKs **and** the AAB
   (workflow artifact `airclone-playstore-aab`; also mirrored to the GitHub Release as
   `airclone-playstore.aab`).
3. **Verify the artifact — do not trust the green check.** Download the AAB (or a universal APK),
   install on a real device / emulator, confirm it launches and browses a remote.

**B. Prepare the what's-new text (≤500 chars/locale)**
4. CI auto-distills `dev/releases/<tag>.md` → `distribution/whatsnew/whatsnew-en-US` (strips headings/
   tables, `head -c 480`). For a **manual** upload, produce the same by hand: 2–4 plain-text lines, no
   markdown, ≤500 chars. Future locales are added as `whatsnew-<locale>` files.

**C. Update the store listing (only when copy/assets changed)**
Play Console → **Grow → Store presence → Main store listing**. Paste from
`docs/store/play/listing-en-US.md`:

| Markdown section | Play Console field | Limit / source |
| :--- | :--- | :--- |
| App name | App name | 30 chars |
| Short description | Short description | 80 chars |
| Full description | Full description | 4000 chars |
| — | App icon (Graphics) | 512×512 · `store-ready/icon-512.png` |
| — | Feature graphic (Graphics) | 1024×500 · `store-ready/feature-1024x500.png` |
| — | Phone / 7-inch / 10-inch screenshots | `store-ready/phone|tablet-7in|tablet-10in/…` |

Save. Listing edits do **not** require a new AAB and can ship independently of a release.

> **Tablet `03-thumbnails.png` is INTENTIONALLY OMITTED** (both sizes) — Google's reviewer read the
> gradient tiles as placeholder/stock images. See `docs/store/play/store-ready/MANIFEST.md`. Re-capture
> with real photos before re-adding; it is **not** an open TODO.

**D. Upload the AAB**
- **Automated (once `PLAY_SERVICE_ACCOUNT_JSON` is set):** the android job pushes the AAB to the
  **internal** track on every tag — nothing to do but watch the job.
- **Manual (today):** Play Console → **Test and release → Testing → Internal testing → Create new
  release** → upload the AAB (`airclone-playstore.aab` from the release assets) → paste the what's-new
  → **Save → Review release → Start rollout to Internal testing**.
- The **very first** release for a brand-new app MUST be a manual Play Console upload — the API cannot
  create an app's first track release.

**E. Verify the upload landed**
- The internal track shows the new versionCode; open the internal-testing opt-in link on a device and
  confirm the build installs and the what's-new text appears.
- For the API lane, the action log should report a release created on `internal`.

**F. Promote to production — a button, not a Console visit** *(since 2026-08-16)*
- CI publishes a tag to **open testing** automatically and never goes further on its own.
- Promote with **Actions → *Promote on Google Play* → Run workflow**: it promotes the version code
  already sitting in the track (Play rejects a re-upload of a code it has seen), defaults to a **10%
  staged rollout**, and widening later is the same workflow with `rollout=100`.
- It refuses to go **backwards** (red run = something is genuinely wrong) and merely **warns** when
  production already serves that build or more — so a red run always means look at me.
- Full runbook, guard semantics and worked examples: [`play-ci-setup.md`](play-ci-setup.md).
- Complete the account-level **Data safety** form and **content rating** questionnaire (required for
  production) if not already done.

## Gotchas

- **versionCode must strictly increase** — the #1 cause of a failed upload.
- **First upload is manual** — the API can't create the first release; do one Play Console upload, then
  the API lane works.
- **Service-account propagation** — a freshly granted SA can take minutes–hours; a first-run **403** on
  the API usually means "wait and re-run."
- **`changesNotSentForReview`** — if the first automated run fails with *"changes cannot be sent for
  review automatically"*, set `changesNotSentForReview: true` for ONE run, then remove it (it errors
  the opposite way once a reviewed release exists). The release.yml step keeps this commented with the
  same note.
- **Pre-release tags stay on internal** — never auto-push a `-beta.N`/`-rc` tag to production.
- **Listing vs. release** — screenshots/description update independently of the AAB; you don't need a
  new build to fix copy.

## See also

- [`dev/android-tv.md`](android-tv.md) — shipping to the Android TV form factor

- One-time CI / service-account setup: `dev/plans/store-automation-plan.md` (§ Google Play).
- Microsoft Store per-release runbook (same house style): `dev/windows-signing-and-store.md` §2.
- Index + pricing policy + pre-submission truth audit: `docs/store/README.md`.
