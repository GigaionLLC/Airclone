import 'package:airclone/src/ui/file_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Search results on a phone read "long-…  Airclo…" (TV/phone emulator pass,
/// 2026-10-05): the name and its folder split the row evenly.
void main() {
  Future<void> pump(WidgetTester tester, String name, double width) =>
      tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: width,
              child: NameWithSubtitle(
                name: name,
                subtitle: 'AircloneTest/Long',
                nameStyle: const TextStyle(fontSize: 14),
                subtitleStyle: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ),
      );

  RenderParagraph paragraph(WidgetTester tester, String text) =>
      tester.renderObject<RenderParagraph>(find.text(text));

  testWidgets('a name that fits is shown whole; the folder takes the rest', (
    tester,
  ) async {
    // The test font draws every glyph a full em wide: this name is 266 px.
    await pump(tester, 'long-sidecar.de.srt', 400);
    expect(paragraph(tester, 'long-sidecar.de.srt').didExceedMaxLines, isFalse);
    expect(find.text('AircloneTest/Long'), findsOneWidget);
  });

  testWidgets('a name too long for the row still leaves the folder a share', (
    tester,
  ) async {
    const name = 'a-very-long-file-name-that-will-never-fit-on-a-phone-row.mkv';
    await pump(tester, name, 260);
    final folderWidth = tester.getSize(find.text('AircloneTest/Long')).width;
    expect(folderWidth, greaterThan(260 * 0.2));
    expect(paragraph(tester, name).didExceedMaxLines, isTrue);
  });
}
