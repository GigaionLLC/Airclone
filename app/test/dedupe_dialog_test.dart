import 'package:airclone/src/rclone/rclone_client.dart';
import 'package:airclone/src/ui/dedupe_dialog.dart';
import 'package:airclone/src/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serves a recursive listing with two duplicate groups and records every
/// operations/deletefile target.
class _FakeClient implements RcloneClient {
  final deleted = <String>[];

  @override
  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    if (method == 'operations/deletefile') {
      deleted.add(params!['remote'] as String);
      return {};
    }
    // operations/list (recurse, showHash)
    return {
      'list': [
        {
          'Path': 'a/dup.txt',
          'Name': 'dup.txt',
          'Size': 10,
          'IsDir': false,
          'Hashes': {'MD5': 'h1'},
        },
        {
          'Path': 'b/dup.txt',
          'Name': 'dup.txt',
          'Size': 10,
          'IsDir': false,
          'Hashes': {'MD5': 'h1'},
        },
        {
          'Path': 'c/uniq.txt',
          'Name': 'uniq.txt',
          'Size': 99,
          'IsDir': false,
          'Hashes': {'MD5': 'h9'},
        },
      ],
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _open(WidgetTester tester, RcloneClient client) async {
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
              onPressed: () => showDedupeDialog(
                ctx,
                client: client,
                fs: 'gdrive:',
                label: 'gdrive:/Work',
                basePath: 'Work',
                onChanged: () async {},
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
  testWidgets('scan surfaces only the duplicate group', (tester) async {
    await _open(tester, _FakeClient());
    await tester.tap(find.widgetWithText(OutlinedButton, 'Scan'));
    await tester.pumpAndSettle();
    // The 2-copy group renders; the unique file does not.
    expect(find.text('a/dup.txt'), findsOneWidget);
    expect(find.text('b/dup.txt'), findsOneWidget);
    expect(find.text('c/uniq.txt'), findsNothing);
    // One copy is queued for deletion by default (keep first).
    expect(find.widgetWithText(FilledButton, 'Delete 1'), findsOneWidget);
  });

  testWidgets('delete removes the non-kept copy and keeps one', (tester) async {
    final client = _FakeClient();
    await _open(tester, client);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Scan'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Delete 1'));
    await tester.pumpAndSettle();
    // Confirm dialog → Delete 1
    await tester.tap(find.widgetWithText(FilledButton, 'Delete 1').last);
    await tester.pumpAndSettle();

    // Default keep = first (a/dup.txt); only b/dup.txt is deleted, with the
    // base path prepended. NEVER both — one copy always survives.
    expect(client.deleted, ['Work/b/dup.txt']);
  });

  testWidgets('choosing a different copy to keep changes what is deleted', (
    tester,
  ) async {
    final client = _FakeClient();
    await _open(tester, client);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Scan'));
    await tester.pumpAndSettle();

    // Tap the second copy's row to keep it instead of the default first.
    await tester.tap(find.text('b/dup.txt'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Delete 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete 1').last);
    await tester.pumpAndSettle();

    // Now the FIRST copy is the one removed; the chosen keep survives.
    expect(client.deleted, ['Work/a/dup.txt']);
  });

  testWidgets('skipping a group deletes nothing', (tester) async {
    final client = _FakeClient();
    await _open(tester, client);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Scan'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Skip group'));
    await tester.pumpAndSettle();
    // Nothing marked → delete button disabled (shows "Delete 0").
    final btn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Delete 0'),
    );
    expect(btn.onPressed, isNull);
    expect(client.deleted, isEmpty);
  });
}
