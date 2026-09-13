import 'package:airclone/src/ui/quick_look.dart';
import 'package:flutter_test/flutter_test.dart';

/// The preview's action menu grew past delete in v0.13.1, and the way it was
/// wired had two holes worth pinning rather than re-discovering.
///
/// The first is the one that mattered: the menu was shown only where a file can
/// be handed to another app. That is false on iOS, so the entire menu — delete,
/// rename, public link, checksums, copy path — disappeared on a platform the
/// app ships to, none of which has anything to do with opening files elsewhere.
///
/// The second is quieter: the menu only existed in the phone's bottom sheet, so
/// on a desktop the operations behind it were unreachable even though every one
/// of them is platform-neutral.
///
/// [previewActionsFor] is the whole of that decision, which is why it is a pure
/// function rather than something you would have to stand up an overlay, an
/// engine and a remote to observe.
void main() {
  group('a platform that cannot open files elsewhere still gets the menu', () {
    test('iOS keeps every operation, and loses only the two that need it', () {
      final actions = previewActionsFor(canOpenExternally: false, touch: true);

      expect(actions, contains(PreviewAction.delete));
      expect(actions, contains(PreviewAction.rename));
      expect(actions, contains(PreviewAction.publicLink));
      expect(actions, contains(PreviewAction.checksums));
      expect(actions, contains(PreviewAction.copyPath));

      expect(actions, isNot(contains(PreviewAction.openExternally)));
      expect(actions, isNot(contains(PreviewAction.share)));
    });

    test('the menu is never empty, whatever the platform cannot do', () {
      for (final canOpen in [true, false]) {
        for (final touch in [true, false]) {
          expect(
            previewActionsFor(canOpenExternally: canOpen, touch: touch),
            isNotEmpty,
            reason: 'canOpenExternally=$canOpen touch=$touch',
          );
        }
      }
    });
  });

  group('the file operations are offered on every shape', () {
    /// Everything that acts on the file itself, as opposed to handing it to
    /// some other app. None of these depend on the platform, so a shape that
    /// omits one is a bug, not a choice.
    const fileOps = [
      PreviewAction.publicLink,
      PreviewAction.checksums,
      PreviewAction.rename,
      PreviewAction.copyPath,
      PreviewAction.delete,
    ];

    test('desktop', () {
      expect(
        previewActionsFor(canOpenExternally: true, touch: false),
        containsAll(fileOps),
      );
    });

    test('phone', () {
      expect(
        previewActionsFor(canOpenExternally: true, touch: true),
        containsAll(fileOps),
      );
    });
  });

  group('the two entries that are genuinely conditional', () {
    test('sharing is touch-only, because desktop has no share sheet', () {
      expect(
        previewActionsFor(canOpenExternally: true, touch: true),
        contains(PreviewAction.share),
      );
      expect(
        previewActionsFor(canOpenExternally: true, touch: false),
        isNot(contains(PreviewAction.share)),
      );
    });

    test('neither external entry survives a platform without the route', () {
      expect(
        previewActionsFor(canOpenExternally: false, touch: false),
        isNot(contains(PreviewAction.openExternally)),
      );
      expect(
        previewActionsFor(canOpenExternally: false, touch: true),
        isNot(contains(PreviewAction.openExternally)),
      );
    });
  });

  test('delete is last, so a slip never lands on it', () {
    for (final canOpen in [true, false]) {
      for (final touch in [true, false]) {
        final actions = previewActionsFor(
          canOpenExternally: canOpen,
          touch: touch,
        );
        expect(
          actions.last,
          PreviewAction.delete,
          reason: 'canOpenExternally=$canOpen touch=$touch',
        );
      }
    }
  });

  test('nothing is offered twice', () {
    for (final canOpen in [true, false]) {
      for (final touch in [true, false]) {
        final actions = previewActionsFor(
          canOpenExternally: canOpen,
          touch: touch,
        );
        expect(actions.toSet().length, actions.length);
      }
    }
  });
}
