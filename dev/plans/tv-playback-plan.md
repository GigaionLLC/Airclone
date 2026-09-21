# 📦 Parcel Plan: TV playback — a remote that can actually run a film

## 📊 State Dashboard
| Metric | Value |
| :--- | :--- |
| **Status** | `BUILT` — §A–E landed together; `flutter analyze` clean, `dart format` clean, 1827 app tests pass (51 new). Both pre-build unknowns were resolved first: production already ships the skip buttons (§4.F), and Android TV does deliver every transport key to the app (§4.E). Outstanding: a remote-only pass on the AVD, the security-review gate, and a Play upload — Play holds nothing newer than v0.13.8, so none of this reaches the reporter until `publish-play.yml` then `promote-play.yml` run. |
| **Version** | `v2.0.0` |
| **Active Persona** | `Architect` |
| **Last Updated** | 2026-09-21 |

---

## 1️⃣ Phase 1: Expansion & Scoping

* **Intent:** On a television, playing a song or a film should behave the way every TV media app
  behaves — the remote's own keys drive playback, an overlay legible from a sofa says where you are
  in the file, and next/previous move through the folder. Today the only thing a remote can do
  during playback is leave the screen. This is a field report from the same Google TV user whose
  earlier three findings produced `2a26933` and `fc14ffb`; the video half is the gap those commits
  explicitly left open and recorded in `dev/android-tv.md`.

* **The report, verbatim (2026-09-21):**
  > "In my opinion what could be improved would be the player for music and videos for the google TV
  > app. If we listen music we cannot go to the next or previous track. If we watch video we cannot
  > skip forward or backward in the video while it's playing."

* **In Scope:**
  - `TvPlaybackKeys` — one key layer that turns the remote into transport controls (D-pad seek,
    centre play/pause, and the dedicated play/pause, rewind, fast-forward and track keys).
  - `TvVideoControls` — our own `Video(controls:)` builder: a 10-foot overlay with a scrub bar, times
    and a transport row, hidden while playing and summoned by any key.
  - `TvNowPlaying` — a 10-foot audio layout replacing the 480 px card on a television.
  - **Same-kind sibling walk**: next/previous from an audio player moves to the next *audio* file, not
    to `cover.jpg`. Same for video.
  - Media-key bindings on **every** platform (a keyboard's transport keys, a Bluetooth remote paired
    to a phone); the D-pad and overlay work stays TV-gated.
  - Verification: a playback leg for `dev/android/tv-dpad-probe.sh` driven by key events only, plus
    widget tests in the paired-trap style of `tv_dpad_test.dart`.
  - ~~The delivery half: confirm what the Play **production** track actually serves.~~ **Done, see
    §4.F: production serves the fix already.** This is a design problem, not a shipping one.
  - Docs: rewrite the "a remote cannot control playback at all" section of `dev/android-tv.md` as
    solved, and put the key table in exactly one place.

* **Out of Scope:**
  - **Subtitle and audio-track pickers.** libmpv exposes both and a TV user watching films will ask
    for them next — deliberately the following iteration, not this one, so that the thing reported
    lands sooner.
  - **MediaSession / system transport integration** (the Google TV "now playing" row, playback that
    survives leaving the app). That needs a platform channel and a foreground service — a separate
    piece of work, and the known Android production gap already tracked in the Android dev notes.
    It becomes the *fallback* path here only if §4.E proves transport keys never reach Dart.
  - Shuffle, a visible/editable queue, resume-where-you-left-off.
  - **A second playback engine.** `video_player`-based control panels exist and one even has an `isTV`
    flag, but adopting one means two players in the app: we would lose libmpv's format coverage and
    the authenticated object-URL path the engine depends on. Rejected on those grounds, not on taste.
  - Replacing media_kit's desktop controls on desktop fullscreen. They work today.
  - Any visual change on a phone or tablet.

---

## 2️⃣ Phase 2: Requirements & Context

* **Relevant Docs Found:**
  - `dev/android-tv.md` §"The gap that investigation exposed: a remote cannot control playback at
    all" — already documents this exact gap from the 2026-09-09 round, with the evidence. This plan
    closes it; that section gets rewritten rather than duplicated.
  - `dev/android-tv.md` §"Focus is the whole game" — the standing rule: **prove focus is visible by
    screenshotting it, not by setting a theme colour and assuming.** An invisible focus ring and an
    absent one produce identical evidence.
  - `dev/android-tv.md` §"Verifying it with a remote and nothing else" — the probe rig, and why a
    filmstrip of identical frames reads exactly like success unless something compares the frames.
  - `app/lib/src/ui/tv.dart` header — the rule for that file: **nothing here may run off a TV.**

