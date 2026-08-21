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

mkdir -p "$OUT_DIR"
rm -rf "${OUT_DIR}/librclone.xcframework"
xcodebuild -create-xcframework \
  -library "${WORK}/out/ios-arm64/librclone.a"     -headers "${WORK}/out/ios-arm64" \
  -library "${WORK}/out/ios-arm64-sim/librclone.a" -headers "${WORK}/out/ios-arm64-sim" \
  -output "${OUT_DIR}/librclone.xcframework"

echo "== built =="
find "${OUT_DIR}/librclone.xcframework" -maxdepth 2 -mindepth 1 | sed 's/^/  /'
