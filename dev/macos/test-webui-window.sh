#!/usr/bin/env bash
# Does `--webui` put a window on screen on macOS?
#
# WHY THIS EXISTS. `--webui` is for a machine you are not sitting at. On macOS
# the window comes from the nib and AppKit shows it whatever the Dart entrypoint
# decides, so the app served the Web UI with an empty window and a Dock icon
# sitting there for as long as it ran. Linux had the same bug from a different
# cause, and CI caught that one only because it looked (linux-runner.yml).
#
# WHAT IT CHECKS. Windows are counted with CoreGraphics, the same list the Dock
# and Mission Control use - not screenshots, which would need a window server to
# cooperate and would then need interpreting. A plain launch must still show a
# window: without that control, a build too broken to open one at all would make
# the --webui half pass for the wrong reason, and on a runner with no window
# server the whole thing would look like a pass.
set -uo pipefail

APP="${1:?usage: test-webui-window.sh /path/to/Airclone.app}"
BIN="$APP/Contents/MacOS/Airclone"
[ -x "$BIN" ] || { echo "no executable at $BIN" >&2; exit 2; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cat > "$work/windows.swift" <<'SWIFT'
import CoreGraphics
import Foundation

// On-screen windows owned by a process whose name contains "airclone".
let info = CGWindowListCopyWindowInfo(
  [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
) as? [[String: Any]] ?? []
let ours = info.filter {
  ($0[kCGWindowOwnerName as String] as? String)?.lowercased().contains("airclone") ?? false
}
print(ours.count)
SWIFT
swiftc -O "$work/windows.swift" -o "$work/windows" 2>"$work/swiftc.log" || {
  echo "could not build the window counter:" >&2
  cat "$work/swiftc.log" >&2
  exit 2
}
count_windows() { "$work/windows" 2>/dev/null || echo 0; }

echo "Windows on screen, with --webui and without:"

"$BIN" --webui --webui-port 5799 >"$work/webui.log" 2>&1 &
app=$!
served=""
for _ in $(seq 1 90); do
  grep -q "Web UI listening" "$work/webui.log" && { served=1; break; }
  kill -0 "$app" 2>/dev/null || break
  sleep 1
done
if [ -z "$served" ]; then
  echo "  --webui never started serving"
  sed -n '1,40p' "$work/webui.log"
  kill "$app" 2>/dev/null || true
  exit 2
fi
sleep 3
webui_windows="$(count_windows)"
kill "$app" 2>/dev/null || true
wait "$app" 2>/dev/null || true
echo "  --webui: $webui_windows window(s)"

"$BIN" >"$work/gui.log" 2>&1 &
gui=$!
gui_windows=0
for _ in $(seq 1 90); do
  gui_windows="$(count_windows)"
  [ "${gui_windows:-0}" -gt 0 ] && break
  kill -0 "$gui" 2>/dev/null || break
  sleep 1
done
kill "$gui" 2>/dev/null || true
wait "$gui" 2>/dev/null || true
echo "  plain launch: $gui_windows window(s)"

if [ "${gui_windows:-0}" -eq 0 ]; then
  echo "a plain launch showed no window either - this runner cannot see windows," >&2
  echo "so the --webui result above proves nothing" >&2
  sed -n '1,20p' "$work/gui.log" >&2
  exit 2
fi
if [ "${webui_windows:-0}" -ne 0 ]; then
  echo "--webui put $webui_windows window(s) on screen" >&2
  exit 1
fi
echo "--webui served with no window, and a plain launch still shows one"
