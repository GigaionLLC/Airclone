# Mac App Store screenshots — store-ready

Captured on a GitHub `macos-latest` runner by
[`mas-screenshots.yml`](../../../../../.github/workflows/mas-screenshots.yml), from the
**sandboxed** build — the one customers get, with its empty Locations sidebar and
without mount/archive/reveal. A screenshot of a feature the shipped binary lacks
is a straightforward rejection.

Apple accepts only exact sizes for Mac: **1280×800**, 1440×900, 2560×1600,
2880×1800. The runner offers none of them, so the display is set to 1920×1080, the
window pinned to 1280×800 centred, and `sips` takes a centre crop — exact pixels,
no rescale.

| File | Size | Shows |
| :--- | :--- | :--- |
| `01-home-1280x800.png` | 1280×800 | Home view, Demo Cloud remote in the sidebar and as a tile, engine running |

## Demo content

The remote is an rclone **alias** pointing inside the app's sandbox container, and
the photographs are the same CC0 set the Play listing uses — see
[`../../../play/DEMO-MEDIA-PROVENANCE.md`](../../../play/DEMO-MEDIA-PROVENANCE.md).

Real media is not a nicety here: Google rejected a screenshot from this project as
*"placeholder images or stock photos"* when it showed gradient tiles named
`IMG_0100.jpg`.

## Still to capture

Browsing the remote, grid view, gallery view, a transfer in flight. Blocked on
driving the UI: Flutter renders its own widgets, so System Events cannot address
them by name (`-1728`), and `click at` delivers nothing. `cliclick` posts real
CGEvents and is the current approach.
