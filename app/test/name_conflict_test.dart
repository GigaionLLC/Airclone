import 'package:airclone/src/state/name_conflict.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('uniqueName', () {
    test('returns the name unchanged when free', () {
      expect(uniqueName('a.txt', {'b.txt'}), 'a.txt');
    });

    test('inserts the suffix before the extension', () {
      expect(uniqueName('report.pdf', {'report.pdf'}), 'report (2).pdf');
    });

    test('walks up until a free slot', () {
      expect(
        uniqueName('report.pdf', {'report.pdf', 'report (2).pdf'}),
        'report (3).pdf',
      );
    });

    test('extension-less names get the suffix at the end', () {
      expect(uniqueName('archive', {'archive'}), 'archive (2)');
    });

    test('dotfiles are treated as having no extension', () {
      expect(uniqueName('.gitignore', {'.gitignore'}), '.gitignore (2)');
    });

    test('multi-dot names only split on the last dot', () {
      expect(uniqueName('a.tar.gz', {'a.tar.gz'}), 'a.tar (2).gz');
    });
  });

  group('planPaste', () {
    final dest = {'a.txt', 'b.txt'};

    test('cancel yields an empty plan', () {
      expect(planPaste(['a.txt'], dest, ConflictChoice.cancel), isEmpty);
    });

    test('skip drops only the colliding names', () {
      final plan = planPaste(
        ['a.txt', 'c.txt'],
        dest,
        ConflictChoice.skip,
      );
      expect(plan.map((p) => p.dst), ['c.txt']); // a.txt skipped
    });

    test('overwrite keeps every name as-is', () {
      final plan = planPaste(
        ['a.txt', 'c.txt'],
        dest,
        ConflictChoice.overwrite,
      );
      expect(plan.map((p) => '${p.src}->${p.dst}'), [
        'a.txt->a.txt',
        'c.txt->c.txt',
      ]);
    });

    test('keep both renames colliding names, leaves free ones', () {
      final plan = planPaste(
        ['a.txt', 'c.txt'],
        dest,
        ConflictChoice.keepBoth,
      );
      expect(plan.map((p) => '${p.src}->${p.dst}'), [
        'a.txt->a (2).txt',
        'c.txt->c.txt',
      ]);
    });

    test('keep both never reuses a name within the same paste', () {
      // Pasting a.txt twice (e.g. odd clipboard) must produce two distinct dsts.
      final plan = planPaste(
        ['a.txt', 'a (2).txt'],
        {'a.txt'},
        ConflictChoice.keepBoth,
      );
      final dsts = plan.map((p) => p.dst).toSet();
      expect(dsts.length, 2); // no collision among assigned names
      expect(dsts.contains('a (2).txt'), isTrue);
    });
  });
}
