import 'package:airclone/src/ui/overflow_name.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Three of the user's remotes are `S3-BRAUNSYNOLOGY1_RC-DISK-C1`, `-M1` and
/// `-O1`. A trailing ellipsis at the sidebar's ~145px label budget cuts all
/// three to the same `S3-BRAUNSYNOLOGY1_RC-…`, so the list showed three
/// identical rows for three different remotes and the only way to tell them
/// apart was to widen the sidebar — every launch, because the width is not
/// persisted. This keeps line one at full size and drops only the overflow to a
/// smaller second line, so the distinguishing tail is always on screen.
const _long = 'S3-BRAUNSYNOLOGY1_RC-DISK-C1';

/// Renders [name] in a box [width] wide, as the sidebar row does.
Widget _host(String name, double width) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: width,
        child: OverflowName(
          name,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          overflowStyle: const TextStyle(fontSize: 11),
        ),
      ),
    ),
  ),
);

/// Every string this widget painted, in order.
List<String> _rendered(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .toList();

void main() {
  testWidgets('a name that fits is left exactly as it was', (tester) async {
    await tester.pumpWidget(_host('localdisk', 400));
    expect(_rendered(tester), ['localdisk']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a name that does not fit continues on a second line', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_long, 145));
    final lines = _rendered(tester);
    expect(lines.length, 2, reason: 'head + smaller tail');
    // Nothing may be dropped or duplicated in the split.
    expect(lines.join(), _long);
    // The point of the exercise: the distinguishing tail is on screen.
    expect(lines.last, endsWith('C1'));
  });

  testWidgets('the second line is the smaller of the two', (tester) async {
    await tester.pumpWidget(_host(_long, 145));
    final texts = tester.widgetList<Text>(find.byType(Text)).toList();
    expect(texts.first.style!.fontSize, 13);
    expect(texts.last.style!.fontSize, 11);
  });

  testWidgets('sibling remotes stay distinguishable at the same width', (
    tester,
  ) async {
    // The failure this widget exists for: at 145px these three used to render
    // the same truncated string.
    final tails = <String>[];
    for (final name in [
      'S3-BRAUNSYNOLOGY1_RC-DISK-C1',
      'S3-BRAUNSYNOLOGY1_RC-DISK-M1',
      'S3-BRAUNSYNOLOGY1_RC-DISK-O1',
    ]) {
      await tester.pumpWidget(_host(name, 145));
      tails.add(_rendered(tester).join());
    }
    expect(tails.toSet().length, 3);
  });

  testWidgets('a width too narrow for anything degrades, it does not throw', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_long, 4));
    expect(tester.takeException(), isNull);
    expect(_rendered(tester), isNotEmpty);
  });

  testWidgets('the full name is still one label for a screen reader', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_long, 145));
    expect(
      find.bySemanticsLabel(_long),
      findsOneWidget,
      reason: 'the two painted fragments are presentation only',
    );
  });
}
