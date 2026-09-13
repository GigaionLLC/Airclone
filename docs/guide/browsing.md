# Browsing your files

The file browser is the part of Airclone you will spend most of your time in. It lists a folder on
a cloud remote or on a local disk, and it works the same way for both: the same views, the same
sorting, the same menus. Nothing is mounted and nothing is downloaded in the background — the
listing you see is fetched from the remote when you open the folder.

If you have not connected anything yet, start with [getting started](getting-started.md).

## Two shells, one browser

Airclone draws one of two layouts, and the choice is made on the **width of the window in logical
pixels**, not on the operating system:

- **700 pixels wide or more** — the desktop shell: sidebar, one or two panes, a details panel, a
  transfers dock along the bottom.
- **Narrower than 700** — the phone shell: a bottom `Files` / `Transfers` / `Settings` bar, one
  pane at a time, bottom sheets instead of menus.

So an Android tablet or an iPad gets the desktop layout, and a desktop window dragged narrow
switches to the phone layout while you watch. An Android TV always gets the phone shell, with the
bottom tabs moved to a left-hand side rail.

Everything below says which shell it applies to when the two differ.

## Panes

A **pane** is one file list. It has its own folder, its own selection, its own view mode and its own
back/forward history.

**On the desktop**, Airclone opens with a single pane. The `Dual-pane view (commander)` button in
the top bar splits the work area into two panes side by side; the same button, now reading
`Single-pane view`, puts it back. Desktop panes are always left and right — there is no stacked
option there.

Drag the divider between two panes to change how they share the width. The drag is clamped so
neither pane can be squeezed below a fifth of the area, and the position is remembered across
launches.

Click anywhere in a pane to make it the **active** pane. The active pane is what the keyboard, the
sidebar, the details panel and the status bar all follow. In the default Airclone skin the active
pane is marked with a small coloured dot at the left of its address row.

**On the phone** the split is opt-in and off by default. Open `⋯` (`More actions`) in the pane
header, and under `Layout` choose `Split view`. Once split you also get `Adaptive`, `Side by side`
and `Stacked`:

| Choice | What it does |
|---|---|
| `Adaptive` | side by side when the area is at least 600px wide, stacked when it is narrower |
| `Side by side` | always left and right |
| `Stacked` | always top and bottom |

`Adaptive` is the default. The second pane's `⋯` sheet has `Close second pane`; the first pane's
has `Close split view`.

## Tabs

Each pane holds tabs. On the desktop, `New tab (Ctrl+T)` in the address row adds one and `Ctrl+W`
closes the current one. The tab strip only appears once a pane has more than one tab, or when its
only tab is a console.

A tab is labelled with the folder name, or the remote name at a remote's root, or `New tab` before
you pick anything. The last tab in a pane cannot be closed.

A pane can also hold a **console tab**, labelled `Console`, which runs rclone commands instead of
showing files. That is covered in [the command console](console.md).

## The address bar and getting around

The desktop address row, left to right: `Back (Alt+←)`, `Forward (Alt+→)`, `Up (Alt+↑)`, `Refresh`,
`New tab (Ctrl+T)`, the breadcrumb path, a filter box, and `Close pane (deselect remote)`.

The breadcrumb shows the remote followed by each folder in the path. Click any crumb to jump
straight there. When the trail is too long for the width, the middle collapses into a `…` chip whose
menu lists the folders it hid.

To **type a path instead**, click the empty space to the right of the breadcrumb or the `Edit path`
button, and the bar turns into a text field (`Type a path…`) with the remote name shown as a fixed
prefix. Press Enter to go, Esc to cancel. `Ctrl+L` or `Alt+D` puts the bar into that mode from the
keyboard.

On the phone the header shows a scrollable breadcrumb you can tap to jump to any ancestor. The
button at the left of the header changes meaning with where you are — its tooltip reads `Up` inside
a folder, `All locations` at a remote's root, and `Close console` on a console tab.

