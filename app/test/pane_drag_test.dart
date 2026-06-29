import 'dart:convert';

import 'package:airclone/src/rclone/models/rclone_file.dart';
import 'package:airclone/src/rclone/models/remote.dart';
import 'package:airclone/src/ui/pane_drag.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PaneDragData survives a JSON round-trip (in-app drop payload)', () {
    final data = PaneDragData(
      const Remote(name: 'gdrive', type: 'drive', fs: 'gdrive:', isLocal: false),
      'Work/Q1',
      [
        RcloneFile(
          name: 'report.pdf',
          path: 'Work/Q1/report.pdf',
          isDir: false,
          size: 1234,
          mimeType: 'application/pdf',
          modTime: DateTime.utc(2026, 1, 2, 3, 4, 5),
        ),
        const RcloneFile(name: 'sub', path: 'Work/Q1/sub', isDir: true),
      ],
    );

    // Simulate the native drag round-trip through JSON (as localData would be).
    final restored = PaneDragData.fromJson(
      jsonDecode(jsonEncode(data.toJson())) as Map<String, dynamic>,
    );

    expect(restored.remote.name, 'gdrive');
    expect(restored.remote.fs, 'gdrive:');
    expect(restored.remote.isLocal, false);
    expect(restored.parentPath, 'Work/Q1');
    expect(restored.files.length, 2);
    expect(restored.files[0].name, 'report.pdf');
    expect(restored.files[0].size, 1234);
    expect(restored.files[0].isDir, false);
    expect(restored.files[0].modTime, DateTime.utc(2026, 1, 2, 3, 4, 5));
    expect(restored.files[1].name, 'sub');
    expect(restored.files[1].isDir, true);
  });

  test('PaneDragData round-trips a local remote (OS drag-out source)', () {
    final data = PaneDragData(
      const Remote(name: 'Disk (C:)', type: 'local', fs: 'C:/', isLocal: true),
      'Users/me',
      const [RcloneFile(name: 'a.txt', path: 'Users/me/a.txt', isDir: false)],
    );
    final restored = PaneDragData.fromJson(
      jsonDecode(jsonEncode(data.toJson())) as Map<String, dynamic>,
    );
    expect(restored.remote.isLocal, true);
    expect(restored.remote.fs, 'C:/');
    expect(restored.files.single.name, 'a.txt');
  });
}
