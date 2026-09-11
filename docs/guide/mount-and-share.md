# Mounting a drive and sharing

There are two ways to hand a cloud remote to the rest of your machine, and a third way to hand one
file to another person.

- **Mount** turns a remote into a drive the whole operating system can see, so any program can open
  files on it.
- **Serve** starts a small server on your computer that speaks HTTP, WebDAV, FTP, SFTP or DLNA, so
  another app or another device on your network can reach the remote.
- **Get public link** asks the cloud provider itself for a shareable URL to one file or folder.

The first two live behind **Advanced mode** and appear only in the desktop layout. The third is
available to everyone, on every platform, wherever the backend supports it.

If you have not set up a remote yet, start with [getting started](getting-started.md).

## Turning on Advanced mode

Open **Settings**. The first card is **Advanced mode**. Its own description reads:

> Power-user features: Sync, include/exclude/filter, dry-run, and saved + scheduled tasks.

That description does not mention mounting or serving, but Advanced mode is what reveals both. With
it on, two more buttons appear in the desktop top bar, to the right of the transfers button:

| Button tooltip | Opens |
|---|---|
| `Serve / Share on LAN` | the serve manager |
| `Mount as a drive` | the mount manager |

Both are also in the command palette (`Ctrl + K`) under the same names.

Advanced mode is off by default and is remembered per device, not per remote.

## Where mounting works

Mounting needs a filesystem driver that only a desktop operating system provides.

| Platform | Mount button | Notes |
|---|---|---|
| Windows | Yes | Needs WinFsp installed first. See below. |
| macOS (downloaded build) | Yes | Needs a FUSE driver installed separately. |
| Linux — AppImage or tar.gz | Yes | Needs FUSE installed separately. |
| Linux — **Flatpak** | No | The button is there and explains why when pressed. See below. |
| macOS from the Mac App Store | No | Hidden entirely. The App Sandbox cannot run FUSE, so the button and the Settings → Mounts group do not appear rather than failing when pressed. |
| Android, iOS | No | Not supported. |

### The Flatpak cannot mount, and no setting changes that

If you installed Airclone as a Flatpak — from a software centre, or with
`flatpak install` — mounting is the one feature you do not have. Pressing **Mount as a drive**
explains this rather than failing.

It is not a permission you can grant, so there is nothing to look for in Flatseal. A Flatpak runs
with its own view of the filesystem, so a drive mounted inside it would be visible **only to
Airclone** — not to your file manager, not to your editor — and other programs seeing the files is
the entire reason to mount one.

