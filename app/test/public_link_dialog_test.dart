import 'package:airclone/src/rclone/rclone_client.dart';
import 'package:airclone/src/ui/public_link_dialog.dart';
import 'package:airclone/src/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Echoes a url on create, succeeds on unlink. Records the last params.
class _FakeClient implements RcloneClient {
  Map<String, dynamic>? lastParams;

  @override
  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    lastParams = params;
    if (params?['unlink'] == true) return {};
    return {'url': 'https://example.com/s/abc'};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _open(WidgetTester tester, RcloneClient client) async {
  tester.view.physicalSize = const Size(900, 800);
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
              onPressed: () => showPublicLinkDialog(
                ctx,
                client,
                fs: 'gdrive:',
                remote: 'Work/report.pdf',
                name: 'report.pdf',
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
  // Capture clipboard writes so Copy can be asserted.
  final clipboard = <MethodCall>[];
  setUp(() {
    clipboard.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') clipboard.add(call);
          return null;
        });
  });

  testWidgets('create → copy shows confirmation and writes the URL', (
    tester,
  ) async {
    await _open(tester, _FakeClient());
    await tester.tap(find.widgetWithText(FilledButton, 'Create link'));
    await tester.pumpAndSettle();
    expect(find.text('https://example.com/s/abc'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Copy'));
    await tester.pumpAndSettle();
    expect(find.text('Link copied.'), findsOneWidget);
    expect(clipboard, isNotEmpty);
    expect(clipboard.first.arguments['text'], 'https://example.com/s/abc');
  });

  testWidgets('revoke sends unlink:true and confirms', (tester) async {
    final client = _FakeClient();
    await _open(tester, client);
    await tester.tap(find.widgetWithText(FilledButton, 'Create link'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Revoke'));
    await tester.pumpAndSettle();
    expect(client.lastParams?['unlink'], true);
    expect(find.text('Link revoked.'), findsOneWidget);
  });

  testWidgets('expire preset is sent only when not "off"', (tester) async {
    final client = _FakeClient();
    await _open(tester, client);
    // Default is "No expiry" → no expire param.
    await tester.tap(find.widgetWithText(FilledButton, 'Create link'));
    await tester.pumpAndSettle();
    expect(client.lastParams?.containsKey('expire'), false);
  });
}
