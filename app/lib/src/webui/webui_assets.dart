/// Finding and safely serving the compiled Flutter web bundle.
///
/// The bundle is not a Flutter asset. Putting ~40 MB of CanvasKit into
/// `pubspec.yaml` assets would ship it inside the Android APK and the iOS IPA,
/// where it is dead weight — a phone is not the machine you point a browser at.
/// It is packaged as plain files beside the executable instead, and only on the
/// platforms that can host it.
library;

import 'dart:io';

/// Overrides where the bundle is read from. Set this to `build/web` to drive
/// the Web UI against a freshly compiled bundle without repackaging.
const String kWebUiRootEnv = 'AIRCLONE_WEBUI_ROOT';

/// Directory name used beside the executable.
const String kWebUiBundleDirName = 'webui';

/// Resolves the directory holding `index.html`, or null when the bundle was not
/// packaged with this build.
///
/// Order: the [kWebUiRootEnv] override, then the platform's packaged location.
/// Only a directory that actually contains `index.html` counts — an empty
/// leftover directory is not a bundle, and saying so here turns a confusing
/// blank page into a clear message at startup.
Directory? resolveWebUiBundle({
  Map<String, String>? environment,
  String? executablePath,
}) {
  final env = environment ?? Platform.environment;
  final override = env[kWebUiRootEnv];
  if (override != null && override.trim().isNotEmpty) {
    final dir = Directory(override.trim());
    return _hasIndex(dir) ? dir : null;
  }

  final exe = File(executablePath ?? Platform.resolvedExecutable);
  final exeDir = exe.parent;

  final candidates = <Directory>[
    if (Platform.isMacOS)
      // Airclone.app/Contents/Resources/webui — Resources is where non-code
      // bundle content belongs, and the release codesign pass already walks it.
      Directory('${exeDir.parent.path}/Resources/$kWebUiBundleDirName'),
    // Windows and Linux: beside the executable, where CMake installs the rest
    // of the app's runtime files.
    Directory('${exeDir.path}${Platform.pathSeparator}$kWebUiBundleDirName'),
    // Running from a source checkout (`flutter run -d windows`), the exe lives
    // deep under build/, so also accept a sibling of the project.
    Directory(
      '${Directory.current.path}${Platform.pathSeparator}build'
      '${Platform.pathSeparator}web',
    ),
  ];

  for (final c in candidates) {
    if (_hasIndex(c)) return c;
  }
  return null;
}

bool _hasIndex(Directory dir) {
  try {
    return File('${dir.path}${Platform.pathSeparator}index.html').existsSync();
  } on FileSystemException {
    return false;
  }
}

/// Resolves a request path to a file inside [root], or null if it escapes.
///
/// Path traversal is the classic way a static file server turns into an
/// arbitrary-file-read, and this one sits in front of a machine holding cloud
/// credentials. The containment check is done on the **resolved absolute**
/// paths — after `..` segments, symlinks and (on Windows) `\` separators have
/// all been collapsed — because every cheaper check has a known bypass.
File? resolveStaticFile(Directory root, String requestPath) {
  var rel = Uri.decodeComponent(requestPath);
  if (rel.startsWith('/')) rel = rel.substring(1);
  if (rel.isEmpty) rel = 'index.html';

  // A NUL byte can truncate a path inside some native calls. Nothing legitimate
  // contains one. Tested by code unit rather than against a string literal: an
  // embedded NUL in source is invisible in every editor and one careless
  // reformat from silently becoming a different character.
  if (rel.codeUnits.contains(0)) return null;

  final rootPath = _canonical(root.path);
  final candidate = File('${root.path}${Platform.pathSeparator}$rel');
  final resolved = _canonical(candidate.path);

  // Must be strictly inside root. The separator check stops `/rootevil` from
  // passing a naive `startsWith('/root')`.
  if (resolved != rootPath &&
      !resolved.startsWith('$rootPath${Platform.pathSeparator}')) {
    return null;
  }
  final file = File(resolved);
  return file.existsSync() ? file : null;
}

String _canonical(String path) {
  try {
    // Resolves `..`, `.` and symlinks against the real filesystem.
    return File(path).absolute.resolveSymbolicLinksSync();
  } on FileSystemException {
    // Does not exist yet: fall back to lexical absolute normalisation, which is
    // still enough to catch traversal.
    return Uri.file(File(path).absolute.path).normalizePath().toFilePath();
  }
}

/// Content type for a bundle file, by extension.
///
/// `application/wasm` is not optional: a browser refuses to stream-compile a
/// WebAssembly module served as anything else, and CanvasKit is a `.wasm`. A
/// wrong type here is a blank page.
String contentTypeFor(String path) {
  final dot = path.lastIndexOf('.');
  final ext = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
  switch (ext) {
    case 'html':
      return 'text/html; charset=utf-8';
    case 'js':
    case 'mjs':
      return 'text/javascript; charset=utf-8';
    case 'json':
      return 'application/json; charset=utf-8';
    case 'wasm':
      return 'application/wasm';
    case 'css':
      return 'text/css; charset=utf-8';
    case 'png':
      return 'image/png';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'svg':
      return 'image/svg+xml';
    case 'webp':
      return 'image/webp';
    case 'ico':
      return 'image/x-icon';
    case 'ttf':
      return 'font/ttf';
    case 'otf':
      return 'font/otf';
    case 'woff':
      return 'font/woff';
    case 'woff2':
      return 'font/woff2';
    case 'bin':
      return 'application/octet-stream';
    case 'map':
      return 'application/json; charset=utf-8';
    case 'txt':
      return 'text/plain; charset=utf-8';
    default:
      return 'application/octet-stream';
  }
}
