# Mac App Store screenshots — store-ready

Five shots, all exactly **1280×800**, captured on a GitHub `macos-latest` runner by
[`mas-screenshots.yml`](../../../../../.github/workflows/mas-screenshots.yml).
Nobody on this project owns a Mac.

| File | Shows |
| :--- | :--- |
| `01-home-1280x800.png` | Home view — Demo Cloud in the sidebar and as a tile, engine running |
| `02-browse-1280x800.png` | Browsing the remote — Documents / Photos / Videos, item count, free space |
| `03-photos-1280x800.png` | List view inside Photos |
| `04-gallery-1280x800.png` | **Gallery view with real photo thumbnails** — the hero shot |
| `05-grid-1280x800.png` | Grid view with thumbnails and filenames |

## Why these are legitimate

**They come from the SANDBOXED build** — the one customers get. So the empty
Locations sidebar is *correct*, not a defect: a Mac App Store build seeds no
default folders, because under the sandbox `$HOME` is redirected into the
container and seeded entries would point at empty folders while looking populated.
Equally, no shot shows **mount, archive or "Show in Finder"**, because the
sandboxed build genuinely does not have them. A screenshot of a feature the
shipped binary lacks is a straightforward rejection.

**The media is real.** The photographs are the same CC0 set the Play listing uses —
provenance in [`../../../play/DEMO-MEDIA-PROVENANCE.md`](../../../play/DEMO-MEDIA-PROVENANCE.md).
That matters: Google rejected a screenshot from this project as *"placeholder
images or stock photos"* when the same `IMG_010x.jpg` filenames held gradient
tiles. The filenames are unchanged; the content is not.

## How the exact dimensions are achieved

Apple accepts only 1280×800, 1440×900, 2560×1600 or 2880×1800 for Mac, and the
runner's display offers **none** of them (800×600 up to 1920×1080). So:

1. `displayplacer` sets the display to 1920×1080
2. the window is pinned to 1280×800 at (320,140) — dead centre
3. `screencapture -x` grabs the full screen
4. `sips` takes a **centre** crop, which is therefore exactly the window rectangle

Exact pixels, no rescale. Upscaling a 1024×768 grab would look soft on a Retina
product page.

## Two things that cost several runs

**`osascript` fails silently without accessibility permission.** Clicks and
keystrokes return success and do nothing. `csrutil` reports SIP disabled on these
runners, so the TCC database is written directly to grant it — defensible only
because it is a throwaway CI VM.

**Flutter renders its own widgets**, so System Events cannot address them by name
(`Can't get static text "Demo Cloud" … (-1728)`), and its `click at` delivers
nothing. **`cliclick`** posts real CGEvents and works — the same approach this
repo's Windows screenshot rig already uses.

Also: the toolbar re-lays out once a remote is open (view toggles move to
x≈778/810/842), so coordinates must be read off captured frames rather than
assumed from the home layout.

## Still worth adding

A transfer in flight showing speed and ETA, and the add-remote wizard with the
provider picker open. Both need more UI driving; the five above are enough to
submit with.
