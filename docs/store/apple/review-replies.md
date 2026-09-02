# App Review replies that worked

The exact text sent to App Review for the 0.6.8 rejections, kept because the
wording took longer to get right than the fix did. Reuse verbatim where the
issue repeats; the reasoning behind each choice is under the text.

Both were sent through **Reply to App Review** on the submission page, and both
needed **Update Review** on the version page afterwards before *Resubmit to App
Review* would enable — see `dev/apple-appstore-and-macos.md` §3.

Apple's reply box caps at **4,000 BYTES**, not characters. Em-dashes are 3 bytes
each in UTF-8, so a draft that counts as 3,996 characters can still be rejected.
Measure with `wc -c`.

---

## macOS — guideline 2.4.5, `com.apple.security.network.server`

**Outcome: accepted.** The version passed review on resubmission and is live.

> The com.apple.security.network.server entitlement is required, and is used only
> for an internal loopback bridge inside the app. No part of Airclone listens for
> connections from other devices.
>
> How it is used:
>
> Airclone embeds the rclone engine as an in-process library (librclone) in the
> Mac App Store build. That library exposes a JSON-RPC interface only - it has no
> way to hand raw file bytes to the app. To display an image preview, generate a
> thumbnail, play a video or audio file, or render a PDF, the app therefore runs
> a small HTTP endpoint inside its own process and streams the bytes to its own
> player and image widgets.
>
> That endpoint binds to InternetAddress.loopbackIPv4 on an ephemeral port
> (HttpServer.bind(InternetAddress.loopbackIPv4, 0)). It is bound to 127.0.0.1
> only, never to 0.0.0.0 or any external interface, so it is not reachable from
> another machine. Each request additionally carries a per-session Authorization
> token generated at launch. The endpoint's only client is Airclone itself.
>
> App Sandbox requires com.apple.security.network.server to call listen() at all,
> including on loopback. Without it, this build has no image previews, no
> thumbnails, no video or audio playback, and no PDF viewer - the entitlement is
> what makes those features work, which is why the automated analysis did not
> find an outward-facing server to match it against.
>
> For completeness: rclone's own "serve" feature, which does expose a real
> network server, is deliberately disabled in the Mac App Store build and cannot
> be reached by the user. The entitlement exists solely for the internal preview
> bridge described above.
>
> Source reference: app/lib/src/rclone/librclone_object_server.dart in our
> repository, which is public at https://github.com/GigaionLLC/Airclone

### Why it is worded that way

- **Denies the scary reading in sentence one.** The scanner's implicit worry is
  a listening server; say it does not exist before explaining anything.
- **Explains why the scan was not wrong.** There genuinely is no outward-facing
  server for it to match. Agreeing with the tool costs nothing and reads as
  competence rather than argument.
- **Names the concrete binding call.** `loopbackIPv4`, ephemeral port, `0.0.0.0`
  explicitly ruled out. A reviewer can check that claim against the cited file.
- **Volunteers the adjacent risk.** rclone HAS a real server feature; saying it
  is disabled pre-empts the obvious next question.
- **DO NOT remove the entitlement to silence the scan.** That deletes previews,
  thumbnails, media playback and the PDF viewer from the MAS build. The
  temptation is real because removing it makes the warning stop.

---

## iOS — guideline 2.1, information needed (new app submission)

**Outcome: pending at the time of writing.** Submitted with a SIMULATOR
recording, because no physical iOS hardware was available.

The full text is the Notes block of `listing-ios-en-US.md` plus the section 1
preamble below. Everything except item 1 is already in App Review Information,
so a future reply can point there instead of restating it.

> 1. SCREEN RECORDING
> A screen recording is attached. It was captured in the iOS Simulator via Xcode
> rather than on physical hardware, which is not available to us at this time. It
> shows the same build you have (0.6.8, build 118) and the complete user flow
> from launch. We are glad to provide further captures or answer any question
> about behaviour we could not show this way.
>
> It begins at launch and shows the Locations list, "On My Device", browsing and
> previewing files, a copy/move transfer with progress, and the transfers view.
>
> There are no gated flows: no account registration, login or deletion, no
> in-app purchase or subscription, no user-generated content. The only permission
> prompts are camera (solely to scan a configuration QR the user generates
> themselves) and Face ID (solely to unlock an encrypted rclone config on the
> device); neither is required to use the app.

### Why it is worded that way

- **The limitation is sentence two, not buried.** A reviewer who discovers
  mid-video that it is a simulator reacts very differently from one told up
  front. It also cannot be read as an attempt to pass it off.
- **"not available to us at this time"** — accurate, ordinary for a small
  developer, and it does not invite the follow-up that "we do not own an iPhone"
  would.
- **"the same build you have"** — the reviewer already has the real binary and
  reviews on real hardware. The video is a navigation aid, not the evidence.
- **The gated-flows paragraph is the actual argument.** Apple wants recordings
  mainly to see what they cannot reach themselves: logins, paywalls, UGC
  reporting. This app has none, so nothing is hidden from them. Stated as fact,
  not as a plea.
- **No apology and no excuses.** One sentence on the limit, then an offer to
  supply more.

Apple asked for the recording to be from a physical device. This answer may not
satisfy that. If it comes back rejected, the fix is ten minutes with any
borrowed iPhone, or a real-device cloud farm (BrowserStack App Live, AWS Device
Farm) — both are physical hardware and both can record.
