#!/usr/bin/env bash
# Builds librclone for iOS as a static c-archive and packages an .xcframework.
#
# Why this differs from dev/desktop/build-librclone.sh beyond the OS name:
#
#  - `-buildmode=c-shared` is NOT supported on iOS. c-archive is the only option,
#    so the engine is statically linked into the app binary and Dart must resolve
#    its symbols with DynamicLibrary.process(), not open().
#  - The package built is dev/ios/librclone_ios.go, a trimmed re-export, NOT
#    rclone's own librclone. See that file for why cmd/mount2 makes the stock one
#    unusable for the simulator slice.
#  - storj.io/common carries a go:linkname into the Go runtime that breaks the
#    c-archive relink, so it is neutralised through a module replace.
#  - Each target gets its OWN GOCACHE. A shared cache silently poisons the
#    simulator build with device-tagged artifacts (golang/go#57442).
#
# Go does NOT apply its own //go:cgo_ldflag directives for c-archive, so the
# consuming Xcode target must link CoreFoundation, Security and libresolv. That
# is the single most common way this fails at the very end.
#
# Usage: dev/ios/build-librclone-ios.sh [-v RCLONE_VERSION] [-o OUT_DIR]
set -euo pipefail

RCLONE_VERSION="v1.75.0"
MIN_VERSION="13.0"          # must match IPHONEOS_DEPLOYMENT_TARGET
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT_DIR="${REPO_ROOT}/app/ios/librclone"

while getopts "v:o:" opt; do
  case "$opt" in
    v) RCLONE_VERSION="$OPTARG" ;;
    o) OUT_DIR="$OPTARG" ;;
    *) echo "usage: $0 [-v RCLONE_VERSION] [-o OUT_DIR]" >&2; exit 2 ;;
  esac
done

WORK="${HOME}/.airclone-librclone-ios"
mkdir -p "$WORK"
cp "${REPO_ROOT}/dev/ios/librclone_ios.go" "$WORK/main.go"
cd "$WORK"

[ -f go.mod ] || go mod init airclone-librclone-ios
go get "github.com/rclone/rclone@${RCLONE_VERSION}"

# --- storj.io/common: neutralise the go:linkname that breaks the relink --------
STORJ_VER="$(go list -m -f '{{.Version}}' storj.io/common 2>/dev/null || true)"
if [ -n "$STORJ_VER" ]; then
  STORJ_SRC="$(go env GOMODCACHE)/storj.io/common@${STORJ_VER}"
  STORJ_DST="${WORK}/storj-patched"
  if [ ! -d "$STORJ_DST" ]; then
    echo "== patching storj.io/common ${STORJ_VER} =="
    cp -R "$STORJ_SRC" "$STORJ_DST"
    chmod -R u+w "$STORJ_DST"
    cat > "${STORJ_DST}/internal/hmacsha512/cpu_darwin_arm64.go" <<'STORJEOF'
// Neutralised for the iOS c-archive build.
// Upstream carries //go:linkname sysctlEnabled internal/cpu.sysctlEnabled,
// which the c-archive relink rejects.
package hmacsha512
STORJEOF
  fi
  go mod edit -replace "storj.io/common=${STORJ_DST}"
  go mod tidy >/dev/null 2>&1 || true
fi

build_slice() { # sdk, goarch, out_dir
  local sdk="$1" goarch="$2" out="$3"
  echo "== ${sdk} ${goarch} =="
  mkdir -p "$out"
  SDK="$sdk" MIN_VERSION="$MIN_VERSION" GOARCH="$goarch" \
  GOOS=ios CGO_ENABLED=1 \
  CC="${REPO_ROOT}/dev/ios/clangwrap.sh" \
  CXX="${REPO_ROOT}/dev/ios/clangwrap.sh" \
  GOCACHE="${WORK}/.gocache-${sdk}-${goarch}" \
    go build -tags 'noselfupdate' -trimpath \
      -ldflags "-s -w -X github.com/rclone/rclone/fs.Version=${RCLONE_VERSION}" \
      -buildmode=c-archive -o "${out}/librclone.a" .
  # A c-archive emits the header beside the archive, but only if the main package
  # actually uses cgo - so its absence is a real signal, not a cosmetic one.
  test -f "${out}/librclone.h" || { echo "no header emitted - cgo not in play?" >&2; exit 1; }
  lipo -info "${out}/librclone.a"
  echo "-- platform stamp --"
  otool -l "${out}/librclone.a" 2>/dev/null | grep -A3 LC_BUILD_VERSION | head -8 || true
}

