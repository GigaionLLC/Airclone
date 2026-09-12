/// Web build of the small probes — see `native_probes.dart` for why this file
/// exists.
///
/// Each answer below is the *correct* one for a browser, not a placeholder:
/// nothing here is an MSIX, nothing here has a Windows filesystem, and the Web
/// UI build never downloads an engine because the engine already runs on the
/// host that served this page.
library;

/// False: a browser tab is not an MSIX package.
bool isWindowsPackagedApp() => false;

/// Null: there is no Windows package identity to read.
String? windowsPackageFamilyName() => null;

/// Null — "cannot be asked". There is no Windows filesystem here, and the one
/// caller treats null as "assume the content is local", which is the fail-open
/// behaviour it already documents for every other platform.
int? windowsFileAttributes(String absolutePath) => null;

/// The web build downloads no engine, so no real ABI applies. Named rather than
/// empty so it is recognisable if it ever reaches a log.
String nativeAbiName() => 'web';

/// False: a browser has no filesystem, so nothing here is a macOS placeholder.
bool macosIsDataless(String absolutePath) => false;
