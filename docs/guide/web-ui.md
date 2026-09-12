# The Web UI

The Web UI serves Airclone's own interface to a browser. You open a page on your phone, laptop or
tablet, and you are driving the Airclone running on another machine.

This is the shape it is built for: Airclone on a machine that is always on — a home server, a NAS, a
box in a cupboard with no monitor — and you reaching it from wherever you happen to be.

**Everything still happens on that machine.** This is the part worth reading twice:

- If you **mount a drive**, it mounts on the machine running Airclone. Not on your phone.
- If you **browse a disk**, you are browsing that machine's disks. "Host computer" in the sidebar is
  its storage, not your device's.
- If you **copy or sync**, that machine's rclone does the work, at its network speed, and it keeps
  going after you close the tab.

Your browser draws the picture and sends your intent. It does not touch a single file.

## Starting it

### From the app

**Settings → Remote access → Web UI.** Turn the switch on. The panel then shows the address, the
username and the password.

### From a command line

For a machine with no screen:

```bash
airclone --webui
```

It prints the address and, the very first time, the generated password. Then it stays running until
you stop it.

| Flag | What it does | Default |
|---|---|---|
| `--webui` | Start the Web UI instead of opening a window | — |
| `--webui-bind <address>` | Which address to listen on. `all` means every network | `127.0.0.1` |
| `--webui-port <port>` | Which port to listen on | `5799` |

```bash
# Reachable from your LAN
airclone --webui --webui-bind all

# One specific interface, on a different port
airclone --webui --webui-bind 192.168.1.50 --webui-port 8080
```

If you give it an address that is not an IP address, it refuses to start rather than quietly
listening somewhere else. Being wrong about who can reach your files is not a small mistake.

## Who can reach it

**It listens only to the machine itself unless you say otherwise.** `127.0.0.1` means the Web UI is
reachable from that computer and nowhere else — useful for testing, useless for a headless server.
To actually use it from another device you have to opt in, with `--webui-bind all` or the **Any
network** button in Settings.

When you do, Airclone says so: a warning in the log, and a banner in Settings that stays there the
whole time it is running.

The connection is encrypted — see [Security](#security) below for the certificate and the browser
warning you should expect. Encryption is not exposure control, though: do not port-forward this to
the internet. A password and a certificate protect the connection, not your patience with whoever
finds the port.

## Signing in

There is always a password. There is no setting, flag or build that turns authentication off,
because the thing behind that password is every remote you have configured.

The first time the Web UI starts, it generates a long random password and saves it next to your
rclone config, in a file called `webui.env`:

| Platform | Where |
|---|---|
| Windows | `%APPDATA%\Gigaion, LLC\Airclone\webui.env` |
| macOS | `~/Library/Application Support/Airclone/webui.env` |
| Linux | `~/.local/share/Airclone/webui.env` |

That file **is a password**. Anyone who can read it can sign in.

- **To see the password again:** open the file, or look in Settings → Remote access while it is
  running.
- **To change it:** delete the file. A new one is generated the next time the Web UI starts. Or
  press **New password** in Settings, which also signs out everyone currently signed in.
- **To supply it yourself**, for a server where you would rather no password sat on disk, set
  `AIRCLONE_WEBUI_USER` and `AIRCLONE_WEBUI_PASSWORD` in the environment. Those win, and no file is
  written.

```ini
# /etc/systemd/system/airclone-webui.service
[Service]
Environment=AIRCLONE_WEBUI_USER=admin
Environment=AIRCLONE_WEBUI_PASSWORD=...
ExecStart=/opt/airclone/airclone --webui --webui-bind all
Restart=on-failure
```

Repeated wrong passwords from the same address start being made to wait, for longer each time. That
is per-address, so somebody guessing at your front door cannot lock you out of your own machine.

## Phone or desktop, automatically

There is one address and one app. The layout follows the screen: a narrow window gets the phone
interface, with the bottom bar and the touch-sized rows, and a wide one gets the desktop interface,
with the sidebar and the two panes. Resizing the window switches between them.

## Moving files between your browser and the server

**Download** sends the file to the browser you are using, rather than copying it to a folder on the
server. That is the only place a web page can put a file, and it is almost certainly what you meant:
you are sitting at the browser, not at the server. Select one or more files and choose `Download`.
Each one arrives as a normal browser download.

**Upload file…**, in the pane menu, picks a file from the machine you are browsing with and writes
it into the folder you are looking at. It appears only in the Web UI, because everywhere else
Airclone can already see both sides and "upload" is just a copy.

Two things worth knowing:

- **An online-only file will not download.** If a file is stored in the cloud and only a placeholder
  is on the server's disk (OneDrive Files On-Demand, iCloud, Proton), downloading it would quietly
  pull the whole thing down first — on the server's connection, possibly on someone's metered plan.
  Airclone refuses and says so. Make it available offline first if you want it.
- **A dropped upload starts over.** There is no resume yet, so a large file over a poor connection
  is worth doing when the connection is good.

## Playing media in a browser

A browser brings its own video decoder, and it is a narrow one. **MP4, WebM and Ogg play; AVI, MKV,
WMV, FLV and MPG do not** — not here, not in any web page. The desktop and phone apps carry their own
decoder and play all of them, which is why the same file opens there and not here.

Airclone says so rather than showing you a failure: open one of those and you get a note naming the
format and pointing at `Download`. Nothing is wrong with the file or the server.

## Security

**The Web UI is HTTPS only.** There is no plain-HTTP option, and nothing to turn on: browsers now
upgrade or block plain HTTP, so it would be a worse experience as well as a second thing to secure.

**Your browser will warn you the first time.** This is expected, and not a sign anything is wrong.
Airclone signs a certificate for your own machine, and no authority can vouch for a computer on your
home network the way it can for a public website. Settings → `Remote access` shows the
certificate's **fingerprint** — compare it with the one your browser shows, once, and then continue.

If you would rather use your own certificate — from your own authority, or one renewed by a script —
put `cert.pem` and `key.pem` in the `webui/imported/` folder beside Airclone's settings. Airclone
uses that pair instead, and leaves its own alone so removing yours falls back rather than breaking.

## What it does not do

- **It is one account.** One username, one password, no separate logins for separate people.
- **Uploads do not resume.** A dropped connection means starting the file again.
- **Downloads are one file at a time.** There is no "download this folder as a zip" yet.
- **You cannot host the Web UI from a phone.** Android and iOS builds do not include it — a phone is
  not the machine you point a browser at.

## When something is wrong

**"This build does not include the web interface files."** You are signed in, but the app itself was
not packaged. Use a release build, or point `AIRCLONE_WEBUI_ROOT` at a `build/web` directory.

**The page will not load at all.** Check the address is the one Airclone printed. If you bound to
`127.0.0.1`, it is not reachable from another device by design.

**"Could not listen on ...:5799"** Something else is using that port. Pass `--webui-port` to pick
another.

**Everything was signed out.** Sessions live in memory, so restarting Airclone ends them. Sign in
again.
