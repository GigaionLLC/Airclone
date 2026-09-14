#!/usr/bin/env bash
# Does closing a second window take the whole app down?
#
# WHY THIS EXISTS. A tester popped an image out into its own window on Linux,
# closed that window, and lost the main window with it - a segmentation fault
# after "'FlutterEngineRemoveView' returned 'kInvalidArguments'. The implicit
# view cannot be removed."
#
# Two suspects that want opposite fixes: desktop_multi_window's teardown on this
# embedder, or what Airclone does to every window it creates - it registers the
# whole generated plugin set on each one, and flutter_acrylic's Linux registrar
# keeps a GLOBAL pointer to the newest registrar, hooks that window's "draw"
# signal, and shows it. A closed pop-out leaves that global pointing at a freed
# engine.
#
# So the same app is built twice, from dev/linux/popout_control_main.dart:
#
#   plain    desktop_multi_window only
#   acrylic  the same, plus flutter_acrylic registered on the second window,
#            the way app/linux/runner/my_application.cc registers it
#
# Each opens a window, closes it, and prints that it survived. A case that dies
# instead names the cause. Exit 0 = both survived, 1 = one died, 2 = the test
# could not run.
set -uo pipefail

need() { command -v "$1" >/dev/null || { echo "missing tool: $1" >&2; exit 2; }; }
need flutter; need Xvfb; need xdpyinfo

WORK="$(mktemp -d)"
DISPLAY_NUM=":98"
xvfb_pid=""
cleanup() {
  [ -n "$xvfb_pid" ] && kill "$xvfb_pid" 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

Xvfb "$DISPLAY_NUM" -screen 0 1280x720x24 +extension COMPOSITE +extension RENDER \
  >/dev/null 2>&1 &
xvfb_pid=$!
export DISPLAY="$DISPLAY_NUM"
for _ in $(seq 1 30); do xdpyinfo >/dev/null 2>&1 && break; sleep 1; done
xdpyinfo >/dev/null 2>&1 || { echo "Xvfb never came up" >&2; exit 2; }

# $1 = label, $2 = "yes" to add flutter_acrylic and register it per window.
build_and_run() {
  local label="$1" with_acrylic="$2" dir="$WORK/$label"
  flutter create --platforms=linux --project-name popout_$label "$dir" >/dev/null 2>&1 \
    || { echo "  [$label] could not create the project" >&2; return 2; }
  cp "$REPO/dev/linux/popout_control_main.dart" "$dir/lib/main.dart"
  (cd "$dir" && flutter pub add desktop_multi_window >/dev/null 2>&1) \
    || { echo "  [$label] could not add desktop_multi_window" >&2; return 2; }

  if [ "$with_acrylic" = yes ]; then
    (cd "$dir" && flutter pub add flutter_acrylic >/dev/null 2>&1) \
      || { echo "  [$label] could not add flutter_acrylic" >&2; return 2; }
    # The line under test, copied from Airclone's runner: every window
    # desktop_multi_window creates gets the generated plugins registered on it.
    python3 - "$dir/linux/runner/my_application.cc" <<'PY'
import io, sys
path = sys.argv[1]
src = io.open(path, encoding='utf-8').read()
anchor = "  fl_register_plugins(FL_PLUGIN_REGISTRY(view));"
if anchor not in src:
    raise SystemExit("generated runner has changed shape: %s" % path)
src = src.replace(
    anchor,
    anchor
    + "\n\n  desktop_multi_window_plugin_set_window_created_callback(\n"
      "      [](FlPluginRegistry* registry) { fl_register_plugins(registry); });",
    1,
)
src = src.replace(
    '#include "flutter/generated_plugin_registrant.h"',
    '#include "flutter/generated_plugin_registrant.h"\n'
    '#include <desktop_multi_window/desktop_multi_window_plugin.h>',
    1,
)
io.open(path, 'w', encoding='utf-8', newline='\n').write(src)
PY
  fi

  (cd "$dir" && flutter build linux --release >"$WORK/$label-build.log" 2>&1) || {
    echo "  [$label] build failed"; tail -20 "$WORK/$label-build.log"; return 2;
  }

  local bin="$dir/build/linux/x64/release/bundle/popout_$label"
  timeout 120 "$bin" >"$WORK/$label.log" 2>&1
  local code=$?
  if grep -q 'the app survived closing the second window' "$WORK/$label.log"; then
    echo "  [$label] survived"
    return 0
  fi
  echo "  [$label] DIED (exit $code)"
  # 139 = segmentation fault through a shell.
  grep -E 'Segmentation|FlutterEngineRemoveView|without an engine|eglMakeCurrent' \
    "$WORK/$label.log" | head -5 | sed 's/^/    /'
  return 1
}

echo "Closing a second window, with and without Airclone's per-window plugin registration:"
plain=0
build_and_run plain no || plain=$?
acrylic=0
build_and_run acrylic yes || acrylic=$?

if [ "$plain" -eq 2 ] || [ "$acrylic" -eq 2 ]; then
  echo "could not run the test itself" >&2
  exit 2
fi
if [ "$plain" -ne 0 ] || [ "$acrylic" -ne 0 ]; then
  exit 1
fi
echo "closing a second window is survivable in both cases"