* **Relevant Code Found:**
  - `app/lib/src/ui/media_preview.dart` → `_surface()` passes `controls: AdaptiveVideoControls`; this
    is the one line that has to branch. `_audio()` is the 480 px card. `AudioSkipButton` and
    `VideoSurfaceFrame` are existing TV-driven work to build on, not replace.
  - `app/lib/src/ui/quick_look.dart` → `_onKey` (arrow keys move the pager, Space/Esc close) exists
    **only** in `_buildWindowed`. Android — therefore every television — takes `_buildFullscreen`,
    which has **no key handling at all**. `_pagerView()` is where `onPrevious`/`onNext` are built.
    `_popOut()` is the precedent for a kind-filtered sibling list with an index map.
  - `app/lib/src/ui/preview_dialog.dart` → `PreviewContent` already carries `onPrevious`/`onNext`;
    `isImagePreview()` at line 123 is the precedent for exposing one predicate per kind.
  - `app/lib/src/ui/tv_row_actions.dart` → `tvSkippableFocusNode` / `TvRowMenuKey`: the precedent for
    "a TV-only key with a deliberate route", and the argument this plan reuses for LEFT/RIGHT.
  - `app/lib/src/ui/tv.dart` → `TvFocusOverlay` (and its covers-the-shell rule, which is why a film
    plays with no ring), `TvFocusSeed` (which will re-seed focus into our overlay the moment it is
    hidden if we do not hand focus back — see the risks), `tvOverscan`.
  - `app/lib/src/state/android_native.dart:17` → `androidIsTelevision`, the only gate.
  - `app/lib/src/state/media_formats.dart` → `isVideoLikeExt()`, `isAudioExt()`.

* **Facts verified in source, not inferred:**
  - `media_kit_video-1.3.1/.../adaptive.dart` routes `TargetPlatform.android` to
    `MaterialVideoControls` — the **touch** controls — and there is no TV branch.
  - Those touch controls contain no key handling, and become visible only from `onTap`, which a
    D-pad never produces. So on a television: no play, no pause, no seek.
  - `material_desktop.dart` binds arrows to ±2 s, J/I to ±10 s, and the media keys to
    `player.next()` / `player.previous()` — mpv's *playlist*, which for us holds one item, so those
    would do nothing even if that control set were reachable.
  - `Video(controls:)` takes a `Widget Function(VideoState)`. Our own control set is a supported
    extension point, not a fork.
  - Flutter's `keyboard_maps.g.dart:99-104` maps Android keycodes 85/87/88/89/90 to
    `mediaPlayPause` / `mediaTrackNext` / `mediaTrackPrevious` / `mediaRewind` / `mediaFastForward`.
    The keys are therefore *expressible* in Dart. Whether Android **delivers** them to the Flutter
    view rather than routing them to an active MediaSession is the one open unknown (§4.E).

---

## 3️⃣ Phase 3: User Clarification

* `[x]` Own controls, or an off-the-shelf TV player interface? → **Ours.** Nothing maintained targets
  D-pad + media_kit; the alternatives mean a second engine (see Out of Scope). We borrow the
  *convention* every TV app shares, not the code.
* `[x]` How much in the first cut? → **Keys + the full 10-foot player**, together.
* `[x]` Which platforms? → **TV-gated, except the media-key bindings**, which are nearly free and go
  everywhere.
* `[x]` Is the customer's build even current? → **Answered 2026-09-21: yes, for this feature.**
  Production serves version code 143 (v0.13.8), which contains `2a26933`. They have the skip buttons
  and cannot use them, which settles the design question: the keys are the fix, not more buttons.
* `[ ]` Does their remote have rewind/fast-forward keys at all? → worth asking in the reply: it
  decides how much weight the D-pad has to carry, though the plan makes both work regardless.

---

## 4️⃣ Phase 4: Detailed Execution Plan

### A. `app/lib/src/ui/tv_player_keys.dart` — one key layer

The semantics, which belong in one table and one file:

| Key | Overlay hidden | Overlay visible |
| :--- | :--- | :--- |
| **OK / centre** | play/pause, and show the overlay | activate the focused control |
| **LEFT / RIGHT** | seek by the step, show the overlay with the pending target | seek when the bar holds focus; otherwise move focus |
| **UP / DOWN** | show the overlay (focus lands on play/pause) | move focus within the row |
| **BACK** | close the player | hide the overlay |
| **Play / Pause / PlayPause** | play/pause | play/pause |
| **Rewind / Fast-forward** | seek 30 s | seek 30 s |
| **Track next / previous** | next / previous sibling of the same kind | same |

