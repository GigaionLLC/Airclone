import 'package:airclone/src/webui/webui_server.dart';
import 'package:flutter_test/flutter_test.dart';

/// A file name comes from a remote, which means it comes from whoever put the
/// file there. A header is line-oriented, so a name carrying a quote, a
/// semicolon or a CRLF is not a display problem — it is a chance to rewrite the
/// response headers. These pin that it cannot.
void main() {
  String header(String path) => contentDispositionAttachment(path);

  test('a plain name appears in both forms', () {
    final h = header('holiday.mp4');
    expect(h, startsWith('attachment;'));
    expect(h, contains('filename="holiday.mp4"'));
    expect(h, contains("filename*=UTF-8''holiday.mp4"));
  });

  test('only the basename is used, never the path', () {
    expect(header('a/b/c/report.pdf'), contains('filename="report.pdf"'));
    expect(header('a/b/c/report.pdf'), isNot(contains('a/b/c')));
  });

  test('a non-ASCII name survives in the encoded form', () {
    final h = header('dir/naïve résumé.pdf');
    // The RFC 5987 form carries the real name...
    expect(h, contains("filename*=UTF-8''"));
    expect(h, contains('na%C3%AFve'));
    // ...while the ASCII fallback is sanitised rather than mangled into bytes.
    expect(h, contains('filename="na_ve_r_sum_.pdf"'));
  });

  group('cannot break out of the header', () {
    for (final nasty in [
      'a"; drop.txt',
      'a\r\nX-Injected: yes',
      'a\nSet-Cookie: evil=1',
      'a; filename="b.exe',
      "a'; rm -rf /",
    ]) {
      test('rejected: ${nasty.replaceAll(RegExp(r'[\r\n]'), '~')}', () {
        final h = header(nasty);
        expect(h.contains('\r'), isFalse);
        expect(h.contains('\n'), isFalse);
        // Exactly two quotes: the pair around the ASCII fallback.
        expect('"'.allMatches(h).length, 2);
      });
    }
  });

  test('a name with nothing usable still yields a filename', () {
    expect(header('///'), contains('filename="download"'));
    expect(header('***'), contains('filename="download"'));
  });
}
