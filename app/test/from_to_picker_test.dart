import 'package:airclone/src/rclone/models/remote.dart';
import 'package:airclone/src/ui/from_to_picker.dart';
import 'package:airclone/src/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Saving a task used to require a dual-pane layout arranged in advance — it
/// read the two panes and refused if either was empty. These cover the picker
/// that replaced that requirement, and the one case it must still refuse.
const _photos = Remote(name: 'photos', type: 'drive', fs: 'photos:');
const _backup = Remote(name: 'backup', type: 's3', fs: 'backup:');

void main() {
  /// Pumps the picker and hands back a one-slot holder the test can read AFTER
  /// the dialog pops — the future does not complete until then, so returning
  /// the value directly would always read null.
  Future<List<FromTo?>> pump(
    WidgetTester tester, {
    FolderRef? src,
    FolderRef? dst,
  }) async {
    final result = <FromTo?>[];
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                opened = true;
                result.add(await showFromToPicker(ctx, src: src, dst: dst));
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
    return result;
  }

  bool continueEnabled(WidgetTester tester) =>
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'))
          .onPressed !=
      null;

  testWidgets('opens with nothing chosen, and refuses to continue', (
    tester,
  ) async {
    // The whole point: it OPENS with no panes arranged. It just cannot finish
    // until both ends are named.
    await pump(tester);
    expect(find.text('From'), findsOneWidget);
    expect(find.text('To'), findsOneWidget);
    expect(find.text('Not chosen yet'), findsNWidgets(2));
    expect(continueEnabled(tester), isFalse);
  });

  testWidgets('a half-filled pair still cannot continue', (tester) async {
    await pump(tester, src: (remote: _photos, path: 'DCIM'));
    expect(find.text('photos:DCIM'), findsOneWidget);
    expect(find.text('Not chosen yet'), findsOneWidget);
    expect(continueEnabled(tester), isFalse);
  });

  testWidgets('panes seed it, and Continue returns both ends', (tester) async {
    final out = await pump(
      tester,
      src: (remote: _photos, path: 'DCIM'),
      dst: (remote: _backup, path: 'phone'),
    );
    expect(find.text('photos:DCIM'), findsOneWidget);
    expect(find.text('backup:phone'), findsOneWidget);
    expect(continueEnabled(tester), isTrue);

    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(find.text('New task'), findsNothing);
    final picked = out.single!;
    expect(picked.src.remote.fs, 'photos:');
    expect(picked.src.path, 'DCIM');
    expect(picked.dst.remote.fs, 'backup:');
    expect(picked.dst.path, 'phone');
  });

  testWidgets('Cancel resolves to null rather than a half-built task', (
    tester,
  ) async {
    final out = await pump(
      tester,
      src: (remote: _photos, path: 'DCIM'),
      dst: (remote: _backup, path: 'phone'),
    );
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(out.single, isNull);
  });

  testWidgets('the same folder on both ends is refused, with a reason', (
    tester,
  ) async {
    // A Sync onto itself is a no-op at best; a Move onto itself is asking to
    // move a folder into itself. Neither is anything a user meant to schedule,
    // so this blocks rather than warns.
    await pump(
      tester,
      src: (remote: _photos, path: 'DCIM'),
      dst: (remote: _photos, path: 'DCIM'),
    );
    expect(continueEnabled(tester), isFalse);
    expect(
      find.textContaining('the same folder'),
      findsOneWidget,
      reason: 'a disabled button with no explanation is a dead end',
    );
  });

  testWidgets('the same remote at DIFFERENT paths is allowed', (tester) async {
    // Reorganising within one remote is a legitimate task; only an identical
    // path is the mistake.
    await pump(
      tester,
      src: (remote: _photos, path: 'DCIM'),
      dst: (remote: _photos, path: 'Archive/DCIM'),
    );
    expect(continueEnabled(tester), isTrue);
    expect(find.textContaining('the same folder'), findsNothing);
  });

  testWidgets('a root folder reads as "remote:"', (tester) async {
    await pump(
      tester,
      src: (remote: _photos, path: ''),
      dst: (remote: _backup, path: ''),
    );
    expect(find.text('photos:'), findsOneWidget);
    expect(find.text('backup:'), findsOneWidget);
    expect(continueEnabled(tester), isTrue);
  });
}
