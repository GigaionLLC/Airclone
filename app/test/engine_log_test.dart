import 'package:airclone/src/rclone/http_rclone_client.dart';
import 'package:airclone/src/state/diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

/// The `rcd` child's stdout and stderr are drained unconditionally — an unread
/// pipe blocks its WRITER once the (1 KiB, on Windows) buffer fills, and rclone
/// logs under one global mutex, so a single blocked line can stall the
/// goroutines serving an OS mount. That is the Explorer freeze reported from the
/// field. Draining is structural; what is RETAINED is the part with a decision
/// in it, and that decision lives in [isEngineFailureLine].
void main() {
  group('isEngineFailureLine', () {
    test('keeps rclone failures', () {
      expect(
        isEngineFailureLine(
          '2026/09/03 11:02:01 ERROR : big.iso: Failed to copy: eof',
        ),
        isTrue,
      );
      expect(
        isEngineFailureLine('2026/09/03 11:02:01 CRITICAL: fatal error'),
        isTrue,
      );
    });

    test('drops the routine chatter a mount produces under load', () {
      // These are the lines that would otherwise fill the ring during exactly
      // the burst of activity a report needs to be readable about.
      expect(
        isEngineFailureLine(
          'NOTICE: Serving remote control on http://127.0.0.1:5572/',
        ),
        isFalse,
      );
      expect(isEngineFailureLine('DEBUG : X:/: >Statfs: errc=0'), isFalse);
      expect(isEngineFailureLine('INFO  : big.iso: Copied (new)'), isFalse);
      expect(isEngineFailureLine(''), isFalse);
    });
  });

  test('a kept line still loses its credentials on the way in', () {
    // Belt and braces: the filter is not the privacy boundary, ingest-time
    // redaction is. A -vv run echoes the rc credentials on an error line.
    final redacted = redactSensitive(
      'ERROR : rc: request failed: Authorization: Basic YWlyY2xvbmU6c2VjcmV0',
    );
    expect(redacted, contains('ERROR'));
    expect(redacted, isNot(contains('YWlyY2xvbmU6c2VjcmV0')));
  });
}
