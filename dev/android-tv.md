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
| bundle upload (`promote-play.yml`) | answer the TV declaration |
| `tvBanner` + `tvScreenshots` upload (`tool/play_images.py`) | submit for TV review |

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
distribution, so weigh that against uploading by hand.

```bash
# TV screenshots (16:9, 1280x720 minimum). --replace because Play APPENDS.
python tool/play_images.py --package com.gigaionllc.airclone \
    --type tvScreenshots --dir docs/store/play/tv --replace --apply
```

## See also

- `dev/google-play-store.md` — the per-release Play runbook
- `dev/android/tv-dpad-probe.sh` — the D-pad rig
- `app/lib/src/ui/tv.dart` — every TV-only widget, in one file
