#!/bin/bash
# fusermount, run on the HOST, for Airclone's Flatpak.
#
# Installed as /app/bin/fusermount3 and /app/bin/fusermount. rclone mounts a
# FUSE filesystem by exec'ing one of those helpers, which performs the mount and
# passes the /dev/fuse descriptor back over a socket named by _FUSE_COMMFD.
#
# WHY IT EXISTS. A mount made inside the Flatpak sandbox exists only inside the
# sandbox's own mount namespace, so no other program - not the file manager, not
# an editor - can see it, and seeing the files from elsewhere is the only reason
# to mount. Running the helper on the host puts the mount in the host namespace,
# where everything can see it. rclone itself stays inside the sandbox and serves
# the filesystem through the descriptor it is handed back.
#
# WHAT IT NEEDS, AND WHY THE APP DOES NOT ASK FOR IT. `flatpak-spawn --host`
# requires --talk-name=org.freedesktop.Flatpak. That permission is not narrow: it
# lets the app run ANY command on the host, not only this one. So Airclone's
# manifest deliberately does not request it - and Flathub would not accept a
# manifest that did - and a user who wants mounting grants it themselves, once,
# having been told what it allows. Without it this script fails immediately and
# says so; the app checks the permission first and explains before getting here.
#
# Same approach as GNOME Builder's fusermount wrapper, which is on Flathub.
set -euo pipefail

say() { echo "fusermount (Airclone Flatpak): $*" >&2; }

if ! command -v flatpak-spawn >/dev/null 2>&1; then
  say "flatpak-spawn is not available, so the host mount helper cannot be reached."
  exit 1
fi

# Distinguish "no permission" from "no FUSE on the host", which otherwise both
# look like the probe below failing and would produce the wrong message.
if ! flatpak-spawn --host true >/dev/null 2>&1; then
  say "this Flatpak has not been allowed to run the mount helper on your computer."
  say "Grant it with: flatpak override --user --talk-name=org.freedesktop.Flatpak ${FLATPAK_ID:-com.gigaionllc.airclone}"
  exit 1
fi

fwd=()

# The socket rclone waits on for the /dev/fuse descriptor. It has to cross into
# the host process, or the mount happens and rclone never receives it.
if [ -n "${_FUSE_COMMFD:-}" ]; then
  case "$_FUSE_COMMFD" in
    '' | *[!0-9]*)
      say "_FUSE_COMMFD is not a file descriptor number: $_FUSE_COMMFD"
      exit 1
      ;;
  esac
  fwd+=("--env=_FUSE_COMMFD=$_FUSE_COMMFD")
  if [ "$_FUSE_COMMFD" -gt 2 ]; then
    fwd+=("--forward-fd=$_FUSE_COMMFD")
  fi
fi

# Any descriptor handed over as a /dev/fd/N argument is forwarded too. Only
# numeric ones: nothing else is a descriptor, and forwarding is not a place to
# pass a caller-controlled string through.
for arg in "$@"; do
  case "$arg" in
    /dev/fd/*)
      n="${arg#/dev/fd/}"
      case "$n" in
        '' | *[!0-9]*) ;;
        *) fwd+=("--forward-fd=$n") ;;
      esac
      ;;
  esac
done

# Prefer the helper this was invoked as, then fuse3's, then fuse2's. rclone looks
# up fusermount3 FIRST and uses whatever it finds - and it will always find this
# wrapper - so a host with only fuse2 installed would otherwise fail on a name it
# does not have, instead of falling back the way rclone does outside a sandbox.
invoked="$(basename "$0")"
host_helper=""
for candidate in "$invoked" fusermount3 fusermount; do
  if flatpak-spawn --host sh -c 'command -v "$1" >/dev/null 2>&1' sh "$candidate"; then
    host_helper="$candidate"
    break
  fi
done
if [ -z "$host_helper" ]; then
  say "FUSE is not installed on this computer (no fusermount3 or fusermount)."
  exit 127
fi

exec flatpak-spawn --host ${fwd[@]+"${fwd[@]}"} "$host_helper" "$@"
