#!/usr/bin/env bash
# Builds rclone as a c-shared library for the in-process desktop engine
# (FfiRcloneClient) on macOS and Linux. Windows counterpart: build-librclone.ps1.
#
# macOS -> a UNIVERSAL librclone.dylib (arm64 + x86_64 via lipo), so one artifact
#          covers Apple Silicon and Intel; needed for the .app bundle / MAS.
# Linux -> librclone.so.
#
# The version is STAMPED (a plain module build reports "vX.Y.Z-DEV", which the
# app's meetsMinRclone() rejects). Unlike Windows, no static-runtime flag is
# needed: the .dylib/.so link the system libc/libpthread, which are always present.
#
# Requires: Go 1.24+, a C compiler (clang on macOS, gcc on Linux), internet on
# first run. CI equivalent: the librclone build step in release.yml.
#
# Usage: dev/desktop/build-librclone.sh [-o OUT_DIR] [-v RCLONE_VERSION]
set -euo pipefail

RCLONE_VERSION="v1.74.4"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT_DIR=""

while getopts "o:v:" opt; do
  case "$opt" in
    o) OUT_DIR="$OPTARG" ;;
    v) RCLONE_VERSION="$OPTARG" ;;
    *) echo "usage: $0 [-o OUT_DIR] [-v RCLONE_VERSION]" >&2; exit 2 ;;
  esac
done

OS="$(uname -s)"
LDFLAGS_VERSION="-X github.com/rclone/rclone/fs.Version=${RCLONE_VERSION}"

# Dummy module pinning the rclone version, kept out of the repo so the module
# cache is reused across runs (mirrors the Windows/Android scripts).
WORK="${HOME}/.airclone-librclone-desktop"
mkdir -p "$WORK"
pushd "$WORK" >/dev/null
[ -f go.mod ] || go mod init rclone-librclone-build
go get "github.com/rclone/rclone@${RCLONE_VERSION}"

build_one() { # goarch, cc, out
  GOARCH="$1" CC="$2" CGO_ENABLED=1 go build -tags 'noselfupdate' -trimpath \
    -ldflags "-s -w ${LDFLAGS_VERSION}" \
    --buildmode=c-shared -o "$3" github.com/rclone/rclone/librclone
}

case "$OS" in
  Darwin)
    : "${OUT_DIR:=${REPO_ROOT}/app/macos/librclone}"
    mkdir -p "$OUT_DIR"
    TMP="$(mktemp -d)"
    export GOOS=darwin
    echo "== building librclone.dylib (arm64 + x86_64, ${RCLONE_VERSION}) =="
    build_one arm64 "clang -arch arm64"  "${TMP}/librclone_arm64.dylib"
    build_one amd64 "clang -arch x86_64" "${TMP}/librclone_amd64.dylib"
    lipo -create -output "${OUT_DIR}/librclone.dylib" \
      "${TMP}/librclone_arm64.dylib" "${TMP}/librclone_amd64.dylib"
    rm -rf "$TMP"
    OUT="${OUT_DIR}/librclone.dylib"
    ;;
  Linux)
    : "${OUT_DIR:=${REPO_ROOT}/app/linux/librclone}"
    mkdir -p "$OUT_DIR"
    export GOOS=linux
    echo "== building librclone.so (${RCLONE_VERSION}) =="
    build_one amd64 gcc "${OUT_DIR}/librclone.so"
    OUT="${OUT_DIR}/librclone.so"
    ;;
  *)
    echo "unsupported OS: $OS (use build-librclone.ps1 on Windows)" >&2
    exit 1
    ;;
esac
popd >/dev/null

ls -lh "$OUT"
echo "done: $OUT"
