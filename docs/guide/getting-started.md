# Getting started

Airclone is a file manager for your cloud storage. It runs on your own machine, connects
straight to the storage accounts you tell it about, and copies files between them. It uses
[rclone](https://rclone.org/) as its engine, so anything rclone can reach, Airclone can browse.

Airclone sends nothing to us. There is no account to create, no sign-in to Airclone itself, and
no usage reporting. See [PRIVACY.md](../../PRIVACY.md).

This page covers installing it and the first five minutes: getting the engine running, adding your
first cloud connection, and checking that it works.

## Installing

| Platform | Where to get it |
| :--- | :--- |
| Windows 10/11 | Microsoft Store, or a direct download |
| macOS | App Store, or a direct download (signed and notarised) |
| Linux | Direct download — an AppImage, a Flatpak, or a tarball |
| Android (phone, tablet, TV) | Google Play, or a direct download |
| iPhone / iPad | App Store only |

The store listings and the direct-download page are linked from the
[project README](../../README.md). The store builds and the free direct-download builds are the
same application. The stores install it and keep it updated for you; a direct download you update
yourself.

One purchase on the Apple App Store covers iPhone, iPad and Mac.

## First launch: the engine

Airclone needs the rclone engine before it can do anything. What you see on first launch depends on
your platform.

| Platform | What happens |
| :--- | :--- |
| Windows | The engine ships with the app. Nothing to download. |
| Android | The engine ships inside the app. Nothing to download. |
| Linux | All three downloads include the engine as a library (`librclone.so`), so Airclone runs straight away with nothing to fetch. If it finds an `rclone` on your machine it prefers that instead. |
| macOS (direct download) | Airclone looks for an rclone on your machine. If it does not find one, it shows a card headed **Set up the rclone engine** with a **Download rclone engine** button. Press it once; there is nothing else to install. |
| iPhone, iPad, Mac App Store | The engine runs inside the app itself. Nothing to download. |

If the engine fails to start, the card is headed **Engine error** and offers **Retry download** and
**Re-check for a local rclone**. See [troubleshooting](troubleshooting.md).

If you already have an rclone config that is password-protected, you get a card headed **Unlock your
config** with a **Config password** field. Type the password and press **Unlock**. The password is
sent to the engine and is not written to disk unless you separately turn on "Remember config
password" in Settings → Security.

On Android, browsing the phone's own storage needs a permission Android does not grant
automatically. Until you grant it, a banner reads *Allow file access to browse this device's
storage*. Tap it to be taken to the Android settings screen that grants it. Cloud remotes work
without it; only local browsing needs it.

Once the engine is up, the desktop status bar along the bottom reads `engine ok · rclone <version>`.

## Which layout you get

Airclone has two shells, and which one you see depends on **window width**, not on the operating
system:

- **Below 700 logical pixels wide** — the phone shell: three tabs along the bottom, `Files`,
  `Transfers` and `Settings`.
- **700 or wider** — the desktop shell: a top bar, a sidebar on the left, one or two file panes, and
  a status bar.

So an Android tablet and an iPad get the desktop layout, and a desktop window you drag narrow
switches to the phone layout while it stays narrow. An Android TV always uses the phone shell, with
the three tabs shown as a side rail on the left instead of along the bottom.

This guide says "on the desktop" to mean the wide layout and "on the phone" to mean the narrow one.

## What a remote is

A **remote** is a name you give to one storage location, together with the details needed to reach
it. `work-drive` might be a Google Drive account. `photos-s3` might be an Amazon S3 bucket.
`nas` might be an SFTP server in your house.

You will see the word everywhere in Airclone, because it is rclone's word. A remote is not an
account you create with anyone — it is a saved connection. It lives in your rclone config file on
this device. Deleting a remote deletes that saved connection and nothing else; the files stay where
they are in the cloud.

Airclone can connect to dozens of storage types. Some are consumer services you sign in to with a
browser. Some are servers you point at with a hostname and a password. Some, like `crypt` and
`alias`, wrap another remote you have already set up rather than talking to a service at all.

## Adding your first remote

**On the desktop**, find the `CLOUD` section in the left sidebar and press the **+** beside it
(tooltip: *Add or encrypt a remote*). Choose **Add a remote…**. If the sidebar is empty it says
*No cloud remotes yet — click + to add one.*

You can also press the **Add a remote** tile in the `Cloud` section of the Home view — the page a
pane shows before you have opened anything.

If the **+** is greyed out with the tooltip *Start the engine to add a remote*, the engine is not
running yet. Wait for it, or fix it first.

**On the phone**, open the `Files` tab, find the `Cloud` heading in the locations list, and tap the
**+** beside it (tooltip: *Add, encrypt, or import a remote*). A sheet offers **Add a remote**,
**Encrypt a remote** and **Import QR Config**. Choose **Add a remote**.

### Choosing a storage type

The dialog opens on **Add a remote** — *Choose a storage type to connect.* It lists every storage
type your engine supports, each with rclone's own one-line description. There is a
**Search storage types…** box at the top; type `drive`, `s3`, `sftp` or whatever you are looking for
to narrow the list.

The list comes from the engine, so it is exactly what your installed rclone version supports. If a
storage type is missing, your engine is older than that backend.

### Filling in the form

Picking a type takes you to a form headed **Set up &lt;type&gt;**. It asks for:

- **Name** — *A short name for this remote (e.g. my-drive).* This is yours to choose. It is the
  label you will see in the sidebar.
- **The type's own settings** — one field per option, labelled with rclone's option name and its
  help text underneath. Options marked with a `*` are required. Text fields show the option's
  default as grey placeholder text.
- **Advanced** — a collapsed section at the foot of the form holding the type's rarely-needed
  options. It is closed by default; open it only if you know you need something in it. This is a
  per-type disclosure and is unrelated to Airclone's own Advanced mode, further down this page.

Press **Create remote** when you are done.

Names must be unique. If you reuse an existing name, Airclone refuses and tells you so rather than
creating the remote — creating over an existing name would silently replace that remote's settings.

### Follow-up questions

Some storage types cannot be set up from a single form. After you press **Create remote**, the
dialog may switch to a page headed **Configure &lt;type&gt;** showing one question at a time, with
rclone's own explanation beneath it. Yes/no questions get **No** and **Yes** buttons; everything
else gets a text box and a **Continue** button. Answer each one and the dialog moves to the next.

Providers that sign you in through a web browser, and providers that ask which drive or bucket to
use, arrive this way. Airclone runs the sign-in step for you as part of this flow. There is no
separate command to run: the console deliberately blocks rclone's `authorize` and `config` commands
and points you back at this dialog, because those commands handle your secrets in the open.

### If it fails

A failure shows **Couldn't create the remote** with the engine's own error message and a
**Start over** button. The message is rclone's, not ours — a wrong password, an unreachable host or
a rejected sign-in reads the way rclone would report it on the command line. Nothing is saved when
this happens.

## Testing a connection

Once a remote exists, check that it actually works before you trust it with a transfer.

- **On the desktop**: hover the remote's row in the `CLOUD` section, press the **⋯** button
  (tooltip: *Actions*) and choose **Test connection**.
- **On the phone**: tap the **⋯** at the end of the remote's row (tooltip: *Remote actions*) and
  choose **Test connection**.

A small dialog headed `Test connection · <name>` shows *Checking…*, then one of:

- **Reachable — &lt;free&gt; free of &lt;total&gt;.** The remote answered and reported its quota.
- **Reachable (this backend reports no usage info).** The remote answered. Not every storage type
  can report free space; this is normal for many of them, and not a fault.
- The engine's error message, in red, with a **Retry** button.

The test is read-only. It asks the remote about itself and, if that is unsupported, lists the root
folder. It never writes anything.

## The other things you can do to a remote

The same **⋯** menu carries the rest:

| Action | Desktop | Phone | What it does |
| :--- | :--- | :--- | :--- |
| **Test connection** | yes | yes | As above. |
| **Edit remote** | yes | yes | Reopens the same form with the current values filled in. |
| **Duplicate remote…** | yes | no | Copies the remote's settings under a new name. |
| **Delete remote** | yes | yes | Removes the saved connection. |

Two behaviours in **Edit remote** are worth knowing. The name is fixed while editing and shown as
plain text — rename by duplicating instead. And password fields are always left **blank**: blank
means *keep the current password*, so you only type in one if you are changing it. The help text
under the field says so.

Editing a **crypt** remote's password is guarded by its own confirmation, headed
**Change encryption password?**, because everything already uploaded under the old password becomes
permanently unreadable. **Cancel** is the focused default there, so pressing Enter by reflex cannot
re-key anything.

**Delete remote** confirms with *This removes the remote from your rclone config. Files stored in
the cloud are not affected.* That is exactly true: it edits your config file, and the cloud never
hears about it.

## Encrypting a remote

The **+** menu's second item, **Encrypt a remote…**, does something different from adding one. It
wraps a remote you already have so that *files and names are encrypted before upload*. It asks for a
**New remote name**, the **Remote to encrypt**, an optional **Subfolder**, an **Encryption
password** and a **Confirm password**. **Filenames** offers **Encrypt (standard)**, **Obfuscate** or
**Leave readable**, with a separate switch for encrypting folder names. An **Advanced** disclosure
adds a second password, labelled *Salt / password2 (optional, recommended)*.

After that you use the wrapper remote like any other. Airclone encrypts on the way up and decrypts
on the way down; the underlying storage only ever holds ciphertext. Keep the password, and the salt
if you set one. Nobody can reset them, and a wrong or extra salt makes the folder list as empty
rather than as an error.

## Advanced mode

Airclone opens in a deliberately small mode. **Advanced mode** is a switch pinned at the top of
Settings, described there as *Power-user features: Sync, include/exclude/filter, dry-run, and saved
+ scheduled tasks.* It is **off by default**, and the setting is per device.

It is off by default because the features behind it can delete files. Sync makes a destination match
a source, which means removing what the source no longer has. Mounting and serving expose your
storage to the rest of the machine or to the local network. None of that belongs in front of someone
who wants to drag a folder to a cloud drive.

Turning it on reveals:

| Feature | Where it appears |
| :--- | :--- |
| **Saved tasks** | Desktop top-bar button. |
| **Serve / Share on LAN** | Desktop top-bar button, where serving is available. See [mount and share](mount-and-share.md). |
| **Mount as a drive** | Desktop top-bar button, where mounting is available. Desktop only. See [mount and share](mount-and-share.md). |
| **The command console** | Tab strip, the desktop pane's address row, and the phone's `Airclone` header. Available on every platform. See [console](console.md). |
| **Two-way sync** | The extra transfer mode in the Copy / Move / Sync dialog. |
| **Set as sync source** and **Sync … into this folder…** | The file list's right-click menu. |
| **Transfer concurrency**, **Engine flags**, **Recents** | Settings. |

Two things the description above gets wrong, and you should know about:

- The **Copy / Move / Sync** dialog — including Sync, include/exclude filters and dry run — is
  reachable **without** Advanced mode, from the desktop `Tools` menu and from the phone's **⋯**
  sheet. Only **Two-way sync** is genuinely hidden. See [transferring](transferring.md).
- **Settings → Automation** is not gated either, on any platform. **Back up a folder** and
  **Saved tasks** are reachable there in the default mode. On a phone that is the only route to
  them. See [backup](backup.md) and [scheduling](scheduling.md).

Turn Advanced mode off again at any time. It hides features; it does not undo anything you set up
while it was on. A saved task keeps running on its schedule whether or not the button that created
it is visible.

## Opening Settings

- **On the desktop**: the gear button at the right of the top bar (tooltip: *Settings*). It opens as
  a dialog over the app.
- **On the phone**: the `Settings` tab at the bottom. It is a full scrolling page.

Both show the same content in the same order, so a path like "Settings → Automation → Back up a
folder" is valid on either. Groups that make no sense on a platform are simply absent — there is no
download-folder setting on a phone, and no engine-path setting off the desktop.

## Finding your way around

On the desktop, two keys are worth learning now:

- **F1** opens the full list of keyboard shortcuts.
- **Ctrl + K** opens the command palette, which can reach most things by name.

The phone shell has no keyboard shortcuts.

## Where to go next

- [Browsing your files](browsing.md) — panes, tabs, views, previews and selection.
- [Copying, moving and syncing](transferring.md) — the transfer dialog, filters and dry runs.
- [Backing up a folder](backup.md) — the copy-only wizard that keeps old versions.
- [Scheduling](scheduling.md) — what runs by itself, and on which platforms.
- [Photo backup on Android](photos-android.md) — camera roll to a remote.
- [Mounting and sharing](mount-and-share.md) — drive letters and LAN servers, desktop only.
- [Config and moving between devices](config-and-devices.md) — where your remotes are stored, and
  how to carry them to another machine.
- [The command console](console.md) — running rclone commands inside Airclone.
- [Troubleshooting](troubleshooting.md) — when something does not work.
- [All guide pages](README.md).
