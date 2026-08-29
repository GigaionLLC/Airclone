# iOS App Store screenshots

Captured on simulators by
[`ios-screenshots.yml`](../../../../.github/workflows/ios-screenshots.yml).
Nobody on this project owns an iPhone or an iPad, and Apple requires **both**:
the app ships `TARGETED_DEVICE_FAMILY = "1,2"`, so iPad screenshots are
mandatory, not a nice-to-have.

Four per device, captured by driving the real app with `integration_test`.

| # | Shows |
| :-- | :--- |
| `01-home` | the sidebar — On My Device, and the Demo Cloud remote |
| `02-remote` | browsing that remote: Photos, Documents, Videos |
| `03-photos` | the photographs, with real names and sizes |
| `04-on-my-device` | the app's own folder, which is all of "local" on iOS |

| Device | Size | Apple's requirement |
| :--- | :--- | :--- |
| iPhone 17 Pro Max | 1320 × 2868 | 6.9" — exact |
| iPad Pro 13-inch (M5) | 2064 × 2752 | 13" — exact |

## Why the sizes need no work

`xcrun simctl io screenshot` captures at the device's **native** resolution, and
those resolutions already are the ones Apple accepts. Nothing is rescaled and
nothing is cropped.

That is a real difference from the Mac rig, which has to set a display mode, pin
the window to 1280×800 and centre-crop, because the runner's display offers none
of Apple's four accepted Mac sizes.

## What these show, and why it is honest

Both come from a build with **librclone statically linked and running** — the
iPad shot's status line reads `engine ok · rclone v1.75.0`, which the app cannot
print without having started the engine.

The content is seeded into each app's own container: an rclone `alias` remote
("Demo Cloud") pointing at the app's Documents directory, plus the same CC0
photographs the Play listing uses. That matters — Google rejected a screenshot
from this project as *"placeholder images or stock photos"* when the same
`IMG_010x.jpg` filenames held gradient tiles. Provenance:
[`../../play/DEMO-MEDIA-PROVENANCE.md`](../../play/DEMO-MEDIA-PROVENANCE.md).

Nothing shown is absent from the iOS build: no mount, no archive, no folder
picker, and no browsing outside the app's own folder.

**iPhone and iPad show genuinely different layouts.** iPad crosses the 700 px
width gate and gets the desktop shell — sidebar, toolbar, transfers dock — while
iPhone gets the phone shell. Both are real, and both are worth showing.

## Two defects these shots found

Worth recording, because the point of looking at output is to see what is wrong
with it:

- an empty **DISKS** section header rendered over nothing. iOS has no browsable
  filesystem and a sandboxed Mac App Store build cannot be granted `/`, so the
  list is empty on both — the header is now hidden when there is nothing under it.
- the iPad said **"This computer"**. iPad crosses the width gate into the desktop
  layout, and the label only special-cased Android.

Both are fixed; the next capture will not show them.

## Two traps in the seeding, both found by looking rather than reasoning

**Never bake a container path into the seeded config.** `flutter drive` reinstalls
the app, and a reinstall *preserves the data while giving the container a new
UUID*. The config travels with the data, the photographs travel with it, and the
absolute path inside the config stays behind — so rclone lists a directory that no
longer exists and the browser correctly shows "Empty folder". From outside the
process this is invisible: the config is there, the files are there, both look
right. The app said it in two lines from inside its own sandbox:

```
PROBE docs=  .../Application/2EBB2267-.../Documents
PROBE conf=  remote = .../Application/CB2C6DC7-.../Documents
```

The demo remote therefore points at `/tmp/airclone-demo` on the host, which a
simulator app can read and which survives any number of reinstalls.

**The view control cycles, and its tooltip names the CURRENT mode.** It reads
"View: List" and tapping goes List → Grid → Gallery, so `byTooltip('Gallery')`
matches only once you are already there. Match the `View: ` prefix instead.

## A wrong screenshot reached the App Store

The `01-home` shots uploaded on 2026-08-29 were the **iOS springboard**, not the
app. `flutter drive` uninstalls the app when the test finishes, so the
"belt and braces" fallback step that followed launched nothing, captured the home
screen of the simulator, and wrote it over the driver's real capture under the
same filename. A `|| echo warning` on the launch is what hid the failure.

Two rules came out of it, both now enforced in the workflow:

- **A fallback must never overwrite a better artifact.** It now runs only when
  the driver produced nothing for that device.
- **A capture step must fail rather than save a picture of the wrong thing.** If
  the launch does not succeed, it refuses to screenshot at all.

The giveaway was file size — 3.6 MB against 145 KB — because a photographic
springboard compresses far worse than a flat app UI. Worth remembering as a cheap
sanity check on any captured set.

## Grid and gallery: attempted, abandoned, and why

They would be the best shots — real thumbnails instead of filenames. Two runs
were spent and both were cancelled:

| Attempt | Result |
| :--- | :--- |
| 90-minute timeout | cancelled at 91 minutes, iPhone half done |
| 180-minute timeout | cancelled at 181 minutes having written **nothing**, not even `01-home`, which is captured before any view switching |

The second is a **hang**, not slowness. Switching view generates thumbnails for
every photograph through the loopback object server, and something in that
interacts badly with the `integration_test` binding — but the run produces no
output to diagnose from, and each attempt costs three hours.

Four screenshots per device are uploaded and the listing is complete, so this was
stopped rather than paid for. The finder is correct and kept in the test for
whoever picks it up. The workflow timeout went back to 120 minutes so a hang
fails in an hour rather than half a day.
