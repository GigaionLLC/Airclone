# Airclone — Privacy Policy

_Last updated: 2026-08-11_

Airclone is a desktop and mobile graphical interface for
[rclone](https://rclone.org), published by **Gigaion, LLC**. This policy
explains what data Airclone does — and does not — handle.

## The short version

**Airclone does not collect, transmit, sell, or share any personal information
about you.** There is no analytics, no telemetry, no advertising, and no
tracking of any kind. Airclone has no account system and no backend server
operated by Gigaion, LLC.

## What stays on your device

- **Your rclone configuration and credentials** (cloud account tokens,
  passwords, and keys) are stored locally on your device — in rclone's
  configuration file and/or your operating system's secure credential store.
  They are never sent to Gigaion, LLC.
- **Your files and their contents** are never routed through us. When you
  browse, copy, move, or sync files, data flows **directly between your device
  and the cloud storage services you have chosen** (for example S3, Google
  Drive, Dropbox, OneDrive, SFTP, or WebDAV) — exactly as rclone does on the
  command line.
- If you use Airclone's optional configuration-sync or export features, your
  configuration is **end-to-end encrypted on your device** before it is placed
  on a remote, file, or QR code that you control. We never hold the key.

## Error reports stay on your device too

Airclone has **no crash reporting and no error telemetry**. Instead, problems
are recorded in a log that lives only in memory on your device, which you can
read under **Settings → Diagnostics → Problem report**.

- Nothing is written to a file unless you save or share a report, and nothing
  is ever transmitted anywhere — not to us, not to anyone.
- Passwords, tokens, keys, email addresses, and the name of your home folder
  are removed **as each entry is recorded**, so they are never in the log to
  begin with. The report header contains version and platform information only.
- If you choose to send a report to us in a bug report, that is a deliberate
  act you take, with the contents visible to you first. We ask you to skim it
  before sharing it.

## "Survive uninstall" — an optional backup you control

On Android, Airclone can keep a copy of your rclone configuration in a folder
outside the app (`Airclone/` in your shared storage), so that reinstalling the
app or setting up a new phone does not lose your remotes. **This is off by
default.**

- When you turn it on, Airclone asks you for a passphrase and **encrypts the
  backup with it** (AES-256-GCM with an Argon2id-derived key). We never hold
  that passphrase, and without it the file cannot be opened by anyone.
- You may choose to turn it on **without** a passphrase, which writes a plain
  `rclone.conf`. Airclone warns you clearly, and requires you to confirm that
  you understand, before doing this: an unencrypted file in shared storage can
  be read by other apps on the phone and is copied by device backups and
  phone-to-phone transfers.
- Turning the setting off deletes the file from your device.

Either way the file stays on your device. It is not uploaded anywhere.

## Network connections Airclone makes

Airclone only makes network connections that you initiate or that keep the
software current:

1. **The cloud storage services you configure** — to browse and transfer your
   files, using the credentials you gave to rclone. This is the core function
   of the app.
2. **Software updates** — Airclone may contact public sources such as
   `downloads.rclone.org` (to obtain or update the bundled rclone engine) and
   the GitHub releases API (to check whether a newer version of Airclone is
   available). These requests download software and version information only;
   they do not send personal data about you.

   _Builds installed from an app store make neither request._ A Microsoft
   Store, Google Play, or App Store copy ships with the rclone engine included
   and is updated by that store; "Check for updates" simply points you at the
   store and contacts nothing.

Airclone does **not** contact any Gigaion, LLC server, because none exists for
this app.

## Children's privacy

Airclone is a general-purpose utility and is not directed at children. It does
not knowingly collect information from anyone.

## Changes to this policy

If this policy changes, the updated version will be posted at this URL with a
new "Last updated" date.

## Contact

Questions about privacy? Open an issue at
<https://github.com/GigaionLLC/Airclone/issues>, or contact Gigaion, LLC through
the support channels listed on the product's store page.
