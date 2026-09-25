---
type: "feature"
name: "Media Playback (in-app player)"
status: "stable"
platforms: ["desktop", "mobile", "tv"]
dependencies: ["08-core-architecture", "06-design-system"]
description: "Playing audio and video straight out of a remote — the pointer player, the television player, and the rules they share."
---

# ▶️ Media Playback

Airclone plays media **out of the remote**, without downloading it first: the engine serves the
object over an authenticated local URL and libmpv (via `media_kit`) reads it. That is why the player
handles formats a browser will not, and why every surface below shares one failure path — a cloud
object arriving through a local engine has many more ways to stall than a local file does.

Three surfaces, one player:

| Surface | Where | What it is |
| :--- | :--- | :--- |
| **Video frame** | preview dialog, Quick Look | media_kit's own control bars, which adapt to touch or pointer |
| **Audio card** | preview dialog, Quick Look | art, previous / play-pause / next, repeat, and a seek slider |
| **Television** | Quick Look on a TV | our own D-pad overlay and a 10-foot now-playing screen |

## What a remote can do

A television is not a small desktop, and it was the form factor that exposed how much of this player
assumed a pointer. Video controls that only appear on a tap, an audio card built at 480px, a seek bar
you drag: none of those exist for someone holding a remote.

So on a TV the player is driven by **keys**, and the full table lives in
[`dev/android-tv.md`](../../dev/android-tv.md) § *Playback with a remote*. In short:

- **OK** is play/pause, and summons the controls.
- **LEFT / RIGHT** seek, accelerating from 10s to 60s as you hold a run of presses; once focus is in
  the control row they move between buttons instead.
- **The remote's own ⏯ ⏪ ⏩ ⏭ ⏮ keys work**, wherever focus happens to be.
- **⏪ / ⏩ — the remote keys or the on-screen buttons — jump 30s on a tap and keep scanning while
  held**, accelerating, until released; the seek lands once, on release.
- **BACK** hides the controls, then leaves.

The controls hide themselves while a film plays and come back on any key — **except while paused**,
because a paused film with no controls cannot be resumed.

Those transport-key bindings are honoured on **every** platform, not only a television: a keyboard's
media keys and a Bluetooth remote paired to a phone are the same keys.

## Previous and next walk their own kind

A folder of songs almost always holds a `cover.jpg`, and often a `.cue` as well. On a phone, a swipe
landing on the cover is a shrug — swipe again. On a television those two keys are the *only* way
through the folder, so "next track" landing on an image is how an album stops being playable.

Previous/next from a media player therefore skips to the next file of the **same kind** — audio to
audio, video to video. Everything else still moves exactly one page, which is what a swipe and the
arrow keys have always done.

At either end of the list the dead control stays **visible but disabled**, never hidden: a row that
changes shape as you move through an album is harder to aim at with a D-pad than one that stays put.

## Repeat

A single persisted toggle, exposed on every player surface, that loops the current file. It takes
effect on what is playing now, not on the next file.

## When it cannot play

libmpv reports almost nothing by throwing — a failed open rejects asynchronously, and decode or
transport problems arrive later on a stream — so anything unobserved reaches the user as a black
rectangle that never plays, which is indistinguishable from a hang. The player therefore watches all
of those paths *and* arms a start deadline (longer for a network stream, which has a manifest to
resolve and segments to fetch), and every failure lands on one card that offers **Try again** and,
where the host supports it, **Open in another app** — the codec libmpv cannot handle is often one the
phone's own player can.

Two failures get their own wording, because the generic message would mislead:

- **A playlist saved on its own.** A `.m3u8` contains no media; it names files relative to its own
  location, so a downloaded copy has nothing to point at. The card says so and points at *Open
  network stream*.
- **A browser that cannot decode it.** In the Web UI, playback is the browser's own decoder, so an
  `.avi` or `.mkv` cannot play however well the app behaves. Said plainly, instead of offering a
  Try again that can never succeed.

## Notes

- **No artwork is read from tags.** Doing so means downloading the object, and the same hydration
  rule the thumbnail path follows applies here: an online-only placeholder must not be pulled down to
  draw a picture.
- **Seeking a cloud object is not free.** Each committed seek can force a fresh ranged request
  through the engine, which is why a run of presses is coalesced into one.

The television work — the field report behind it, the measurement that proved the remote's transport
keys reach the app, and the two traps it walked into — is recorded with its evidence in
[`dev/plans/tv-playback-plan.md`](../../dev/plans/tv-playback-plan.md).
