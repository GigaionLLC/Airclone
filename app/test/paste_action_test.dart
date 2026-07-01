import 'package:airclone/src/rclone/models/job.dart';
import 'package:airclone/src/rclone/models/rclone_file.dart';
import 'package:airclone/src/rclone/models/remote.dart';
import 'package:airclone/src/rclone/rclone_client.dart';
import 'package:airclone/src/state/clipboard_controller.dart';
import 'package:airclone/src/state/engine_controller.dart';
import 'package:airclone/src/ui/paste_action.dart';
import 'package:airclone/src/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// flutter_test's binding also defines `EnginePhase`; hide it so ours wins.
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;

/// Returns a canned recursive-free listing for the destination folder and
/// records any transfer RPCs (so we can assert none run on cancel).
class _FakeClient implements RcloneClient {
  final transfers = <String>[];

  @override
  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    if (method == 'operations/list') {
      return {
        'list': [
          {'Name': 'dup.txt', 'Path': 'sub/dup.txt', 'IsDir': false, 'Size': 1},
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

const _remote = Remote(name: 'gdrive', type: 'drive', fs: 'gdrive:');

void main() {
  testWidgets('pasting into a subfolder lists it, detects the collision, and '
      'prompts', (tester) async {
    final client = _FakeClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          engineControllerProvider.overrideWith(() => _FakeEngine(client)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Consumer(
            builder: (ctx, ref, _) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    // Stage a file named dup.txt on the clipboard.
                    ref
                        .read(clipboardControllerProvider.notifier)
                        .copy(_remote, '', const [
                          RcloneFile(
                            name: 'dup.txt',
                            path: 'dup.txt',
                            isDir: false,
                            size: 1,
                          ),
                        ]);
                    // Paste into a subfolder whose listing isn't held locally →
                    // the helper must list it (knownNames: null) to find dup.txt.
                    pasteClipboardIntoFolder(
                      ctx,
                      ref,
                      destRemote: _remote,
                      destPath: 'sub',
                      refreshPaneIndex: 0,
                      knownNames: null,
                    );
                  },
                  child: const Text('paste'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('paste'));
    await tester.pumpAndSettle();

    // The conflict prompt appeared because the pre-list surfaced the collision.
    expect(find.text('1 of 1 already exist here'), findsOneWidget);

    // Cancelling must run no transfer.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(client.transfers, isEmpty);
  });

  testWidgets('drag-drop core prompts on a collision (known listing, no '
      're-list)', (tester) async {
    final client = _FakeClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          engineControllerProvider.overrideWith(() => _FakeEngine(client)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Consumer(
            builder: (ctx, ref, _) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  // Simulates dropping "dup.txt" onto a folder that already
                  // holds it — knownNames supplied, so no operations/list.
                  onPressed: () => transferNamesIntoFolder(
                    ctx,
                    ref,
                    srcRemote: _remote,
                    srcParentPath: 'from',
                    names: const ['dup.txt'],
                    destRemote: _remote,
                    destPath: 'sub',
                    type: JobType.copy,
                    refreshPaneIndex: null,
                    knownNames: const {'dup.txt'},
                  ),
                  child: const Text('drop'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('drop'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 1 already exist here'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(client.transfers, isEmpty);
  });

  testWidgets('a skip-everything CUT keeps the clipboard (nothing moved)', (
    tester,
  ) async {
    final client = _FakeClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          engineControllerProvider.overrideWith(() => _FakeEngine(client)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Consumer(
            builder: (ctx, ref, _) {
              final n = ref.watch(clipboardControllerProvider).files.length;
              return Scaffold(
                body: Column(
                  children: [
                    Text('clip:$n'),
                    ElevatedButton(
                      onPressed: () async {
                        ref
                            .read(clipboardControllerProvider.notifier)
                            .cut(_remote, '', const [
                              RcloneFile(
                                name: 'dup.txt',
                                path: 'dup.txt',
                                isDir: false,
                                size: 1,
                              ),
                            ]);
                        await pasteClipboardIntoFolder(
                          ctx,
                          ref,
                          destRemote: _remote,
                          destPath: 'sub',
                          refreshPaneIndex: 0,
                          knownNames: const {'dup.txt'},
                        );
                      },
                      child: const Text('cutpaste'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('cutpaste'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 1 already exist here'), findsOneWidget);

    await tester.tap(find.text('Skip these'));
    await tester.pumpAndSettle();
    // Nothing moved → the cut selection must survive (not be cleared).
    expect(find.text('clip:1'), findsOneWidget);
    expect(client.transfers, isEmpty);
  });
}
