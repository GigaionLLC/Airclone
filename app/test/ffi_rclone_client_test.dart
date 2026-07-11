import 'package:airclone/src/rclone/ffi_rclone_client.dart';
import 'package:airclone/src/rclone/librclone_ffi.dart';
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
}
