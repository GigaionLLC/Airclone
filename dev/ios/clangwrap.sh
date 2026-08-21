#!/bin/sh
# cgo invokes $CC once per file, so the SDK and target triple have to be injected
# on every invocation - hence a wrapper rather than flags.
#
# The device/simulator distinction lives ENTIRELY here: Go has one ios/arm64
# target for both, and only the -target triple's `-simulator` suffix and the
# matching version-min flag tell them apart. Getting this wrong produces an
# archive stamped as a device binary that xcodebuild then refuses to put in an
# xcframework (golang/go#57442).
set -e
case "$GOARCH" in
  arm64) CARCH=arm64  ;;
  amd64) CARCH=x86_64 ;;
  *) echo "unsupported GOARCH: $GOARCH" >&2; exit 1 ;;
esac
SDK_PATH=$(xcrun --sdk "$SDK" --show-sdk-path)
CLANG=$(xcrun --sdk "$SDK" --find clang)
if [ "$SDK" = "iphoneos" ]; then
  TARGET="-target ${CARCH}-apple-ios${MIN_VERSION}"
  VERMIN="-miphoneos-version-min=${MIN_VERSION}"
else
  TARGET="-target ${CARCH}-apple-ios${MIN_VERSION}-simulator"
  VERMIN="-mios-simulator-version-min=${MIN_VERSION}"
fi
# Deliberately NO -fembed-bitcode: bitcode was deprecated in Xcode 14 and removed
# in 16, but gomobile's own env.go still appends it and most recipes copy that.
exec "$CLANG" -arch "$CARCH" $TARGET -isysroot "$SDK_PATH" $VERMIN "$@"
