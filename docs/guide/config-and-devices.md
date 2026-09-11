# Your remotes, and moving them between devices

Every cloud connection you add to Airclone is stored in one file: the rclone config. This page
explains where that file is on each platform, how to lock it with a password, and the three ways to
carry it to another device — an encrypted export file, an offline QR transfer, and (on Android) a
backup that survives uninstalling the app.

Treat the config as a password file. It holds OAuth tokens, access keys and crypt passwords in
recoverable form. Anyone who gets the file gets your remotes.

## What is in the config

- One entry per **remote** — its type, its endpoint, and the credentials needed to reach it.
- Nothing else. Your files stay in the cloud; the config only knows how to get to them.
- It does not contain your Airclone settings, your saved tasks or your thumbnails. Those live
  separately and do not travel with an export.

Deleting a remote removes it from this file only: "This removes the remote from your rclone config.
Files stored in the cloud are not affected."

## Where the config lives

Open **Settings → Config**. The `Config location` section shows the exact path for the device you
are on, and under it a line reading `Encrypted` or `Not encrypted`, then the number of remotes.

| Platform | Where it is | Can you move it? |
|---|---|---|
| Windows | `%APPDATA%\rclone\rclone.conf` (rclone's own default) | Yes — `Use a different config file…` |
| macOS | `~/.config/rclone/rclone.conf` (or under `$XDG_CONFIG_HOME` if you set one) | Yes — `Use a different config file…` |
| Linux | `~/.config/rclone/rclone.conf` (or under `$XDG_CONFIG_HOME` if you set one) | Yes — `Use a different config file…` |
| Android (phone, tablet, TV) | Private app storage, inside the app itself | No |
| iOS | The app's private container | No |

On desktop the row has a folder button, tooltip `Open containing folder`, and Airclone asks rclone
itself where its config is, so the path shown is the one the engine actually loads. If you point
Airclone at a different file it validates the file first, restarts the engine, and marks the row with
a `Custom` badge; `Back to default` returns to rclone's own location.

On Android and iOS the path is shown but cannot be changed. That is deliberate: the config sits in
private app storage where no other app — and no device backup — can read it. The cost is that
**uninstalling the app on Android deletes it**, which is what [Survive uninstall](#android-surviving-an-uninstall)
below exists to solve.

## The automatic backups

Before anything overwrites your config, Airclone copies it first. Snapshots are taken before an
import, a replace, a config-file switch, a password change, removing encryption, and `Remove all
remotes`. The ten most recent are kept.

To get one back: **Settings → Config → Import & export → `Restore a backup…`**. Each row is a UTC
timestamp with a `Restore` button. The confirmation (`Restore this backup?`) says plainly that your
current config is snapshotted first, so restoring is itself reversible. Restoring restarts the
engine.

One deliberate exception: encrypting a plaintext config does **not** take a snapshot. A backup there
would scatter a readable copy of the very secrets you are encrypting into the backups folder.

## Encrypting the config with a password

**Desktop only** (Windows, macOS, Linux). This uses rclone's own config encryption, which needs the
rclone binary; the controls are not shown on Android, on an Android tablet running the wide layout,
or on iOS.

In **Settings → Config**, under the path, you will see either `Encrypt this config…`, or — once it is
encrypted — `Change password…` and `Remove encryption…`.

What changes when you turn it on:

- The file on disk becomes unreadable without the password. Anyone who copies it gets nothing.
- Every time Airclone starts, it shows an `Unlock your config` screen with a `Config password` field
  before the engine runs.
- The engine restarts briefly during the change, so finish any running transfers first.
- There is no recovery. If you lose the password the config cannot be opened, by you or by anyone.
  Store it in a password manager.

What does not change: your files, your other devices, and any export you made earlier. An export
carries its own separate passphrase.

### Not typing it at every launch

**Settings → Security → `Remember config password`** stores it in the device's own credential store
(Windows Credential Manager, macOS Keychain, Linux Secret Service, Android Keystore, iOS Keychain).
Anyone who can unlock your device can recover it. Turning the switch off clears the stored password
immediately, and tells you if the removal failed.

Below it, on a device with a fingerprint or face enrolled, there is a biometric unlock option. It is
only available once `Remember config password` is on, because it gates the release of a stored
secret; with nothing stored it would have nothing to release. It is a casual-access gate on an
already-unlocked device, not protection against someone who knows your device passcode.

### Removing encryption

`Remove encryption…` writes every secret back to disk in plain text, so it asks you to type
`DECRYPT` rather than accepting a single click. The encrypted config is backed up first.

## Exporting to a file

**Settings → Config → Import & export → `Export File Config`**. Available on every platform.

**Step 1 — what to export.** `All remotes`, or `Choose remotes` and tick the ones you want. If you
pick a crypt, alias, union or combine remote, the remote it is built on is added for you; the dialog
lists each one as "X needs Y — included". Without that, the export would arrive on the other device
unusable.

**Step 2 — format.**

| Format | What you get | When to use it |
|---|---|---|
| `Airclone encrypted (recommended)` | AES-256-GCM under a passphrase you choose, saved as `airclone-remotes.airclone-config` | Moving remotes to another Airclone |
| `Plaintext rclone.conf` | A readable `rclone.conf` | Feeding the rclone command line |
| `Exact copy (stays rclone-encrypted)` | A byte-for-byte copy of your encrypted config | Keeping rclone's own encryption |

The encrypted format asks for the passphrase twice and refuses anything under 8 characters. There is
no recovery: lose the passphrase and the export cannot be opened.

The plaintext format stops on a second screen, `Export readable secrets?`, before it writes: that
file contains the keys to your cloud accounts in recoverable form. Store it somewhere safe and delete
it when you are done.

`Exact copy` only appears when your config is already encrypted and you are exporting all remotes. It
opens with rclone and its own password, not with an Airclone passphrase.

## Importing from a file

**Settings → Config → Import & export → `Import File Config`** → `Choose a file…`. Available on every
platform.

Airclone works out what the file is rather than asking you. It accepts:

- a plaintext `rclone.conf`;
- `rclone config dump` JSON;
- a config encrypted by rclone itself — it asks for the `Config password`;
- an Airclone encrypted export — it asks for the `Passphrase`.

Anything else stops with "That file isn't a recognised rclone or Airclone config." A wrong password
retries in place; a file that is not an Airclone export at all says so distinctly, so you are never
left guessing which of the two went wrong.

### The review step

Nothing is written until you have seen it. The `Review import` screen lists every incoming remote
with its name, its type, and its endpoint — the `host:` or `url:` line. Secrets are never shown
there, and the endpoint is: it means a config that has been swapped or tampered with cannot quietly
re-point one of your remotes at somebody else's server without you seeing it.

If an incoming name is already in use, the row gets an `Import as` field pre-filled with
`<name>-imported`, which you can edit. Remote names may contain letters, numbers, `_`, `-` and `.`.

From there you have three choices:

| Button | What happens |
|---|---|
| `Merge` | Incoming remotes are added. Clashing names land beside your existing ones under their new name. |
| `Replace the N existing` tick, then `Replace + merge` | Clashing remotes land **on top of** the ones you have. |
| `Replace instead…` → `Replace config` | Your entire config is overwritten with the imported one and the engine restarts. |

Both replacing paths back up your config first, and both say what replacing costs. It is worth
reading once: an encrypted remote replaced with a different password or salt still connects and still
reports free space, but it can no longer read the names of what it stored, so the folder lists as
empty. The files are still there; the remote can no longer see them.

If you replace the whole config, every remote not in the imported file disappears until you restore.
If your config is encrypted, the replacement is re-encrypted with your current config password, so
encryption at rest is never silently dropped.

The last screen reports per remote: `Merged`, `Replaced`, and `Didn't import` with the reason.

**On Android**, if the file picker hands back a file from a cloud or download provider, the import
may not be able to read it. Copy the file onto the device first and pick it again.

## The offline QR transfer

This moves a config onto a phone with no Wi-Fi, no account and no server. The whole config travels
inside the picture. The device showing the QR is usually a computer, but a second phone or a tablet
can show it just as well.

It is **led by the phone that will scan**, and the order matters:

1. **On the phone**, open `Import QR Config` (Settings → Config → Import & export, or the `+` beside
   `Cloud` in the Files tab). It shows `Your one-time code` — eight characters in two groups.
2. **On the computer**, open `Export QR Config`. Choose `All remotes` or `Choose remotes`, then type
   the phone's code into the `Code` field and press `Make QR`. The field is obscured; the eye button
   (`Show code` / `Hide code`) lets you check it. Dashes are optional and the code is uppercased for
   you.
3. **On the phone**, tap `Scan the QR` and point the camera at the screen. The phone already knows
   the code, so it unlocks automatically and goes straight to the same `Review import` screen
   described above.

The code never travels inside the QR. Someone who photographs your screen has the encrypted config
but not the key to it, and the encryption is deliberately slow to attack, because a photographed QR
can be attacked at leisure.

### When the config is too big for one QR

Airclone splits it across several codes, which then cycle on their own on the computer's screen.
Point the phone at the square and leave it there; it collects them in any order and shows "Scanned X
of Y codes". The arrows and the pause button let you hold one code still if you prefer. A config too
large even for a batch (more than 40 codes) is refused — choose fewer remotes and try again.

### Where QR works, and where it does not

| Device | `Export QR Config` | `Import QR Config` (scanning) |
|---|---|---|
| Windows | Yes | No |
| Linux | Yes | No |
| macOS | Yes | Yes on the direct-download build; no in the Mac App Store build |
| Android phone or tablet | Yes | Yes |
| iPhone, iPad | Yes | Yes |
| Android TV | Yes | No — a television has no camera |

Where a live scan is not available, `Import QR Config` does not fail silently: it opens a dialog
titled `QR import needs a camera` that tells you so and points you at the file-based route instead.
On macOS, whether a scan is offered depends on the build you are running — open `Import QR Config`
and the app will tell you which you have.

To move a config **to** a Windows or Linux computer, use `Export File Config` on the device that has
the remotes and `Import File Config` on the computer.

## Android: surviving an uninstall

On Android your remotes live in private app storage, which the system deletes when the app is
uninstalled, and which Airclone deliberately keeps out of Android's own backup system so your
credentials cannot be read off-device. **So on Android, uninstalling loses every remote unless you
turn this on first.**

**Settings → Config → `Survive uninstall`**. This is Android only. Desktop does not need it — the
config already lives outside the app and survives reinstalling — and it does not work on iOS.

Turning the switch on asks for a passphrase (at least 8 characters, typed twice). That prompt is the
setup: there is no separate "choose encryption" step. Airclone then keeps an encrypted copy in a
folder outside the app and refreshes it automatically whenever your remotes change. `Back up now`
forces a refresh.

You can continue without a passphrase, but only through a second screen that spells out what it
means — a plain `rclone.conf` in shared storage that any app with file access can read, that rides
along in device backups and phone-to-phone transfers, and that anyone holding your unlocked phone can
open in a file manager. It needs an explicit tick box before the red button enables. Use a passphrase
unless you specifically need a plain file.

Other things worth knowing:

- Writing outside the app needs **All Files Access**. If it is not granted, the section says so and
  offers a `Grant` button.
- Only one copy ever exists. Switching from unprotected to encrypted deletes the plain file.
- Turning the switch **off deletes the backup file**, after asking. If you were relying on it to
  survive an uninstall you were about to do, keep it.
- Write the passphrase down. It is held in the device's own credential vault, which uninstalling
  destroys — so after a reinstall you type it once to restore, which is exactly as it should be.

### After you reinstall

Airclone looks for a backup left by the previous install and offers `Restore your remotes?` once,
when you have no cloud remotes yet. The offer can only appear after All Files Access is granted, so
it may show up a little after launch rather than at the first screen. Accepting hands the file to the
ordinary import wizard: the same passphrase prompt, the same review, the same merge rules.

You can also start it yourself at any time with `Restore from backup…`.

One thing that looks wrong but is not: straight after a reinstall the `Survive uninstall` switch
reads **off** even though the backup file is plainly there. Uninstalling wiped the setting; it did
not wipe the file. Airclone says so in that section. Turn the switch back on to resume keeping it up
to date.

## Moving your remotes to a new device

| You are going… | Do this |
|---|---|
| Computer → computer | `Export File Config` (Airclone encrypted) on the old one, copy the file across, `Import File Config` on the new one |
| Computer → phone | `Import QR Config` on the phone first for the code, then `Export QR Config` on the computer, then scan |
| Phone → computer | `Export File Config` on the phone and open the file on the computer |
| Phone → new phone | Turn on `Survive uninstall` (Android), or export a file and import it on the new phone |
| Into the rclone command line | `Export File Config` → `Plaintext rclone.conf` |

## What Airclone will not do

- It never uploads your config anywhere. There is no account, no sync service and no phone-home; see
  [PRIVACY](../../PRIVACY.md).
- It will not import anything without showing you the remotes first.
- It will not overwrite your config without taking a backup.
- It cannot recover a lost passphrase — not for an export, not for the config, not for the Android
  backup. Every one of those is unrecoverable by design.
- It will not pretend to scan a QR on a device that cannot reach a camera — it says so and offers the
  file route instead.

If something here failed and you want to know why, **Settings → Diagnostics → `Problem report`** holds
a local, redacted record of the failure that you can copy. Nothing is sent anywhere until you send
it.

## Related pages

- [Getting started](getting-started.md) — installing, and adding your first remote
- [Backing up a folder](backup.md) — backing up your *files*, which is a different thing from backing
  up this config
- [Troubleshooting](troubleshooting.md) — when a remote lists as empty, or the engine will not start
- [All guide pages](README.md)
