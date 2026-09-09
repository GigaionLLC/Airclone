# Android TV — how Airclone ships to the TV form factor

Airclone is one app and one bundle. Android TV is not a separate build, a
separate applicationId, or a separate listing: it is four manifest lines, a
banner, a different shell choice at runtime, and a Play Console opt-in that
only a human can press.

## The one line that can break the shipped app

```xml
<uses-feature android:name="android.software.leanback" android:required="false"/>
```

`required="false"` is load-bearing. Setting it to `true` tells Play the app is
TV-ONLY, and it stops being served to every phone and tablet that has it today.
There is no warning for this — the build succeeds and the listing looks fine.

The same goes for the touchscreen line, for the opposite reason:

```xml
<uses-feature android:name="android.hardware.touchscreen" android:required="false"/>
```

Android implicitly requires a touchscreen of every app that does not say
otherwise. That implicit requirement is the sole reason a TV could not see
Airclone before this work. Declaring it optional only ADDS eligible devices.

Verify with the APK, never with the source — this is what Play actually reads:

```
aapt2 dump badging build/app/outputs/flutter-apk/app-release.apk \
  | grep -E "uses-feature|uses-implied-feature|launchable-activity"
```

Both of these must appear, and there must be NO `uses-implied-feature` naming
touchscreen:

```
launchable-activity: name='app.airclone.airclone.MainActivity'
leanback-launchable-activity: name='app.airclone.airclone.MainActivity'
  uses-feature-not-required: name='android.hardware.touchscreen'
  uses-feature-not-required: name='android.software.leanback'
```

`launchable-activity` is phones keeping the app. `leanback-launchable-activity`
is the TV gaining it. Both lines, every release.

## The two banners are different images

Confusing them is easy and neither surface complains.

| Size | Where it lives | What draws it |
| :--- | :--- | :--- |
| 320x180 | `app/android/app/src/main/res/drawable-xhdpi/tv_banner.png`, named by `android:banner` | the TV home screen |
| 1280x720 | `docs/store/play/tv-banner/`, uploaded as the `tvBanner` image type | the Play TV storefront |

Both are generated from the master icon, so they cannot drift from it:

```bash
python dev/brand/make-tv-banner.py
```

Both must carry the app NAME as part of the image — neither surface draws a
separate label, so a logo-only banner ships an unnamed tile.

## Why a TV gets the touch shell, not the desktop one

A 1080p TV reports 960dp wide at xhdpi, which cleared the `width < 700` gate and
landed on the DESKTOP shell — whose primary verbs are right-click, hover and
drag, none of which a D-pad can produce. `home_screen.dart` now routes on
`androidIsTelevision` first.

The touch shell was already the right base: `isTouchPrimary` is true on Android,
so single-tap-to-open is the existing behaviour and it maps exactly onto the
remote's centre button. No gesture rewiring was needed. TV-only chrome (side
rail, overscan inset, focus theme, focus seeding) lives in `lib/src/ui/tv.dart`,
gated on a flag that is false on every phone and every other platform.

Detection is native (`MainActivity.isTelevision`) and checks two signals,
because neither is reliable alone: `UI_MODE_TYPE_TELEVISION` is what the
platform reports and what emulators set, `FEATURE_LEANBACK` is what Play filters
on and what some manufacturer boxes report instead.

## Focus is the whole game

A TV review fails on operability, not looks. With no pointer, the focus ring IS
the cursor. Two separate things had to be fixed, and the first one hid the
second.

**Focus needs an origin.** Flutter moves focus by DIRECTIONAL traversal: an
arrow key asks what is nearest, in that direction, to whatever holds focus now.
With nothing focused there is no origin. `TvInitialFocus` seeds focus and
re-seeds it whenever focus is lost, because on a TV "focus is nowhere" is a dead
end the user cannot escape. It owns its `FocusScopeNode` rather than calling
`FocusScope.of(context)`: the ambient scope there is the route's, whose
`focusedChild` is already non-null for unrelated reasons, so the "is anything
focused?" guard read YES and the seed never ran.

**Focus has to be VISIBLE, and Material will lie about this.** The first D-pad
filmstrip came back with byte-identical frames across arrow presses, which reads
exactly like focus not moving. It was moving the whole time: the press *after*
those arrows activated a different tab, which is only possible if focus had
already travelled there. `NavigationRail` draws its own focus overlay and
ignores `ThemeData.focusColor`, so setting that changed nothing on screen.