Opening things:

| Gesture | Desktop | Phone and tablet touch |
|---|---|---|
| Single click or tap on a folder | opens it | opens it |
| Single click or tap on a file | selects it | opens Quick Look |
| Double click on a file | opens Quick Look | — (no double tap; it would delay every single tap) |
| Right click / long press | opens the item menu | opens the item menu |

On touch you can also **pull down on the list to refresh** it. The desktop refreshes with the
`Refresh` button or `F5`.

## View modes

| View | Called | Shows | Available on |
|---|---|---|---|
| List | `List` | rows with Name, Size and Modified columns | everywhere |
| Icons | `Icons` on the desktop switcher, `Grid` in the phone sheet | thumbnail or icon tiles | everywhere |
| Gallery | `Media gallery` in the desktop View menu, `Gallery` elsewhere | images and video only, grouped by day | everywhere |
| Tree | `Tree` | folders you expand in place, with the same columns | Windows, macOS and Linux only |

The **Tree** is absent on Android and iOS. That is deliberate rather than an oversight — there is no
room on a touch screen for indentation plus three columns — and it holds even on an Android tablet
or an iPad showing the desktop layout. A remote you last viewed as a tree on a computer opens as a
list on a phone.

On the desktop the `View` menu in the command row carries the modes plus four icon sizes:
`Extra large icons`, `Large icons`, `Medium icons` and `Small icons`. Picking a size also switches
the pane to Icons. Under the `Windows Explorer`, `macOS Finder` and `Linux (GNOME)` skins the pane
additionally gets a small segmented switcher next to the `Sort` menu, and the Windows skin puts
`Details view` and `Large thumbnails` toggles in the bottom-right of the status bar.

On the phone, `⋯` → `View` lists `List`, `Grid` and `Gallery`, and the view button in the header
cycles through those three in that order. Its tooltip tells you where you are: `View: List`,
`View: Grid`, `View: Gallery`.

Airclone remembers the view mode, sort order and icon size **per remote**, so a photo remote can
open in Gallery while a documents remote opens as a list.

### The Gallery

The Gallery shows images and video and nothing else. Items are grouped by the day they were last
modified, newest day first, under headers that stay pinned as you scroll; anything without a
modification time is collected into a final `Unknown date` group.

Because it filters, a folder of documents looks empty in this view. Rather than leave you at a dead
end, the Gallery says `No photos or videos here`, tells you how many folders and files it is
hiding, and offers a `Show all files` button that switches the pane to the list.

### The Tree

Click a folder's arrow to expand it; the contents are listed the first time you open it and cached
after that. With the tree focused, the arrow keys move a cursor (Left collapses or climbs to the
parent, Right expands or steps into the first child), Home and End jump to the ends, and Enter or
Space toggles a folder or previews a file.

Two behaviours are worth knowing because they look like bugs and are not:

- **Collapsing a folder drops any selected rows inside it.** A selection you cannot see is a
  selection a later Delete would act on blindly, so the app lets it go.
- **The details panel shows the folder summary, not the row, while the tree is showing.** A tree row
  can live several levels down, and the details panel is built around one flat folder.

## Sorting

Sort by `Name`, `Size` or `Modified` — from the `Sort` menu on the desktop, from `⋯` → `Sort by` on
the phone, or by clicking a column header in the List and Tree views. Choosing the column you are
already sorted by flips the direction.

Two rules never change, whatever you sort by:

- **Folders always come before files.**
- **Items with no modification time sort last**, in both directions, because the remote did not tell
  us when they changed rather than telling us they are old.

In the List and Tree views the `Size` and `Modified` columns can be resized by dragging the thin
divider on their left edge. The widths are remembered.

## Filtering, and searching

These are two different things and it is worth keeping them apart.

