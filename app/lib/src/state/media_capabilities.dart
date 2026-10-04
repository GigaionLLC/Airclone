/// What THIS build's libmpv can actually open, asked of libmpv itself.
///
/// **Why this exists.** The extension tables in `media_formats.dart` were once
/// justified by "verified against the binaries", which turned out to be an
/// ad-hoc string scan of two of the five platforms' libraries, with no script
/// kept. A string being present in a binary is a strong hint, not proof, and
/// macOS, iOS and the distro libmpv on Linux were never looked at. mpv answers
/// the real question through three properties — `demuxer-lavf-list`,
/// `decoder-list` and `protocol-list` — and this file turns their raw text
/// into a report a person can paste into `dev/media-support-matrix.md`.
///
/// Pure on purpose: the dump itself needs a live player (see
/// `ui/media_capabilities_dialog.dart`), but parsing and the report are text
/// in, text out, and are pinned by `test/media_capabilities_test.dart`.
library;

import 'dart:convert';

/// The names worth a yes/no line in the report — the rows of the support
/// matrix. Containers are matched against the demuxer list, codecs against
/// the decoder list (by codec OR decoder name, since `libdav1d` decodes `av1`).
///
/// The "expected absent" entries are here deliberately: a row that says
/// `caf: missing` is what keeps `.caf` out of the audio table, and the day a
/// libmpv update ships it, the report says so.
const List<String> kProbeDemuxers = [
  'matroska',
  'mov',
  'avi',
  'asf',
  'flv',
  'mpegts',
  'mpeg',
  'ogg',
  'rm',
  'mxf',
  'hls',
  'dash',
  'ape',
  'wv',
  'tta',
  'dsf',
  'aiff',
  'ac3',
  'eac3',
  'dts',
  'mpc',
  'mpc8',
  'caf',
  'amr',
  'w64',
  'voc',
  'wtv',
  'ivf',
  'dff',
  'swf',
  'vobsub',
  'sup',
];

const List<String> kProbeDecoders = [
  'h264',
  'hevc',
  'av1',
  'vp9',
  'vc1',
  'mpeg2video',
  'theora',
  'prores',
  'ac3',
  'eac3',
  'dts',
  'truehd',
  'aac',
  'flac',
  'alac',
  'opus',
  'ape',
  'wavpack',
  'hdmv_pgs_subtitle',
  'dvd_subtitle',
  'dvb_subtitle',
  'ass',
  'subrip',
  'webvtt',
];

/// One entry of a parsed mpv list: its name, plus the decoder (driver) name
/// when it differs, e.g. codec `av1` decoded by `libdav1d`.
class MpvListEntry {
  const MpvListEntry(this.name, [this.driver]);

  final String name;
  final String? driver;

  @override
  String toString() =>
      driver == null || driver == name ? name : '$name ($driver)';
}

/// Parses one of mpv's list properties as returned by
/// `mpv_get_property_string`.
///
/// Two shapes arrive. A string-list property (`demuxer-lavf-list`,
/// `protocol-list`) prints as comma-separated names. A node property
/// (`decoder-list`) prints as JSON: an array of maps with `codec`, `driver` and
/// `description`. Both are accepted, so a libmpv that changes how it prints one
/// of them degrades to a flat list rather than to an empty report.
List<MpvListEntry> parseMpvList(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return const [];
  if (text.startsWith('[')) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is List) {
        final out = <MpvListEntry>[];
        for (final item in decoded) {
          if (item is String && item.isNotEmpty) {
            out.add(MpvListEntry(item));
          } else if (item is Map) {
            final codec = item['codec'];
            final driver = item['driver'];
            final name = codec is String && codec.isNotEmpty
                ? codec
                : (driver is String ? driver : '');
            if (name.isEmpty) continue;
            out.add(MpvListEntry(name, driver is String ? driver : null));
          }
        }
        return out;
      }
    } on FormatException {
      // Not JSON after all; fall through to the comma-separated reading.
    }
  }
  return [
    for (final part in text.split(','))
      if (part.trim().isNotEmpty) MpvListEntry(part.trim()),
  ];
}

/// True when [name] appears in [entries] as a name or as a driver.
bool mpvListHas(List<MpvListEntry> entries, String name) =>
    entries.any((e) => e.name == name || e.driver == name);

/// The raw property values one dump collected.
class MediaCapabilityDump {
  const MediaCapabilityDump({
    required this.platform,
    this.mpvVersion = '',
    this.ffmpegVersion = '',
    this.hwdec = '',
    this.hwdecCurrent = '',
    this.demuxers = '',
    this.decoders = '',
    this.protocols = '',
  });

  /// `HostPlatform.operatingSystem`, plus whatever the caller knows (TV).
  final String platform;
  final String mpvVersion;
  final String ffmpegVersion;

  /// The `hwdec` option as configured, and `hwdec-current`, which only names a
  /// decoder while a file is actually playing.
  final String hwdec;
  final String hwdecCurrent;

  final String demuxers;
  final String decoders;
  final String protocols;
}

/// The report, in plain ASCII so it survives a paste into an issue, a cp1252
/// console, or the matrix doc.
String buildMediaCapabilityReport(MediaCapabilityDump d) {
  final demuxers = parseMpvList(d.demuxers);
  final decoders = parseMpvList(d.decoders);
  final protocols = parseMpvList(d.protocols);
  String orUnknown(String v) => v.trim().isEmpty ? '(not reported)' : v.trim();

  final b = StringBuffer()
    ..writeln('Airclone media capabilities')
    ..writeln('Platform: ${d.platform}')
    ..writeln('mpv: ${orUnknown(d.mpvVersion)}')
    ..writeln('ffmpeg: ${orUnknown(d.ffmpegVersion)}')
    ..writeln('hwdec option: ${orUnknown(d.hwdec)}')
    ..writeln(
      'hwdec-current: ${orUnknown(d.hwdecCurrent)} '
      '(only meaningful while a video is playing)',
    )
    ..writeln()
    ..writeln('Matrix rows (container demuxers):');
  for (final name in kProbeDemuxers) {
    b.writeln('  $name: ${mpvListHas(demuxers, name) ? 'yes' : 'missing'}');
  }
  b
    ..writeln()
    ..writeln('Matrix rows (decoders):');
  for (final name in kProbeDecoders) {
    b.writeln('  $name: ${mpvListHas(decoders, name) ? 'yes' : 'missing'}');
  }
  b
    ..writeln()
    ..writeln('Demuxers (${demuxers.length}):')
    ..writeln('  ${demuxers.join(', ')}')
    ..writeln()
    ..writeln('Decoders (${decoders.length}):')
    ..writeln('  ${decoders.join(', ')}')
    ..writeln()
    ..writeln('Protocols (${protocols.length}):')
    ..writeln('  ${protocols.join(', ')}');
  return b.toString();
}

/// One line for the diagnostics log: versions and counts, never the full lists
/// (the ring holds 300 entries and three lists of several hundred names would
/// push out the errors it exists to keep).
String mediaCapabilitySummary(MediaCapabilityDump d) {
  final demuxers = parseMpvList(d.demuxers).length;
  final decoders = parseMpvList(d.decoders).length;
  final protocols = parseMpvList(d.protocols).length;
  return 'libmpv ${d.mpvVersion.trim().isEmpty ? '?' : d.mpvVersion.trim()}: '
      '$demuxers demuxers, $decoders decoders, $protocols protocols';
}
