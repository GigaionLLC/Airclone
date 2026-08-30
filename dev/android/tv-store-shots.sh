#!/usr/bin/env bash
# Capture the Google Play ANDROID TV screenshot set from a TV emulator.
#
# Play wants 1-8 images, 16:9, at least 1280x720. The tv_1080p emulator renders
# at exactly 1920x1080, so frames are captured at native size and need no
# scaling - which is why dev/android-tv.md specifies a 1080p AVD.
#
#   dev/android/tv-store-shots.sh [outdir]     # default docs/store/play/tv
#
# Drives the app with D-PAD KEYS ONLY, like tv-dpad-probe.sh: a shot taken after
# a mouse click could show a state a remote cannot reach, which would advertise
# something the reviewer then cannot do.
#
# Each screen is captured from a FRESH LAUNCH rather than by walking from the
# previous one. Walking looked cheaper and produced a set where three files were
# byte-identical pictures of the wrong screen: without a known starting point
# every key press is a guess about where focus already was, and one wrong guess
# silently corrupts every shot after it. A relaunch costs 30s and is certain.

set -euo pipefail

OUT="${1:-docs/store/play/tv}"
PKG=com.gigaionllc.airclone
export MSYS_NO_PATHCONV=1  # Git Bash rewrites /sdcard/... into a Windows path

SDK="${ANDROID_HOME:-$HOME/android-sdk}"
ADB=""
for cand in "$SDK/platform-tools/adb" "$SDK/platform-tools/adb.exe"; do
  [ -x "$cand" ] && ADB="$cand" && break
done
[ -n "$ADB" ] || ADB="$(command -v adb || true)"
[ -n "$ADB" ] || { echo "error: no adb found" >&2; exit 1; }

mkdir -p "$OUT"
DPAD_DOWN=20 DPAD_RIGHT=22 DPAD_CENTER=23

press() { "$ADB" shell input keyevent "$1" >/dev/null; sleep "${2:-2}"; }

launch() {
  "$ADB" shell am force-stop "$PKG" >/dev/null 2>&1 || true
  sleep 2
  "$ADB" shell monkey -p "$PKG" -c android.intent.category.LEANBACK_LAUNCHER 1 >/dev/null 2>&1
  until [ -n "$("$ADB" shell pidof "$PKG" 2>/dev/null | tr -d '\r')" ]; do sleep 2; done
  sleep 30  # engine start + first listing
}

# Refuse to capture anything that is not our app in the foreground.
#
# A screenshot of the WRONG APP passes every cheap check: it is 1920x1080, it is
# 16:9, and its hash differs from the others. One run of this shipped a picture
# of the Google Play sign-in screen as "04-transfers.png" because the app had
# gone to background. Size and uniqueness say nothing about what is IN the
# frame, so the window itself has to be asserted.
shot() {
  local focus
  focus=$("$ADB" shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus || true)
  case "$focus" in
    *"$PKG"*) : ;;
    *)
      echo "  $1: REFUSED - foreground window is not $PKG" >&2
      echo "     ($focus)" >&2
      return 1
      ;;
  esac
  "$ADB" exec-out screencap -p > "$OUT/$1.png"
  python - "$OUT/$1.png" <<'PY'
import struct, sys, hashlib, os
p = sys.argv[1]
d = open(p, 'rb').read()
w, h = struct.unpack('>II', d[16:24])
ok = 'OK ' if (w >= 1280 and h >= 720 and abs(w*9 - h*16) <= 16) else 'BAD'
print(f"  {os.path.basename(p):20} {w}x{h} {ok} {hashlib.md5(d).hexdigest()[:8]}")
PY
}

# Seed the demo remote. The app creates files/ on first run, so this cannot be
# written before it has launched once.
if [ "${SEED:-1}" = "1" ]; then
  launch >/dev/null 2>&1 || true
  "$ADB" shell appops set "$PKG" MANAGE_EXTERNAL_STORAGE allow >/dev/null 2>&1 || true
  "$ADB" shell am force-stop "$PKG" >/dev/null 2>&1 || true
  sleep 2
  "$ADB" shell "run-as $PKG sh -c 'printf \"[Demo Cloud]\ntype = alias\nremote = /sdcard/Download\n\" > files/rclone.conf'" \
    || echo "warning: could not seed the demo remote (release build? run-as needs a debuggable one)" >&2
fi

echo "capturing to $OUT"

launch
shot 01-locations

launch
press $DPAD_RIGHT; press $DPAD_DOWN
shot 02-focus                       # the focus ring, which is the TV story
press $DPAD_CENTER 6
shot 03-browsing                    # a real folder listing

launch
press $DPAD_DOWN                    # rail: Files -> Transfers
press $DPAD_CENTER 4
shot 04-transfers

echo "done - $(ls "$OUT"/*.png | wc -l) screenshots"
echo "Every line above must read OK, and no two hashes may match."
