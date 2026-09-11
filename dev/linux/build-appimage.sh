#!/usr/bin/env bash
# Package a built Flutter Linux bundle as an AppImage.
#
# Until v0.8.1 the only Linux artifact was `airclone-linux-x64.tar.gz` — the raw
# Flutter bundle. It runs, but it integrates with nothing: no menu entry, no
# icon, no file associations. You unpack it somewhere and remember where. Every
# other platform gets an installer; Linux got a folder.
#
# Usage (from anywhere):
#   dev/linux/build-appimage.sh [BUNDLE_DIR] [OUTPUT]
#
# Defaults to app/build/linux/x64/release/bundle and Airclone-x86_64.AppImage in
# the repo root. Needs no root: both tools are AppImages fetched to a cache dir.
#
# WHAT MUST BE INSTALLED TO RUN THIS. linuxdeploy copies libraries FROM THE
# BUILD MACHINE, so the machine packaging the AppImage needs the same runtime
# libraries the build needed — libmpv, libsecret-1, libasound2. Without them it
# stops with "Could not find dependency: libsecret-1.so.0" rather than shipping
# an AppImage that is missing one. CI already installs them to build at all.
#
# Testing under WSL: run it with a Linux-only PATH
# (`env PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`).
# WSL appends the Windows PATH, linuxdeploy walks every entry, and an unreadable
# one aborts it with a std::filesystem "Permission denied" that looks nothing
# like the real cause.
#
# THE LAYOUT TRAP. A Flutter Linux app finds its assets RELATIVE TO ITS OWN
# BINARY — `data/` and `lib/` must be siblings of the executable, not merged into
# the AppDir's usr/lib. So the whole bundle goes into usr/bin/ intact and
# linuxdeploy is pointed at the executable already sitting there. Flattening the
# bundle produces an AppImage that builds fine and then dies at startup with
# "Failed to load AOT snapshot".
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUNDLE="${1:-$REPO/app/build/linux/x64/release/bundle}"
OUTPUT="${2:-$REPO/Airclone-x86_64.AppImage}"
PKG="$REPO/app/linux/packaging"
WORK="${APPIMAGE_WORK:-$(mktemp -d)}"
TOOLS="${APPIMAGE_TOOLS:-$HOME/.cache/airclone-appimage-tools}"

# Pinned rather than "continuous": an AppImage that silently changes its runtime
# between releases is the kind of thing that breaks on one distro and nowhere a
# maintainer can see.
LINUXDEPLOY_URL="https://github.com/linuxdeploy/linuxdeploy/releases/download/1-alpha-20240109-1/linuxdeploy-x86_64.AppImage"
APPIMAGETOOL_URL="https://github.com/AppImage/appimagetool/releases/download/1.9.0/appimagetool-x86_64.AppImage"

say() { printf '\n== %s\n' "$*"; }

[ -x "$BUNDLE/airclone" ] || {
  echo "No Flutter bundle at $BUNDLE — run 'flutter build linux --release' first." >&2
  exit 1
}

# appimagetool shells out to desktop-file-validate and refuses to run without it,
# with a message that arrives only AFTER the slow part (staging, and resolving
# the whole libmpv dependency tree) has already succeeded. Say so up front
# instead: it is `desktop-file-utils` on Debian/Ubuntu and Fedora alike.
command -v desktop-file-validate >/dev/null || {
  echo "desktop-file-validate is missing — appimagetool needs it." >&2
  echo "Install it:  sudo apt-get install -y desktop-file-utils" >&2
  exit 1
}

say "Fetching packaging tools"
mkdir -p "$TOOLS"
fetch() { # url dest
  [ -x "$2" ] && { echo "  cached $(basename "$2")"; return; }
  echo "  downloading $(basename "$2")"
  curl -fsSL --retry 3 -o "$2" "$1"
  chmod +x "$2"
}
fetch "$LINUXDEPLOY_URL" "$TOOLS/linuxdeploy"
fetch "$APPIMAGETOOL_URL" "$TOOLS/appimagetool"

# Both tools are themselves AppImages. A CI container (and WSL) often has no
# FUSE, and mounting would fail with a message that reads like a build error, so
# always self-extract instead.
export APPIMAGE_EXTRACT_AND_RUN=1
export ARCH=x86_64

APPDIR="$WORK/AppDir"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin"

say "Staging the Flutter bundle"
# -a, and the WHOLE bundle: airclone, data/, lib/ and librclone.so (the
# in-process engine) all keep their relative positions. See the layout trap above.
cp -a "$BUNDLE"/. "$APPDIR/usr/bin/"
chmod +x "$APPDIR/usr/bin/airclone"
echo "  staged $(du -sh "$APPDIR/usr/bin" | cut -f1)"

say "Installing desktop entry and icons"
# The desktop file is named for the GTK application id (APPLICATION_ID in
# linux/CMakeLists.txt, which my_application.cc passes to g_set_prgname). A
# mismatch here is why a running app sometimes shows a generic cog in the dock
# instead of its own icon: the shell matches the window's class to a .desktop
# file by name.
install -Dm644 "$PKG/app.airclone.airclone.desktop" \
  "$APPDIR/usr/share/applications/app.airclone.airclone.desktop"
for size in 64 128 256 512; do
  install -Dm644 "$PKG/icons/$size.png" \
    "$APPDIR/usr/share/icons/hicolor/${size}x${size}/apps/app.airclone.airclone.png"
done

say "Resolving shared libraries"
# linuxdeploy walks every ELF file in the AppDir and copies what they need,
# honouring the upstream exclude list — glibc, libGL, X11 and friends are
# deliberately NOT bundled, because bundling them is what makes an AppImage fail
# on a machine whose graphics stack differs. What it does bundle is the part a
# distro may genuinely not have: libmpv (media preview) and libsecret (the OS
# credential store), plus their dependency trees.
"$TOOLS/linuxdeploy" \
  --appdir "$APPDIR" \
  --executable "$APPDIR/usr/bin/airclone" \
  --desktop-file "$APPDIR/usr/share/applications/app.airclone.airclone.desktop" \
  --icon-file "$PKG/icons/256.png" \
  --icon-filename app.airclone.airclone

say "Checking nothing is left unresolved"
# The failure this catches is the expensive one: an AppImage that builds, ships,
# and then refuses to start on a machine that happens to lack one library. Run it
# against the AppDir now rather than finding out from a bug report.
missing=0
while IFS= read -r -d '' elf; do
  if ldd "$elf" 2>/dev/null | grep -q 'not found'; then
    echo "  UNRESOLVED in ${elf#"$APPDIR"/}:"
    ldd "$elf" 2>/dev/null | grep 'not found' | sed 's/^/    /'
    missing=1
  fi
done < <(find "$APPDIR" -type f \( -name '*.so' -o -name '*.so.*' -o -name airclone \) -print0)
if [ "$missing" -ne 0 ]; then
  echo "Refusing to package an AppImage with unresolved libraries." >&2
  exit 1
fi
echo "  all libraries resolved"

say "Building the AppImage"
rm -f "$OUTPUT"
"$TOOLS/appimagetool" "$APPDIR" "$OUTPUT"

say "Done"
ls -lh "$OUTPUT"
echo "Run it with:  $OUTPUT"
