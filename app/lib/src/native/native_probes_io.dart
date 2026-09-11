/// Native build of the small probes — see `native_probes.dart` for why this
/// file exists.
///
/// Every function here is best-effort: each is wrapped, each has a defined
/// answer when the API is missing, and no caller branches on "it failed" as
/// distinct from the fallback. That is deliberate — a broken or unexpected
/// Windows build should degrade a link or a thumbnail, never the app.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// `APPMODEL_ERROR_NO_PACKAGE` — returned by the App Model APIs when the caller
/// is NOT running from an MSIX package.
const int _appmodelErrorNoPackage = 15700;

/// `ERROR_INSUFFICIENT_BUFFER` — the expected first answer when sizing a buffer.
const int _errorInsufficientBuffer = 122;

/// Whether this process is running from a Windows MSIX package.
///
/// Used to decide whether the app may download and exec its own rclone engine
/// (a packaged app may not) and, separately, where "check for updates" is
/// allowed to point. False everywhere but Windows: no other platform is
/// Store-packaged in a way that constrains those today, and a future sandboxed
/// Mac App Store build must add its OWN check here before it may ship.
bool isWindowsPackagedApp() {
  if (!Platform.isWindows) return false;
  try {
    final getCurrentPackageFullName = DynamicLibrary.open('kernel32.dll')
        .lookupFunction<
          Int32 Function(Pointer<Uint32>, Pointer<Utf16>),
          int Function(Pointer<Uint32>, Pointer<Utf16>)
        >('GetCurrentPackageFullName');
    final length = malloc<Uint32>()..value = 0;
    try {
      // A null name buffer: unpackaged -> APPMODEL_ERROR_NO_PACKAGE; packaged ->
      // ERROR_INSUFFICIENT_BUFFER (122) or ERROR_SUCCESS (0).
      final rc = getCurrentPackageFullName(length, nullptr);
      return rc != _appmodelErrorNoPackage;
    } finally {
      malloc.free(length);
    }
  } catch (_) {
    // GetCurrentPackageFullName exists on Windows 8+ (we require 10), so this is
    // unexpected. Default to "not packaged": the common case is the unpackaged
    // installer/zip, and an MSIX resolves reliably via the API above.
    return false;
  }
}

/// This process's Windows package family name, or null when running unpackaged.
///
/// Read from the same App Model API that [isWindowsPackagedApp] uses, so the
/// link and the decision behind it can never disagree about which build this is.
String? windowsPackageFamilyName() {
  if (!Platform.isWindows) return null;
  try {
    final getCurrentPackageFamilyName = DynamicLibrary.open('kernel32.dll')
        .lookupFunction<
          Int32 Function(Pointer<Uint32>, Pointer<Utf16>),
          int Function(Pointer<Uint32>, Pointer<Utf16>)
        >('GetCurrentPackageFamilyName');
    final length = malloc<Uint32>()..value = 0;
    try {
      // First call sizes the buffer (in CHARACTERS, including the terminator).
      final probe = getCurrentPackageFamilyName(length, nullptr);
      if (probe != _errorInsufficientBuffer || length.value == 0) return null;
      final buffer = malloc<Uint16>(length.value).cast<Utf16>();
      try {
        if (getCurrentPackageFamilyName(length, buffer) != 0) return null;
        return buffer.toDartString();
      } finally {
        malloc.free(buffer);
      }
    } finally {
      malloc.free(length);
    }
  } catch (_) {
    // Unpackaged, or the API is unavailable — the caller falls back to the
    // Store's updates page, which needs no identity.
    return null;
  }
}

typedef _GetFileAttributesWC = Uint32 Function(Pointer<Utf16>);
typedef _GetFileAttributesWDart = int Function(Pointer<Utf16>);

/// Bound once. Null off Windows (or if kernel32 won't load), which makes
/// [windowsFileAttributes] a safe no-op there.
final _GetFileAttributesWDart? _getFileAttributesW = _bindGetFileAttributesW();

_GetFileAttributesWDart? _bindGetFileAttributesW() {
  if (!Platform.isWindows) return null;
  try {
    return DynamicLibrary.open(
      'kernel32.dll',
    ).lookupFunction<_GetFileAttributesWC, _GetFileAttributesWDart>(
      'GetFileAttributesW',
    );
  } catch (_) {
    return null;
  }
}

/// Raw `GetFileAttributesW` for [absolutePath], or null when it cannot be
/// asked — off Windows, on an empty path, or on any failure.
///
/// Returns the bare DWORD rather than an interpretation so the one caller that
/// cares (`state/cloud_placeholder.dart`) keeps the meaning of the bits, which
/// is where the fail-open reasoning lives.
int? windowsFileAttributes(String absolutePath) {
  final fn = _getFileAttributesW;
  if (fn == null || absolutePath.isEmpty) return null;
  Pointer<Utf16>? p;
  try {
    p = absolutePath.toNativeUtf16();
    return fn(p);
  } catch (_) {
    return null;
  } finally {
    if (p != null) malloc.free(p);
  }
}

/// The running ABI as rclone names architectures, e.g. `windows_x64`,
/// `macos_arm64`. Used to pick the right engine download.
String nativeAbiName() => Abi.current().toString();