**The filter box** (`Ctrl+F`, hint text `Filter`) narrows the folder you are looking at. It matches
anywhere in the name, it is instant because it works on the listing already on screen, and it does
not look inside subfolders. Navigating anywhere clears it. When a filter hides everything, the pane
says `No matches` rather than `Empty folder`.

**Search** (`Ctrl+Shift+F` on the desktop, the magnifier or `⋯` → `Search this folder` on the phone)
opens a dialog titled `Search in <remote>/<folder>`. Type into `Name contains…` and press `Search`.
It scans every file and folder beneath the current one — the dialog says so — so on a large remote
it takes a while and it costs a listing request. Multiple words all have to match, in the name or in
the path.

Results are capped at 500 on screen; beyond that you get
`Showing first 500 of N matches — refine your search.` and the true total. Clicking a result opens
the folder, or opens the file's parent folder and selects the file for you.

## Selecting files

**On the desktop**, click a file to select it and click it again to deselect. Click more files to add
them. `Ctrl+A` selects everything currently displayed and `Esc` clears the selection. The status bar
shows the count and the total size, and the command row shows `N selected` with the actions that
apply to it.

**On touch**, long-press an item and choose `Select` at the top of the menu. The pane drops into
selection mode: a plain tap now toggles items instead of opening them, and the pane header turns
into a selection bar with a close button, the live count, select-all, `Copy`, `Cut` and `Delete`.
The system Back button clears a selection before it does anything else.

`Select all` is deliberately narrower than it sounds in two views:

- In the **Gallery** it selects the photos and videos on screen only — never the folders and other
  files the gallery is hiding. Selecting something invisible and then deleting it would remove far
  more than you asked for.
- In the **Tree** it selects the rows currently expanded and on screen, for the same reason.

## The details panel

`Show details (Ctrl+I)` opens a 300-pixel panel on the right of the desktop shell, headed `DETAILS`.
It follows the active pane and has two tabs, `Overview` and `More`. There is no details panel in the
phone shell.

With one file selected, `Overview` shows a large thumbnail or type icon, the name, the kind and
size, `Modified`, `Path` and `Remote`, and a row of quick actions:

| Action | When it appears |
|---|---|
| `Preview` | always |
| `Open` | local files, desktop |
| `Show in folder` | local files, on builds allowed to launch your file manager |
| `Download` | files on a cloud remote |
| `Copy path` | always |
| `Copy link` | only when the backend supports public links |

`More` shows the MIME type, the full path, the remote's rclone `fs` string, the backend type and
whether the backend supports public links. With several files selected you get the count, the total
size and `Download all`. With nothing selected you get a summary of the folder itself.

## Quick Look and Preview

Airclone has two viewers, and they are not the same thing.

**Quick Look** is the immersive one. Press `Space` on a selected file, or double-click a file on the
desktop, or tap a file on a phone. It opens over the whole window and you can move through every
file in the folder without going back to the list.

- **Desktop:** chevrons at the sides, `←` and `→` to move, `Space` or `Esc` to close. The hint at
  the bottom says so. An image can be sent to its own resizable window with
  `Pop out to a new window`; the overlay stays open behind it.
- **Android and iOS:** edge to edge on black with the system bars hidden. Swipe between items, tap
  once to hide or show the controls. The overflow holds `Open in another app` and `Share…`.

**Preview** is the smaller dialog. It comes from `Preview` in the right-click menu and from the
`Preview` pill in the details panel. It shows one file, with its name, size and a close button.

Both render the same things:

| Kind | Extensions recognised |
|---|---|
| Images | png, jpg, jpeg, gif, webp, bmp |
| Video | mp4, mkv, webm, mov, avi, m4v, mpg, mpeg, wmv, flv |
| Streams | m3u8, m3u (HLS), mpd (MPEG-DASH) |
| Audio | mp3, flac, wav, ogg, m4a, aac, opus, wma |
| Documents | pdf, md, markdown |
| Text and code | txt, log, json, yaml, yml, dart, js, ts, py, sh, c, cpp, h, xml, csv, ini, conf, toml |

