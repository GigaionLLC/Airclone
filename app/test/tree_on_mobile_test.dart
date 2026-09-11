/// The tree view on a phone.
///
/// The tree used to be forced to a list on touch platforms, on the reasoning
/// that a phone had no room for indentation plus three columns. That was true
/// of the row as it was built, not of the tree: dropping the two fixed-width
/// detail columns below [kTreeDetailsMinWidth] gives the space back to
/// indentation, and the indentation IS the tree — a tree squeezed to zero
/// indent is a list with arrows on it.
///
/// So these tests are about the thing that makes it work, not about the flag
/// that used to block it.
library;

import 'package:airclone/src/rclone/models/rclone_file.dart';
import 'package:airclone/src/rclone/models/remote.dart';
import 'package:airclone/src/ui/file_row.dart';
import 'package:airclone/src/ui/pane_drag.dart';
import 'package:airclone/src/ui/theme/app_theme.dart';
import 'package:airclone/src/ui/tree_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _file = RcloneFile(
  name: 'report.pdf',
  path: 'Work/report.pdf',
  isDir: false,
  size: 4096,
  modTime: DateTime(2026, 1, 1),
);

Future<void> pumpRow(
  WidgetTester tester, {
  required double width,
  required bool showDetails,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SizedBox(
            width: width,
            child: FileRow(
              file: _file,
              selected: false,
              selectionMode: false,
              dragData: const PaneDragData(
                Remote(name: 'demo', type: 'alias', fs: 'demo:'),
                'Work',
                [],
              ),
              onOpen: () {},
              onToggle: () {},
              onPreview: () {},
              onContextMenu: (_) {},
              onDropInto: (_) {},
              showDetails: showDetails,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('FileRow detail columns', () {
    testWidgets('a wide row shows size and modified', (tester) async {
      await pumpRow(tester, width: 900, showDetails: true);
      expect(find.text('4.0 KB'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a narrow row drops them without overflowing', (tester) async {
      await pumpRow(tester, width: 320, showDetails: false);
      // The size text is what would have eaten the name's width.
      expect(find.text('4.0 KB'), findsNothing);
      // The name must survive: it is the only thing the row is really for.
      expect(find.text('report.pdf'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('details at phone width really do overflow — hence the '
        'threshold', (tester) async {
      // Not a hypothetical. This is the row the tree would have drawn on a
      // phone if it kept its columns, and it overflows: the name is Expanded,
      // but the icon, the disclosure slot and the two fixed columns have
      // minimums that together exceed 320dp.
      //
      // Asserting the failure keeps the reason for kTreeDetailsMinWidth
      // attached to evidence. If someone later makes the row genuinely
      // resilient at this width, this test fails and they can delete it
      // knowing what it was protecting.
      await pumpRow(tester, width: 320, showDetails: true);
      final overflow = tester.takeException();
      expect(overflow, isA<FlutterError>());
      expect('$overflow', contains('overflowed'));
    });
  });

  group('the width threshold', () {
    test('a portrait phone is below it and a desktop pane is above', () {
      // 390 is an iPhone 14/15 in portrait; a half-width 1440 desktop pane is
      // 720. The threshold has to sit between them or it does nothing useful.
      expect(390, lessThan(kTreeDetailsMinWidth));
      expect(720, greaterThan(kTreeDetailsMinWidth));
    });
  });
}