If you want a mounted drive on Linux, use the **AppImage** or the **tar.gz** instead; both can. If
you only want to work with your files inside Airclone, you do not need a mount at all — browsing a
remote directly is usually faster than one (see [below](#why-the-in-app-explorer-is-usually-faster)).

Two things about the button that are worth knowing before you hunt for it:

- **The phone layout has no mount manager at all.** The shell is chosen by window width: below 700
  logical pixels you get the phone layout, which has no top bar and no command palette. Narrowing a
  desktop window past that point takes the button away with it.
- **The desktop layout also appears on large tablets.** An iPad or an Android tablet 700 pixels wide
  or more gets the desktop layout, so with Advanced mode on the `Mount as a drive` button can be
  visible there. Those systems still cannot provide a mounted drive. Treat mounting as a desktop
  feature.

An organisation can also switch mounting off for a whole fleet. When that has been done, the manager
opens and says `Mounting is disabled by policy.` and nothing can be started from it.

### One real limitation today

The mount manager asks for a **drive letter**: either `Auto (next free letter)` or a specific letter
from `D:` to `Z:`. There is no field for choosing a folder to mount into, which is how mounting works
on macOS and Linux. In this release the mount manager is built around the Windows model.

### Installing WinFsp on Windows

Airclone does not install the driver for you. When the engine reports that no mount type is
available, the manager shows this banner at the top:

> Mounting on Windows needs WinFsp. Install it from winfsp.dev, then restart Airclone.

Install WinFsp, close Airclone completely, and open it again. The banner goes away once the engine
can see the driver.

## Mounting a remote

The engine has to be running: the status bar at the bottom of the window should read
`engine ok · rclone <version>`.

1. Press the `Mount as a drive` button.
2. **Remote** — pick the remote to mount. The list also contains `This device`, the built-in shortcut
   to your home folder; that is not a configured remote, so it is not a useful thing to mount.
3. **Subfolder** — optional. Leave it empty to mount the whole remote, or type a path to mount just
   that folder.
4. **Drive** — `Auto (next free letter)`, or pick a letter yourself.
5. Tick the box under the dropdown if you want the same letter next time. With a letter chosen it
   reads `Always mount this on X:`; with `Auto` chosen it reads
   `Reuse whichever letter this mount gets, next time`, and the letter is remembered after the mount
   succeeds — whatever was actually assigned.
6. Press **Mount**.

The letter is remembered per mounted path, not per remote, so `gdrive:` and `gdrive:work` can each
keep their own. Unticking the box forgets the pin rather than leaving a stale one behind.

If the mount fails, the reason is shown in red inside the dialog.

## Tuning a mount

Under the drive row is a collapsed **Tuning** section. Its one-line summary shows what the mount will
start with, for example `Cache: full · 10Gi · 24h`. If you change anything it gains a
`(N changed)` suffix and a `Reset to defaults` button, so you can always tell whether you are looking
at your defaults or at a deviation from them.

| Option | Ships as | What the app says about it |
|---|---|---|
| Cache mode | `full (recommended)` | "full caches reads, so a folder is only downloaded once." |
| Cache size | `10Gi` | "Per mount, not shared." Three mounts at this setting is three times the disk. |
| Keep cached for | `24h` | "Time since a file was last read." |
| Directory cache | `5m` | "How long a folder listing is reused." |
| Read chunk | `32Mi` | "Smaller is faster to open a file." |
| Chunk grows to | `1Gi` | "Chunks double up to here for big reads." |
| Attribute cache | `5s` | "How long file details are reused." |
| Fast change detection | on | "Fewer round-trips deciding whether a file changed. Slightly less precise." |
| Mount as a network drive | off | Windows only. "Windows stops treating it as local storage, so the search indexer leaves it alone. It appears under Network rather than as a normal drive." |

Cache size and Keep cached for are greyed out unless the cache mode is `full` or `writes` — nothing
is being cached to disk in the other modes, so there is nothing to bound.

Changes made here apply **to this mount only**. The note under the section says so:

> Applies to this mount only. Change what new mounts start with in Settings.

To change what every future mount starts from, use **Settings → Mounts → Defaults for new mounts**
(desktop only, and only where mounting is available). That section carries its own warning:

> Changing these does not affect a mount that is already running - unmount and mount it again to
> apply them.

That is not a shortcoming of the settings screen. rclone fixes these options at the moment a mount
starts and offers no way to change them afterwards. A `Restore recommended` button appears once you
have changed anything away from what Airclone ships.

## Managing mounted drives

The lower half of the mount manager is **Mounted drives**. With nothing mounted it reads
`Nothing mounted.` Each live mount gets a row showing its drive letter and the path it is serving,
with two buttons:

- **Refresh cache (pick up outside changes)** — re-reads the folder listings so changes made
  elsewhere (from another device, or in Airclone's own explorer) show up in the mounted drive without
  unmounting. On a large remote this runs in the background and the dialog says so.
- **Unmount** — disconnects that drive.

**Unmount all** at the top right of the section disconnects everything at once.

Mounts are not remembered. Nothing is written to disk about them, so a mount never comes back by
itself after you quit — you mount again when you need it.

### Closing Airclone with a drive still mounted

Mounted drives are the one thing closing Airclone takes away from other programs, so the close stops
and asks first:

> `<drive>` is mounted through Airclone. Closing disconnects it — any app still using that drive may
> lose unsaved work.

The buttons are `Keep Airclone open` and `Disconnect and close`. Clicking outside the dialog does not
dismiss it, and counts as neither answer — the app stays open. If you confirm, Airclone unmounts
first and stops the engine afterwards, so you are never left with a drive letter that looks alive but
is backed by nothing.

## Why the in-app explorer is usually faster

Airclone's own file list talks to the cloud service directly and asks only for what it is showing.
A mount cannot do that. It has to present the remote to every program on the machine as if it were a
local disk, which means answering whatever the operating system asks of a disk: thumbnails, search
indexing, repeated checks on files nobody opened. That is why the mount caches so heavily by default,
and why a busy mount can feel slow in Explorer or Finder while Airclone's own window stays quick.

Use a mount when another program must open the files — an editor, a video player, a build script.
Use Airclone's explorer to browse, copy and move. See [browsing your files](browsing.md) and
[copying, moving and syncing](transferring.md).

## Serving a remote on your network

**Serve** starts a small server inside Airclone that exposes a remote over a network protocol. It is
useful for pointing another program at a remote (a WebDAV-aware app, an FTP client) or for streaming
media to a TV.

Like mounting, it sits behind Advanced mode, is reachable only from the desktop layout, and is hidden
in the Mac App Store build. When it has been switched off by policy the dialog says
`Serving is disabled by policy.`

### Starting a server

1. Press the `Serve / Share on LAN` button.
2. **Remote** and **Subfolder** — the same pair as the mount manager.
3. **Protocol** — the list is whatever your engine supports, out of these five:

   | Protocol | Default port | Username and password |
   |---|---|---|
   | HTTP | 8080 | supported |
   | WEBDAV | 8080 | supported |
   | FTP | 2121 | supported |
   | SFTP | 2022 | supported |
   | DLNA | 8200 | none — the protocol has no concept of it |

4. **Port** — pre-filled with the default for the protocol; change it if something else is using it.
5. **Reachable from** — `This device only` (the default) or `My local network`.
6. **Read-only** — a switch, off by default. Turn it on if the other end should not be able to change
   or delete anything.
7. Press **Start server**.

### What the app refuses, and why

- **`This device only` is the default.** It binds to your machine's loopback address, so nothing
  outside the computer can connect, whatever your firewall is set to.
- **A network server must have a username and password.** Choosing `My local network` on HTTP,
  WebDAV, FTP or SFTP makes the Username and Password fields appear, and `Start server` stays
  disabled until both are filled in. This is enforced where the server is actually started, not just
  in the dialog, so there is no path to an unauthenticated server on your network.
- **DLNA has to be acknowledged instead.** DLNA cannot authenticate at all, so serving it to your
  network shows a tick box you have to confirm:
  `I understand DLNA has no password — anyone on my network can stream this.`
- **Choosing `My local network` shows a warning either way.** For DLNA:
  "Anyone on your local network can browse and stream this — DLNA has no password." For everything
  else: "This will be reachable by other devices on your network. It stops when Airclone's engine
  restarts or the app quits."

That last sentence is the important one. A server is not a background service. It lives inside the
running app, nothing about it is saved, and quitting Airclone or restarting the engine ends it.

### What it will not do

- There are no certificate or TLS settings. HTTP, WebDAV and FTP traffic crosses your network
  unencrypted.
- Nothing here opens a port on your router or makes anything reachable from the internet.
  "My local network" means exactly that.
- No server restarts itself when you reopen Airclone.

### Running servers

The lower half of the dialog is **Running servers**, or `No servers running.` Each row shows the
protocol and path, the URL, and whether it is `this device only` or `reachable on your network` —
with a padlock icon for the first and an open globe for the second. A DLNA row shows
`DLNA on port <port>` instead of a URL, because there is nothing to paste into a browser.

Each row has:

- **Open in browser** — only for HTTP and WebDAV, which browsers can speak.
- **Copy URL** — puts the address on the clipboard to paste into another device.
- **Stop**.

**Stop all** at the top right stops every running server at once.

## Public links

Some cloud services can mint a URL that lets anyone open one file or folder. Where the backend
supports it, Airclone can ask for one. This is not Advanced-mode gated and works on every platform.

To find out whether a remote supports it, select a file and open the details panel (`Ctrl + I` on the
desktop), then the **More** tab: the row **Public links** reads `yes` or `no`.

Two ways in:

- Right-click a file or folder (long-press on a touchscreen) and choose **Get public link**. The item
  only appears when the backend reports support.
- In the details panel's **Overview** tab, the **Copy link** pill. It opens the same dialog rather
  than copying immediately.

The dialog is titled **Public link**. Before a link exists, it offers an **Expires** dropdown:

| Choice |
|---|
| `No expiry` (the default) |
| `1 hour` |
| `1 day` |
| `1 week` |
| `1 month` |

Pick anything other than `No expiry` and a note appears:
"Some backends ignore expiry — treat it as best-effort." Airclone passes your choice to the provider;
whether it is honoured is the provider's decision, not Airclone's.

Press **Create link**. The URL appears in the dialog, selectable, with three buttons: **Copy**
(confirmed by `Link copied.`), **Revoke** (confirmed by `Link revoked.`), and **Close**.

What this will not do:

- Airclone does not host anything and the link does not pass through Airclone. It is created by, and
  served by, the cloud service holding the file.
- Some remotes accept the request and return nothing, in which case the dialog says
  "No link returned (this remote may not support it)."
- Revoking asks the provider to withdraw the link. As with expiry, the provider decides what that
  means.

## If something does not work

Common causes: the engine is not running (check the status bar), Advanced mode is off (the buttons
are simply absent), the window is under 700 pixels wide (the phone layout has neither manager), or
WinFsp is not installed. For anything else, see [troubleshooting](troubleshooting.md).

The [command console](console.md) can also run rclone commands directly if you want to see what the
engine says about a mount or a server.

## Related

- [Getting started](getting-started.md)
- [Browsing your files](browsing.md)
- [Copying, moving and syncing](transferring.md)
- [Troubleshooting](troubleshooting.md)
- [All guide pages](README.md)
