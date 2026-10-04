import 'package:airclone/src/state/media_capabilities.dart';
import 'package:flutter_test/flutter_test.dart';

/// The capability dump (player format plan, A0.1) replaces a "verified against
/// the binaries" claim that was an ad-hoc string scan. The dump itself needs a
/// live libmpv; what it does with mpv's answer is pinned here.
void main() {
  group('parseMpvList', () {
    test('a string-list property is comma-separated names', () {
      final list = parseMpvList('matroska,webm,mov,mp4,mpegts');
      expect(list.map((e) => e.name), [
        'matroska',
        'webm',
        'mov',
        'mp4',
        'mpegts',
      ]);
    });

    test('decoder-list arrives as JSON maps of codec and driver', () {
      const raw =
          '[{"codec":"h264","driver":"h264","description":"H.264"},'
          '{"codec":"av1","driver":"libdav1d","description":"dav1d"}]';
      final list = parseMpvList(raw);
      expect(list, hasLength(2));
      expect(list[1].name, 'av1');
      expect(list[1].driver, 'libdav1d');
      expect(list[1].toString(), 'av1 (libdav1d)');
      expect(list[0].toString(), 'h264', reason: 'same driver is not repeated');
    });

    test('a decoder is found by codec or by driver name', () {
      final list = parseMpvList('[{"codec":"av1","driver":"libdav1d"}]');
      expect(mpvListHas(list, 'av1'), isTrue);
      expect(mpvListHas(list, 'libdav1d'), isTrue);
      expect(mpvListHas(list, 'hevc'), isFalse);
    });

    test('empty and malformed input degrade instead of throwing', () {
      expect(parseMpvList(''), isEmpty);
      expect(parseMpvList('   '), isEmpty);
      expect(parseMpvList('[not json'), [isA<MpvListEntry>()]);
    });
  });

  group('the report', () {
    const dump = MediaCapabilityDump(
      platform: 'android (television)',
      mpvVersion: 'mpv 0.36',
      demuxers: 'matroska,mov,mpegts',
      decoders: '[{"codec":"hevc","driver":"hevc"}]',
      protocols: 'http,https',
    );

    test('every matrix row says yes or missing', () {
      final report = buildMediaCapabilityReport(dump);
      expect(report, contains('  matroska: yes'));
      expect(report, contains('  caf: missing'));
      expect(report, contains('  mpc: missing'));
      expect(report, contains('  hevc: yes'));
      expect(report, contains('  av1: missing'));
      expect(report, contains('Platform: android (television)'));
    });

    test('subtitle codecs get no verdict: mpv never lists them', () {
      // The Android TV dump said "subrip: missing" while an .srt was on screen.
      final report = buildMediaCapabilityReport(dump);
      expect(report, isNot(contains('subrip: missing')));
      expect(report, contains('check by playing a file'));
      expect(report, contains('subrip'));
    });

    test('says when hwdec-current has nothing to report', () {
      expect(
        buildMediaCapabilityReport(dump),
        contains('hwdec-current: (not reported)'),
      );
    });

    test('is plain ASCII, so it survives any console and any paste', () {
      final report = buildMediaCapabilityReport(dump);
      expect(report.codeUnits.every((c) => c < 128), isTrue);
    });

    test('the log line is counts, never the lists', () {
      expect(
        mediaCapabilitySummary(dump),
        'libmpv mpv 0.36: 3 demuxers, 1 decoders, 2 protocols',
      );
    });
  });
}
