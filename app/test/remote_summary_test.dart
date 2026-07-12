import 'package:airclone/src/state/remote_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('remoteEndpointSummary', () {
    test('surfaces the first location-ish key, formatted key: value', () {
      expect(
        remoteEndpointSummary({'type': 'sftp', 'host': 'files.example.com'}),
        'host: files.example.com',
      );
      expect(
        remoteEndpointSummary({'type': 'webdav', 'url': 'https://dav.example'}),
        'url: https://dav.example',
      );
    });

    test('prefers host over url when both are present (fixed precedence)', () {
      expect(
        remoteEndpointSummary({'url': 'https://u', 'host': 'h.example'}),
        'host: h.example',
      );
    });

    test('never surfaces a secret — only location keys are considered', () {
      // A section with ONLY secrets/opaque fields has no endpoint to show.
      expect(
        remoteEndpointSummary({
          'type': 's3',
          'access_key_id': 'AKIA...',
          'secret_access_key': 'shh',
          'token': '{"a":"b"}',
          'pass': 'obscured',
        }),
        '',
      );
    });

    test('is empty for an empty or location-less section', () {
      expect(remoteEndpointSummary(const {}), '');
      expect(remoteEndpointSummary({'type': 'crypt'}), '');
    });

    test('skips an empty value and falls through to the next key', () {
      expect(
        remoteEndpointSummary({'host': '', 'endpoint': 'ep.example'}),
        'endpoint: ep.example',
      );
    });
  });
}
