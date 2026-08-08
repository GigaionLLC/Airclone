# Demo-remote media — provenance and licences

The store screenshots are captured against a demo remote (`D:\AircloneDemo`, **outside this
repo**). This file records where that demo media came from and under what licence, so the
listing's provenance is auditable without redistributing third-party assets under the repo's
AGPLv3.

**Why real photographs at all:** the previous demo photos were synthetic gradient tiles named
`IMG_0100.jpg … IMG_0105.jpg`, and a Play reviewer read that grid as *"placeholder images or stock
photos"* — the thumbnail screenshot had to be pulled from the listing. See
[`store-ready/MANIFEST.md`](store-ready/MANIFEST.md).

## Photographs — `google-drive/Photos/2026 Summer/`

All six are **CC0 1.0 (public domain dedication)** from Wikimedia Commons. Attribution is **not
required** by the licence; the authors are credited here anyway.

| Staged as | Source file (Commons) | Author | Licence |
| :--- | :--- | :--- | :--- |
| `IMG_0100.jpg` | [Paxos coastline at sunrise DSC06029.jpg](https://commons.wikimedia.org/wiki/File:Paxos_coastline_at_sunrise_DSC06029.jpg) | Jess Stubenbord | CC0 |
| `IMG_0101.jpg` | [Boat Harbour Beach 20190722-004.jpg](https://commons.wikimedia.org/wiki/File:Boat_Harbour_Beach_20190722-004.jpg) | Gary Houston | CC0 |
| `IMG_0102.jpg` | [Mountain and Landscape.jpg](https://commons.wikimedia.org/wiki/File:Mountain_and_Landscape.jpg) | Unknown author | CC0 |
| `IMG_0103.jpg` | [Garden flowers, Runita, Moldova.jpg](https://commons.wikimedia.org/wiki/File:Garden_flowers,_Runita,_Moldova.jpg) | Iurie | CC0 |
| `IMG_0104.jpg` | [Forest trail, Oberlibbach.jpg](https://commons.wikimedia.org/wiki/File:Forest_trail,_Oberlibbach.jpg) | Gerda Arendt | CC0 |
| `IMG_0105.jpg` | [Valenica Mar Harbour Spain - Image with boats in line up.jpg](https://commons.wikimedia.org/wiki/File:Valenica_Mar_Harbour_Spain_-_Image_with_boats_in_line_up.jpg) | Yannick Sl | CC0 |

### Screening: licence is not the only check

**CC0 waives copyright. It does not waive personality/publicity rights.** The first candidate for
`IMG_0100` — [Beach in the summer.jpg](https://commons.wikimedia.org/wiki/File:Beach_in_the_summer.jpg),
CC0, perfectly usable copyright-wise — showed a hotel pool full of **identifiable people**,
including a child in the water and a woman in swimwear in the foreground. Putting strangers into a
public store listing on the strength of a copyright licence alone is not something the licence
actually permits, so it was replaced with a people-free coastline shot.

**Every future demo photo must be eyeballed for identifiable people before it is staged**, no
matter how clean its licence is. A licence gate in a script cannot catch this.

### How they were processed

Fetched 2026-08-07 through the Commons API with a **fail-closed licence gate** — a file is only
downloaded when the API reports its licence as CC0/public domain, so a mis-tagged or re-licensed
image can never silently reach a store screenshot. Then, per photo:

- EXIF-transposed to its upright orientation, and **re-saved with all metadata stripped** — the
  originals carry the photographer's camera details and possibly GPS coordinates, none of which
  belongs in a demo asset.
- capped at 2400 px on the long edge (583 KB – 2.1 MB each, down from 2.2–7.0 MB).
- back-dated to the timestamps the gradient tiles used, so the gallery's Jun 20 / Jun 21 date
  grouping still reads naturally.

Reproduce with `scratchpad/fetch-cc0-photos.ps1` + `scratchpad/stage_demo_photos.py` (see
[`dev/plans/play-screenshots-plan.md`](../../../dev/plans/play-screenshots-plan.md)).

## Video — `google-drive/Videos/`, `onedrive/Projects/`

Still **synthetic** (ffmpeg gradient clips, generated 2026-08-07). They are deliberately not
replaced with real footage yet:

- The emulator cannot render video **at all** — media_kit forces software rendering there and
  `eglCreateContext` fails with `EGL_BAD_ATTRIBUTE` — and video *thumbnails* go through the same
  libmpv path. So no video frame can appear in any emulator-captured screenshot regardless of the
  source material.
- With no physical Android device available, the "video playing" screenshot slot is omitted from
  the listing rather than filled with a loading or error state.

If hardware becomes available, replace these with CC0/public-domain footage and record it here
before capturing.

## Residual risk

The Play finding said "placeholder images **or stock photos**." Real CC0 photographs are a large
improvement over solid gradients, but openly-licensed imagery can still read as stock. Prefer
ordinary-looking photographs over glossy compositions, and review the captured set before
submitting.
