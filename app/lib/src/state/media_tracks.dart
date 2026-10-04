/// The audio and subtitle tracks of a playing file, as a person reads them.
///
/// **Why this exists.** Until the player format plan, Airclone had no track
/// choice anywhere: a film MKV with three languages played whatever libmpv
/// picked, and a Blu-ray rip whose default subtitle was a PGS image track
/// showed nothing at all, with nothing to say why. media_kit hands over raw
/// tracks (`id`, `codec`, an ISO code); this file turns them into the rows a
/// picker lists, and decides which rows can actually work here.
///
/// Pure on purpose — no widgets, no player — so every rule below is pinned by
/// `test/media_tracks_test.dart` rather than by a television.
///
/// **A label never contains a track's `id`.** For an embedded track the id is a
/// harmless number, but a subtitle added from a URL through media_kit's own
/// `SubtitleTrack.uri` carries that URL as its id, and an object URL from the
/// spawned engine has the engine's password in its userinfo. The picker shows
/// what this file builds, and this file only ever reads title, language and
/// codec.
library;

import 'package:media_kit/media_kit.dart';

/// Which picker a choice belongs to.
enum TrackKind { audio, subtitle }

/// Whether a subtitle track is text the Flutter subtitle view can draw, or a
/// bitmap that only libmpv's own renderer can.
enum SubKind { text, image, unknown }

/// ffmpeg codec names of bitmap subtitle formats: Blu-ray PGS, DVD VobSub,
/// DVB, DivX XSUB, and teletext (decoded to bitmaps by default).
const Set<String> kImageSubCodecs = {
  'hdmv_pgs_subtitle',
  'dvd_subtitle',
  'dvb_subtitle',
  'xsub',
  'dvb_teletext',
};

/// See [SubKind]. Decided by codec, not media_kit's `image` flag, which mpv
/// sets for cover art and still images rather than for subtitles.
SubKind subKindOf(SubtitleTrack t) {
  final codec = t.codec?.trim().toLowerCase();
  if (codec == null || codec.isEmpty) return SubKind.unknown;
  return kImageSubCodecs.contains(codec) ? SubKind.image : SubKind.text;
}

/// The ids mpv has actually selected right now (`aid` / `sid`): a numeric id,
/// `no`, or `auto` when nothing has been decided yet.
typedef TrackSelection = ({String audio, String subtitle});

// ── languages ────────────────────────────────────────────────────────────────

/// One language: its ISO 639-1 code, its ISO 639-2 bibliographic and
/// terminology codes (the same for most), and an English name.
class _Lang {
  const _Lang(this.one, this.b, this.name, [String? t]) : t = t ?? b;
  final String one;
  final String b;
  final String t;
  final String name;
}

/// The languages a film's tracks actually arrive in. Small on purpose: an
/// unknown code is shown as itself, which is still more useful than a guess.
const List<_Lang> _languages = [
  _Lang('en', 'eng', 'English'),
  _Lang('de', 'ger', 'German', 'deu'),
  _Lang('fr', 'fre', 'French', 'fra'),
  _Lang('es', 'spa', 'Spanish'),
  _Lang('it', 'ita', 'Italian'),
  _Lang('pt', 'por', 'Portuguese'),
  _Lang('nl', 'dut', 'Dutch', 'nld'),
  _Lang('ru', 'rus', 'Russian'),
  _Lang('uk', 'ukr', 'Ukrainian'),
  _Lang('pl', 'pol', 'Polish'),
  _Lang('cs', 'cze', 'Czech', 'ces'),
  _Lang('sk', 'slo', 'Slovak', 'slk'),
  _Lang('sl', 'slv', 'Slovenian'),
  _Lang('hr', 'hrv', 'Croatian'),
  _Lang('sr', 'srp', 'Serbian'),
  _Lang('bg', 'bul', 'Bulgarian'),
  _Lang('ro', 'rum', 'Romanian', 'ron'),
  _Lang('hu', 'hun', 'Hungarian'),
  _Lang('el', 'gre', 'Greek', 'ell'),
  _Lang('tr', 'tur', 'Turkish'),
  _Lang('sv', 'swe', 'Swedish'),
  _Lang('da', 'dan', 'Danish'),
  _Lang('no', 'nor', 'Norwegian'),
  _Lang('nb', 'nob', 'Norwegian Bokmål'),
  _Lang('nn', 'nno', 'Norwegian Nynorsk'),
  _Lang('fi', 'fin', 'Finnish'),
  _Lang('is', 'ice', 'Icelandic', 'isl'),
  _Lang('et', 'est', 'Estonian'),
  _Lang('lv', 'lav', 'Latvian'),
  _Lang('lt', 'lit', 'Lithuanian'),
  _Lang('ca', 'cat', 'Catalan'),
  _Lang('eu', 'baq', 'Basque', 'eus'),
  _Lang('gl', 'glg', 'Galician'),
  _Lang('ar', 'ara', 'Arabic'),
  _Lang('he', 'heb', 'Hebrew'),
  _Lang('fa', 'per', 'Persian', 'fas'),
  _Lang('hi', 'hin', 'Hindi'),
  _Lang('bn', 'ben', 'Bengali'),
  _Lang('ta', 'tam', 'Tamil'),
  _Lang('te', 'tel', 'Telugu'),
  _Lang('ur', 'urd', 'Urdu'),
  _Lang('th', 'tha', 'Thai'),
  _Lang('vi', 'vie', 'Vietnamese'),
  _Lang('id', 'ind', 'Indonesian'),
  _Lang('ms', 'may', 'Malay', 'msa'),
  _Lang('tl', 'tgl', 'Tagalog'),
  _Lang('zh', 'chi', 'Chinese', 'zho'),
  _Lang('ja', 'jpn', 'Japanese'),
  _Lang('ko', 'kor', 'Korean'),
];