Decisions inside that table which are the difference between "works" and "feels right":

* **Coalesce.** Ten quick LEFT presses must be **one** seek of −100 s, not ten seeks. Accumulate into
  a pending offset, show it in the overlay immediately, and commit once after ~350 ms of quiet. This
  is what makes a TV player feel instant, and over a cloud object it is also the difference between
  one ranged request and ten.
* **Accelerate.** After four presses inside the window the step grows 10 → 30 → 60 s, capped at 10 %
  of the duration per press. A two-hour film is unusable at a fixed 10 s.
* **Clamp** to `[0, duration]`, and when the duration is unknown or zero (a live stream) seeking is
  disabled and the overlay says so rather than appearing to do nothing.
* **Return `handled` only for keys we acted on**, so focus traversal keeps working everywhere else —
  the same discipline as `TvRowMenuKey`.
* **Gating:** media keys register on every platform; D-pad and OK only when `androidIsTelevision`.
* **Placement:** inside the media branch of `PreviewContent`, not around Quick Look. That way the
  preview *dialog* host gets it too, and the layer can never swallow a key on a non-media page.
* **The LEFT/RIGHT re-assignment, stated plainly:** on desktop, Quick Look's arrows move the pager
  between files. On a television, LEFT/RIGHT inside a *video* must mean **seek**; moving between
  files is what the track keys and the overlay's own buttons are for. Nothing is being taken away —
  the fullscreen shape a TV renders has never had key handling at all. Same shape of argument as
  "RIGHT opens the row menu": the key is not losing a meaning, it is gaining its first one.

### B. `app/lib/src/ui/tv_video_controls.dart` — our own `Video(controls:)`

* Hidden while playing; any key shows it; auto-hides after 5 s of no key, and **never** auto-hides
  while paused (a paused film with no controls is the dead end this whole plan is about).
* Bottom scrim, inside `tvOverscan`: file name, elapsed / total, a progress bar carrying the buffer
  range and the *pending* scrub marker, then the transport row (previous, rewind, play/pause,
  fast-forward, next) at TV scale (≥56 dp targets, 40 dp icons). At the ends of the list the dead
  control stays **visible but disabled** — the rule `AudioSkipButton` already established, so a row
  does not reflow under someone's aim.
* A transient centre indicator (e.g. `« 30s`) while a coalesced seek is pending.
* **Focus hand-back is the load-bearing detail.** When the overlay appears, its play/pause takes
  focus; when it hides, focus must be returned to the video surface explicitly. Otherwise
  `TvFocusSeed` re-seeds into a now-invisible control and `TvFocusOverlay` rings something nobody can
  see — the same class of bug as the blue rectangle, arriving by a different road.
* Keep the overlay from being a shell-covering focus target, so `TvFocusOverlay`'s covers-the-shell
  rule keeps a playing film ring-free.
* Wiring: in `_surface()`, `controls: androidIsTelevision ? TvVideoControls : AdaptiveVideoControls`.
  One branch; every other platform stays byte-identical.

### C. `app/lib/src/ui/tv_now_playing.dart` — 10-foot audio

* `_audio()` branches once on `androidIsTelevision`; the phone/desktop card is untouched.
* Large art tile (~320 dp) or the music glyph, track name at ~32 sp with the folder beneath it, times
  and progress, the same transport row, repeat at the end, and a `3 of 14` counter so an album is
  legible from a sofa.
* **Play/pause autofocuses**, so OK works the instant the screen appears — which is the answer for
  anyone who never thinks to press a media key, and the most direct fix for "we cannot go to the next
  or previous track".

### D. Same-kind siblings

* Add `isAudioPreview()` / `isVideoPreview()` beside the existing `isImagePreview()` in
  `preview_dialog.dart` (same one-line shape, same private `_kindFor`).
* In `quick_look.dart`, build the media player's `onPrevious`/`onNext` from the **kind-filtered**
  list with an index map back to the pager, exactly as `_popOut()` already does for images. The pager
  must still `animateToPage` to the correct absolute index — a parallel cursor would desynchronise
  the counter and the top bar.
* Ends of the *filtered* list are what disable the buttons, so a folder of songs plus one cover image
  behaves like an album.

### E. Test & verification plan

