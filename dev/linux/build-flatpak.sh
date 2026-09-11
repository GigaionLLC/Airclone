#!/usr/bin/env bash
# Package a built Flutter Linux bundle as a Flatpak bundle (.flatpak).
#
#   dev/linux/build-flatpak.sh [BUNDLE_DIR] [OUTPUT]
#
# Defaults to app/build/linux/x64/release/bundle and airclone.flatpak in the repo
# root. Produces a SINGLE-FILE bundle a user installs with:
#
#   flatpak install --user ./airclone.flatpak
#
# Needs flatpak + flatpak-builder and the GNOME runtime/SDK. Unlike the AppImage
# script this one cannot fetch its own tooling: flatpak-builder is not
# distributable as a standalone binary, so it has to be installed.
#
# WHY IT BUILDS FROM THE PREBUILT BUNDLE. The GNOME SDK has no Flutter
# toolchain, and teaching the manifest to fetch one so it can rebuild what CI
# just built serves nobody for a direct download. FLATHUB WOULD DIFFER: it
# requires a source build or `extra-data` with checksums, and it would also
# question the app ID — `app.airclone.airclone` implies the airclone.app domain,
# and Flathub wants an ID you demonstrably control (otherwise
# `io.github.gigaionllc.Airclone`). Changing it is not free: APPLICATION_ID in
# linux/CMakeLists.txt is what the running window reports, so the ID, the
# .desktop filename and that constant have to move together or the app loses its
# icon in the dock.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUNDLE="${1:-$REPO/app/build/linux/x64/release/bundle}"
OUTPUT="${2:-$REPO/airclone.flatpak}"
PKG="$REPO/app/linux/packaging"
APP_ID="app.airclone.airclone"
RUNTIME_VERSION="${FLATPAK_RUNTIME_VERSION:-48}"
WORK="${FLATPAK_WORK:-$(mktemp -d)}"

say() { printf '\n== %s\n' "$*"; }

[ -x "$BUNDLE/airclone" ] || {
  echo "No Flutter bundle at $BUNDLE — run 'flutter build linux --release' first." >&2
  exit 1
}
command -v flatpak >/dev/null || { echo "flatpak is not installed." >&2; exit 1; }
command -v flatpak-builder >/dev/null || {
  echo "flatpak-builder is not installed." >&2; exit 1;
}

say "Ensuring the GNOME runtime is available"
flatpak remote-add --user --if-not-exists flathub \
  https://dl.flathub.org/repo/flathub.flatpakrepo
# Both, and non-interactively: the SDK is needed to BUILD, the Platform to RUN,
# and flatpak-builder's error when one is missing names only the other.
flatpak install --user --noninteractive flathub \
  "org.gnome.Platform//$RUNTIME_VERSION" "org.gnome.Sdk//$RUNTIME_VERSION" || {
  echo "Could not install the GNOME runtime $RUNTIME_VERSION." >&2
  echo "Set FLATPAK_RUNTIME_VERSION to a version Flathub still offers." >&2
  exit 1
}

say "What the runtime already provides"
# The Flutter binary hard-links libmpv (media preview) and libsecret (the
# credential store). The AppImage gets them by copying from the build host;
# a Flatpak cannot — the sandbox has no access to the host's libraries, so
# anything the runtime lacks has to be BUILT as a module in the manifest.
# Printing it makes that a fact rather than a guess, and shows when a runtime
# bump changes the answer.
flatpak run --user --command=sh "org.gnome.Sdk//$RUNTIME_VERSION" -c \
  'ldconfig -p | grep -E "libmpv|libplacebo|libass|libsecret|libavcodec" || true' \
  2>/dev/null | sed 's/^/  /' || echo "  (could not inspect the runtime)"

say "Staging the build context"
CTX="$WORK/context"
rm -rf "$CTX"; mkdir -p "$CTX/bundle" "$CTX/icons"
cp -a "$BUNDLE"/. "$CTX/bundle/"
cp "$PKG/$APP_ID.desktop" "$PKG/$APP_ID.metainfo.xml" "$CTX/"
cp "$PKG"/icons/*.png "$CTX/icons/"
cp "$PKG/$APP_ID.yml" "$CTX/"

# /app/bin/airclone. Keeps the bundle intact under /app/airclone (see the
# manifest) while giving Flatpak the single `command` it expects on PATH.
cat > "$CTX/airclone-launcher" <<'LAUNCHER'
#!/bin/sh
# The Flutter binary must be executed from its own directory tree so it can find
# data/ and lib/ beside itself; exec keeps the PID so the sandbox still tracks it.
exec /app/airclone/airclone "$@"
LAUNCHER
chmod +x "$CTX/airclone-launcher"
echo "  staged $(du -sh "$CTX" | cut -f1)"

say "Building"
# --force-clean so a previous half-build cannot contribute files, and a private
# state dir so this never collides with a user's own flatpak-builder cache.
flatpak-builder \
  --force-clean \
  --state-dir "$WORK/state" \
  --repo "$WORK/repo" \
  --user \
  "$WORK/build" \
  "$CTX/$APP_ID.yml"

say "Exporting a single-file bundle"
rm -f "$OUTPUT"
flatpak build-bundle "$WORK/repo" "$OUTPUT" "$APP_ID" \
  --runtime-repo=https://flathub.org/repo/flathub.flatpakrepo

say "Done"
ls -lh "$OUTPUT"
echo "Install with:  flatpak install --user $OUTPUT"