/// Codes that mean "no language": undetermined, no linguistic content,
/// uncoded, multiple.
const Set<String> _noLanguage = {'und', 'zxx', 'mis', 'mul', 'unknown'};

/// Splits `pt-BR` / `pt_br` into (`pt`, `BR`).
(String, String?) _splitTag(String code) {
  final parts = code.trim().split(RegExp('[-_]'));
  final base = parts.first.toLowerCase();
  final region = parts.length > 1 && parts[1].isNotEmpty
      ? parts[1].toUpperCase()
      : null;
  return (base, region);
}

_Lang? _lookup(String base) {
  for (final l in _languages) {
    if (l.one == base || l.b == base || l.t == base) return l;
  }
  // Full English names appear in sidecar file names (`movie.english.srt`).
  for (final l in _languages) {
    if (l.name.toLowerCase() == base) return l;
  }
  return null;
}

/// True when [code] names a language this file knows: a 639-1 or 639-2 code,
/// optionally with a region, or a full English name.
bool isKnownLanguage(String code) => _lookup(_splitTag(code).$1) != null;

/// An English name for [code] (`eng` → `English`, `pt-BR` →
/// `Portuguese (BR)`), the code itself when it is not in the table, or null
/// when there is no language to name.
String? languageName(String? code) {
  if (code == null) return null;
  final trimmed = code.trim();
  if (trimmed.isEmpty) return null;
  final (base, region) = _splitTag(trimmed);
  if (_noLanguage.contains(base)) return null;
  final lang = _lookup(base);
  if (lang == null) return trimmed;
  return region == null ? lang.name : '${lang.name} ($region)';
}

/// The form a preference is stored in: ISO 639-2/B (`ger`, not `de` or
/// `deu`), so the same language picked from two files that tag it differently
/// is the same preference. Unknown codes are kept lower-cased as given; null
/// for "no language".
String? canonicalLanguage(String? code) {
  if (code == null) return null;
  final trimmed = code.trim();
  if (trimmed.isEmpty) return null;
  final base = _splitTag(trimmed).$1;
  if (_noLanguage.contains(base)) return null;
  return _lookup(base)?.b ?? base;
}

/// Every spelling of [code] mpv might meet in a file, for `alang` / `slang`.
///
/// mpv compares language tags literally in the libmpv builds we ship, and a
/// file tagged `de` does not match a preference of `ger`. Listing the aliases
/// makes the preference survive whatever tagging the file's author chose.
String mpvLanguageList(String code) {
  final base = _splitTag(code).$1;
  final lang = _lookup(base);
  if (lang == null) return base;
  return {lang.b, lang.t, lang.one}.join(',');
}

// ── labels ───────────────────────────────────────────────────────────────────

/// A short name for an audio or subtitle codec, or null to leave it out.
String? codecLabel(String? codec) {
  final c = codec?.trim().toLowerCase();
  if (c == null || c.isEmpty) return null;
  if (c.startsWith('pcm_')) return 'PCM';
  return switch (c) {
    'ac3' => 'AC-3',
    'eac3' => 'E-AC-3',
    'dts' => 'DTS',
    'truehd' => 'TrueHD',
    'mlp' => 'MLP',
    'aac' => 'AAC',
    'mp3' || 'mp3float' => 'MP3',
    'mp2' => 'MP2',
    'flac' => 'FLAC',
    'alac' => 'ALAC',
    'opus' => 'Opus',
    'vorbis' => 'Vorbis',
    'wmav2' || 'wmapro' => 'WMA',
    _ => c.toUpperCase(),
  };
}