**The unknown is settled — spike run 2026-09-21 on the `airclone_tv` AVD
(`sdk_google_atv64_x86_64`, leanback + leanback_only). No MediaSession fallback is needed.**

*Platform layer* — a throwaway native activity logging `dispatchKeyEvent`, driven only by
`adb shell input keyevent`. **All thirteen keys were delivered to the foreground app**, transport keys
included: 23/21/22/19/20 (D-pad) and **85 PLAY_PAUSE, 126 PLAY, 127 PAUSE, 86 STOP, 89 REWIND,
90 FAST_FORWARD, 87 NEXT, 88 PREVIOUS**. `dumpsys media_session` throughout: `Media key listener:
null`, `Media button session is null`, `0 sessions`. media_kit registers no MediaSession of its own
(grepped `media_kit` and `media_kit_libs_android_video`), so nothing in our own app competes either.

*Dart layer* — a widget test simulating each key with `platform: 'android'` (which exercises
Flutter's own android→logical mapping) confirms a `CallbackShortcuts` binding on
`LogicalKeyboardKey.media*` **fires for every one of them**, and that ten presses arrive as ten
events, so the §A debounce has something real to collapse. Port that test into
`app/test/tv_player_keys_test.dart`.

Two things the spike also taught, both worth keeping:

* `LogicalKeyboardKey` **has no primitive equality**, so it cannot be a `const` map key
  ("does not have a primitive equality"). Use a list of records in these tests.
* **A probe that cannot render looks exactly like a key that was not delivered.** The first two runs
  reported every key — D-pad included — as undelivered. The cause was the probe: a fresh Flutter
  *debug* app never produced a first frame on this image, so `InputDispatcher` logged *"no window has
  focus"* and ANR-killed it. Airclone's own installed build renders on the same AVD perfectly, so the
  lesson is not "Flutter cannot render here". Gate any future rig on a **focused window** (`dumpsys
  window | grep mCurrentFocus`) and re-check the process is **alive after every key**; the D-pad keys
  are the control, because they are known to arrive and their silence indicts the rig.

**Residual risk, unreproducible on an emulator:** the device had zero media sessions. On a real
television where another media app holds an active `MediaSession`, `MediaSessionService` can route
transport keys to *that* session instead of the foreground app. The D-pad path is unaffected. If a
user ever reports the transport keys working for the D-pad but not the dedicated buttons, that is
this, and the answer is the deferred MediaSession work — which is wanted anyway for the Google TV
now-playing row.

Then extend the rig:

```bash
dev/android/tv-dpad-probe.sh /tmp/tv-playback
```

* Add a playback leg: open a video, then send the five transport codes and DPAD_LEFT/RIGHT/CENTRE,
  capturing after each. The rig's existing `NO CHANGE` detector is precisely what proves a key
  arrived — without it a filmstrip of identical frames reads as success.
* Repeat for an audio file in a folder that also contains an image, to exercise §D.

Widget tests, each paired with a test of the un-wrapped widget that demonstrates the trap (the
`tv_dpad_test.dart` convention, so a refactor that drops a wrapper fails here rather than in a living
room):

* `app/test/tv_player_keys_test.dart` — every key reaches the intended call on a fake player;
  ten LEFT presses commit **one** seek; the step accelerates; clamped at 0 and at the duration;
  an unknown duration disables seeking; unrelated keys return `ignored`; with the TV flag false the
  media keys still work and the D-pad keys do nothing.
* `app/test/tv_video_controls_test.dart` — hidden while playing, appears on a key, auto-hides after
  the timeout, does **not** auto-hide while paused, focus returns to the surface on hide, ends
  disabled rather than hidden.
* `app/test/tv_now_playing_test.dart` — at 960 dp TV metrics: art, name, an autofocused play/pause,
  and no clipped control row (the fixed-width-dialog lesson).
* `app/test/audio_skip_controls_test.dart` — extend for kind-filtered siblings.

Before pushing, both of these, because CI fails on any info-level lint:

```bash
cd app && flutter analyze && dart format --set-exit-if-changed .
```

Finally, a remote-only pass on the `airclone_tv` AVD (x86_64, so the bundled engine actually runs),
with a screenshot proving the focus ring on the transport row. **It still cannot be verified on a
physical television from here, and the docs must keep saying so.**

### F. Delivery — checked first, and it is not the problem

**Settled 2026-09-21, before any code.** The daily `store-feedback.yml` run
([35614218663](https://github.com/GigaionLLC/Airclone/actions/runs/35614218663)) reports:

```
internal    [100] completed at 100%  100 (0.4.0)
alpha       —
beta        [143] completed at 100%  v0.13.8
production  [143] completed at 100%  0.13.8
```

Code 143 is **v0.13.8**, and `git merge-base --is-ancestor 2a26933 v0.13.8` returns YES — as it does
for `fc14ffb` (the focus ring) and `ab6af97` (repeat). So:

* **The user already has the previous/next buttons.** Complaint #1 is not a missing feature and not
  an undelivered one: it is a 480 px card with 28 px icons in the middle of a television, reachable
  only by hunting with a D-pad. That is the whole argument for §A and §C — the keys are the fix.
* Correction to an earlier draft of this plan: those fixes first shipped in **v0.8.0** (2026-09-09),
  not v0.13.9. **The version numbers in this repo are not chronological** — v0.13.9 was tagged
  2026-09-19, ten days *after* v0.8.0 — so `git merge-base --is-ancestor` is the only safe way to
  ask whether a release contains a commit. Do not reason from the number.

**Separate finding, worth a decision of its own:** Play holds nothing newer than v0.13.8 on *any*
track, while `main` is at v0.21.0+146. v0.13.9, v0.20.0 and v0.21.0 — including the guided "Add a
cloud" work — have never been uploaded. The last `publish-play.yml` run (2026-09-19) was dispatched
with `TAG: v0.13.8` and re-published code 143. Both lanes are manual by design, so this is a button
nobody pressed rather than a broken pipeline — but it means **this TV work will not reach the person
who reported it until `publish-play.yml` then `promote-play.yml` run.** Ship accordingly.

Then reply to the customer: answer both points, say plainly that one control exists today and where
it is, that the remote's keys are coming, and ask the one question worth asking — whether their
remote has rewind/fast-forward keys at all.

### G. Docs

* Rewrite `dev/android-tv.md` §"a remote cannot control playback at all" as solved, keeping its
  evidence (it is the reason the next person will believe the branch in `_surface()` matters).
* The key table lives **only** there, so it cannot drift from the code.
* A short `wiki/features/feat-media-playback.md`: playing music and video, and what a remote does.
* `dev/releases/<tag>.md` note when it ships.

---

### H. What was built, and where it differs from the plan above

Four deviations, all deliberate:

1. **`TvPlaybackTarget`, a five-member seam over the player.** Not in the plan, and it is the reason
   every rule above is provable: a real `Player` initialises libmpv, so without it the timings could
   only be checked on a television. 51 tests run on a fake in under a second.
2. **`tv_video_controls.dart` also hosts the shared `TvTransportRow`, `TvScrubBar` and
   `formatMediaClock`**, which `tv_now_playing.dart` imports. Two surfaces rendering the same picture
   from two widgets is how they drift into different gestures for the same icon.
3. **No burst-timing window.** The plan called for a press-timing window for acceleration; a burst is
   instead just the run of presses that has not committed, because a pause longer than `commitDelay`
   commits and resets *by definition*. One clock instead of two, and a test can move it.
4. **No `3 of 14` counter on the audio screen.** Quick Look's own top bar already shows it on a
   television, and two counters that could disagree are worse than one.

Also, because the tests demanded it: `sameKindNeighbour` is a public top-level function in
`quick_look.dart` rather than a private method, since the widget around it needs a running engine
and the decision needs nothing.

## 5️⃣ Phase 5: Product Owner Review
* **Status:** `PENDING`

## 6️⃣ Phase 6: Senior Dev Hygiene Review
* **Status:** `PENDING`

---

## 7️⃣ Risks

1. ~~**Transport keys may never reach Dart.**~~ **Retired 2026-09-21** — measured on the TV AVD, both
   layers pass (§4.E). What remains is the narrower case that no emulator can stage: a *foreign*
   MediaSession on a real television claiming the transport keys. D-pad unaffected; fallback is the
   deferred MediaSession work.
2. **Focus hand-back when the overlay hides.** `TvFocusSeed` exists to make focus impossible to lose,
   and it will happily seed into a hidden control. Explicitly tested (§4.E).
3. **Seeking a cloud object is not free.** Each commit can force a fresh ranged request through the
   engine; coalescing is what keeps a scrub from hammering a remote. Worth one real-world check on a
   large file over a slow remote.
4. **Key collisions.** Anything bound here must return `ignored` for keys it does not own, or it
   becomes the next "the D-pad does nothing" report. The existing `TvDpadEscape` / `TvRowMenuKey`
   bindings are the ones to check against.
5. **No physical television.** Every claim here is emulator- or test-backed, and the docs say which.
