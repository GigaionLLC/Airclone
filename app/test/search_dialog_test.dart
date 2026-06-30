import 'package:airclone/src/rclone/models/rclone_file.dart';
import 'package:airclone/src/rclone/rclone_client.dart';
import 'package:airclone/src/ui/search_dialog.dart';
import 'package:airclone/src/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A client whose `operations/list` returns a canned recursive listing and
/// records the params it was called with.
class _FakeClient implements RcloneClient {
  ({String method, Map<String, dynamic>? params})? lastCall;

  @override
  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    lastCall = (method: method, params: params);
    return {
      'list': [
        {'Name': 'report.pdf', 'Path': 'Q1/report.pdf', 'Size': 2048, 'IsDir': false},
        {'Name': 'notes.txt', 'Path': 'Q1/notes.txt', 'Size': 12, 'IsDir': false},
        {'Name': 'Archive', 'Path': 'Q1/Archive', 'IsDir': true},
        {'Name': 'budget.pdf', 'Path': 'Q2/budget.pdf', 'Size': 99, 'IsDir': false},
      ],
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _open(
  WidgetTester tester,
  RcloneClient client, {
  required void Function(RcloneFile) onOpen,
  String basePath = 'Work',
}) async {
  tester.view.physicalSize = const Size(1000, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showSearchDialog(
                ctx,
                client: client,
                fs: 'gdrive:',
                label: 'gdrive:/Work',
                basePath: basePath,
                onOpen: onOpen,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('search filters the recursive listing by name', (tester) async {
    final client = _FakeClient();
    await _open(tester, client, onOpen: (_) {});

    await tester.enterText(find.byType(TextField), 'pdf');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // Sent a recursive list scoped to the base path.
    expect(client.lastCall?.method, 'operations/list');
    expect(client.lastCall?.params?['remote'], 'Work');
    expect((client.lastCall?.params?['opt'] as Map)['recurse'], true);

    // Only the two .pdf files match; the .txt and the folder are filtered out.
    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('budget.pdf'), findsOneWidget);
    expect(find.text('notes.txt'), findsNothing);
    expect(find.text('2 matches'), findsOneWidget);
  });

  testWidgets('tapping a match calls onOpen with the right file and closes', (
    tester,
  ) async {
    final client = _FakeClient();
    RcloneFile? opened;
    await _open(tester, client, onOpen: (f) => opened = f);

    await tester.enterText(find.byType(TextField), 'report');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    await tester.tap(find.text('report.pdf'));
    await tester.pumpAndSettle();

    expect(opened?.name, 'report.pdf');
    expect(opened?.path, 'Q1/report.pdf'); // relative to the searched folder
    expect(opened?.isDir, false);
    expect(find.byType(TextField), findsNothing); // dialog dismissed
  });

  testWidgets('a query with no hits shows "No matches."', (tester) async {
    await _open(tester, _FakeClient(), onOpen: (_) {});
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('No matches.'), findsOneWidget);
  });
}
