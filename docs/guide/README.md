# Airclone user guide

Airclone is a file manager for cloud storage. It connects straight from your own device to the
storage accounts you tell it about — Google Drive, OneDrive, Dropbox, S3, SFTP, WebDAV and dozens
more — and lets you browse them, copy files between them, and keep folders backed up. Underneath it
uses [rclone](https://rclone.org/), so anything rclone can reach, Airclone can show you.

There is no Airclone account and nothing is reported back to us. You sign in to your own storage
providers, those connections are stored on your device, and every transfer runs between your device
and the provider.

**Start here:** [Getting started](getting-started.md) — installing it, the first launch, and adding
your first cloud connection.

## The pages

| Page | What it covers |
| :--- | :--- |
| **[What works on each platform](platforms.md)** | A checklist of every feature on every build (Windows, Microsoft Store, macOS, Mac App Store, Linux, Flatpak, Android, Android TV, iPhone and iPad), which features need Advanced mode, and why some are missing. |
| [Getting started](getting-started.md) | Installing Airclone on each platform, the first-launch engine setup, what a remote is, adding and testing your first one, and what Advanced mode turns on. |
| [Browsing your files](browsing.md) | Panes, tabs, view modes, sorting, filter versus search, selection, the details panel, Quick Look, thumbnails and drag-and-drop. |
| [Copying, moving and syncing](transferring.md) | The four transfer modes and why only Sync can lose data, dry runs and the preview, the conflict prompt, and the transfers list — including what pause really does. |
| [Backing up a folder](backup.md) | The Back up a folder wizard, where the files land, why a backup only ever copies, how replaced files are kept as versions, the retention window, and how to restore. |
| [Running tasks on a schedule](scheduling.md) | Saved tasks, the schedule kinds, what "run while Airclone is closed" arranges on each platform, and the delete cap and pause that protect a repeating sync. |
| [Backing up your photos (Android)](photos-android.md) | Android-only camera-roll backup: setting it up, what it copies, where it lands, the Wi-Fi and charging constraints, and the permissions Airclone asks for. |
| [Mounting a drive and sharing](mount-and-share.md) | Mounting a remote as a drive, serving it over HTTP, WebDAV, FTP, SFTP or DLNA on your network, and asking a provider for a public link. |
| [Your remotes, and moving them between devices](config-and-devices.md) | Where your rclone config lives on each platform, how to lock it with a password, and the three ways to carry your remotes to another device. |
| [The Web UI](web-ui.md) | Opening Airclone in a browser on another device: starting it from Settings or with `--webui`, who can reach it, the generated password, and why every mount and every transfer still happens on the machine running Airclone. |
| [The command console](console.md) | The built-in rclone command console: how to open it, what it runs, what it refuses and why, and how it differs between the two engines. |
| [When something goes wrong](troubleshooting.md) | Symptom-to-cause troubleshooting, and where the local Problem report lives. |

## Which platform are you on?

Airclone is one application on Windows, macOS, Linux, Android (phone, tablet and TV) and iOS, but
the platforms genuinely differ. These are the differences worth knowing before you plan anything
around them.

**The layout follows the window, not the operating system.** Below 700 logical pixels wide you get
the phone shell — three tabs along the bottom, `Files`, `Transfers` and `Settings`. At 700 or wider
you get the desktop shell — a top bar, a sidebar, one or two panes and a status bar. So an Android
tablet and an iPad get the desktop layout, a desktop window dragged narrow switches to the phone
layout, and an Android TV always uses the phone shell with the tabs as a side rail. The layouts are
compared in [Browsing your files](browsing.md).

**The full platform-by-platform checklist is on its own page: [What works on each
platform](platforms.md).** It covers every build, including the Microsoft Store, Mac App Store,
Flatpak, Google Play and Android TV builds. It marks which features need Advanced mode and explains
why each missing feature is missing.

Two more differences that catch people out: the rclone engine ships inside the app on Windows,
Android and Linux, is downloaded on first launch on the macOS direct-download build, and runs inside
the app itself on iPhone, iPad and the Mac App Store build
([Getting started](getting-started.md)); and your rclone config sits in an ordinary folder on
desktop but in private app storage on Android and iOS, where uninstalling the app deletes it
([Your remotes, and moving them between devices](config-and-devices.md)).

## What this guide is not

- **Bug reports, feature requests and contributing.** This guide explains how to use the app. The
  project [README](../../README.md) is where the repository, the releases and the development
  documentation are.
- **Privacy and data handling.** The full statement — what stays on your device, what network
  connections Airclone makes, and what it never collects — is in [PRIVACY](../../PRIVACY.md).
  [When something goes wrong](troubleshooting.md) covers the local Problem report, which leaves your
  device only when you send it.
- **rclone itself.** Airclone drives rclone but does not document it. For what a particular backend
  supports, or what a flag does, see [rclone.org](https://rclone.org/).
