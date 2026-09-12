/// The extensions Airclone treats as playable media — in ONE place.
///
/// **Why this file exists.** Video and audio extensions used to be listed twice:
/// once in `ui/file_icon.dart` (which picks the icon and decides what gets a
/// thumbnail) and again in `ui/preview_dialog.dart` (which picks the preview
/// body). The two had already drifted — `.flv` was in the icon table but not the
/// preview one, so an `.flv` showed a film-strip icon and then "No preview
/// available". Adding streaming formats to one table and not the other would
/// have made a third such pair, so the tables were merged instead.
///
/// **IMAGE extensions are deliberately NOT here, and must not be merged in.**
/// The two image lists differ for a real reason: `file_icon.dart` recognises
/// `heic`, `heif`, `tiff`, `svg` and `avif` because they deserve a picture icon,
/// while the preview dialog's list is exactly what Flutter's `Image` widget can
/// decode. Merging them would hand the decoder formats it cannot read and turn a
/// clear "no preview" into a broken one. That divergence is correct; this
/// comment exists so the next person does not "fix" it.
library;

/// Container formats libmpv decodes directly — a real file with real media in it.
const Set<String> kVideoExts = {
  'mp4',
  'mov',
  'mkv',
  'webm',
  'avi',
  'm4v',
  'wmv',
  'flv',
  'mpg',
  'mpeg',
};

/// Audio containers libmpv decodes directly.
const Set<String> kAudioExts = {
  'mp3',
  'flac',
  'wav',
  'aac',
  'ogg',
  'm4a',
  'opus',
  'wma',
};

/// Streaming MANIFESTS: HLS (`.m3u8`, `.m3u`) and MPEG-DASH (`.mpd`).
///
/// These carry no media of their own. They are small text documents listing
/// segment URLs, which the player fetches separately — usually by RELATIVE path,
/// resolved against the manifest's own URL. That one detail drives most of the
/// handling around them:
///
///   * they play through the video pipeline, because libmpv resolves and
///     fetches the segments itself (the shipped libmpv carries the `hls`
///     demuxer, `mpegts`, and the `https`/`tls` protocols on every platform we
///     build for — verified against the binaries, not assumed);
///   * they are NEVER thumbnailable. A manifest has no keyframe, a live one has
///     no duration to seek within, and the thumbnailer would hold a libmpv
///     instance open against a network origin for its full timeout. See
///     [isPlaylistExt]'s callers in `ui/file_icon.dart`;
///   * and they only play from an object URL whose shape lets a RELATIVE
///     segment reference resolve back to the same directory. The spawned-`rcd`
///     engine serves `/[fs]/dir/file.m3u8`, so `seg1.ts` resolves correctly. A
///     query-shaped URL (`?fs=…&remote=…`) does not, and silently yields a
///     manifest whose segments all 404.
///
/// `.ts` is deliberately absent. It is an MPEG transport-stream segment AND the
/// TypeScript extension, and in a file manager the second is far more likely.
/// It stays classified as source code; libmpv still fetches `.ts` segments when
/// a manifest names them, which is the case that actually matters.
const Set<String> kPlaylistExts = {'m3u8', 'm3u', 'mpd'};

/// True when [ext] (lower-case, no dot) is a streaming manifest.
bool isPlaylistExt(String ext) => kPlaylistExts.contains(ext);

/// True when [ext] plays through the VIDEO pipeline: a real container, or a
/// manifest that resolves to one.
///
/// Manifests are treated as video rather than audio because HLS is
/// predominantly video, and the video surface plays an audio-only stream
/// correctly anyway — it simply shows nothing. Guessing the other way would
/// break actual video.
bool isVideoLikeExt(String ext) =>
    kVideoExts.contains(ext) || kPlaylistExts.contains(ext);

/// True when [ext] plays through the AUDIO pipeline.
bool isAudioExt(String ext) => kAudioExts.contains(ext);
