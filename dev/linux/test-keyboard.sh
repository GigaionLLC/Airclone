#!/usr/bin/env bash
# Does a keystroke reach the app at all, on Linux?
#
# WHY THIS EXISTS. A tester on WSL could click everything and type nothing - not
# in the filter, not anywhere - in both the AppImage and the Flatpak, while
# xterm on the same display typed fine. Two packages that share no GTK, no
# libraries and no sandbox, failing the same way, points at something Airclone
# itself does to its window. The suspect is the ARGB visual the runner asks for
# when the session is composited (my_application.cc, apply_window_chrome), which
# only started taking effect in v0.10.0: flutter_acrylic asks for one too, but
# AFTER realize, which GTK documents as doing nothing.
#
# HOW IT ANSWERS THAT. The app is run with --log-input, which prints one line per
# key event and whether a text field had focus (lib/src/ui/input_log.dart). The
# test types into the window and reads those lines. An earlier version of this
# script compared screenshots instead and reported "typing did not reach the app"
# against a window whose GL surface it could not capture at all - it measured
# zero pixels of change while the app sat IDLE, which is the tell that a pixel
# test proves nothing here.
#
# It runs twice: with a compositing manager, which is what makes the app take the
# ARGB path (the window then reports depth 32), and without.
set -uo pipefail

BIN="${1:?usage: test-keyboard.sh /path/to/binary [window-name]}"
[ -x "$BIN" ] || { echo "not executable: $BIN" >&2; exit 1; }
# The window to type into, by name. Parameterised so the same harness can run
# against a STOCK Flutter app as a control: if a bare flutter-create app logs no
# keys either, the fault is not Airclone's.
WINDOW_NAME="${2:-airclone}"

DISPLAY_NUM=":99"
TYPED="zzzz"
MIN_LINES=4   # one per key down; key up lines are a bonus, not a requirement

need() { command -v "$1" >/dev/null || { echo "missing tool: $1" >&2; exit 1; }; }
need Xvfb; need xdotool; need xdpyinfo; need xwininfo

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

# One run of the app: $1 is a label, $2 is "yes" to run a compositing manager.
run_case() {
  local label="$1" composited="$2" cm_pid="" app_pid="" win="" log depth focus
  local dir="$work/$label"
  mkdir -p "$dir"
  log="$dir/app.log"

  if [ "$composited" = yes ]; then
    command -v xcompmgr >/dev/null || { echo "missing tool: xcompmgr" >&2; return 2; }
    xcompmgr >/dev/null 2>&1 &
    cm_pid=$!
    sleep 1
  fi

  "$BIN" --log-input >"$log" 2>&1 &
  app_pid=$!

  for _ in $(seq 1 90); do
    win="$(xdotool search --onlyvisible --name "$WINDOW_NAME" 2>/dev/null | head -1 || true)"
    [ -n "$win" ] && break
    kill -0 "$app_pid" 2>/dev/null || break
    sleep 1
  done
  if [ -z "$win" ]; then
    echo "  [$label] the app never mapped a window"
    sed -n '1,20p' "$log"
    kill "$app_pid" 2>/dev/null; [ -n "$cm_pid" ] && kill "$cm_pid" 2>/dev/null
    return 2
  fi

  # Depth 32 is the ARGB visual in use; 24 means the branch was not taken, so a
  # pass in this case says nothing about the other one.
  depth="$(xwininfo -id "$win" 2>/dev/null | sed -n 's/.*Depth: *//p' | head -1)"

  # The app must be up enough to be listening: the flag prints a banner line
  # when logging starts, which is the earliest honest "ready" signal there is.
  local ready=""
  for _ in $(seq 1 60); do
    grep -q 'input logging on' "$log" && { ready=1; break; }
    kill -0 "$app_pid" 2>/dev/null || break
    sleep 1
  done
  if [ -z "$ready" ]; then
    echo "  [$label] the app never started input logging"
    sed -n '1,20p' "$log"
    kill "$app_pid" 2>/dev/null; [ -n "$cm_pid" ] && kill "$cm_pid" 2>/dev/null
    return 2
  fi
  sleep 4

  # Focus the way a person does: pointer in, click, then type. These are XTEST
  # events, which are real input; XSendEvent ones (xdotool --window) are what
  # toolkits routinely ignore, and a test built on those would fail for its own
  # reasons rather than the app's.
  local wx wy
  wx="$(xwininfo -id "$win" | sed -n 's/.*Width: *//p' | head -1)"
  wy="$(xwininfo -id "$win" | sed -n 's/.*Height: *//p' | head -1)"
  xdotool windowfocus "$win" 2>/dev/null || true
  xdotool mousemove --window "$win" $(( ${wx:-800} / 2 )) $(( ${wy:-600} / 2 )) click 1 2>/dev/null || true
  sleep 2
  focus="$(xdotool getwindowfocus 2>/dev/null || echo none)"

  xdotool type --clearmodifiers --delay 80 "$TYPED" 2>/dev/null || true
  sleep 3

  local seen
  seen="$(grep -c '^input: ' "$log" 2>/dev/null || echo 0)"
  kill "$app_pid" 2>/dev/null; wait "$app_pid" 2>/dev/null
  [ -n "$cm_pid" ] && { kill "$cm_pid" 2>/dev/null; wait "$cm_pid" 2>/dev/null; }

  echo "  [$label] window $win depth ${depth:-?}, X focus $focus, $seen key events logged"
  grep '^input: ' "$log" 2>/dev/null | head -4 | sed 's/^/    /'
  if [ "${seen:-0}" -ge "$MIN_LINES" ]; then
    return 0
  fi
  echo "  [$label] KEYSTROKES DID NOT REACH THE APP"
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
