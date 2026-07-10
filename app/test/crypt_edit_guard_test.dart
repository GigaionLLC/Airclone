import 'package:airclone/src/rclone/models/provider.dart';
import 'package:airclone/src/rclone/models/remote.dart';
import 'package:airclone/src/rclone/rclone_client.dart';
import 'package:airclone/src/state/engine_controller.dart';
import 'package:airclone/src/state/providers_provider.dart';
import 'package:airclone/src/ui/add_remote_dialog.dart';
import 'package:airclone/src/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// flutter_test's binding also defines `EnginePhase`; hide it so ours wins.
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;

class _CapturingClient implements RcloneClient {
  final calls = <({String method, Map<String, dynamic>? params})>[];
  Map<String, dynamic> Function(String, Map<String, dynamic>?)? onRpc;

  @override
  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    calls.add((method: method, params: params));
    return onRpc?.call(method, params) ?? <String, dynamic>{};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeEngine extends EngineController {
  _FakeEngine(this._client);
  final RcloneClient _client;
  @override
  EngineUi build() => EngineUi(phase: EnginePhase.ready, client: _client);
}

// A crypt provider with a single password field keeps exactly ONE TextField on
// the edit form, so the test can target the password entry unambiguously.
const _crypt = RcloneProvider(
  name: 'crypt',
  description: '',
  options: [ProviderOption(name: 'password', isPassword: true)],
);

Map<String, dynamic> _cryptGet(String method, Map<String, dynamic>? _) =>
    method == 'config/get'
    ? {'type': 'crypt', 'password': 'OBSCURED_TOKEN'}
    : <String, dynamic>{};

/// Opens the edit dialog for a crypt remote (via [showEditRemoteDialog], so it's
/// a real dialog route) and settles the async startEdit prefill.
Future<_CapturingClient> _openCryptEdit(WidgetTester tester) async {
  final client = _CapturingClient()..onRpc = _cryptGet;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        engineControllerProvider.overrideWith(() => _FakeEngine(client)),
        providersProvider.overrideWith((ref) async => [_crypt]),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showEditRemoteDialog(
                  ctx,
                  const Remote(name: 'secret', type: 'crypt', fs: 'secret:'),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  // The prefilled edit form is up.
  expect(find.text('Save changes'), findsOneWidget);
  return client;
}

void main() {
  testWidgets('typing a new crypt password gates the save behind a confirm', (
    tester,
  ) async {
    final client = await _openCryptEdit(tester);
    await tester.enterText(find.byType(TextField), 'newpass');
    await tester.pump(); // let the value land in controller state before save
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    // Guard fires — the confirm is shown and nothing has been written yet.
    expect(find.text('Change encryption password?'), findsOneWidget);
    expect(client.calls.any((c) => c.method == 'config/update'), isFalse);

    // Confirming (the destructive action) proceeds with the re-key.
    await tester.tap(find.text('Change password'));
    await tester.pumpAndSettle();
    expect(client.calls.any((c) => c.method == 'config/update'), isTrue);
  });

  testWidgets('cancelling the confirm leaves the crypt remote untouched', (
    tester,
  ) async {
    final client = await _openCryptEdit(tester);
    await tester.enterText(find.byType(TextField), 'newpass');
    await tester.pump(); // let the value land in controller state before save
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(find.text('Change encryption password?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    // No update issued; the edit form is still open for another try.
    expect(client.calls.any((c) => c.method == 'config/update'), isFalse);
    expect(find.text('Save changes'), findsOneWidget);
  });

  testWidgets('leaving the crypt password blank saves without a confirm', (
    tester,
  ) async {
    final client = await _openCryptEdit(tester);
    // Don't touch the (blank) password field — blank means "keep current".
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(find.text('Change encryption password?'), findsNothing);
    expect(client.calls.any((c) => c.method == 'config/update'), isTrue);
  });
}