/// `5.1`, `stereo`, `mono` from mpv's channel layout (`5.1(side)`) or, when
/// that is missing, from the channel count.
String? channelLabel({String? layout, int? count}) {
  final l = layout?.trim();
  // mpv names a layout it cannot identify `unknownN` (seen on a mono AC-3
  // track in the TV emulator). That is not a label - fall back to the count,
  // or to N itself.
  final unknown = l == null ? null : RegExp(r'^unknown(\d+)$').firstMatch(l);
  if (unknown != null) {
    count = (count != null && count > 0)
        ? count
        : int.tryParse(unknown.group(1)!);
  } else if (l != null && l.isNotEmpty) {
    final paren = l.indexOf('(');
    return paren > 0 ? l.substring(0, paren) : l;
  }
  if (count == null || count <= 0) return null;
  return switch (count) {
    1 => 'mono',
    2 => 'stereo',
    6 => '5.1',
    8 => '7.1',
    _ => '${count}ch',
  };
}

/// The row text for one track: `English · 5.1 · AC-3 (default)`,
/// `German · Forced`, `English · movie.en.srt · external`.
///
/// Built from title, language, codec and channels only — never from an id
/// (see the library comment). [fallback] names a track with nothing else to
/// go on, by its position in the list.
String trackLabel({
  String? title,
  String? language,
  String? codec,
  String? channels,
  bool isDefault = false,
  bool isForced = false,
  bool external = false,
  String fallback = 'Track',
}) {
  final parts = <String>[];
  final lang = languageName(language);
  if (lang != null) parts.add(lang);
  final t = title?.trim();
  if (t != null &&
      t.isNotEmpty &&
      t.toLowerCase() != lang?.toLowerCase() &&
      t.toLowerCase() != language?.trim().toLowerCase()) {
    parts.add(t);
  }
  if (channels != null && channels.isNotEmpty) parts.add(channels);
  final c = codecLabel(codec);
  if (c != null) parts.add(c);
  if (isForced && !(t ?? '').toLowerCase().contains('forced')) {
    parts.add('forced');
  }
  if (external) parts.add('external');
  final label = parts.isEmpty ? fallback : parts.join(' · ');
  return isDefault ? '$label (default)' : label;
}

// ── choices ──────────────────────────────────────────────────────────────────

/// One row of a picker.
class TrackChoice {
  const TrackChoice({
    required this.kind,
    required this.id,
    required this.label,
    this.language,
    this.enabled = true,
    this.isOff = false,
  });

  final TrackKind kind;

  /// mpv's id for the track, used to SELECT it and never shown. `no` for the
  /// subtitle picker's "Off" row.
  final String id;

  final String label;

  /// The track's language tag as the file gave it, for the remembered
  /// preference; null when the file did not say.
  final String? language;

  /// False for a row that is listed but cannot work here — an image subtitle
  /// while libass rendering is off.
  final bool enabled;

  /// The subtitle "Off" row.
  final bool isOff;

  @override
  bool operator ==(Object other) =>
      other is TrackChoice &&
      other.kind == kind &&
      other.id == id &&
      other.label == label &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(kind, id, label, enabled);

  @override
  String toString() => 'TrackChoice($kind, $label)';
}

/// The suffix on an image subtitle row that cannot be drawn here.
const String kImageSubUnavailable = "can't be shown here";

bool _isPlaceholder(String id) => id == 'auto' || id == 'no';

/// The audio picker's rows: every real track, in file order. `auto` and `no`
/// are media_kit placeholders and are never listed — silencing a film is the
/// volume control's job.
List<TrackChoice> audioChoices(Tracks t) {
  final out = <TrackChoice>[];
  for (final a in t.audio) {
    if (_isPlaceholder(a.id)) continue;
    out.add(
      TrackChoice(
        kind: TrackKind.audio,
        id: a.id,
        language: a.language,
        label: trackLabel(
          title: a.title,
          language: a.language,
          codec: a.codec,
          channels: channelLabel(layout: a.channels, count: a.channelscount),
          isDefault: a.isDefault ?? false,
          fallback: 'Track ${out.length + 1}',
        ),
      ),
    );
  }
  return out;
}