That is why `TvNavRail` is hand-built from `InkWell` with an explicit 3px ring.
The general rule for anything added to the TV shell: **prove focus is visible by
screenshotting it, not by setting a theme colour and assuming.** An invisible
focus ring and an absent one produce identical evidence.

**Focus must reach DIALOGS, and it did not.** A user with a Google TV remote
reported the app as unusable: "I can select the config file and add passphrase
but cannot navigate to click on the button *Unlock*. Same kind of issue if I try
to add a remote manually." Two independent traps, both outside the shell:

- *The TV affordances wrapped the wrong thing.* `TvFocusTheme`, `TvFocusOverlay`
  and the focus seed sat around `MobileHomeScreen`'s `Scaffold` body. A
  `showDialog` route is a SIBLING entry in the Navigator's overlay, not a
  descendant of that screen, so every dialog got none of them: no ring, no
  seeded focus, and Material's ~10% focus wash, which is invisible across a
  room. They now wrap the whole app from `MaterialApp.builder`, which sits above
  the Navigator — see `TvShell`. `TvFocusSeed` is the route-agnostic half of
  that: it watches `FocusManager` and, whenever a bare `FocusScopeNode` holds
  primary focus (which is exactly the state a freshly pushed dialog leaves), it
  seeds focus into the route's first control.
- *A text field is a one-way door for a D-pad.* Flutter binds a bare
  ArrowUp/ArrowDown to a text-editing intent on Android, and `EditableText`
  enables that action whenever the selection is valid — always. The key is
  consumed to move the caret and never reaches focus traversal, so the
  passphrase field could be typed into and never left. `TvDpadEscape` rebinds
  the two vertical arrows to `DirectionalFocusIntent(..., ignoreTextFields:
  false)`, which the field's own `DirectionalFocusAction.forTextField()` honours.
  It is installed inside `MaterialApp.builder`, therefore BELOW the app-level
  `DefaultTextEditingShortcuts`, and key events bubble outwards from the focused
  node, so the inner binding wins. LEFT/RIGHT are deliberately left to the caret
  so a typo in a passphrase is still fixable.

Both are covered by `app/test/tv_dpad_test.dart`, and each has a paired test of
the UN-wrapped widget that demonstrates the trap — a refactor that drops a
wrapper fails there instead of in a living room.

## Field reports from a Google TV user (2026-09-09)

Three, from someone actually using it on a set. The first two are focus
problems, which is the pattern this page keeps predicting; the third was a
missing control that only a remote makes obvious.

**"Sometimes the navigation goes on the three dots on the right of the screen."**
A file row is one thing the user is aiming at, but it contains two focusable
things: the row itself and its trailing ⋯ button. Directional traversal picks by
geometry, so pressing DOWN repeatedly drifts sideways into that right-hand
column and stays there. Nothing was broken — there were simply two targets where
the user was aiming at one.

`tvSkippableFocusNode` (`ui/tv_row_actions.dart`) takes the ⋯ out of traversal on
a television. `skipTraversal` leaves the node focusable and clickable; it only
stops the arrow keys from choosing it, so a pointer remote still works and no
other platform changes at all.

That would strand the menu, so `TvRowMenuKey` gives it a deliberate route:
**RIGHT on a focused row opens that row's actions**. RIGHT specifically because
RIGHT already went there — the ⋯ was the nearest focusable to the right, so a
right-press landed on it before this existed. The key did not mean something
else and lose its meaning; the same destination just stopped needing an
intermediate stop on a 15 px glyph. The menu opens at the row's own centre,
since a television has no pointer position to fall back on.

**"When we listen music on the player we cannot navigate to the previous or next
song."** Correct, and it had nothing to do with focus: the audio card was
play/pause, repeat and a seek bar, and that was all. On a phone a swipe moves
the pager and on a desktop the arrow keys do; a remote has neither, so an audio
player with only play/pause is one you cannot get out of without leaving the
screen.

`AudioSkipButton` (`ui/media_preview.dart`) adds previous/next either side of
play/pause, wired through `PreviewContent` to Quick Look's existing pager — so
they move through the same sibling list a swipe already did. Two details worth
keeping: with **both** callbacks null the buttons render nothing (the host
passed no sibling list, and two permanently dead buttons are worse than none),
and at either **end** of a real list the dead one stays visible but disabled,
because a control row that changes shape as you move through an album is harder
to aim at with a D-pad than one that stays put.

