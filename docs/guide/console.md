# The command console

The command console is a tab inside Airclone that runs rclone commands and shows their output.
It exists for the times when the file panes are the long way round: checking a remote's quota,
counting what is in a folder, comparing two remotes, or copying with a flag the transfer dialog does
not offer.

It is **not a shell**. You cannot pipe, redirect, chain commands with `&&`, or run anything that is
not rclone. What you type is split into arguments and handed to rclone directly, so there is no shell
to interpret `|`, `>` or `;` — those characters are passed through as ordinary text.

It is also not the whole of rclone. The console runs a curated list of rclone subcommands, and
refuses everything else. The refusals are listed below, with the reason for each.

If you only want to copy, move or sync files, use the transfer dialogs described in
[Transferring files](transferring.md). The console is for the things those dialogs do not cover.

## Turning it on

Every route to the console is hidden until **Advanced mode** is on. It is off by default, and it is
a per-device setting.

Turn it on in **Settings → Advanced mode** (the card at the top of Settings — a dialog on desktop, the
`Settings` tab on a phone).

## Opening a console tab

A console is a tab in a pane, alongside browser tabs. Its tab is labelled `Console`.

| Where | Control | Available on |
|---|---|---|
| The pane's address row | Terminal icon, tooltip `New console tab (run rclone commands)` | Windows, macOS, Linux |
| The command palette (`Ctrl + K`) | `New console tab (run rclone commands)` | The desktop shell |
| The pane's tab strip | Terminal icon, tooltip `New console tab` | Any platform, whenever the strip is showing |
| The phone's `Files` tab | Terminal icon in the `Airclone` header, tooltip `Open console` | The phone shell |

The tab strip only appears when a pane has more than one tab (or when its only tab is a console), so
on a fresh single-tab pane the address-row button is the one you will find first.

To close a console: the `✕` on its tab on desktop, or the header button on a phone, whose tooltip
reads `Close console`. On the phone, the system Back button closes a console tab too. Closing a
console stops any command still running in it and discards its output.

## Running a command

Type the command **without** the leading word `rclone` — the console supplies that. So you type
`ls gdrive:Photos`, not `rclone ls gdrive:Photos`.

Press `Enter`, or use the `Run` button next to the input.

Above the input is a preview bar showing the exact command that will run, prefixed with `rclone`, and
a badge saying what the console makes of it:

| Badge | Meaning |
|---|---|
| `runs` | Read-only or additive. It runs as soon as you press Enter. |
| `destructive` | It can delete or overwrite data. A confirmation appears first. |
| `blocked` | The console will not run it. Pressing Enter prints the reason. |

While a command is running the input is disabled, the hint reads `running…`, and the `Run` button is
replaced by `Stop`. Every console command also appears in the transfers list while it runs, so you can
stop it from there as well.

`Clear` in the console header empties the output. It does not clear the command history. The output
keeps roughly the last two thousand lines; older lines are dropped.

The console needs the engine to be running. If it is not, you get `Engine not ready.` — the status bar
at the foot of the desktop window tells you what the engine is doing.

## Autocomplete

Start typing and a suggestion list appears above the input.

- On the first word you get rclone subcommands, with a one-line description. Commands the console
  blocks are not offered at all.
- On a word starting with `-` you get common flags.
- Anywhere else you get your remotes, as `name:`.

`Tab` accepts the highlighted suggestion. `↑` and `↓` move through the list. `Esc` hides it until you
type again. Destructive entries are shown in the error colour. Where rclone has a documentation page
for a suggestion, a `docs ↗` link on the row opens it in your browser.

## History recall

Each console tab keeps the commands you ran in it, in memory, for the life of that tab. With the
suggestion list closed (press `Esc`, or start from an empty prompt), `↑` walks back through them and
`↓` walks forward. Stepping forward past the newest restores whatever you had half-typed.

A command that was refused is still recorded, so you can press `↑`, fix the part that was wrong, and
run it again. Repeating the same command twice in a row only stores it once. The history is never
written to disk, and it is not shared between tabs.

## Commands worth knowing

