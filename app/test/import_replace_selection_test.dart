import 'package:airclone/src/state/config_io.dart';
import 'package:flutter_test/flutter_test.dart';

/// Importing a config over one that already has remotes used to offer exactly
/// one answer to a name clash: rename the incoming one to `foo-imported`. A user
/// carrying sixteen remotes between two machines, nine of them colliding, then
/// had to delete that suffix nine times by hand — and the whole point of the
/// import was to REPLACE those nine.
///
/// The plan already carried [ImportDecision.replaceExisting]; what was missing
/// was a way to choose it per remote. These pin the rules the per-remote choice
/// relies on, since a wrong one here silently overwrites the wrong remote.
void main() {
  ConfigModel cfg(Map<String, String> typesByName) => {
    for (final e in typesByName.entries) e.key: {'type': e.value},
  };

  group('what planImport marks as a collision', () {
    test('only a name the existing config already has', () {
      final plan = planImport(
        cfg({'keep': 'sftp', 'shared': 's3'}),
        cfg({'shared': 's3', 'fresh': 'drive'}),
      );
      final byName = {for (final d in plan) d.name: d};
      expect(byName['shared']!.collision, isTrue);
      expect(byName['fresh']!.collision, isFalse);
    });

    test('a non-colliding remote gets no rename to undo', () {
      final plan = planImport(cfg({}), cfg({'solo': 'sftp'}));
      expect(plan.single.collision, isFalse);
      expect(plan.single.renamedTo, isNull);
    });

    test(
      'the suffix is only a default, and the original name is preserved',
      () {
        // The UI offers "replace" against d.name, so the incoming name must
        // survive planning intact even when a rename was suggested.
        final plan = planImport(cfg({'photos': 's3'}), cfg({'photos': 's3'}));
        expect(plan.single.name, 'photos');
        expect(plan.single.renamedTo, 'photos-imported');
      },
    );
  });

  group('a replace decision', () {
    test('keeps the incoming name and carries no rename', () {
      // Mutually exclusive on purpose: a decision either lands beside the
      // existing remote or on top of it, never both.
      const d = ImportDecision(
        name: 'photos',
        type: 's3',
        collision: true,
        replaceExisting: true,
      );
      expect(d.name, 'photos');
      expect(d.renamedTo, isNull);
      expect(d.replaceExisting, isTrue);
    });

    test('differs from the rename decision for the same remote', () {
      const replace = ImportDecision(
        name: 'photos',
        type: 's3',
        collision: true,
        replaceExisting: true,
      );
      const rename = ImportDecision(
        name: 'photos',
        type: 's3',
        collision: true,
        renamedTo: 'photos-imported',
      );
      expect(replace, isNot(equals(rename)));
    });

    test('a mixed plan is expressible — the reason this is per remote', () {
      // The case that motivated it: some collisions replaced, others kept.
      final plan = planImport(
        cfg({'a': 's3', 'b': 's3'}),
        cfg({'a': 's3', 'b': 's3'}),
      );
      final decided = [
        for (final d in plan)
          if (d.name == 'a')
            ImportDecision(
              name: d.name,
              type: d.type,
              collision: true,
              replaceExisting: true,
            )
          else
            ImportDecision(
              name: d.name,
              type: d.type,
              collision: true,
              renamedTo: d.renamedTo,
            ),
      ];
      expect(decided.where((d) => d.replaceExisting).map((d) => d.name), ['a']);
      expect(decided.where((d) => d.renamedTo != null).map((d) => d.name), [
        'b',
      ]);
    });
  });
}
