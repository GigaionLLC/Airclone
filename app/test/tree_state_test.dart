import 'package:airclone/src/rclone/models/rclone_file.dart';
import 'package:airclone/src/state/tree_state.dart';
import 'package:flutter_test/flutter_test.dart';

RcloneFile _dir(String name, String path) =>
    RcloneFile(name: name, path: path, isDir: true);
RcloneFile _file(String name, String path) =>
    RcloneFile(name: name, path: path, isDir: false, size: 1);

/// Root:  A/  b.txt        A: C/  a1.txt        A/C: c1.txt
const _rootEntries = <RcloneFile>[];
final _root = [_dir('A', 'A'), _file('b.txt', 'b.txt')];
final _a = [_dir('C', 'A/C'), _file('a1.txt', 'A/a1.txt')];
final _ac = [_file('c1.txt', 'A/C/c1.txt')];

List<String> _names(List<TreeRow> rows) => [
  for (final r in rows)
    switch (r.kind) {
      TreeRowKind.entry => '${'  ' * r.depth}${r.file.name}',
      TreeRowKind.empty => '${'  ' * r.depth}<empty>',
      TreeRowKind.error => '${'  ' * r.depth}<error>',
    },
];

void main() {
  group('flattenTree', () {
    test('a collapsed folder is one row; nothing beneath it is visited', () {
      final rows = flattenTree(
        rootPath: '',
        rootEntries: _root,
        tree: TreeState(children: {'A': _a}),
      );
      expect(_names(rows), ['A', 'b.txt']);
      expect(rows.first.parentPath, '');
    });

    test('an expanded folder shows its cached children one level deeper, '
        'each carrying the folder it was listed from', () {
      final rows = flattenTree(
        rootPath: '',
        rootEntries: _root,
        tree: TreeState(
          children: {'A': _a, 'A/C': _ac},
          expanded: const {'A', 'A/C'},
        ),
      );
      expect(_names(rows), ['A', '  C', '    c1.txt', '  a1.txt', 'b.txt']);
      final c1 = rows[2];
      expect(c1.parentPath, 'A/C');
      expect(c1.path, 'A/C/c1.txt');
      expect(c1.depth, 2);
    });

    test('rows are relative to a non-root tree root', () {
      final rows = flattenTree(
        rootPath: 'A',
        rootEntries: _a,
        tree: TreeState(children: {'A/C': _ac}, expanded: const {'A/C'}),
      );
      expect(_names(rows), ['C', '  c1.txt', 'a1.txt']);
      expect(rows[0].parentPath, 'A');
      expect(rows[1].parentPath, 'A/C');
    });

    test('an expanded folder with no children shows an Empty placeholder, '
        'and a failed one shows the error', () {
      final rows = flattenTree(
        rootPath: '',
        rootEntries: [_dir('E', 'E'), _dir('F', 'F'), _dir('L', 'L')],
        tree: const TreeState(
          children: {'E': []},
          expanded: {'E', 'F', 'L'},
          errors: {'F': 'boom'},
          loading: {'L'},
        ),
      );
      // L is still loading: no placeholder, the disclosure spins instead.
      expect(_names(rows), ['E', '  <empty>', 'F', '  <error>', 'L']);
      expect(rows[3].message, 'boom');
      expect(rows[1].path, 'E'); // a placeholder's path is its folder
      expect(rows[1].key, isNot(rows[0].key));
    });

    group('filter', () {
      final tree = TreeState(
        children: {'A': _a, 'A/C': _ac},
        expanded: const {'A', 'A/C'},
      );

      test('keeps a matching row and the expanded ancestors above it, even '
          'when their own names do not match', () {
        final rows = flattenTree(
          rootPath: '',
          rootEntries: _root,
          tree: tree,
          filter: 'c1',
        );
        expect(_names(rows), ['A', '  C', '    c1.txt']);
      });

      test('drops an expanded folder with nothing matching beneath it', () {
        final rows = flattenTree(
          rootPath: '',
          rootEntries: _root,
          tree: tree,
          filter: 'b.t',
        );
        expect(_names(rows), ['b.txt']);
      });

      test('is a filter over what is loaded, not a search: a collapsed '
          'folder is not opened to look inside', () {
        final rows = flattenTree(
          rootPath: '',
          rootEntries: _root,
          tree: TreeState(children: {'A': _a}), // A cached but collapsed
          filter: 'a1',
        );
        expect(rows, isEmpty);
      });

      test('hides placeholders while filtering', () {
        final rows = flattenTree(
          rootPath: '',
          rootEntries: [_dir('E', 'E')],
          tree: const TreeState(children: {'E': []}, expanded: {'E'}),
          filter: 'e',
        );
        expect(_names(rows), ['E']);
      });
    });

    test('an empty root flattens to nothing', () {
      expect(
        flattenTree(
          rootPath: '',
          rootEntries: _rootEntries,
          tree: TreeState.empty,
        ),
        isEmpty,
      );
    });
  });

  group('visibleExpandedFolders', () {
    test('only folders whose every ancestor is expanded, shallowest first', () {
      const tree = TreeState(expanded: {'A/C', 'A', 'X/Y', 'B'});
      // X/Y's parent X is not expanded, so it is not on screen.
      expect(visibleExpandedFolders('', tree), ['A', 'B', 'A/C']);
    });

    test('is scoped to the tree root', () {
      const tree = TreeState(expanded: {'A', 'A/C', 'A/C/D', 'B'});
      expect(visibleExpandedFolders('A', tree), ['A/C', 'A/C/D']);
      // A prefix that is not a path component is not containment.
      const sib = TreeState(expanded: {'Ab', 'A/C'});
      expect(visibleExpandedFolders('A', sib), ['A/C']);
    });
  });

  group('groupByParent', () {
    test('groups entry rows by folder, first-seen order both ways, and skips '
        'placeholders', () {
      final rows = [
        TreeRow.entry(entry: _file('y', 'A/B/y'), parentPath: 'A/B', depth: 2),
        TreeRow.entry(entry: _file('x', 'A/x'), parentPath: 'A', depth: 1),
        const TreeRow.empty(parentPath: 'A/E', depth: 2),
        TreeRow.entry(entry: _file('z', 'A/B/z'), parentPath: 'A/B', depth: 2),
      ];
      final g = groupByParent(rows);
      expect(g.keys.toList(), ['A/B', 'A']);
      expect(g['A/B']!.map((f) => f.name), ['y', 'z']);
      expect(g['A']!.map((f) => f.name), ['x']);
    });
  });

  group('path helpers', () {
    test('parentOf / leafOf / isUnder', () {
      expect(parentOf('A/B/c.txt'), 'A/B');
      expect(parentOf('c.txt'), '');
      expect(leafOf('A/B/c.txt'), 'c.txt');
      expect(leafOf('c.txt'), 'c.txt');
      expect(isUnder('A/B', 'A'), isTrue);
      expect(isUnder('A', 'A'), isFalse);
      expect(isUnder('AB', 'A'), isFalse);
      expect(isUnder('anything', ''), isTrue);
      expect(isUnder('', ''), isFalse);
    });
  });
}
