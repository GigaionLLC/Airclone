#!/usr/bin/env bash
# Drive Airclone on an Android TV emulator with a REMOTE and nothing else.
#
# This exists because "it looks right on a TV" and "it can be operated on a TV"
# are different claims, and only the second one is what Google's TV review
# checks. A mouse click in the emulator window proves nothing: it is an input a
# real remote cannot produce. So this sends only D-pad key events, and captures
# the screen after each one, leaving a filmstrip that shows where focus actually
# went - including when it went nowhere.
#
#   dev/android/tv-dpad-probe.sh [outdir]
#
# Reads nothing, changes nothing, installs nothing. Build and install first.

set -euo pipefail

OUT="${1:-/tmp/tv-dpad}"
PKG=com.gigaionllc.airclone
# .exe too: on Windows (Git Bash) the bare name is not an executable file, and
# testing for it silently fell through to a PATH lookup that was not there.
SDK="${ANDROID_HOME:-$HOME/android-sdk}"
ADB=""
for cand in "$SDK/platform-tools/adb" "$SDK/platform-tools/adb.exe"; do
  [ -x "$cand" ] && ADB="$cand" && break
done
[ -n "$ADB" ] || ADB="$(command -v adb || true)"
if [ -z "$ADB" ]; then
  echo "error: no adb found (looked in $SDK/platform-tools and on PATH)" >&2
  exit 1
fi

mkdir -p "$OUT"
rm -f "$OUT"/*.png

# Capture, and say whether the screen actually CHANGED. A filmstrip of
# identical frames is the signature of focus having nowhere to move from, and
# it is invisible unless something compares them - the first run of this script
# produced seven identical frames and read as a success.
_prev=""
shot() {
  "$ADB" exec-out screencap -p > "$OUT/$1.png"
  local h
  h=$(md5sum "$OUT/$1.png" | cut -c1-8)
  if [ "$h" = "$_prev" ]; then
    echo "  $1: NO CHANGE (focus did not move)"
  else
    echo "  $1: changed"
  fi
  _prev="$h"
}

# Key codes, spelled out - the numbers are unreadable six months from now.
DPAD_UP=19 DPAD_DOWN=20 DPAD_LEFT=21 DPAD_RIGHT=22 DPAD_CENTER=23 BACK=4
press() { "$ADB" shell input keyevent "$1" >/dev/null; sleep "${2:-2}"; }

# Force-stop FIRST. `monkey` only brings an already-running task to the front,
# tab state and all, so without this the filmstrip opens on whatever screen the
# last run happened to leave behind - which is indistinguishable from the app
# launching there, and cost one full run to spot.
"$ADB" shell am force-stop "$PKG" >/dev/null 2>&1 || true
sleep 2
"$ADB" shell monkey -p "$PKG" -c android.intent.category.LEANBACK_LAUNCHER 1 >/dev/null 2>&1
until [ -n "$("$ADB" shell pidof "$PKG" 2>/dev/null | tr -d '\r')" ]; do sleep 2; done
sleep 20  # engine start + first listing

shot 00-launch
# Out of the rail and into the content, then down the list.
press $DPAD_RIGHT;  shot 01-right
press $DPAD_DOWN;   shot 02-down
press $DPAD_DOWN;   shot 03-down
press $DPAD_CENTER 4; shot 04-open      # open whatever has focus
press $BACK 3;      shot 05-back        # and back out of it
press $DPAD_LEFT;   shot 06-left        # back to the rail
press $DPAD_DOWN;   shot 07-rail-down   # Transfers
press $DPAD_CENTER 3; shot 08-transfers

echo "wrote $(ls "$OUT"/*.png | wc -l) frames to $OUT"