**"There is a small blue rectangle on the middle of the screen [that] do not
disappear when we watch any movie."** Our own focus ring, but not for the reason
it looks like. Two independent bugs stacked:

1. `_video()` built its frame as a **loosely-fitted** `Stack`, and a loose Stack
   takes the size of its largest NON-positioned child. While the loading spinner
   was up, that child was the spinner: **36 x 36**. The `Positioned.fill` video
   surface — media_kit's `Video`, and the `Focus(autofocus: true)` its controls
   wrap it in — was therefore laid out to 36 px at dead centre until the first
   frame arrived. No phone user could ever see this: the surface is black until
   that frame anyway. It also shrank a *playing* video to 36 px for the length of
   any mid-film buffering stall, on every platform.
2. `TvFocusOverlay` measured the focused widget when **focus** moved, and only
   then. media_kit's `Focus` takes focus the instant the preview opens — which,
   over a cloud stream, is well inside the loading window — so the ring was
   measured around that 36 px box. The surface then grew to fill the screen, but
   a widget growing is not a focus change, so nothing re-measured. A 42 x 42,
   3 px, radius-10 outline in the theme's primary blue, at screen centre, for the
   whole film.

`VideoSurfaceFrame` fixes the layout (`StackFit.expand`, spinner centred over the
full-size surface). `TvFocusOverlay` gains two rules: it **re-measures after every
frame while anything holds focus** (a post-frame callback does not request a
frame, so an idle screen costs nothing, and any relayout is by definition inside
a frame), and it **draws no ring for a target that covers the whole shell** —
that is a page or a route's bare scope or a video surface, not a control, and a
ring around it is four stray arcs in the corners that say nothing about where the
D-pad is. A film now plays with no ring; the ring returns the moment focus moves
to a real control.

Covered by `app/test/tv_focus_overlay_test.dart`. The layout half is
platform-neutral; nothing TV-specific was added outside `tv.dart`.

### The gap that investigation exposed: a remote cannot control playback at all

Confirmed in media_kit_video 1.3.1's own source, not inferred. `AdaptiveVideoControls`
branches on `Theme.platform`, so **Android — and therefore Android TV — gets the
TOUCH controls** (`material.dart`), never the desktop ones. Those controls contain
**zero** key handling (`grep -cE 'KeyEvent|Shortcuts\(|LogicalKeyboardKey'` returns
0, against 15 in `material_desktop.dart`), and they only appear at all from
`onTap` (`material.dart:655-658`), which a D-pad never produces.

So on a television a film plays and the only thing the remote can do is leave.
**No play, no pause, no seek.** This is not a regression and it is not what the
user reported — they reported the rectangle — but it is the larger problem, and
it needs D-pad video controls of our own rather than a fix to these. Tracked
separately.

Covered by `app/test/tv_row_actions_test.dart` and
`app/test/audio_skip_controls_test.dart`, both confirmed RED against the code
with the fix removed. Neither could be verified on a physical television from
here — see *What a machine cannot do* below.

## A television has no file picker

Verified 2026-09-04 on the `airclone_tv` AVD (`sdk_google_atv64_x86_64`, API 36)
while confirming the focus fixes: pressing **Import File Config → Choose a
file…** starts
`com.android.tv.frameworkpackagestubs/.Stubs$DocumentsStub`, the framework's
*stub* for an intent nothing on the device handles, which finishes immediately.
A stock Android TV image ships no DocumentsUI at all, so `ACTION_OPEN_DOCUMENT`
has nowhere to go and the button silently does nothing.

This is a platform gap, not a focus bug, and it does not reproduce on TVs whose
OEM ships a file manager — the user who reported the focus problem got as far as
typing a passphrase, so theirs has one. **Import QR Config** needs no picker and
is the path that always works on a television.

Two things follow for anyone adding a feature here. Do not reach for a system
picker on TV without a fallback; and when a picker returns nothing, remember
that "the user cancelled" and "there was never a picker" look identical from
Dart, which is why the button reads as broken rather than unavailable.

## Verifying it with a remote and nothing else

```bash
dev/android/tv-dpad-probe.sh /tmp/tv
```

It sends ONLY D-pad key events — a mouse click in the emulator window proves
nothing, because it is an input a real remote cannot produce — and prints
whether each press changed the screen. A run whose steps all say `NO CHANGE` is
the failure above, and without that comparison a filmstrip of identical frames
reads exactly like a successful one.

