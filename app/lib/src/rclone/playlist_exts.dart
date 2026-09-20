/// Streaming-manifest extensions, as the object server needs to know them.
///
/// Lives with the engine layer rather than with the app's media code because
/// the layer that serves bytes is the one that has to care: a manifest's inner
/// URLs are RELATIVE, so a query-shaped object URL loses the remote and the
/// player fetches segments from nowhere. [LibrcloneObjectServer] therefore
/// hands manifests a path-shaped URL, and it cannot ask the app which
/// extensions those are.
///
/// The app's `state/media_formats.dart` imports these, so there is one list.
library;

/// Extensions whose content is a playlist pointing at other files.
///
/// `.ts` is deliberately absent. It is an MPEG transport-stream segment AND the
/// TypeScript extension, and in a file manager the second is far more likely.
/// It stays classified as source code; libmpv still fetches `.ts` segments when
/// a manifest names them, which is the case that actually matters.
const Set<String> kPlaylistExts = {'m3u8', 'm3u', 'mpd'};

/// True when [ext] (lower-case, no dot) is a streaming manifest.
bool isPlaylistExt(String ext) => kPlaylistExts.contains(ext);
