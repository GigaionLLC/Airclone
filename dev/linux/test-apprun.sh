#!/usr/bin/env bash
# Tests the AppImage launcher's library decisions against simulated hosts.
#
# AppRun decides at launch whether to put the bundled last-resort libraries on
# the search path. Getting that wrong is invisible on the build machine, which
# has every library, and harmful on users' machines in one of two directions:
# a missing fallback means the app does not start, and a fallback that is used
# when it should not be shadows a working system library - on an NVIDIA desktop,
# a bundled libGLESv2 in front of the driver's own.
#
# So this extracts the REAL AppRun from build-appimage.sh and runs it against a
# fake `ldconfig -p` for each host shape. Only the extracted COPY is altered, in
# two ways, and neither touches a decision:
#   - `/sbin/ldconfig` is pointed at a path that does not exist, so AppRun falls
#     through to `ldconfig` on PATH (its own documented fallback order) and finds
#     the fake. On a real Linux box /sbin/ldconfig would otherwise win.
#   - the final `exec` is replaced by printing LD_LIBRARY_PATH.
#
# Usage: dev/linux/test-apprun.sh
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO/dev/linux/build-appimage.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

start="$(grep -n "^cat > \"\$APPDIR/AppRun\" <<'APPRUN'" "$SCRIPT" | cut -d: -f1)"
end="$(grep -n '^APPRUN$' "$SCRIPT" | cut -d: -f1)"
[ -n "$start" ] && [ -n "$end" ] || { echo "could not find AppRun in $SCRIPT" >&2; exit 1; }

sed -n "$((start + 1)),$((end - 1))p" "$SCRIPT" |
  sed 's#/sbin/ldconfig#/nonexistent/ldconfig#' |
  grep -v '^exec ' > "$T/AppRun"
echo 'echo "LD=${LD_LIBRARY_PATH:-<unset>}"' >> "$T/AppRun"
bash -n "$T/AppRun"

# The substitution must have happened, or the fakes below are never consulted
# and every "nothing added" case passes for the wrong reason.
if grep -q '/sbin/ldconfig' "$T/AppRun"; then
  echo "harness error: /sbin/ldconfig still present in the extracted AppRun" >&2
  exit 1
fi

mkdir -p "$T/bin"
pass=0
fail=0

check() {
  local name="$1" libs="$2" want_alsa="$3" want_gles="$4" out got_alsa got_gles
  if [ "$libs" = "__NO_LDCONFIG__" ]; then
    out="$(env -i PATH="$T/empty" HOME=/tmp /bin/bash "$T/AppRun" 2>/dev/null)"
  else
    printf '#!/bin/sh\necho "%s"\n' "$libs" > "$T/bin/ldconfig"
    chmod +x "$T/bin/ldconfig"
    out="$(env -i PATH="$T/bin:/usr/bin:/bin" HOME=/tmp /bin/bash "$T/AppRun" 2>/dev/null)"
  fi
  got_alsa=no
  got_gles=no
  case "$out" in *"/usr/lib/fallback:"* | *"/usr/lib/fallback") got_alsa=yes ;; esac
  case "$out" in *fallback-gles*) got_gles=yes ;; esac
  if [ "$got_alsa" = "$want_alsa" ] && [ "$got_gles" = "$want_gles" ]; then
    echo "PASS  $name"
    pass=$((pass + 1))
  else
    echo "FAIL  $name"
    echo "      wanted alsa=$want_alsa gles=$want_gles, got alsa=$got_alsa gles=$got_gles ($out)"
    fail=$((fail + 1))
  fi
}

check "a normal desktop has everything, so nothing is added" \
  'libasound.so.2 libGLESv2.so.2 libGLdispatch.so.0 libEGL_mesa.so.0' no no

check "reported WSL case: Mesa EGL present, no libGLESv2 -> GLES fallback" \
  'libasound.so.2 libGLdispatch.so.0 libEGL_mesa.so.0' no yes

check "NVIDIA driver present, no libGLESv2 -> GLES fallback" \
  'libasound.so.2 libGLdispatch.so.0 libEGL_nvidia.so.0' no yes

check "no graphics stack -> no GLES fallback; the runner explains instead" \
  'libasound.so.2' no no

check "glvnd core but no EGL vendor -> no GLES fallback, nothing to forward to" \
  'libasound.so.2 libGLdispatch.so.0' no no

check "ISOLATION: host lacking only ALSA must not get the bundled libGLESv2" \
  'libGLESv2.so.2 libGLdispatch.so.0 libEGL_nvidia.so.0' yes no

check "ldconfig unavailable -> assume the host has everything" \
  "__NO_LDCONFIG__" no no

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
