# Google Play — per-release submission runbook

Companion to `dev/windows-signing-and-store.md` (Microsoft Store) — same house style. This covers the
**recurring, per-release** Play steps. The **one-time** service-account / CI setup lives in
[`dev/play-ci-setup.md`](play-ci-setup.md) and is NOT repeated here.

> **Status (2026-09-06): CI is LIVE.** Every `v*` tag builds the AAB, uploads it to **open testing**
> (the API's `beta` track) via `r0adkll/upload-google-play@v1`, and then asks Play to confirm the
> version code landed — a failed confirmation fails the release. Production promotion is the manual
> `promote-play.yml`; CI never ships to production on its own. A manual Console upload is now only a
> fallback for when the credential is missing or rotated. For the credential and CI state,
> [`dev/play-ci-setup.md`](play-ci-setup.md) is the copy that wins.

> **PAID listing** — the Play version carries the small store-listing fee; listing copy must NOT claim
> the app is free / no-paywall (see `docs/store/README.md`). Direct-download / self-build stays free.

## Facts you'll reuse

| Thing | Value |
| :--- | :--- |
| Package name | `com.gigaionllc.airclone` |
| Listing copy | `docs/store/play/listing-en-US.md` |
| Upload-ready screenshots | `docs/store/play/store-ready/` (+ `MANIFEST.md`) |
| Privacy policy (required) | `https://github.com/GigaionLLC/Airclone/blob/main/PRIVACY.md` |
| CI upload action | `r0adkll/upload-google-play@v1` → `tracks: beta` (the Console's **Open testing**), status `completed`. `tracks` is **plural**; the singular `track:` is deprecated and would kill the lane silently on a future action bump |
| What's-new source | `docs/store/store-release-notes.txt` — one generic line, copied verbatim, every release. CI fails the job above **500 bytes** (not chars). Why, and when to break it: `docs/store/store-release-notes.md` |
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

**B. Prepare the what's-new text — nothing to do**
4. The same generic line ships every release: CI copies `docs/store/store-release-notes.txt` verbatim
   to `distribution/whatsnew/whatsnew-en-US` and fails the job above **500 bytes**. The detailed notes
   live on the GitHub release, which is where anyone who wants them looks. Only edit that file when a
   release changes something a user must act on — then put it back afterwards
   (`docs/store/store-release-notes.md`, "When to break the rule"). CI reads the file from the tagged
   tree, so an edit has to land *before* the tag is cut. Future locales are added as
   `whatsnew-<locale>` files.

**C. Update the store listing (only when copy/assets changed)**

*Images ship from the repo.* **Actions → *Play Store listing images* → Run workflow**: pick the image
`type`, point `dir` at the folder below, leave `replace=true`, run `mode=report` first and then
`mode=apply`. `--replace` is load-bearing — Play **appends** an uploaded image to a set rather than
overwriting it, so a second run without it leaves duplicates in the listing. The workflow writes
images only: it cannot touch text, attach a build, or publish.

*Text is still Console-only.* Play Console → **Grow → Store presence → Main store listing**. Paste
from `docs/store/play/listing-en-US.md`. The table below is both the field map and the fallback for
uploading graphics by hand:

| Markdown section | Play Console field | Limit / source |
| :--- | :--- | :--- |
| App name | App name | 30 chars |
| Short description | Short description | 80 chars |
| Full description | Full description | 4000 chars |
| — | App icon (Graphics) | 512×512 · `store-ready/icon-512.png` · workflow `type=icon` |
| — | Feature graphic (Graphics) | 1024×500 · `store-ready/feature-1024x500.png` · `type=featureGraphic` |
| — | Phone / 7-inch / 10-inch screenshots | `store-ready/phone` · `tablet-7in` · `tablet-10in` — workflow `type=phoneScreenshots`, `sevenInchScreenshots`, `tenInchScreenshots` |

> **`--dir` is a whole directory, not a file.** `tool/play_images.py` uploads *every* `.png`/`.jpg`
> in the directory into the one named slot; there is no per-file option. `icon-512.png` and
> `feature-1024x500.png` sit in the same `store-ready/` folder, so pointing `type=icon` at it pushes
> the feature graphic into the icon slot as well. Give those two their own directory, or upload them
> in the Console. Nothing catches this — neither has a size rule in the script.

Android TV has two more image types of its own — see [`dev/android-tv.md`](android-tv.md).

Save. Listing edits do **not** require a new AAB and can ship independently of a release.

> The rejection that shaped this set is **fixed, not outstanding**: a reviewer read the synthetic
> gradient tiles as placeholder/stock images, so the shots were re-taken with real CC0 photos
> (`docs/store/play/DEMO-MEDIA-PROVENANCE.md`) and `03-gallery.png` now ships in both tablet sizes.
> The one slot still deliberately empty is a video-playback shot — the emulator cannot render video.
> `store-ready/MANIFEST.md` is the copy that wins for which file fills which slot.

**D. Upload the AAB**
- **Automated (the normal path):** the android job uploads the AAB to **Open testing** on every tag
  and then verifies it landed — nothing to do but watch the job.
- **Manual (fallback only — the secret is absent or mid-rotation):** Play Console → **Test and
  release → Testing → Open testing → Create new release** → upload `airclone-playstore.aab` from the
  GitHub release assets → paste the what's-new → **Save → Review release → Start rollout to Open
  testing**.
- The **very first** release for a brand-new app MUST be a manual Play Console upload — the API cannot
  create an app's first track release.

**E. Verify the upload landed**
- CI already asks Play. The `Verify the build really landed in open testing` step runs
  `tool/play_tracks.py --expect beta=<pubspec build number>` and **fails the release** if Play does
  not hold that code, so a green android job is real evidence rather than a green check.
- To read every track by hand at any time:
  `GOOGLE_APPLICATION_CREDENTIALS=key.json python tool/play_tracks.py --package com.gigaionllc.airclone`.
- Delivery-path check, still worth doing on a release that changes install behaviour: open the
  **open testing** opt-in link on a device and confirm the build installs and the what's-new text
  appears. The API assertion proves Play accepted the bundle, not that Play served it.

**F. Promote to production — a button, not a Console visit** *(since 2026-08-16)*
- CI publishes a tag to **open testing** automatically and never goes further on its own.
- Promote with **Actions → *Promote on Google Play* → Run workflow**: it promotes the version code
  already sitting in the track (Play rejects a re-upload of a code it has seen), defaults to a **10%
  staged rollout**, and widening later is the same workflow with `rollout=100`.
- **`dry_run` defaults to `true`**, so a run left on its defaults prints the plan and changes
  nothing; set `dry_run=false` to actually ship. The order that has never gone wrong here: dry run →
  `rollout=10, dry_run=false` → widen with `rollout=100, dry_run=false`.
- It refuses to go **backwards** (red run = something is genuinely wrong) and merely **warns** when
  production already serves that build or more — so a red run always means look at me.
- Full runbook, guard semantics and worked examples: [`play-ci-setup.md`](play-ci-setup.md).
- Complete the account-level **Data safety** form and **content rating** questionnaire (required for
  production) if not already done.

**G. Read what users are actually saying** *(since 2026-09-09)*
- **Actions → *Store feedback*** (`.github/workflows/store-feedback.yml`) also runs **daily at 08:00
  UTC** on its own. Two jobs, both writing into the run summary: *What Play is serving* — every
  track and the version code it holds ([`tool/play_tracks.py`](../tool/play_tracks.py)) — and
  *Google Play reviews* ([`tool/play_reviews.py`](../tool/play_reviews.py)).
- It is scheduled rather than left as a button because **Play serves roughly the last seven days of
  reviews** on this endpoint. A window nobody fetched in time is a window nobody can ever read back.
- It never goes red on review content unless you pass `fail_at_or_below` by hand: a one-star review
  is not a broken pipeline, and a workflow that goes red for something you cannot fix by pushing is
  a workflow people learn to ignore.
- Worth opening deliberately after a release that changes install or playback behaviour. The Google
  TV bugs fixed in v0.8 reached us out of band, from a user who had no other route in.

## Android developer verification — both signing keys must be registered

Google's requirement (announced 2026-07-15): every package distributed on Android must be registered
by **2026-09-30**, together with **every key it is signed with — including keys used outside Play**.
Play auto-registered our package on 2026-07-10, but auto-registration only covers the key *Play
itself* distributes with. Airclone ships through **two** certificates:

| Certificate | SHA-256 | Signs |
| :--- | :--- | :--- |
| Play **app signing** key (Google-managed) | `C7:66:4C:7D:34:1B:6A:6A:79:F5:02:02:59:4C:39:3D:CB:12:BB:5B:65:DE:4A:9D:27:53:8E:7E:65:BE:E5:2E` | what a **Play** install carries — Play re-signs the AAB server-side |
| **Upload** key = the release keystore | `FA:32:10:49:80:AF:70:95:A7:D7:55:8B:D9:F7:F7:D5:5A:BA:04:A2:75:A9:5E:B7:05:71:EB:08:02:33:17:ED` | the AAB we upload **and every APK on the GitHub release** |

The second is the easy miss. `release.yml` signs the per-ABI and universal APKs with the upload key, so
a **sideloaded** install carries a certificate Play never sees — exactly the "additional keys for your
Play apps that you use to sign them outside of Play" the Console banner asks for. Registered by hand on
**2026-09-09**: Play Console → **Android developer verification** → the package row → **Add key**, paste
the SHA-256. Fingerprint only — no PEM upload. A newly added key sits at **In review** before it flips
to **Verified**.

Reading the fingerprints back, when you need to check rather than trust:

- Upload key, from the keystore: `keytool -list -v -keystore <keystore> -alias <alias>` (credentials in
  `dev/secrets/`, never in the repo).
- What a shipped APK **actually** carries: `apksigner verify --print-certs <apk>` — the honest check,
  since it reads the artifact users install rather than the key we think CI used.
- Both, from Play: Console → the app → **Protected with Play** → **App signing**. The page shows the
  upload certificate directly; the app-signing SHA-256 is in the Digital Asset Links snippet at the
  bottom. (The old **Test and release → App integrity** entry now just redirects here.)

Enforcement is staged — participating stores on certified devices in Brazil, Indonesia, Singapore and
Thailand from 2026-09-30, global from 2027 — but the **registration** deadline is the same date for
everyone, so there is no version of this worth deferring.

**If the upload key is ever reset** (Console offers "Request upload key reset"), the replacement
fingerprint has to be registered here too, or GitHub-installed builds silently fall out of
verification. Same for any future channel that re-signs our APKs, e.g. an F-Droid build.

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
- **Every tag goes to open testing, pre-release or not.** All **three** Play steps — prepare notes,
  upload, and the `play_tracks.py --expect` verification — gate only on `refs/tags/*` plus the
  secret; `tracks: beta` is hardcoded and there is **no `-beta.N`/`-rc` exclusion anywhere on the
  Play path** (pre-release detection exists only for the GitHub Release flag). Open testing is
  **public** — anyone with the opt-in link gets it. If a pre-release must stay private, gate all
  three on the same `*alpha*|*beta*|*rc*` test `release.yml` already uses for the Release
  pre-release flag — not a `-` match, which misses a tag like `v1.0.0.rc1` — or route it to
  `internal` first. Gating only the upload leaves the verify step failing on a build it cannot find.
  Production is never automatic either way.
- **Listing vs. release** — screenshots/description update independently of the AAB; you don't need a
  new build to fix copy.

## See also

- [`dev/android-tv.md`](android-tv.md) — shipping to the Android TV form factor
- Daily Play monitoring — reviews and what each track is serving:
  [`.github/workflows/store-feedback.yml`](../.github/workflows/store-feedback.yml) (step G above).
- One-time CI / service-account setup, from nothing: [`dev/play-ci-setup.md`](play-ci-setup.md).
  (`dev/plans/store-automation-plan.md` is the original 2026-07-09 research, superseded — do not
  follow its track or release-notes claims.)
- Microsoft Store per-release runbook (same house style): `dev/windows-signing-and-store.md` §2.
- Index + pricing policy + pre-submission truth audit: `docs/store/README.md`.
