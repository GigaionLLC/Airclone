---
type: "feature"
name: "Add a Cloud (guided remote setup)"
status: "shipped"
platforms: ["desktop", "mobile"]
dependencies: ["08-core-architecture", "11-validation-standards", "15-security"]
description: "The guided flow that adds a cloud in one click — rclone's own interactive config machine, driven properly, with today's full options form kept as Advanced."
---

# ☁️ Add a Cloud

Adding storage used to mean choosing from 69 alphabetically-sorted backend names starting at
`alias`, then filling a form of up to 78 options, then answering every field you left blank a second
time as a question. It worked. Nobody would call it guided.

This is the guided path: **pick a cloud, press one button, done** — with the old form intact behind
**Advanced** for anyone who wants to set every value themselves.

**Guided and Advanced are two front ends over one driver.** There is no second implementation of
anything: both drive rclone's own interactive config state machine, the same one `rclone config`
drives. What differs is only which `parameters` the opening call carries and which questions the app
answers on the user's behalf.

---

## 1. Where it lives

| Surface | What opens |
| :--- | :--- |
| **+ Add a cloud** (sidebar, Home, browser empty state, mobile `+` sheet) | The picker: ten tiles, then everything |
| **Advanced** — on each tile, in the guided step header, and on the failure screen | The full option form, values carried across |
| **Edit remote** (a remote's ⋯ menu) | Always the Advanced form. Editing is unchanged. |

Code: [`ui/add_remote_dialog.dart`](../../app/lib/src/ui/add_remote_dialog.dart) is a thin router;
the screens are in [`ui/add_remote/`](../../app/lib/src/ui/add_remote/); the driver is
[`state/add_remote_controller.dart`](../../app/lib/src/state/add_remote_controller.dart); the
curated data is [`state/remote_setup_recipes.dart`](../../app/lib/src/state/remote_setup_recipes.dart).

## 2. Why the old flow asked everything twice

`config/create` used to be called with `opt.all: true`. That makes rclone walk **every** option as a
separate question, and only non-empty values count as pre-answered — so every field left blank in
the form came straight back as a question. Adding Google Drive asked for `client_id`,
`client_secret`, `scope` and `service_account_file` again, then "Edit advanced config?", before it
ever reached the sign-in.

Dropping `all` is most of what made this feel guided. With it off, only the backend's own post-config
runs, and **46 of rclone's 69 backends ask nothing at all**.

## 3. Ephemeral answers have to be re-sent every time

rclone strips `config_*` keys before saving (`fs.ConfigKeyEphemeralPrefix`) and rebuilds its answer
map from `parameters` on **every** call. An answer given once is therefore forgotten by the next
step and the question comes back. The driver keeps them in `AddRemoteState.sticky` and merges them
into `parameters` on every call, including the continues.

Passwords are the exact opposite and must **never** be re-sent: the opening call carries
`opt.obscure`, a continue does not, so re-sending would write a password back in the clear.

## 4. Sign-in

`config/create` blocks for as long as an OAuth sign-in takes. The in-process engine serialises every
RPC through one worker isolate, so a blocking create would freeze every other call the app makes —
which is why the whole flow runs as an **async job** (`_async: true` + `job/status`), not as a
nicety but as a requirement.

While the job runs, the app polls **`config/oauthstatus`** for the link and cancels with
**`config/oauthstop`**. Both are rclone 1.75 methods and both work identically on the spawned daemon
and the in-process library.

- **One primary button.** *Sign in with <provider>*. The alternatives sit behind *Other ways to sign
  in* and are visible before anything fails.
- **The link only works where port 53682 on this device is reachable.** That is not our choice: the
  provider always redirects to loopback. So *Show me the link* also offers the
  `ssh -L localhost:53682:localhost:53682 …` line, and *Authorize on another device* uses rclone's
  own `rclone authorize` hand-off, which needs nothing to reach this machine at all.
- **Never an embedded WebView.** Google refuses OAuth from one. `LaunchMode.inAppBrowserView` is a
  Custom Tab on Android and an `SFSafariViewController` on iOS.
- **Waiting is indefinite**, with the link on screen and Cancel available throughout. At ~45 s a
  quiet nudge offers another way without cancelling.

### 4.1 Cancelling is not just closing the dialog

Two things have to happen, and the dialog's `dispose` does them however it was closed — button,
Escape, or a tap on the barrier:

1. **Release the flow.** rclone is blocked on a listener holding port 53682. Abandon it and the next
   attempt fails to bind.
2. **Delete the half-created remote.** rclone writes `[name] type = …` as soon as a call returns at
   a question, so an abandoned create can leave a remote that exists and connects to nothing.

**Cancelling an edit deletes nothing, ever.**

`config/delete` cannot report failure — it calls rclone's `DeleteRemote`, which is `void`, and
`SaveConfig()` swallows its own error after retrying. It answers `200` whether it deleted the
remote, deleted nothing, or failed to write the file. So the driver **re-reads the config** and says
so if the remote survived.

### 4.2 Google's retiring shared sign-in

rclone 1.75 no longer opens Drive and Google Photos straight into OAuth. It asks first:

> rclone's shared Google Drive client_id is being retired and will stop working during 2026.

rclone's own default answer is to **decline**. A one-click sign-in that quietly answered yes would
enrol people in something with a stated expiry and tell them nothing, so this is a real screen with
two honest choices: set up your own sign-in (recommended, with a four-point summary and a link to
rclone's guide), or use the shared one for now with the expiry stated.

Both paste boxes are **obscured**, although rclone flags `client_secret` as neither `IsPassword` nor
`Sensitive`. Trusting that flag would print a live secret on screen, and a screenshot is a
publishing channel.

The screen is chosen by **the question rclone asks**, not by a hard-coded provider list — Google
Cloud Storage has no such warning, and if rclone adds it elsewhere the flow follows.

## 5. What the guided screens actually show

- **Recipes** for the eight backends where rclone asks nothing (`s3`, `b2`, `sftp`, `webdav`, `ftp`,
  `smb`, `azureblob`, `crypt`): a hand-written, ordered list of the fields that matter, in our
  words. A unit test checks every option name against a real `config/providers` capture, because
  inventing one would leave a field that silently writes nothing.
- **Everything else** falls back to the backend's standard options, narrowed by `provider` exactly
  as rclone narrows them — which turns s3's union-of-every-S3-service back into the handful that
  applies to the service chosen.
- **rclone's own questions** get real controls: `Examples` become a picker (this is what fixes the
  Shared Drive question, previously a bare text field you had to type a drive ID into), bools become
  Yes/No, secrets obscure.
- **The name is settled before creation**, prefilled and editable. It has to be: for an OAuth
  backend the config section exists from the moment sign-in starts, and renaming afterwards would
  mean re-running `config/create`, which re-runs the post-config and would start the sign-in over.
- **Finish** runs the existing connection test and shows what was reached. On failure it shows
  rclone's actual error with *Fix settings* (values intact) and *Keep anyway*.

## 6. The picker

Ten tiles — Google Drive, OneDrive, Dropbox, iCloud Drive, Google Photos, Amazon S3, Cloudflare R2,
Backblaze B2, SFTP, WebDAV — then "All storage types" for the rest. Wasabi, MinIO and DigitalOcean
Spaces are **search aliases** that resolve to `s3` with `provider` preset, so nobody has to know
that Wasabi is spelled "s3". Storj resolves to rclone's **native** `storj` backend rather than its
S3 gateway.

Note that two backend names contain spaces: `google photos` and `google cloud storage`.

No provider logos: names are nominative use and fine, artwork is a trademark question.

## 7. What Advanced gained

A filter box over the option list, and nothing else. s3 has 78 options and finding `endpoint` by
scrolling was the previous reality. A filter that matches only advanced options opens that section,
so results are never hidden behind a collapsed header that reads as "no matches".

## 8. Platform notes

- **Mac App Store:** `com.apple.security.network.server` (already present for the preview bridge)
  is what lets rclone listen for the OAuth redirect at all. State both uses to App Review.
- **Android:** the manifest declares `http` and `https` VIEW intents. Under Android 11+ package
  visibility an app cannot see a browser it has not declared an intent for, and without them the
  Custom Tab does not open.
- **Android TV:** nothing TV-specific is built. The chooser hides what cannot work and points at
  importing a config, which on a TV lists candidates from the shared-storage `Airclone/` folder
  because `OPEN_DOCUMENT` there is a framework stub.
- **Older rclone:** `RcloneEngine.minRcloneVersion` is 1.73.5, and on desktop the user may supply
  their own binary. Those builds have neither oauth method, so the flow falls back to reading the
  link out of the engine's own log (`AuthUrlObserver`) and cancelling with a loopback GET. Which
  path is used is decided by **calling** `config/oauthstatus`, not by comparing version strings.

## 9. Where the behaviour is written down

Everything above that sounds like an arbitrary decision is a verified fact about rclone, recorded
with its evidence in [`dev/plans/guided-remote-setup-plan.md`](../../dev/plans/guided-remote-setup-plan.md)
— §2.1 ground truth, §2.2/§2.3/§2.4 the live captures. The transcripts that drive the tests are in
`app/test/fixtures/config_flows/`, captured by `dev/plans/fd2-probe/capture_flow.dart`. **Re-run the
capture whenever the rclone pin moves**: the Google client_id change is exactly the kind of thing a
pin bump introduces, and it was found this way rather than by reading.