These all work on both engines (see [Two engines](#two-engines-two-consoles) below). Replace `gdrive:`
and `onedrive:` with your own remote names.

| Command | What it does |
|---|---|
| `listremotes` | Lists the remotes in your config. |
| `version` | Prints the rclone version the engine is running. |
| `about gdrive:` | Quota: total, used, free. Not every provider reports it. |
| `lsd gdrive:` | Lists only the folders at that path. |
| `ls gdrive:Photos` | Lists files with their sizes. |
| `size gdrive:Photos` | Counts the objects and totals their bytes. Can take a while on a big folder. |
| `md5sum gdrive:Documents` | MD5 for every object under the path. `sha1sum` likewise. |
| `check gdrive:Docs onedrive:Docs` | Reports which files differ between two paths. Changes nothing. |
| `mkdir gdrive:Archive/2026` | Creates a folder. |
| `link gdrive:Reports/q1.pdf` | Asks the provider for a public link, where it supports one. |
| `copy gdrive:Docs onedrive:Docs --dry-run` | Shows what a copy would transfer, without transferring it. |

`--dry-run` (or `-n`) is worth reaching for before anything that writes. It is the cheapest way to find
out that a path is wrong.

The destructive commands — `sync`, `move`, `moveto`, `delete`, `deletefile`, `purge`, `rmdir`,
`rmdirs`, `cleanup`, `bisync`, `convmv`, `dedupe`, `backend` — run too, behind the confirmation
described next.

## Destructive commands ask first

If the command can delete or overwrite data, pressing Enter raises a dialog titled
**`Run a destructive command?`**. It explains that the command "can delete or overwrite data and
cannot be undone", suggests adding `--dry-run` first, and shows the exact command it is about to run.
The buttons are `Cancel` and `Run anyway`.

A safe command can be promoted to destructive by a flag, and the console watches for that. Adding any
of `--delete-during`, `--delete-before`, `--delete-after`, `--delete-excluded` or `--rmdirs` to an
otherwise harmless verb raises the same confirmation, because those flags delete at the destination.

The console has no undo. It does not stage a copy of anything before deleting it. The confirmation is
the only thing standing between the command and your files, which is why it names the command back to
you rather than asking a generic "are you sure".

## What the console refuses, and why

The console works from an allowlist. **A command it does not recognise is refused**, rather than tried
in case it works. Anything that reaches rclone has been recognised, classified and, where it is
risky, confirmed.

### Commands that are blocked outright

| Command | Why | Do this instead |
|---|---|---|
| `config` | Mutates your config file and can print secrets. | Use the `+` next to `CLOUD` in the sidebar (`Add or encrypt a remote`); import and export live in Settings → Config. |
| `obscure` | Its argument is a plaintext password. | Passwords are obscured for you when you add or edit a remote. |
| `reveal` | Prints a stored password back. | Airclone never prints stored secrets. Edit the remote if you need to change one. |
| `authorize`, `reconnect` | Interactive provider sign-in. | Add or edit the remote; Airclone runs the sign-in for you. |
| `mount` | Would start a mount outside Airclone's own tracking, so nothing would clean it up. | `Mount as a drive` — see [Mounting and sharing](mount-and-share.md). |
| `serve` | Same reason: a long-lived server nothing would stop. | `Serve / Share on LAN`. |
| `rc`, `rcd` | Would talk to, or start, another rclone control server. | Airclone already runs and drives the engine. |
| `selfupdate` | Would replace the engine binary behind Airclone's back. | Settings → Engine. |
| `gendocs`, `gitannex` | Developer tooling, no use inside the app. | — |

A misspelling lands here too, with a different message: `Unknown command "…". The console accepts a
curated set of rclone commands — start typing to see the matching ones.`

### Flags that are blocked on any command

Three families of flag are refused whatever verb they are attached to:

- `--rc` and any `--rc-…` — these start rclone's own remote-control server inside the command, which
  could expose your config to the local network.
- `--config` and any `--config-…` — these would point the command at a different config file, or at
  one you did not mean to touch. Airclone pins its own config onto every console command internally,
  so the remotes you see in the sidebar are the ones the console uses.
- `--dump` and any `--dump-…` — these echo request headers and bodies, which contain credentials.

The message names the flag rather than the command, so you can remove it and run the same verb again.

### Verbosity that would print credentials

`-vv` (or any two or more `-v`, `--verbose 2`, or `--log-level DEBUG`) is refused:
`Refused: -vv / --dump can echo credentials to the log. Remove it, or use a lower verbosity.`

A single `-v` is fine. The console blocks this rather than trying to scrub debug output, because
debug output has no fixed shape and a scrubber that misses once has leaked a token into a buffer you
can select and copy.

### Secrets are hidden in the echo and the output

Where a flag's value is a secret — anything whose name contains `pass`, `key`, `secret`, `token`,
`auth`, `credential` and so on — the command echoed into the output shows `‹redacted›` in its place,
as does the preview bar and the confirmation dialog. The same applies to secrets embedded in a
connection string such as `:s3,secret_access_key=…:bucket`.

Output lines are scrubbed on the way in as well: `Authorization:` headers, `Bearer` tokens, AWS
`Credential=` values and `token=`/`password=` parameters are replaced before they ever reach the
screen.

This is display only. The real command runs with the real value — the redaction protects the
scrollback, a screenshot and a copied line, not the request.

## Two engines, two consoles

Airclone can run rclone in two ways, and the console is not identical between them.

| Platform | Engine normally used | Console |
|---|---|---|
| Windows | Bundled rclone binary | Full CLI output |
| macOS (direct download) | rclone binary | Full CLI output |
| Linux | rclone binary | Full CLI output |
| Android (phone, tablet, TV) | Bundled rclone binary | Full CLI output |
| iOS | In-process engine | Translated subset |
| Mac App Store build | In-process engine | Translated subset |

On desktop you can also choose the engine yourself in Settings → Engine (`Auto`, `Binary`,
`In-process`). Choosing `In-process` gives you the translated console on that machine too.

**With the binary engine** the console streams rclone's real output, line by line, exactly as the
command-line tool would print it.

**With the in-process engine** there is no separate rclone process to run a command in, so the console
translates what you typed into a structured call instead, and renders the result itself. A banner
across the top of the console says so:

> In-process engine — structured RC-method console. Text-output commands (cat, tree, raw streams) run
> only on the desktop binary engine.

What that means in practice:

- Listing commands (`ls`, `lsl`, `lsf`, `lsjson`, `lsd`) all produce the same Airclone-rendered listing
  rather than four different CLI formats.
- `cat`, `tree`, `rcat`, `touch`, `checksum`, `cryptcheck`, `cryptdecode`, `convmv`, `dedupe`,
  `backend` and `settier` are refused, with a message telling you they need the desktop binary engine.
- Only a fixed set of flags is understood: `--dry-run`, `--transfers`, `--checkers`, `--checksum`,
  `--size-only`, `--update`, `--ignore-existing`, `--track-renames`, `--immutable`, `--max-delete`,
  `--order-by`, `--suffix`, `--suffix-keep-extension`, `--include`, `--exclude`, `--filter`, and for
  listings `--recursive`, `--dirs-only`, `--files-only`, `--hash`. The short forms `-n`, `-c`, `-P`,
  `-u` and `-R` are understood too. `--progress`, `--stats` and `--stats-one-line` are accepted and
  noted in the output, but have no effect on this engine.
- **Any other flag refuses the whole command.** That is deliberate. A flag this engine cannot carry
  would otherwise be silently dropped — and silently dropping a `--max-delete` or a
  `--delete-excluded` changes what the command does to your files. Refusing the line is the safe
  failure.
- Paths need to be a remote in `name:path` form. A bare local path has no remote to attach to and is
  refused for the commands that need one.

Autocomplete offers the same flag list on both engines, so on the in-process engine it can suggest a
flag the translator then refuses. If that happens, the refusal message names the flag.

## Stopping a command

`Stop` cancels a running command. On the binary engine that closes the connection carrying the output,
which cancels the command inside rclone. On the in-process engine it asks rclone to stop the
command it is running.

A stopped command prints `■ stopped`. Stopping is not an undo: whatever a `copy` had already
transferred, or a `delete` had already removed, stays that way.

You can also stop a console command from the transfers list, where it appears like any other transfer
while it runs.

## What the console will not do

- It will not run non-rclone programs, shell builtins, pipes or redirections.
- It will not read from standard input, so commands that expect typed answers have no way to receive
  them. This is part of why the interactive commands are blocked.
- It will not change your rclone config. Adding, editing, encrypting, importing and exporting remotes
  all happen in the app's own screens — see [Config and devices](config-and-devices.md).
- It will not survive the tab. Output and history go when the tab closes, and nothing is written to
  disk.

## See also

- [Getting started](getting-started.md) — installing, adding your first remote, Advanced mode
- [Transferring files](transferring.md) — copy, move and sync through the dialogs
- [Mounting and sharing](mount-and-share.md) — the supported replacements for `mount` and `serve`
- [Config and devices](config-and-devices.md) — where your remotes actually live
- [Troubleshooting](troubleshooting.md) — engine problems and problem reports
