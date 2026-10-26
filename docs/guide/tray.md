# Keeping Airclone in the tray

On Windows, macOS and Linux, Airclone puts an icon in the system tray: the notification area on
Windows, the menu bar on macOS, and the status icons area on Linux. From there you can see what it
is doing and control it with the window closed. You can also have it quit as before when you close
the window, or start it hidden when you sign in.

None of this exists on Android, iPhone, iPad or in the Web UI. Phones have no tray, and the Web UI
is a browser tab.

## Closing the window

Settings → Tray → **Closing the window keeps Airclone running in the tray**.

- **Off (the default):** closing the window quits Airclone, as it always has. Transfers that are
  still running stop, and so do mounted drives and servers.
- **On:** closing the window only hides it. Airclone keeps running in the tray, and you quit from
  the tray icon (**Quit Airclone**), or with Cmd-Q on macOS.

**If you have never chosen and something is still running**, closing the window asks once: *Keep
running in the tray*, *Quit Airclone* or *Cancel*. Your answer is saved as the setting above, so you
are not asked again. Closing an idle window just quits.

The switch is greyed out when there is no tray to hide in. Closing the window then always quits,
so Airclone never ends up running with no window and no icon. See [Linux needs a tray
host](#linux-needs-a-tray-host).

On **Windows only**, Settings → Tray → **Minimizing the window hides it to the tray**
lets the minimize button hide the window too. It is **off by default**, independent of the
close-to-tray setting, and disabled without a tray icon. Click the tray icon or choose
**Open Airclone** from its menu to restore the window; transfers, mounts and schedules keep running.

## What keeps running in the tray

Everything that runs while the window is open keeps running while it is hidden:

- **Transfers**, including the ones waiting in the queue.
- **Mounted drives and servers** (HTTP, WebDAV, FTP, SFTP, DLNA, and the Web UI).
- **Scheduled tasks.** On macOS and Linux, where [schedules run only while Airclone is
  open](platforms.md#backup-and-scheduling), the tray is how you keep them running all day without a
  window on screen. See [Running tasks on a schedule](scheduling.md).

## The tray menu

| Item | What it does |
| :--- | :--- |
| *Status line* | What Airclone is doing now: `Idle`, or something like `Transferring 2 files, 4.1 MB/s, 3 min left · 1 queued · Limit 5M/s`. On Linux it updates at most every two seconds. On Windows and macOS the hover text carries the live status, and the menu line refreshes when you pause, resume or change the limit. |
| **Open Airclone** | Shows the window again. |
| **Pause all** / **Resume all** | Pauses the queue. Transfers waiting in the queue wait. Transfers already running finish, because stopping one halfway would leave a partial file. **Resume all** lets the queue go again. |
| **Bandwidth limit** | Sets the speed limit for every transfer: Unlimited, 1, 5, 10, 50 or 100 MB/s. A limit you set elsewhere in the app shows up here as well, ticked. It is greyed out while the engine is still starting. |
| **Quit Airclone** | Quits for real, the same as quitting with the window open. If a drive is mounted, you are asked first. |

On **Windows** a left click opens the window and a right click opens the menu. Hovering over the icon
shows the same status as the status line. On **macOS** any click opens the menu. On **Linux** your
desktop decides how the menu opens, and there is no hover text, so the status line in the menu is
the only place the status appears.

## Starting in the tray when you sign in

Settings → Tray → **Start Airclone in the tray when I sign in**. When it is on, Airclone starts
hidden in the tray each time you sign in, with no window. Open it from the tray icon.

| Build | How it is done | Notes |
| :--- | :--- | :--- |
| Windows (installer, portable) | A `HKCU\…\CurrentVersion\Run` value named `Airclone` | You can see it in Task Manager → Startup apps. Uninstalling the installed version removes it. |
| Windows (Microsoft Store) | Not offered yet | A Store app has to register a startup task in its package. That is not built yet. |
| macOS (direct download and Mac App Store) | A login item | Needs macOS 13 or later. It appears in System Settings → General → Login Items, where you can remove it too. |
| Linux (AppImage, tarball) | `~/.config/autostart/com.gigaionllc.airclone.desktop` | For the AppImage, the entry points at the `.AppImage` file. If you move that file, turn the switch off and on again. |
| Linux (Flatpak) | Not offered | The sandbox cannot add itself to your startup applications. Add Airclone in your desktop's startup settings yourself and give it `--tray`, as in `flatpak run com.gigaionllc.airclone --tray`. |

There is no Snap package. Where the switch is not offered, Settings says why in its place.

Each entry starts Airclone's own program file, with `--tray` and nothing else.

### `--tray`

`airclone --tray` starts Airclone hidden in the tray, which is what the sign-in entry does. If there
is no tray to start in, it opens the window instead, so a launch never stays invisible.

**Only one Airclone window runs at a time.** If Airclone is already in the tray and you start it
again from the Start menu, the dock or your app launcher, the running copy shows its window and the
new launch exits. Command-line runs such as `--run-task` and `--webui` are not affected, so
scheduled runs still happen while the app is open.

## Linux needs a tray host

Linux desktops show tray icons through the StatusNotifier (AppIndicator) protocol, and only if the
desktop has a host for them.

- **KDE Plasma, Cinnamon, Xfce, MATE, Budgie, and Ubuntu's GNOME** have one already.
- **Plain GNOME** (Fedora, Debian, Arch and others) has none until you install the *AppIndicator
  and KStatusNotifierItem Support* extension (`gnome-shell-extension-appindicator` in most
  distributions). After you install it, sign out and back in.

Without a host, Airclone runs without an icon, the close-to-tray switch is greyed out, and closing
the window quits.

The AppImage and the Flatpak bring the library they need with them (`libayatana-appindicator3`). The
tarball needs it installed, which the [README](../../README.md) lists with the other libraries.

## When something goes wrong

**The switch is greyed out on Linux.** Your desktop has no tray host. See [Linux needs a tray
host](#linux-needs-a-tray-host).

**There is no icon after signing in, but Airclone is running.** On GNOME, the tray extension may
have loaded after Airclone did. Start Airclone again: the running copy opens its window.

**The window took a moment to come forward on Linux (Wayland).** Some Wayland desktops do not let
an app bring itself to the front. They flash its entry in the dock or taskbar instead. Click it.

## Related pages

- [What works on each platform](platforms.md): the tray rows in the scheduling table
- [Running tasks on a schedule](scheduling.md): what runs with the window closed
- [Copying, moving and syncing](transferring.md): what pausing the queue really does
