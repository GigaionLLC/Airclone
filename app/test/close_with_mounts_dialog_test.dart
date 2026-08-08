import 'package:airclone/src/ui/close_with_mounts_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Captures what the dialog resolved to. Stays null until it closes.
class _Answer {
  bool? value;
}

/// Pumps a host, opens the dialog, and settles — leaving it on screen.
Future<_Answer> _open(WidgetTester tester, List<String> mounts) async {
  final answer = _Answer();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                answer.value = await confirmCloseWithMounts(context, mounts);
              },
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  return answer;
}

void main() {
  group('confirmCloseWithMounts', () {
    testWidgets('names a single drive and warns about unsaved work', (
      tester,
    ) async {
      await _open(tester, ['X:']);

      expect(find.text('Disconnect X:?'), findsOneWidget);
      expect(
        find.textContaining('X: is mounted through Airclone'),
        findsOneWidget,
      );
      expect(find.textContaining('may lose unsaved work'), findsOneWidget);
    });

    testWidgets('pluralises for several drives', (tester) async {
      await _open(tester, ['X:', 'Y:']);

      expect(find.text('Disconnect mounted drives?'), findsOneWidget);
      expect(
        find.textContaining('X:, Y: are mounted through Airclone'),
        findsOneWidget,
      );
      expect(find.textContaining('those drives'), findsOneWidget);
    });

    testWidgets('"Disconnect and close" proceeds with the close', (
      tester,
    ) async {
      final answer = await _open(tester, ['X:']);

      await tester.tap(find.text('Disconnect and close'));
      await tester.pumpAndSettle();

      expect(answer.value, isTrue);
    });

    testWidgets('"Keep Airclone open" cancels the close', (tester) async {
      final answer = await _open(tester, ['X:']);

      await tester.tap(find.text('Keep Airclone open'));
      await tester.pumpAndSettle();

      expect(answer.value, isFalse);
    });

    testWidgets('a tap outside does NOT dismiss it', (tester) async {
      final answer = await _open(tester, ['X:']);

      // barrierDismissible:false — a stray click must not decide something
      // this consequential in either direction.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.text('Disconnect X:?'), findsOneWidget);
      expect(answer.value, isNull);
    });
  });
}
