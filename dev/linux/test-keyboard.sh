#!/usr/bin/env bash
# Does a keystroke reach the app at all, on Linux?
#
# WHY THIS EXISTS. A tester on WSL could click everything and type nothing - not
# in the filter, not anywhere - in both the AppImage and the Flatpak, while
# xterm on the same display typed fine. Two packages that share no GTK, no
# libraries and no sandbox, failing the same way, points at something Airclone
# itself does to its window. The prime suspect is the ARGB visual the runner
# asks for when the session is composited (my_application.cc, apply_window_chrome):
# before v0.10.0 nothing set a visual that GTK actually honoured, because
# flutter_acrylic sets one AFTER realize, which GTK documents as having no effect.
#
# So this runs the real binary twice on a virtual display - once with a
# compositing manager running, which is what makes the app ask for the ARGB
# visual, and once without - types into it, and checks the screen changed.
#
# WHAT "CHANGED" MEANS. There is no way to ask a Flutter app what it received,
# so the evidence is pixels. Two shots are taken before typing to measure how
# much the screen churns on its own (a caret blinks, animations settle). Then
# Ctrl+F opens the filter, a string is typed, and the screen is compared again.
# Input that arrives moves far more pixels than a blinking caret. A test that
# only asserted "something changed" would pass on the caret alone, which is why
# the idle churn is measured rather than assumed.
set -uo pipefail

BIN="${1:?usage: test-keyboard.sh /path/to/airclone}"
[ -x "$BIN" ] || { echo "not executable: $BIN" >&2; exit 1; }

DISPLAY_NUM=":99"
TYPED="zzzzzzzzzzzzzzzz"   # matches nothing, so the list empties: a big change
# How much more than the idle churn counts as "the app saw it". Generous on
# purpose: this test is here to catch NOTHING arriving, not to measure pixels.
MULTIPLE=4
FLOOR=2000                 # and at least this many pixels, for a quiet screen

need() { command -v "$1" >/dev/null || { echo "missing tool: $1" >&2; exit 1; }; }
need Xvfb; need xdotool; need import; need compare; need xdpyinfo; need identify; need xwininfo

work="$(mktemp -d)"
xvfb_pid=""
cleanup() {
  [ -n "$xvfb_pid" ] && kill "$xvfb_pid" 2>/dev/null
  rm -rf "$work"
}
trap cleanup EXIT

# +extension COMPOSITE is what gives the server a 32-bit ARGB visual to hand
# out; without it gdk_screen_get_rgba_visual() returns NULL and the branch under
# test cannot be reached at all.
Xvfb "$DISPLAY_NUM" -screen 0 1280x720x24 +extension COMPOSITE +extension RENDER \
  >/dev/null 2>&1 &
xvfb_pid=$!
export DISPLAY="$DISPLAY_NUM"
for _ in $(seq 1 30); do xdpyinfo >/dev/null 2>&1 && break; sleep 1; done
xdpyinfo >/dev/null 2>&1 || { echo "Xvfb never came up" >&2; exit 1; }

# Capture the APP's window, not the root: a root grab on a bare X server can be
# uniformly black whether or not the app drew anything.
shot() { import -window "$2" "$1" >/dev/null 2>&1; }
# How many distinct colours a capture holds. One means a flat rectangle - the
# app has not drawn, or software GL never presented - and no typing test run
# against that proves anything at all.
colours() { identify -format '%k' "$1" 2>/dev/null || echo 0; }
# compare writes the count to stderr and exits 1 when images differ, which is
# the normal case here.
pixels() { compare -metric AE "$1" "$2" null: 2>&1 | tr -d '\n' | cut -d. -f1; }