/// The subtitle picker's rows: `Off`, then every real track.
///
/// An image track is listed even when it cannot be drawn
/// ([imageSubsRenderable] false), disabled and saying so — a missing row reads
/// as "Airclone did not see my subtitles", which is a worse thing to tell
/// someone than the truth. [externalTitles] are the titles Airclone gave the
/// sidecar files it added, which is how an external track is told apart:
/// media_kit does not pass mpv's own `external` flag through.
List<TrackChoice> subtitleChoices(
  Tracks t, {
  required bool imageSubsRenderable,
  Set<String> externalTitles = const {},
}) {
  final out = <TrackChoice>[
    const TrackChoice(
      kind: TrackKind.subtitle,
      id: 'no',
      label: 'Off',
      isOff: true,
    ),
  ];
  var n = 0;
  for (final s in t.subtitle) {
    if (_isPlaceholder(s.id)) continue;
    n++;
    final image = subKindOf(s) == SubKind.image;
    final enabled = !image || imageSubsRenderable;
    var label = trackLabel(
      title: s.title,
      language: s.language,
      isDefault: s.isDefault ?? false,
      external: s.title != null && externalTitles.contains(s.title),
      fallback: 'Track $n',
    );
    if (image) label = '$label · image';
    if (!enabled) label = '$label · $kImageSubUnavailable';
    out.add(
      TrackChoice(
        kind: TrackKind.subtitle,
        id: s.id,
        language: s.language,
        label: label,
        enabled: enabled,
      ),
    );
  }
  return out;
}

/// Whether the audio button is worth showing: only when there is a choice.
bool hasAudioChoice(Tracks t) => audioChoices(t).length > 1;

/// Whether the subtitle button is worth showing: the file has a subtitle
/// track, or sidecar files were found next to it (they arrive a moment after
/// playback starts, and the button should not pop in late when we already
/// know they are coming).
bool hasSubtitleChoice(Tracks t, {bool sidecarsExpected = false}) =>
    sidecarsExpected || t.subtitle.any((s) => !_isPlaceholder(s.id));

/// True when mpv auto-selected an image subtitle that cannot be drawn here,
/// so the player should switch subtitles off rather than show nothing (plan
/// Q3). [selectedId] is mpv's current `sid`.
bool shouldDropAutoSubtitle({
  required Tracks tracks,
  required String? selectedId,
  required bool imageSubsRenderable,
}) {
  if (imageSubsRenderable) return false;
  if (selectedId == null || _isPlaceholder(selectedId)) return false;
  for (final s in tracks.subtitle) {
    if (s.id == selectedId) return subKindOf(s) == SubKind.image;
  }
  return false;
}

/// What picking [c] should remember as the preferred language: `off` for the
/// subtitle Off row, the canonical code of a tagged track, or null (leave the
/// preference alone) for a track with no language.
String? preferenceFor(TrackChoice c) {
  if (c.isOff) return kLanguageOff;
  return canonicalLanguage(c.language);
}

/// The stored value meaning "subtitles off".
const String kLanguageOff = 'off';

/// The libmpv options a remembered language turns into, set before a file is
/// opened so libmpv's own track selection does the work (plan Q4).
///
/// Nothing for no preference. Subtitles `off` is `sid=no`, not an empty
/// `slang`: an empty list means "no preference" to mpv, which would still pick
/// the file's default track.
Map<String, String> languageOptions({String? audio, String? subtitle}) => {
  if (audio != null && audio.isNotEmpty && audio != kLanguageOff)
    'alang': mpvLanguageList(audio),
  if (subtitle == kLanguageOff)
    'sid': 'no'
  else if (subtitle != null && subtitle.isNotEmpty)
    'slang': mpvLanguageList(subtitle),
};

// ── a track the build cannot decode ──────────────────────────────────────────

/// The codec named by libmpv's "Failed to initialize a decoder for codec
/// 'truehd'." error, or null for any other message.
String? undecodableCodecIn(String message) {
  final m = RegExp(
    r"decoder for codec '([^']+)'",
    caseSensitive: false,
  ).firstMatch(message);
  return m?.group(1)?.toLowerCase();
}

/// What to do when the codec of [failed] could not be decoded: the first
/// other audio track whose codec is not in [bad], or `AudioTrack.no()` to
/// carry on without sound. Null when [failed] is not an audio codec of this
/// file at all — a video decoder failure is fatal and stays an error.
///
/// Found on the Android TV emulator: the shipped Android libmpv has no TrueHD
/// decoder, and a film whose DEFAULT track is TrueHD failed outright, although
/// its AC-3 track and its picture were perfectly playable. A Blu-ray remux
/// is exactly that file.
AudioTrack? fallbackAudioTrack(
  List<AudioTrack> tracks,
  String failed, {
  Set<String> bad = const {},
}) {
  bool real(AudioTrack t) => t.id != 'auto' && t.id != 'no';
  final audio = tracks.where(real).toList();
  if (!audio.any((t) => t.codec?.toLowerCase() == failed)) return null;
  final skip = {...bad, failed};
  for (final t in audio) {
    if (!skip.contains(t.codec?.toLowerCase())) return t;
  }
  return AudioTrack.no();
}
