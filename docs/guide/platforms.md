# What works on each platform

Airclone is one app on every platform, but each operating system and each store puts limits on it.
This page shows what you get on each build. It also shows which features need **Advanced mode**, and
explains *why* a feature is missing where it is.

A missing feature is usually missing for one of three reasons:

- **The platform cannot do it.** For example, a phone has no way to mount a network drive.
- **The store forbids it.** For example, the Mac App Store does not allow an app to start another
  program.
- **We have not built it yet.** Those are marked ⏳, and each one could change in a future release.

## How to read the tables

| Mark | Meaning |
| :---: | :--- |
| ✅ | Available. |
| ⚠️ | Available, with a condition. The notes under the table say what it is. |
| ⏳ | Not yet. The platform allows it, but it has not been built. |
| ❌ | Not available on this platform or build, and the [reasons below](#why-some-features-are-missing) say why. |
| 🔧 | Hidden until you turn on **Advanced mode** (Settings, at the top). |

**The columns are builds, not just operating systems.** The same operating system can have two
builds with different limits:

- **Windows** is the installer or the portable zip. **Windows (MS Store)** is the Microsoft Store
  package; the `.msix` on the Releases page is that same package and behaves the same way. The only
  difference between the two columns is how the app and its rclone engine are updated.
- **macOS** is the signed download from GitHub. **macOS (App Store)** is the Mac App Store build,
  which runs inside Apple's App Sandbox and has real limits (see below).
- **Linux** is the AppImage or the tar.gz. **Linux (Flatpak)** is the Flatpak, from Flathub or from
  the Releases page.
- **Android** is the same build whether it comes from **Google Play** or the **APK** on the Releases
  page. Only updates differ: Play updates itself, and the APK tells you when a new version is out.
  **Android TV** is that same build on a television.
- **iPhone / iPad** comes from the App Store only.

**The layout follows the screen, not the device.** A window narrower than 700 pixels gets the phone
layout, with three tabs along the bottom. A wider one gets the desktop layout, with a sidebar, two
panes and a top bar. So an iPad or an Android tablet gets the desktop layout, and a desktop window
dragged narrow gets the phone layout. The ⚠️ marks for tablets below are about this.

## Browsing and files

| Feature | Advanced | Windows | Windows (MS Store) | macOS | macOS (App Store) | Linux | Linux (Flatpak) | Android | Android TV | iPhone / iPad |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| Browse every remote, previews, thumbnails, video and audio | | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Search, find duplicates, get a public link | | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Desktop layout (sidebar, two panes, top bar) | | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ tablets | ❌ | ⚠️ iPad |
| Tree view | | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| Drag and drop (between panes and to or from the OS) | | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| Keyboard shortcuts and the Ctrl+K command palette | | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ tablets | ❌ | ⚠️ iPad |
| Open a file in another app / share sheet | | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⏳ |
| Show in File Explorer / Finder / file manager | | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ |
| Compress, extract and list archives | | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ |
| Window backdrop (Mica / Acrylic) | | ✅ Win 11 | ✅ Win 11 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

- **Tablets** (⚠️) get these only in the desktop layout, which needs a window at least 700 pixels
  wide. Android TV always uses the phone layout, with the tabs as a side rail, and you drive it with
  the remote.

## Copying, syncing and transfers

| Feature | Advanced | Windows | Windows (MS Store) | macOS | macOS (App Store) | Linux | Linux (Flatpak) | Android | Android TV | iPhone / iPad |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| Copy, Move and Sync, with filters and dry run | | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Two-way sync (bisync) | 🔧 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Set as sync source, then Sync … into this folder | 🔧 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Transfer concurrency and engine flags | 🔧 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Bandwidth limit control | | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ tablets | ❌ | ⚠️ iPad |
| Default downloads folder | | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| Transfers keep going when you switch to another app | | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |

- **Copy, Move and Sync do not need Advanced mode.** The transfer dialog, including Sync, filters
  and dry run, is always reachable from the desktop `Tools` menu and the phone's **⋯** sheet.
  Advanced mode adds only the Two-way mode.
- **Android** keeps a transfer running in the background, with a notification. **iOS** suspends an
  app shortly after you leave it, so a transfer on an iPhone or iPad only runs while Airclone is on
  screen.

## Backup and scheduling

| Feature | Advanced | Windows | Windows (MS Store) | macOS | macOS (App Store) | Linux | Linux (Flatpak) | Android | Android TV | iPhone / iPad |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| Back up a folder (the wizard) and saved tasks | | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Scheduled tasks run while Airclone is open | | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⏳ |
| Scheduled tasks run with Airclone closed | | ✅ | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ✅ | ❌ |
| Camera-roll (photo) backup | | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ⚠️ | ❌ |

- **Saved tasks and Back up a folder do not need Advanced mode.** They are always in Settings →
  Automation. Advanced mode also puts a `Saved tasks` button in the desktop top bar.
- **On macOS and Linux**, a schedule runs while Airclone is open. A run missed while it was closed
  starts once on the next launch.
- **On iPhone and iPad** you run saved tasks by hand.
- **Android TV** shows the photo backup section, but a television has no camera roll to copy.

## Drives, sharing and remote access

| Feature | Advanced | Windows | Windows (MS Store) | macOS | macOS (App Store) | Linux | Linux (Flatpak) | Android | Android TV | iPhone / iPad |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| Mount a remote as a drive | 🔧 | ⚠️ WinFsp | ⚠️ WinFsp | ⚠️ macFUSE | ❌ | ⚠️ FUSE | ⚠️ permission | ❌ | ❌ | ❌ |
| Serve a remote on your network (HTTP, WebDAV, FTP, SFTP, DLNA) | 🔧 | ✅ | ✅ | ✅ | ⏳ | ✅ | ✅ | ❌ | ❌ | ❌ |
| Host the Web UI for other devices | | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| *Open* someone else's Web UI in your browser | | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

- **Mounting needs a driver you install yourself.** On Windows that is [WinFsp](https://winfsp.dev/).
  On macOS it is macFUSE or FUSE-T, and mounting on macOS has not yet been tested end to end. On
  Linux it is FUSE (`sudo apt install fuse3`). The Flatpak also needs one permission that you grant
  it; see [Mounting from the Flatpak](mount-and-share.md#mounting-from-the-flatpak-needs-one-permission).
- **Hosting the Web UI does not need Advanced mode.** It is in Settings → Remote access, or run
  `airclone --webui` on a desktop build. Any device with a browser can open it, phones included. You
  then see and control the *host's* files, disks and transfers; see [The Web UI](web-ui.md).

## Your remotes, security and the console

| Feature | Advanced | Windows | Windows (MS Store) | macOS | macOS (App Store) | Linux | Linux (Flatpak) | Android | Android TV | iPhone / iPad |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| Command console | 🔧 | ✅ | ✅ | ✅ | ⚠️ subset | ✅ | ✅ | ✅ | ✅ | ⚠️ subset |
| Encrypt the config with a password | | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Remember the config password in the OS vault | | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Unlock with fingerprint or face | | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ❌ | ✅ |
| Choose where the config file lives | | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ |
| Export a config as a file or a QR code | | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Import a QR by scanning it with the camera | | ⚠️ image | ⚠️ image | ✅ | ❌ | ⚠️ image | ⚠️ image | ✅ | ❌ | ✅ |
| Keep an encrypted config backup that survives uninstalling | | — | — | — | — | — | — | ✅ | ✅ | ❌ |
| Recent locations list | 🔧 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

- **The console on iPhone, iPad and the Mac App Store build** runs a translated subset of commands,
  not the full rclone command line, because those builds run rclone inside the app. See
  [The command console](console.md#two-engines-two-consoles).
- **"Image"** means that Windows and Linux have no camera scanner, but can read the QR code from a
  picture file you pick instead.
- **The uninstall-proof backup** is not needed on a computer (—), because a desktop config already
  lives outside the app and survives a reinstall. On Android, uninstalling deletes the app's private
  storage and your remotes with it, so this switch keeps an encrypted copy outside the app. See
  [Surviving an uninstall](config-and-devices.md#android-surviving-an-uninstall).

## The rclone engine and updates

| Feature | Advanced | Windows | Windows (MS Store) | macOS | macOS (App Store) | Linux | Linux (Flatpak) | Android | Android TV | iPhone / iPad |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| rclone engine included, nothing to download | | ✅ | ✅ | ⚠️ one click | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Update the rclone engine from Settings | | ✅ | ❌ | ✅ | ❌ | ✅ | ⚠️ | ❌ | ❌ | ❌ |
| Choose the engine (separate process or in-app) | | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ |
| The app updates itself | | ✅ | ✅ Store | ✅ | ✅ Store | ✅ | ⚠️ | ⚠️ Play only | ⚠️ Play only | ✅ Store |

- **macOS (downloaded build)** looks for an rclone already on your Mac. If it finds none, it offers
  a **Download rclone engine** button on first launch.
- **Engine updates.** Every store build updates its engine only when the app itself updates, through
  the store. The Flatpak from the Releases page can update its engine in Settings; the Flathub
  Flatpak cannot. Android and iOS always use the engine that shipped with the app.
- **App updates.** The Windows installer, the Windows portable zip, the macOS download, the Linux
  AppImage and the tar.gz can replace themselves from inside the app. The Flatpak from the Releases
  page and the Android APK tell you a new version is out, and you install it yourself. Flathub,
  Google Play and the other store builds make no request to GitHub at all; their store delivers the
  update.

## Why some features are missing

**Phones and tablets cannot mount a drive.** Mounting needs a filesystem driver (FUSE on Linux and
macOS, WinFsp on Windows) that plugs into the operating system. Android and iOS do not let an app
add one. To use a file in another app on a phone, use **Open in another app** or the share sheet.

**Phones and tablets do not serve to your network or host the Web UI.** A server has to stay
reachable, but a phone stops apps you are not looking at: iOS within seconds, Android whenever it
needs the memory or battery. A server that stops when the screen turns off is not something you can
point other devices at. The phone is where you *open* the Web UI, not where it runs.

**iPhone and iPad cannot start another program.** iOS gives apps no way to run a separate process,
so Airclone runs rclone inside the app itself. That rules out anything rclone offers only as a
separate command: archives, the full command-line console, and swapping in a different rclone. iOS
also pauses an app shortly after you leave it, so there is no scheduling with the app closed, and a
transfer only runs while Airclone is on screen.

**The Mac App Store build runs in Apple's App Sandbox.** A sandboxed app may only run code that was
signed with it, may only open the folders you choose for it, and cannot load a filesystem driver.
So that build runs rclone inside the app, like iOS, and cannot mount, show a file in Finder, work
with archives, or download a newer engine. Serving to your network is turned off in that build to
keep Apple's review simple; the sandbox would allow it. **If you need these on a Mac, use the signed
download from the Releases page.** It is the same app without the sandbox.

**The Microsoft Store build is a packaged (MSIX) app.** Windows checks that a packaged app's files
match what the Store signed, so it cannot replace its own rclone engine or update itself. Both
arrive with Store updates instead. Everything else is the same as the installer.

**The Flatpak runs in a sandbox too.** It can do almost everything the AppImage can. A drive it
mounted inside its own sandbox would be visible only to Airclone, so mounting uses a helper outside
the sandbox, which needs a permission you grant once. The Flathub build also does not download
engines, because Flathub reviews and delivers what runs.

**Android TV has no camera, and usually no file picker.** QR scanning and the camera-roll backup
have nothing to work with on a television. A stock Android TV also has no file picker, so
`Import File Config` works only on TVs whose maker added a file manager.

**Drag and drop, and the tree view, are desktop features.** On a touch screen, long-pressing an item
opens its menu, which is the same gesture a drag would need. A tree with indentation and three
columns does not fit on a phone.

**Background scheduling on macOS and Linux is not built yet.** Windows uses Task Scheduler and
Android uses WorkManager. The macOS (launchd) and Linux (systemd) versions are planned. Until they
exist, the app says plainly that a schedule runs only while it is open, rather than letting you
close it and expect a backup that never happens.

## Why Advanced mode exists

Airclone starts in a deliberately small mode, and the 🔧 features stay hidden until you switch
Advanced mode on at the top of Settings. The features behind it either **can delete files** (Two-way
sync, Sync into a marked folder), **expose your storage beyond the app** (mounting, serving), or
**run rclone directly** (the console, engine flags). None of that belongs in front of someone who
just wants to drag a folder to a cloud drive.

Advanced mode is per device, and it only hides things. Turning it off does not undo a mount, a
server or a task you already set up. The full list is in
[Getting started → Advanced mode](getting-started.md#advanced-mode).

## Related pages

- [Getting started](getting-started.md): installing on each platform and the first launch
- [Mounting a drive and sharing](mount-and-share.md): the mount drivers and the Flatpak permission
- [Running tasks on a schedule](scheduling.md): what "run while Airclone is closed" arranges on each platform
- [The Web UI](web-ui.md): hosting Airclone for a browser on another device
- [Your remotes, and moving them between devices](config-and-devices.md): where the config lives, and QR transfer
