import 'package:airclone/src/rclone/ffi_rclone_client.dart';
import 'package:airclone/src/rclone/librclone_ffi.dart';
import 'package:airclone/src/rclone/librclone_object_server.dart';
import 'package:airclone/src/rclone/rclone_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mapRpcResult', () {
    test('2xx returns the decoded JSON body', () {
      final body = mapRpcResult('core/version', 200, '{"version":"v1.74.4"}');
      expect(body['version'], 'v1.74.4');
    });

    test('empty output on 2xx is an empty map (matches HTTP client)', () {
      expect(mapRpcResult('core/quit', 200, ''), isEmpty);
      expect(mapRpcResult('core/quit', 200, '   '), isEmpty);
    });

    test('non-2xx throws RcloneException carrying rclone\'s error field', () {
      expect(
        () => mapRpcResult('operations/list', 500, '{"error":"boom"}'),
        throwsA(
          isA<RcloneException>()
              .having((e) => e.message, 'message', 'boom')
              .having((e) => e.statusCode, 'statusCode', 500)
              .having((e) => e.method, 'method', 'operations/list'),
        ),
      );
    });

    test('non-2xx with no error field falls back to the HTTP code', () {
      expect(
        () => mapRpcResult('x/y', 404, '{}'),
        throwsA(
          isA<RcloneException>().having(
            (e) => e.message,
            'message',
            'HTTP 404',
          ),
        ),
      );
    });

    test('a 2xx code other than 200 (e.g. 204) still succeeds', () {
      expect(mapRpcResult('x/y', 204, ''), isEmpty);
    });
  });

  group('librcloneFileName', () {
    test('picks the right shared-library name per OS', () {
      expect(librcloneFileName('macos'), 'librclone.dylib');
      expect(librcloneFileName('windows'), 'librclone.dll');
      expect(librcloneFileName('linux'), 'librclone.so');
      // Any other unix falls back to the .so name.
      expect(librcloneFileName('fuchsia'), 'librclone.so');
    });
  });

  group('parseByteRange (preview bridge Range header)', () {
    const total = 1000;
    test('a bounded range is inclusive', () {
      expect(parseByteRange('bytes=0-99', total), (0, 99));
      expect(parseByteRange('bytes=100-199', total), (100, 199));
    });
    test('an open-ended range runs to the last byte', () {
      expect(parseByteRange('bytes=100-', total), (100, 999));
    });
    test('a suffix range is the last N bytes', () {
      expect(parseByteRange('bytes=-100', total), (900, 999));
      // suffix larger than the file clamps to the whole file
      expect(parseByteRange('bytes=-5000', total), (0, 999));
    });
    test('an end past EOF clamps to the last byte', () {
      expect(parseByteRange('bytes=0-99999', total), (0, 999));
    });
    test('unsatisfiable / malformed ranges return null (send whole file)', () {
      expect(
        parseByteRange('bytes=2000-3000', total),
        isNull,
      ); // start >= total
      expect(parseByteRange('bytes=500-100', total), isNull); // start > end
      expect(parseByteRange('bytes=abc-def', total), isNull);
      expect(parseByteRange('nonsense', total), isNull);
      expect(parseByteRange('bytes=0-99', 0), isNull); // empty file
    });
    test('only the first range of a multi-range set is honoured', () {
      expect(parseByteRange('bytes=0-9,20-29', total), (0, 9));
    });
  });
}