rm -rf "${WORK}/out"
build_slice iphoneos        arm64 "${WORK}/out/ios-arm64"
build_slice iphonesimulator arm64 "${WORK}/out/ios-arm64-sim"
# x86_64 simulator is NOT optional, even though every Mac worth having is arm64
# now: `flutter build ios --simulator` always emits a FAT x86_64+arm64 binary,
# and -force_load of an archive that lacks an architecture is only a WARNING.
# The link succeeds, the x86_64 slice quietly contains no engine at all, and it
# surfaces much later as symbols that are simply not in the binary.
build_slice iphonesimulator amd64 "${WORK}/out/ios-amd64-sim"

# One fat simulator archive: the linker picks the matching slice out of it, so a
# single -force_load covers both simulator architectures.
mkdir -p "${WORK}/out/sim-fat"
lipo -create \
  "${WORK}/out/ios-arm64-sim/librclone.a" \
  "${WORK}/out/ios-amd64-sim/librclone.a" \
  -output "${WORK}/out/sim-fat/librclone.a"
cp "${WORK}/out/ios-arm64-sim/librclone.h" "${WORK}/out/sim-fat/librclone.h"
echo "== fat simulator archive =="
lipo -info "${WORK}/out/sim-fat/librclone.a"

# STABLE paths are what the Xcode target links, deliberately NOT the xcframework
# slice directories: xcodebuild names those itself, and ios-arm64-simulator
# becomes ios-arm64_x86_64-simulator the moment a second architecture appears -
# so a -force_load pointed into the xcframework breaks whenever the slice set
# changes. device/ and simulator/ never move.
mkdir -p "$OUT_DIR"
rm -rf "${OUT_DIR}/device" "${OUT_DIR}/simulator" "${OUT_DIR}/librclone.xcframework"
mkdir -p "${OUT_DIR}/device" "${OUT_DIR}/simulator"
cp "${WORK}/out/ios-arm64/librclone.a" "${OUT_DIR}/device/librclone.a"
cp "${WORK}/out/ios-arm64/librclone.h" "${OUT_DIR}/device/librclone.h"
cp "${WORK}/out/sim-fat/librclone.a"   "${OUT_DIR}/simulator/librclone.a"
cp "${WORK}/out/sim-fat/librclone.h"   "${OUT_DIR}/simulator/librclone.h"

# The xcframework is still built: it is the portable form to hand to anyone else,
# and creating it validates the platform stamps. Nothing in this repo links it.
# -headers copies the whole directory, so the .a has to be kept out of it or it
# is duplicated inside Headers/ in the shipped xcframework.
for slice in ios-arm64 sim-fat; do
  mkdir -p "${WORK}/out/${slice}/include"
  cp "${WORK}/out/${slice}/librclone.h" "${WORK}/out/${slice}/include/"
done

xcodebuild -create-xcframework \
  -library "${WORK}/out/ios-arm64/librclone.a" -headers "${WORK}/out/ios-arm64/include" \
  -library "${WORK}/out/sim-fat/librclone.a"   -headers "${WORK}/out/sim-fat/include" \
  -output "${OUT_DIR}/librclone.xcframework"

echo "== built =="
echo "-- what the Xcode target actually links --"
for a in "${OUT_DIR}/device/librclone.a" "${OUT_DIR}/simulator/librclone.a"; do
  printf '  %s: ' "$a"; lipo -info "$a" | sed 's/^.*: //'
done
find "${OUT_DIR}/librclone.xcframework" -maxdepth 2 -mindepth 1 | sed 's/^/  /' 
