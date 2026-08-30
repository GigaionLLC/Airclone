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
