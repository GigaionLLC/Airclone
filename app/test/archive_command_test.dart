import 'package:airclone/src/state/archive_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildArchiveCommand (pure argv)', () {
    test('create: source dest + --format, cross-remote', () {
      final c = buildArchiveCommand(
        op: ArchiveOp.create,
        source: 'gdrive:Photos',
        dest: 's3:backups/photos.zip',
        format: ArchiveFormat.zip,
      );
      expect(c.args, [
        'archive',
        'create',
        'gdrive:Photos',
        's3:backups/photos.zip',
        '--format',
        'zip',
      ]);
      expect(c.sourceLabel, 'gdrive:Photos');
      expect(c.destLabel, 's3:backups/photos.zip');
    });

    test('create: --full-path + advanced extra flags appended verbatim', () {
      final c = buildArchiveCommand(
        op: ArchiveOp.create,
        source: 'local:dir',
        dest: 'local:out.tar.gz',
        format: ArchiveFormat.tarGz,
        fullPath: true,
        extraFlags: ['--transfers', '8', '--exclude', '*.tmp'],
      );
      expect(c.args, [
        'archive',
        'create',
        'local:dir',
        'local:out.tar.gz',
        '--format',
        'tar.gz',
        '--full-path',
        '--transfers',
        '8',
        '--exclude',
        '*.tmp',
      ]);
    });

    test('extract: source dest, no format flag (auto-detect)', () {
      final c = buildArchiveCommand(
        op: ArchiveOp.extract,
        source: 's3:backups/photos.zip',
        dest: 'gdrive:Restored',
      );
      expect(c.args, [
        'archive',
        'extract',
        's3:backups/photos.zip',
        'gdrive:Restored',
      ]);
      expect(c.args, isNot(contains('--format')));
    });

    test('list: source only, never a destination', () {
      final c = buildArchiveCommand(op: ArchiveOp.list, source: 's3:a.tar.zst');
      expect(c.args, ['archive', 'list', 's3:a.tar.zst']);
      expect(c.destLabel, '');
    });

    test(
      'guards: create/extract need a dest; list rejects one; create needs a format',
      () {
        expect(
          () => buildArchiveCommand(
            op: ArchiveOp.create,
            source: 'a:',
            format: ArchiveFormat.zip,
          ),
          throwsArgumentError,
          reason: 'create without dest',
        );
        expect(
          () => buildArchiveCommand(op: ArchiveOp.extract, source: 'a:x.zip'),
          throwsArgumentError,
          reason: 'extract without dest',
        );
        expect(
          () => buildArchiveCommand(
            op: ArchiveOp.list,
            source: 'a:x.zip',
            dest: 'b:',
          ),
          throwsArgumentError,
          reason: 'list with dest',
        );
        expect(
          () => buildArchiveCommand(
            op: ArchiveOp.create,
            source: 'a:',
            dest: 'b:out.zip',
          ),
          throwsArgumentError,
          reason: 'create without format',
        );
        expect(
          () => buildArchiveCommand(
            op: ArchiveOp.create,
            source: '   ',
            dest: 'b:o.zip',
            format: ArchiveFormat.zip,
          ),
          throwsArgumentError,
          reason: 'empty source',
        );
      },
    );
  });

  group('format detection + naming', () {
    test('longest extension wins (.tar.gz before .gz/.tar)', () {
      expect(archiveFormatForName('a.tar.gz'), ArchiveFormat.tarGz);
      expect(archiveFormatForName('a.TGZ'), ArchiveFormat.tarGz);
      expect(archiveFormatForName('a.tar'), ArchiveFormat.tar);
      expect(archiveFormatForName('photos.zip'), ArchiveFormat.zip);
      expect(archiveFormatForName('a.tar.zst'), ArchiveFormat.tarZst);
    });

    test('non-archives are not detected', () {
      expect(archiveFormatForName('report.pdf'), isNull);
      expect(archiveFormatForName('noext'), isNull);
      expect(looksLikeArchive('a.zip'), isTrue);
      expect(looksLikeArchive('a.txt'), isFalse);
    });

    test('defaultArchiveName appends the format extension to the leaf', () {
      expect(
        defaultArchiveName('Photos', ArchiveFormat.tarGz),
        'Photos.tar.gz',
      );
      expect(defaultArchiveName('', ArchiveFormat.zip), 'archive.zip');
    });

    test(
      'escapeRcloneGlob escapes filter metacharacters (literal --include)',
      () {
        expect(escapeRcloneGlob('data[1].csv'), r'data\[1\].csv');
        expect(escapeRcloneGlob('report{v2}.pdf'), r'report\{v2\}.pdf');
        expect(escapeRcloneGlob('a*b?c.txt'), r'a\*b\?c.txt');
        expect(escapeRcloneGlob(r'back\slash'), r'back\\slash');
        expect(escapeRcloneGlob('100%[final].zip'), r'100%\[final\].zip');
        expect(escapeRcloneGlob('normal-file.txt'), 'normal-file.txt');
      },
    );
  });
}