# One run of the app: $1 is a label, $2 is "yes" to run a compositing manager
# (which is what makes the app ask for an ARGB visual).
run_case() {
  local label="$1" composited="$2" cm_pid="" app_pid="" win="" base after verdict
  local dir="$work/$label"
  mkdir -p "$dir"

  if [ "$composited" = yes ]; then
    command -v xcompmgr >/dev/null || { echo "missing tool: xcompmgr" >&2; return 2; }
    xcompmgr >/dev/null 2>&1 &
    cm_pid=$!
    sleep 1
  fi

  "$BIN" >"$dir/app.log" 2>&1 &
  app_pid=$!

  for _ in $(seq 1 90); do
    win="$(xdotool search --onlyvisible --name airclone 2>/dev/null | head -1 || true)"
    [ -n "$win" ] && break
    kill -0 "$app_pid" 2>/dev/null || break
    sleep 1
  done
  if [ -z "$win" ]; then
    echo "  [$label] the app never mapped a window"
    sed -n '1,20p' "$dir/app.log"
    kill "$app_pid" 2>/dev/null; [ -n "$cm_pid" ] && kill "$cm_pid" 2>/dev/null
    return 2
  fi

  # Depth 32 here is the ARGB visual in use; 24 means the branch was not taken.
  local depth
  depth="$(xwininfo -id "$win" 2>/dev/null | sed -n 's/.*Depth: *//p' | head -1)"
  echo "  [$label] window $win, depth ${depth:-?}"

  # Wait for the app to actually DRAW. Without this the test happily compares
  # two identical black rectangles and reports that typing did nothing.
  local drew=""
  for _ in $(seq 1 40); do
    shot "$dir/first.png" "$win"
    if [ "$(colours "$dir/first.png")" -gt 1 ] 2>/dev/null; then drew=yes; break; fi
    sleep 2
  done
  if [ -z "$drew" ]; then
    echo "  [$label] the window never drew anything - cannot test typing here"
    sed -n '1,20p' "$dir/app.log"
    kill "$app_pid" 2>/dev/null; [ -n "$cm_pid" ] && kill "$cm_pid" 2>/dev/null
    return 2
  fi
  sleep 3                       # let the first frame settle

  # Focus the way a user does: pointer into the window, then a click. XTEST
  # events (no --window) are real input; XSendEvent ones are what toolkits
  # routinely ignore, and a test that sent those would fail for its own reasons.
  local wx wy
  wx="$(xwininfo -id "$win" | sed -n 's/.*Width: *//p' | head -1)"
  wy="$(xwininfo -id "$win" | sed -n 's/.*Height: *//p' | head -1)"
  xdotool windowfocus "$win" 2>/dev/null || true
  xdotool mousemove --window "$win" $(( ${wx:-800} / 2 )) $(( ${wy:-600} / 2 ))     click 1 2>/dev/null || true
  sleep 2

  shot "$dir/idle1.png" "$win"; sleep 2; shot "$dir/idle2.png" "$win"
  base="$(pixels "$dir/idle1.png" "$dir/idle2.png")"

  xdotool key --clearmodifiers ctrl+f 2>/dev/null || true
  sleep 1
  xdotool type --clearmodifiers --delay 60 "$TYPED" 2>/dev/null || true
  sleep 3
  shot "$dir/typed.png" "$win"
  after="$(pixels "$dir/idle2.png" "$dir/typed.png")"

  kill "$app_pid" 2>/dev/null; wait "$app_pid" 2>/dev/null
  [ -n "$cm_pid" ] && { kill "$cm_pid" 2>/dev/null; wait "$cm_pid" 2>/dev/null; }

  base="${base:-0}"; after="${after:-0}"
  if [ "$after" -gt "$FLOOR" ] && [ "$after" -gt "$((base * MULTIPLE))" ]; then
    verdict="typing reached the app"
    echo "  [$label] $verdict (idle churn $base px, after typing $after px)"
    return 0
  fi
  echo "  [$label] TYPING DID NOT REACH THE APP (idle churn $base px, after typing $after px)"
  return 1
}

echo "Keyboard input, on a composited display (ARGB visual) and a plain one:"
rc=0
run_case composited yes || rc=$?
plain_rc=0
run_case plain no || plain_rc=$?

if [ "$rc" -eq 2 ] || [ "$plain_rc" -eq 2 ]; then
  echo "could not run the test itself" >&2
  exit 2
fi
if [ "$rc" -ne 0 ] || [ "$plain_rc" -ne 0 ]; then
  echo "keyboard input did not reach the app" >&2
  exit 1
fi
echo "keyboard input reaches the app in both cases"
