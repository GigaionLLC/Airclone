import 'package:airclone/src/rclone/models/rclone_file.dart';
import 'package:airclone/src/rclone/models/remote.dart';
import 'package:airclone/src/rclone/rclone_client.dart';
import 'package:airclone/src/state/browser_controller.dart';
import 'package:airclone/src/state/download_settings.dart';
import 'package:airclone/src/state/engine_controller.dart';
import 'package:airclone/src/ui/selection_actions.dart';
import 'package:airclone/src/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// flutter_test's binding also defines `EnginePhase`; hide it so ours wins.
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;

/// Downloading a file you already have used to destroy the local copy without
/// asking.
///
/// `showCopyConflictDialog` had exactly ONE caller — the paste path — while
/// Download, drag-and-drop and the pane-to-pane transfer button went straight
/// at `TransferService.transfer()`. rclone overwrites by default, so the
/// destination file was gone with no prompt and no undo.
///
/// This drives the one entry point that is reachable as a plain function.
/// The other three are private widget methods routed through the same helper
/// in the same change; `paste_action_test.dart` covers the helper itself.
class _FakeClient implements RcloneClient {
  final transfers = <String>[];

  @override
  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    if (method == 'operations/list') {
      // The download folder already holds a file of the same name.
      return {
        'list': [
          {'Name': 'dup.txt', 'Path': 'dup.txt', 'IsDir': false, 'Size': 1},
        ],
      };
    }
    if (method == 'operations/copyfile' || method == 'operations/movefile') {
      transfers.add((params?['dstRemote'] ?? '').toString());
    }
    return {'jobid': 1};
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

/// A saved download folder, so `resolveDownloadDir` returns without opening a
/// native folder picker (which a widget test cannot answer).
class _FakeDir extends DownloadDir {
  @override
  String? build() => '/downloads';
}

class _NoPrompt extends DownloadAlwaysPrompt {
  @override
  bool build() => false;
}

/// A pane holding one selected file named dup.txt.
class _FakePane extends BrowserController {
  @override
  BrowserState build() => const BrowserState(
    remote: Remote(name: 'gdrive', type: 'drive', fs: 'gdrive:'),
    path: 'from',
    entries: [
      RcloneFile(name: 'dup.txt', path: 'from/dup.txt', isDir: false, size: 1),
    ],
    selected: {'dup.txt'},
  );
}

void main() {
  testWidgets('downloading onto an existing file prompts instead of '
      'overwriting', (tester) async {
    final client = _FakeClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          engineControllerProvider.overrideWith(() => _FakeEngine(client)),
          downloadDirProvider.overrideWith(_FakeDir.new),
          downloadAlwaysPromptProvider.overrideWith(_NoPrompt.new),
          browserAProvider.overrideWith(_FakePane.new),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Consumer(
            builder: (ctx, ref, _) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => selectionDownload(ctx, ref, 0),
                  child: const Text('download'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('download'));
    await tester.pumpAndSettle();

    // The bug: this dialog never appeared on the download path.
    expect(find.text('1 of 1 already exist here'), findsOneWidget);

    // And cancelling must leave the local file alone.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(client.transfers, isEmpty);
  });
}
