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
install -Dm644 "$PKG/com.gigaionllc.airclone.desktop" \
  "$APPDIR/usr/share/applications/com.gigaionllc.airclone.desktop"
for size in 64 128 256 512; do
  install -Dm644 "$PKG/icons/$size.png" \
    "$APPDIR/usr/share/icons/hicolor/${size}x${size}/apps/com.gigaionllc.airclone.png"
done

say "Resolving shared libraries"
# linuxdeploy walks every ELF file in the AppDir and copies what they need,
# honouring the upstream exclude list — glibc, libGL, X11 and friends are
# deliberately NOT bundled, because bundling them is what makes an AppImage fail
# on a machine whose graphics stack differs. What it does bundle is the part a
# distro may genuinely not have: libmpv (media preview) and libsecret (the OS
# credential store), plus their dependency trees.
# linuxdeploy's exclude list treats libjack as a system library, and on a machine
# with JACK installed it is one. Plenty of desktops have no JACK at all, and mpv
# links it rather than dlopen-ing it, so an AppImage without it dies at startup
# on those machines with "libjack.so.0: cannot open shared object file". Bundle
# it when the build host has it.
#
# libasound is deliberately NOT forced in HERE, because anything in usr/lib is on
# the search path and would shadow the host's on every machine. It is handled
# separately, as a conditional last resort — see "Staging a last-resort ALSA"
# below.
EXTRA=()
for lib in libjack.so.0; do
  path="$(ldconfig -p | awk -v n="$lib" '$1 == n { print $NF; exit }')"
  if [ -n "$path" ]; then
    echo "  force-bundling $lib ($path)"
    EXTRA+=(--library "$path")
  else
    echo "  NOTE: $lib is not on this build host, so it will not be bundled"
  fi
done

"$TOOLS/linuxdeploy" \
  --appdir "$APPDIR" \
  --executable "$APPDIR/usr/bin/airclone" \
  --desktop-file "$APPDIR/usr/share/applications/com.gigaionllc.airclone.desktop" \
  --icon-file "$PKG/icons/256.png" \
  --icon-filename com.gigaionllc.airclone \
  "${EXTRA[@]}"

say "Staging a last-resort ALSA"
# libasound is the one library that must NOT be bundled the ordinary way, and
# must still be available if the machine has none.
#
# Why not the ordinary way: DT_RUNPATH is searched BEFORE ld.so.cache, so a copy
# in usr/lib would shadow the host's on EVERY machine, not just one missing it.
# That breaks working systems, because ALSA loads plugin modules from host paths
# (/usr/lib/<triplet>/alsa-lib, /usr/share/alsa/alsa.conf) and the route to
# PipeWire/PulseAudio *is* one of those plugins. Our build-host copy would look
# for them where Ubuntu puts them and find nothing on a Fedora or an Arch.
#
# Why have it at all: without libasound the app does not degrade, it does not
# start — the dynamic linker refuses before main(), so someone who only wanted to
# copy files gets nothing. Slim containers and WSL really are like this.
#
# So: keep it OUT of the search path, in usr/lib/fallback, and let AppRun add
# that directory only when the system has no libasound at all. On such a machine
# audio was never going to work anyway; the point is that the app runs.
FALLBACK="$APPDIR/usr/lib/fallback"
mkdir -p "$FALLBACK"
alsa="$(ldconfig -p | awk '$1 == "libasound.so.2" { print $NF; exit }')"
if [ -n "$alsa" ]; then
  cp -L "$alsa" "$FALLBACK/libasound.so.2"
  echo "  staged $(basename "$alsa") as a fallback only"
else
  echo "  NOTE: the build host has no libasound either — no fallback staged"
fi

# linuxdeploy leaves AppRun as a SYMLINK straight to the executable, which means
# nothing can be decided at launch. Replace it with a launcher that can.
#
# rm FIRST, and this is not tidiness: `cat >` follows a symlink and writes
# THROUGH it. Without the rm, the launcher below overwrites usr/bin/airclone —
# the actual Flutter binary — while AppRun stays a symlink pointing at it. The
# AppImage then builds, passes a file-exists check, and dies at startup looking
# for usr/bin/usr/bin/airclone.
rm -f "$APPDIR/AppRun"
cat > "$APPDIR/AppRun" <<'APPRUN'
#!/bin/sh
# Airclone AppImage launcher.
HERE="$(dirname "$(readlink -f "$0")")"

# Use the bundled ALSA ONLY when the system has none. ldconfig lives in /sbin on
# most distros and is not always on a user's PATH, so try both; if neither can be
# run we assume the system has one, which is the safe guess — shadowing a working
# ALSA is worse than the app failing to start on a machine that has none.
if ! { /sbin/ldconfig -p 2>/dev/null || ldconfig -p 2>/dev/null; } \
     | grep -q 'libasound\.so\.2'; then
  export LD_LIBRARY_PATH="$HERE/usr/lib/fallback${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

exec "$HERE/usr/bin/airclone" "$@"
APPRUN
chmod +x "$APPDIR/AppRun"
echo "  AppRun replaced with a launcher that chooses at run time"

say "Checking the libraries a distro may not have are really inside"
# A POSITIVE check, because the ldd one below cannot do this job: ldd resolves
# against the BUILD MACHINE, which has every one of these installed, so it passes
# whether or not they were bundled. That is exactly how an AppImage ships looking
# verified and then fails on a user's machine.
for lib in libmpv.so.2 libsecret-1.so.0; do
  if find "$APPDIR" -name "$lib" -print -quit | grep -q .; then
    echo "  $lib bundled"
  else
    echo "$lib is NOT in the AppDir — the AppImage would rely on the user having it." >&2
    exit 1
  fi
done

say "Checking the rclone engine is where the app will look for it"
# Deliberately NOT a find-anywhere check like the loop above. RcloneEngine
# resolves a bundled engine relative to its OWN binary
# (bundledDesktopBinary(): exeDir + "/rclone"), so a copy that linuxdeploy had
# relocated into usr/lib would satisfy `find` and be invisible to the app.
#
# Why fatal: without it the engine search falls through to `which rclone` and
# picks up whatever version happens to be on the user's PATH — or, on a machine
# with none, sits on first run downloading one. Both were reported on Ubuntu
# 24.04 against v0.8.3, which shipped no binary at all.
if [ -s "$APPDIR/usr/bin/rclone" ] && [ -x "$APPDIR/usr/bin/rclone" ]; then
  echo "  rclone is beside the executable ($(stat -c %s "$APPDIR/usr/bin/rclone") bytes)"
else
  echo "usr/bin/rclone is missing, empty or not executable — this AppImage would" >&2
  echo "download an engine on first run instead of using the bundled one." >&2
  exit 1
fi
# librclone.so is the in-process engine and is genuinely optional: the binary
# above is the fallback, so note its absence rather than failing the build.
if [ -s "$APPDIR/usr/bin/librclone.so" ]; then
  echo "  librclone.so is beside the executable (in-process engine available)"
else
  echo "  NOTE: no librclone.so — this AppImage ships the binary engine only."
fi

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
