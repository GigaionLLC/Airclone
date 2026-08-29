import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Driver half of the App Store screenshot run.
///
/// `integration_test` takes the picture inside the app process; this side
/// receives the bytes and writes them out. Anything the test asks to capture
/// lands in `screenshots/<name>.png` relative to the app directory, which is
/// what `ios-screenshots.yml` then collects.
///
/// Deliberately dumb: no naming rules, no post-processing. The capture is at the
/// device's native resolution because that is what the Flutter surface is, and
/// those resolutions already are the sizes Apple accepts.
Future<void> main() async {
  await integrationDriver(
    onScreenshot:
        (String name, List<int> bytes, [Map<String, Object?>? _]) async {
          final file = File('screenshots/$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes);
          stdout.writeln('wrote ${file.path} (${bytes.length} bytes)');
          return true;
        },
  );
}
