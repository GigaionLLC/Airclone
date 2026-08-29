# iOS App Store screenshots

Captured on simulators by
[`ios-screenshots.yml`](../../../../.github/workflows/ios-screenshots.yml).
Nobody on this project owns an iPhone or an iPad, and Apple requires **both**:
the app ships `TARGETED_DEVICE_FAMILY = "1,2"`, so iPad screenshots are
mandatory, not a nice-to-have.

| File | Device | Size | Apple's requirement |
| :--- | :--- | :--- | :--- |
| `iphone/01-home-1320x2868.png` | iPhone 17 Pro Max | 1320 × 2868 | 6.9" — exact |
| `ipad/01-home-2064x2752.png` | iPad Pro 13-inch (M5) | 2064 × 2752 | 13" — exact |

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

## Still worth adding

These are Home views. A browsed folder and the photo gallery with real thumbnails
would sell the app far better, and both need the UI actually *driven* rather than
just launched — the Mac rig uses `cliclick`, and the simulator equivalent needs
either that against the Simulator window or a tool like `idb`. One screenshot per
device size is enough to submit; it is not enough to be proud of.