### Streams and network playback

A `.m3u8`, `.m3u` or `.mpd` on a remote is a **playlist**, not a video: a short text file listing
the segments that make up the stream. Opening one plays it — Airclone fetches the segments as it
goes. Playlists never get a thumbnail, because there is no picture in the file to take one from.

You can also play a stream that is not on a remote at all. **Open network stream…**, in the pane
menu and in the `+` sheet on a phone, takes an address and plays it: HLS, MPEG-DASH and RTSP, plus
RTMP and SRT. It needs no remote, because a stream is not a file on one.

Airclone sends **no account details** to an address you type. The sign-in Airclone uses for its own
engine is for a port on your own machine, and it never travels anywhere else.

A file with no extension falls back to the type the remote reports. Anything else gets a
`No preview available` card with an `Open in another app` button where handing the file to another
app is possible. Text and markdown are capped at 512 KB and truncated past that, with a note, so a
stray multi-megabyte log cannot lock up the window.

### Operations from the preview

Both preview surfaces have a **delete** button. It asks first, with the same confirmation the file
list uses.

Quick Look carries the rest of the file's operations behind its `⋯` menu, so you rarely need to
close it and go and find the file again. The menu is the same everywhere: a bottom sheet on a phone,
a drop-down from the toolbar on a desktop.

| | |
| :--- | :--- |
| **Rename** | Keeps the file on screen under its new name — a rename is not a reason to lose your place in a folder you are working through. |
| **Public link** | A shareable link, where the backend can mint one. This is usually where you decide a file is the one to send. |
| **Checksums** | The same dialog the file list offers. |
| **Copy path** | The full `remote:path`, for the console, a script or a message. |
| **Delete** | Always last in the menu and set apart from the rest, because it is the one that cannot be undone. |
| **Open in another app** | Hands the file to whatever your system uses for it. Not shown on iOS, which has no route for it. |
| **Share…** | Phones only, where the system has a share sheet. |

Copying or moving to another folder is still done from the file list: those need a destination, and
choosing one from inside a fullscreen preview is a different design problem than adding a button.

The smaller **Preview** dialog has delete and nothing else. It opens from the details panel, where
`Copy path` and `Copy link` are already a row away from the `Preview` pill that opened it.

In Quick Look the overlay **stays open and moves to the next file**, which is the point: culling a
folder of photos is one confirmation per file instead of preview, close, find, delete, reopen. It
closes when the last file is gone. The folder behind it re-lists straight away, so what you see is
what is there.

## Thumbnails

Thumbnails are generated by Airclone itself: images are decoded from their bytes, videos have a
frame captured. They are cached on disk, and **the cache is encrypted at rest** — bound to your
rclone config password when the config is encrypted.

Thumbnails are **on by default**. Local folders are always on, because there is no bandwidth to
spend. For a cloud remote you can turn them off per remote: `View` → `Thumbnails` on the desktop, or
the `Thumbnails` switch in the phone's `⋯` sheet. The choice is remembered for that remote. For a
local folder the menu reads `Thumbnails (always on)` and does nothing.

Three maintenance actions appear once thumbnails are on for the remote you are looking at:

| Action | What it does |
|---|---|
| `Reload thumbnails` | asks tiles that never loaded to try again; tiles that already have a picture are untouched. This is the cheap fix for "some of them didn't appear". |
| `Load all in this folder` | fetches a thumbnail for every image and video in the folder, not only the ones on screen, so scrolling is instant afterwards. It tells you how many it is loading, or says `No images or videos to load here`. |
| `Rebuild (clear cache)` — `Rebuild thumbnails (clear cache)` on the phone | throws away what is cached and regenerates every visible thumbnail. Use it when a cached picture is stale or plainly wrong. |

On the desktop these sit at the foot of the `View` menu. On the phone they are inside the collapsed
`ADVANCED` group at the bottom of the `⋯` sheet. (That group is just a collapsed heading. It is not
related to the Advanced mode setting and everybody has it.)

