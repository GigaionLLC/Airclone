import 'package:airclone/src/state/engine_flags.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseEngineFlags', () {
    test('tokenizes, respecting double quotes', () {
      expect(parseEngineFlags('--transfers 8 --bwlimit "10 M"'), [
        '--transfers',
        '8',
        '--bwlimit',
        '10 M',
      ]);
      expect(parseEngineFlags(''), isEmpty);
      expect(parseEngineFlags('  --fast-list '), ['--fast-list']);
    });
  });

  group('toggleEngineFlag', () {
    test('adds a bare flag, then removes it', () {
      final on = toggleEngineFlag('', '--fast-list');
      expect(on, '--fast-list');
      expect(hasEngineFlag(on, '--fast-list'), isTrue);
      final off = toggleEngineFlag(on, '--fast-list');
      expect(off, '');
      expect(hasEngineFlag(off, '--fast-list'), isFalse);
    });

    test('adds a value flag and removes the value with it', () {
      final on = toggleEngineFlag('--fast-list', '--transfers 8');
      expect(on, '--fast-list --transfers 8');
      expect(hasEngineFlag(on, '--transfers 8'), isTrue);
      final off = toggleEngineFlag(on, '--transfers 8');
      expect(off, '--fast-list'); // value dropped too
    });

    test('chip reflects an existing flag regardless of its value', () {
      // User typed --transfers 4; the "--transfers 8" chip reads as selected.
      expect(hasEngineFlag('--transfers 4', '--transfers 8'), isTrue);
      // Toggling off removes the user's --transfers 4 entirely.
      expect(toggleEngineFlag('--transfers 4', '--transfers 8'), '');
    });

    test('leaves unrelated flags intact', () {
      expect(
        toggleEngineFlag('--fast-list --checkers 16', '--no-traverse'),
        '--fast-list --checkers 16 --no-traverse',
      );
    });
  });
}
