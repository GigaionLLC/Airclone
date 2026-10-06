/// Subtitle files that sit next to a video: `movie.srt` beside `movie.mkv`.
///
/// **Why Airclone has to find them itself.** libmpv's own `sub-auto` only
/// scans a LOCAL directory, and the player never opens a local path: every
/// preview is an `http://127.0.0.1` object URL served by the engine. So a
/// sidecar that VLC would pick up without being asked was silently ignored.
/// The host already holds the folder's listing; this file decides which
/// entries in it are subtitles for which video, and the player adds them with
/// mpv's `sub-add` once the film is playing (player format plan, 4.C).
///
/// **The content is attacker-authored.** Anyone a folder is shared with can
/// put a file in it, and a subtitle file goes straight into ffmpeg's and mpv's
/// parsers. So: text formats only ([kSidecarSubExts] — no `.sub/.idx` or
/// `.sup`, which are binary, until spike A0 says otherwise), a size cap, and a
/// URL that can only ever be the engine's own loopback object URL
/// ([sidecarUrl]) — never `file://`, never a string built from a name.
///
/// Pure, so all of it is pinned by `test/sidecar_subs_test.dart`.
library;

import 'package:airclone_rc/airclone_rc.dart';

import 'media_tracks.dart';

/// The sidecar formats loaded: plain text, parsed by ffmpeg's text demuxers.
const Set<String> kSidecarSubExts = {'srt', 'ass', 'ssa', 'vtt'};

/// Larger than any real text subtitle (a feature film's SRT is ~100 KiB, a
/// heavily typeset ASS a few hundred), small enough that a hostile file named
/// `.srt` costs nothing to refuse.
const int kSidecarMaxBytes = 2 * 1024 * 1024;

/// File-name tags that mark a hearing-impaired track.
const Set<String> _sdhTags = {'sdh', 'cc', 'hi'};

/// One sidecar subtitle for a video.
class Sidecar {
  const Sidecar({
    required this.file,
    this.language,
    this.forced = false,
    this.sdh = false,
  });

  final RcloneFile file;

  /// The language the file name declares (`movie.en.srt`), as written; null
  /// when it declares none.
  final String? language;

  /// `movie.de.forced.srt`: only the lines in a foreign language.
  final bool forced;

  /// `movie.en.sdh.srt`: subtitles for the deaf and hard of hearing.
  final bool sdh;

  /// The title it is added to the player under, and so the picker label. The
  /// file's own name: unambiguous between two English sidecars, and something
  /// the person can find in their folder. Never the URL.
  String get title => file.name;
}

String _extOf(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1).toLowerCase();
}

String _stemOf(String name) {
  final dot = name.lastIndexOf('.');
  return (dot <= 0 ? name : name.substring(0, dot)).toLowerCase();
}

/// A language tag a file name can carry: a code in the table, a full English
/// name, or any 2-3 letter code with an optional region (`pt-br`).
bool _isLanguageTag(String tag) =>
    isKnownLanguage(tag) ||
    RegExp(r'^[a-z]{2,3}([-_][a-z0-9]{2,4})?$').hasMatch(tag);

/// The sidecars for [video] among [siblings] (the folder's FULL listing, not
/// a filtered view of it: a filter for `mkv` must not hide the `.srt`).
///
/// A sibling matches when it is `<stem>.<ext>`, or `<stem>.<tag>[.<tag>…].<ext>`
/// where every tag is a language, `forced`, `sdh`, `cc` or `hi`; anything else
/// (`movie.part2.srt`) belongs to some other file. Case-insensitive, and a stem
/// may contain dots (`My.Film.2020.1080p`). Directories, other extensions,
/// files over [kSidecarMaxBytes], files of unknown size (the cap must be a real
/// cap), and anything [skip] rejects — the caller passes the "would hydrate a
/// cloud placeholder" check — are left out. Sorted by name, so the order the
/// player adds them in, and therefore their ids, is the same on every Retry.
List<Sidecar> findSidecars(
  RcloneFile video,
  List<RcloneFile> siblings, {
  bool Function(RcloneFile file)? skip,
}) {
  final stem = _stemOf(video.name);
  if (stem.isEmpty) return const [];
  final out = <Sidecar>[];
  for (final f in siblings) {
    if (f.isDir || identical(f, video) || f.name == video.name) continue;
    if (!kSidecarSubExts.contains(_extOf(f.name))) continue;
    if (f.size < 0 || f.size > kSidecarMaxBytes) continue;
    final s = _stemOf(f.name);
    final List<String> tags;
    if (s == stem) {
      tags = const [];
    } else if (s.startsWith('$stem.')) {
      tags = s.substring(stem.length + 1).split('.');
    } else {
      continue;
    }
    String? language;
    var forced = false;
    var sdh = false;
    var valid = true;
    final hasOtherLanguage = tags.any(
      (t) => t != 'hi' && !_sdhTags.contains(t) && _isLanguageTag(t),
    );
    for (final tag in tags) {
      if (tag == 'forced') {
        forced = true;
      } else if (_sdhTags.contains(tag) && (tag != 'hi' || hasOtherLanguage)) {
        // `hi` is also Hindi: a flag only when another tag names the language.
        sdh = true;
      } else if (_isLanguageTag(tag)) {
        language ??= tag;
      } else {
        valid = false;
        break;
      }
    }
    if (!valid) continue;
    if (skip != null && skip(f)) continue;
    out.add(Sidecar(file: f, language: language, forced: forced, sdh: sdh));
  }
  out.sort((a, b) => a.file.name.compareTo(b.file.name));
  return out;
}

/// Which sidecar, by index, the player should SELECT as it adds them — or
/// null to add them all with mpv's `auto` flag, so they appear in the picker
/// and the file's own choice stands (plan 4.C).
///
/// Only when the file has no subtitle track of its own: then a sidecar in the
/// [preferred] language is selected (an unforced one first), or, with no
/// language match, the only sidecar there is. Never when the person has
/// switched subtitles `off`.
int? sidecarToSelect(
  List<Sidecar> sidecars, {
  required bool fileHasSubtitles,
  required String? preferred,
}) {
  if (sidecars.isEmpty || fileHasSubtitles) return null;
  if (preferred == kLanguageOff) return null;
  if (preferred != null) {
    int? forcedMatch;
    for (var i = 0; i < sidecars.length; i++) {
      if (canonicalLanguage(sidecars[i].language) != preferred) continue;
      if (!sidecars[i].forced) return i;
      forcedMatch ??= i;
    }
    if (forcedMatch != null) return forcedMatch;
  }
  return sidecars.length == 1 ? 0 : null;
}

/// The URL mpv may be given for [object], or null when it must not be given
/// one at all.
///
/// Only the engine's loopback object URL, with its credential moved into the
/// userinfo exactly as the video's own URL is (see
/// `loopbackUrlWithCredentials` for why a header is the wrong place). The
/// scheme is checked as well as the host, so nothing but `http`/`https` to
/// this machine can ever reach `sub-add` — mpv opens `file://` natively, past
/// the protocol whitelist.
String? sidecarUrl(ObjectRef object) {
  final url =
      loopbackUrlWithCredentials(object.url, object.headers) ?? object.url;
  final scheme = Uri.tryParse(url)?.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;
  if (!isLoopbackUrl(url)) return null;
  return url;
}

/// A sidecar with the object reference the host resolved for it.
class SidecarSource {
  const SidecarSource(this.sidecar, this.object);

  final Sidecar sidecar;
  final ObjectRef object;
}