Two things Airclone will refuse to do:

- **It will not download an online-only file just to draw a thumbnail.** See
  [Files stored online only](#files-stored-online-only) below — Airclone shows the plain type icon
  rather than pulling the whole file down to make a picture of it.
- **It will not fetch an enormous image original.** Images above 128 MiB are skipped. Videos are not
  size-limited, because a frame is streamed rather than the whole file read.

The disk cache is managed in Settings → `Storage & updates` → `Preview cache`, which shows how much
is on disk and offers `Clear cache`.

## Files stored online only

A folder synced by OneDrive, Proton Drive, iCloud or Dropbox can hold files that are not really on
the disk — only a placeholder. Opening one makes the system fetch the whole file first. Airclone
recognises these on **Windows** (Files On-Demand) and on **macOS** (File Provider), and marks them in
the file list with a **cloud outline** instead of the usual type icon, so you can see which files
would need downloading before you touch them. **Folders are marked the same way** when the provider
says the folder's contents are not here — worth seeing before opening one that would pull down
gigabytes.

Asking for one thumbnail anyway is a right-click: `Show thumbnail (downloads it)`. That choice lasts
for the session and is not remembered, because a decision made on home wifi should not still apply
on a hotel connection next week.

**Browsing costs nothing.** Names, sizes, dates, sorting, searching, renaming and moving all read the
placeholder, never the file, so you can work through a synced folder freely on any connection.

**Reading the contents is what downloads it,** and Airclone always asks first:

| Action | What happens |
| :--- | :--- |
| Browse, sort, search, rename, move | Free. Nothing is downloaded. |
| Preview / Quick Look | **Asks.** Shows the size and a `Download & preview` button. |
| Checksum | **Asks**, the same way. |
| Thumbnail | Skipped, and the file shows a cloud outline instead. Right-click → `Show thumbnail (downloads it)` if you want one for that file. |
| Duplicate scan | Skips them, and tells you how many it skipped and how much they hold. |
| Download, Copy, Sync, Backup | **Proceeds.** Downloading is the thing you asked for. |

That last row is the deliberate exception. Everywhere else a download would be a side effect of
looking at something; in a transfer it is the point, and asking twice would just be nagging.

## The item menu

Right-click an item on the desktop, or long-press it on a phone. What you get depends on the item
and on the platform, which is why the list is not identical everywhere:

| Item | Where it appears |
|---|---|
| `Select` | touch only — this is the way into multi-select |
| `Open` | folders |
| `Preview` | files |
| `Open in another app…` | where handing the file to another app is possible |
| `Open with default app` | local files on desktop |
| `Show in File Explorer` | local files, on builds allowed to start another program — not the Mac App Store build, not iOS, not Android |
| `Download` | files on a cloud remote, everywhere except Android |
| `Copy path`, `Checksums…` | always (Checksums for files) |
| `Copy`, `Cut`, `Paste` | always (Paste when something is on the clipboard) |
| `Copy to…`, `Move to…`, `Open in other pane` | always |
| `Set as sync source`, `Sync … into this folder…` | folders, Advanced mode only |
| `Compress…` | builds allowed to start another program |
| `Extract here`, `Extract to…`, `List contents…` | the same builds, and only on a recognised archive |
| `Rename`, `Delete` | always |
| `Get public link` | only when the backend supports it |

There is no `Download` item on Android. Android's folder picker hands back a kind of address that
rclone's local backend cannot write to, so on a phone you copy the file and paste it into a local
folder instead.

Right-clicking or long-pressing **empty space** in a pane gives a shorter menu: `Paste`,
`New folder`, `Refresh`, `Select all`, plus the sync-source items in Advanced mode.

Deleting always confirms first, and the wording is blunt on purpose:
"This permanently deletes the folder and everything inside it. This cannot be undone." There is no
undo and no trash of Airclone's own — what the remote itself does with a deleted file is the
remote's business.

## Drag and drop

Dragging is a **desktop** gesture. On Android and iOS it is switched off deliberately, because the
long press that would start a drag is the long press that opens the item menu.

On the desktop you can:

- Drag items from one pane onto the other, or onto a folder tile or row, to copy them there.
- Drag files in from Explorer, Finder or your Linux file manager to upload them into the folder
  you drop them on.
- Drag a **local** file out of Airclone onto the desktop or a file manager window to copy it out.
  This works for files on a local disk only — a file on a cloud remote has no path for the
  operating system to fetch — and the drag carries the first file of a multiple selection.

Dragging near the top or bottom of a list scrolls it.

## Folder tools

The desktop `Tools` menu, and the phone's `⋯` sheet, carry the things that act on the whole folder:

| Item | Desktop | Phone |
|---|---|---|
| `Copy / Move / Sync this folder…` | `Tools` menu | `⋯` → `ADVANCED` |
| `Compare with other pane` | `Tools` menu | `⋯` → `ADVANCED` |
| `Upload from URL…` | `Tools` menu | the `+` button → `Upload from URL` |
| `Folder size` | `Tools` menu | `⋯` → `Tools` |
| `Storage breakdown…` | `Tools` menu | `⋯` → `Tools` |
| `Empty trash…` | `Tools` menu | `⋯` → `Tools` |

Copying, moving and syncing are covered in [moving files around](transferring.md).

## When a folder looks empty

Three different messages, three different meanings:

- **`Empty folder`** — the remote listed the folder and there was nothing in it.
- **`No matches`** — there are items, but your filter is hiding all of them. Clear the filter box.
- **`N items hidden`**, with a padlock — this appears on an encrypted (crypt) remote. rclone could
  not decrypt a single name, so it returned none of them, and the folder is **not** empty. Almost
  always the crypt remote's password or salt does not match the data it is wrapping. If only some
  entries were withheld you get the same fact as a strip above a listing that did come back.

That last message exists because "Empty folder" would be a lie there, and an expensive one — it
sends people looking for missing data instead of a mistyped password.

## Keyboard shortcuts

These work in the desktop shell. **The phone shell has no keyboard shortcuts.** Press `F1` at any
time to see the list in the app; this is the whole of it.

| Keys | Does |
|---|---|
| `Ctrl + K` | Command palette |
| `Ctrl + Shift + F` | Search subfolders |
| `Alt + ←` | Back |
| `Alt + →` | Forward |
| `Alt + ↑` | Up a folder |
| `Ctrl + F` | Filter the list |
| type… | Jump to a name |
| `Ctrl + T` | New tab |
| `Ctrl + W` | Close tab |
| `Ctrl + I` | Toggle details |
| `Ctrl + A` | Select all |
| `Esc` | Clear selection |
| `Enter` | Open folder / preview file |
| `Space` | Quick Look |
| `F2` | Rename |
| `Del` | Delete |
| `Ctrl + C` | Copy |
| `Ctrl + X` | Cut |
| `Ctrl + V` | Paste |

Four more are bound but not printed in that dialog: `F1` opens it, `F5` refreshes the active pane,
`Ctrl + L` and `Alt + D` focus the address bar for typing a path, and `Backspace` goes up one
folder.

Typing plain letters jumps to the first item whose name starts with what you typed; the buffer
clears after about a second of not typing.

None of these fire while you are typing in the filter box or the address bar. The keys belong to the
field you are in.

## Where next

- [Moving files around](transferring.md) — copy, move, sync, and what the confirmations protect you
  from
- [Backing up a folder](backup.md)
- [Scheduling](scheduling.md) — and which platforms can run a task while Airclone is closed
- [Mounting and sharing](mount-and-share.md) — desktop only
- [The command console](console.md)
- [Config and moving between devices](config-and-devices.md)
- [Troubleshooting](troubleshooting.md)
