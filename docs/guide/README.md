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
| [Getting started](getting-started.md) | Installing Airclone on each platform, the first-launch engine setup, what a remote is, adding and testing your first one, and what Advanced mode turns on. |
| [Browsing your files](browsing.md) | Panes, tabs, view modes, sorting, filter versus search, selection, the details panel, Quick Look, thumbnails and drag-and-drop. |
| [Copying, moving and syncing](transferring.md) | The four transfer modes and why only Sync can lose data, dry runs and the preview, the conflict prompt, and the transfers list — including what pause really does. |
| [Backing up a folder](backup.md) | The Back up a folder wizard, where the files land, why a backup only ever copies, how replaced files are kept as versions, the retention window, and how to restore. |
| [Running tasks on a schedule](scheduling.md) | Saved tasks, the schedule kinds, what "run while Airclone is closed" arranges on each platform, and the delete cap and pause that protect a repeating sync. |
| [Backing up your photos (Android)](photos-android.md) | Android-only camera-roll backup: setting it up, what it copies, where it lands, the Wi-Fi and charging constraints, and the permissions Airclone asks for. |
| [Mounting a drive and sharing](mount-and-share.md) | Mounting a remote as a drive, serving it over HTTP, WebDAV, FTP, SFTP or DLNA on your network, and asking a provider for a public link. |
| [Your remotes, and moving them between devices](config-and-devices.md) | Where your rclone config lives on each platform, how to lock it with a password, and the three ways to carry your remotes to another device. |
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

| Capability | Windows | macOS | Linux | Android | iOS |
| :--- | :--- | :--- | :--- | :--- | :--- |
| Scheduled tasks run while Airclone is open | yes | yes | yes | yes | no |
| Scheduled tasks run with Airclone closed | yes | no | no | yes | no |
| Mount a remote as a drive | yes, with WinFsp | yes, except the Mac App Store build | yes | no | no |
| Serve a remote on your network | yes | yes, except the Mac App Store build | yes | no | no |
| Camera-roll backup | no | no | no | yes | no |
| Keyboard shortcuts | yes | yes | yes | in the desktop layout only | in the desktop layout only |

- **Background scheduling.** Only Windows and Android can run a saved task with Airclone closed, and
  only they show the `Also run while Airclone is closed` checkbox. macOS and Linux run schedules
  while the app is open and catch up one missed run on the next launch. On iPhone and iPad you start
  saved tasks by hand. See [Running tasks on a schedule](scheduling.md).
- **Mounting and serving are desktop features.** Both sit behind Advanced mode and appear only in
  the desktop shell's top bar and command palette. A large Android tablet gets that top bar, but
  Android cannot provide a mounted drive — treat both as Windows, macOS and Linux only. See
  [Mounting a drive and sharing](mount-and-share.md).
- **Camera-roll backup is Android only.** The `Back up your photos` section does not exist on any
  other platform; elsewhere, back up a folder instead. See
  [Backing up your photos (Android)](photos-android.md) and [Backing up a folder](backup.md).
- **The phone shell has no keyboard shortcuts**, no details panel and no bandwidth control, and it
  puts Settings in a tab rather than a dialog. Everything else — including the transfer dialog,
  saved tasks and the command console — is reachable there. See [Browsing your files](browsing.md).

Two more differences that catch people out: the rclone engine ships inside the app on Windows and
Android, is downloaded on first launch on Linux and the macOS direct-download build, and runs inside
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