The emulator (create once):

```bash
sdkmanager "system-images;android-36;android-tv;x86_64"
avdmanager create avd -n airclone_tv -k "system-images;android-36;android-tv;x86_64" -d tv_1080p
emulator -avd airclone_tv
```

x86_64 matters: the bundled rclone engine ships arm64-v8a, armeabi-v7a and
x86_64 jniLibs, so the x86_64 image runs the real engine rather than failing to
start it.

## What a machine cannot do

The Play Developer API (`androidpublisher/v3`) has **no form-factor resource**.
Android TV opt-in, like Wear OS and Auto, exists only in the Play Console UI,
and adding it triggers a separate manual review by Google's TV team against the
TV quality guidelines.

So the split is:

| Automated | Human, in the Console |
| :--- | :--- |
| manifest, banners, TV shell, D-pad verification | opt in to the Android TV form factor |
| bundle build + upload to open testing (`release.yml` android job, on a `v*` tag) | answer the TV declaration |
| `tvBanner` + `tvScreenshots` upload (`play-images.yml` → `tool/play_images.py`) | submit for TV review |

The TV-supporting bundle reaches users in two moves, and confusing them
changes what production serves: **`release.yml` uploads** it to open testing on
the tag, and **`promote-play.yml` promotes** that same version code to
production later. The promote workflow cannot upload anything - Play rejects a
version code it has already seen, so promotion is a metadata edit on the build
that is already up there.

### The Console flow, as actually done (v0.7.0, 2026-08-30)

Test and release -> the form-factor dropdown -> **Manage form factors** ->
*Advanced settings / Form factors* -> **Add form factor** -> Android TV. That
reveals a two-step checklist with the second step locked: upload TV screenshots,
then opt in.

Four things were not what I expected:

- **Nothing ever checks for `LEANBACK_LAUNCHER`.** I had written that the Console
  validates it before letting you add the form factor. It does not - the form
  factor was added, and the opt-in completed, while production still served a
  bundle with no TV support at all. Ship the TV bundle first anyway: the reason
  is that Google reviews the TV experience against whatever is actually live,
  not that the Console will stop you.
- **"Upload screenshots" means SAVED, not drafted.** *Save as draft* leaves the
  change private, Publishing overview reports "no unpublished changes", and the
  checklist stays incomplete without saying why. The button is **Save**.
- **Opting in applies immediately** - the form factor flips to Active and never
  enters the review queue. Only the listing images do.
- **Promoting through the API sweeps pending listing changes into that
  submission**, so the TV assets reach review together with the build that
  supports TV. That is the ordering you want, for free.

Uploading the images needs the service account to hold **Manage store
presence**. Without it `edits.commit` returns a bare 403 *after* the upload step
reports success - the images sit in an edit that is then discarded, so nothing
lands and nothing breaks. Granting it also grants edit access to pricing and
distribution, so weigh that against uploading by hand. The full grant list, and
the rest of the credential, is `dev/play-ci-setup.md` §5.

Send them from **Actions -> *Play Store listing images* -> Run workflow**:
`type=tvScreenshots`, `dir=docs/store/play/tv`, `replace=true`, `mode=report`
first, then re-run with `mode=apply`. Same again with `type=tvBanner`,
`dir=docs/store/play/tv-banner`. `replace` is not optional: Play APPENDS an
uploaded image to a set, so a second run without it leaves duplicates. Only the
two `type` values and their directories are TV-specific; the flags and the
report-then-apply ordering are the same for every image type, explained once in
`dev/google-play-store.md` §C.

The workflow is just a wrapper that supplies the key from the repo secret and
shreds it afterwards. The same thing locally, for anyone who still holds a key
on disk (`play-ci-setup.md` §6 tells you to delete it):

```bash
# TV screenshots (16:9, 1280x720 minimum). --replace because Play APPENDS.
python tool/play_images.py --package com.gigaionllc.airclone \
    --type tvScreenshots --dir docs/store/play/tv --replace --apply
```

## See also

- `dev/google-play-store.md` — the per-release Play runbook
- `dev/play-ci-setup.md` — the service-account credential every Play lane here
  uses, and the four grants it needs
- `dev/android/tv-dpad-probe.sh` — the D-pad rig
- `app/lib/src/ui/tv.dart` — every TV-only widget, in one file
