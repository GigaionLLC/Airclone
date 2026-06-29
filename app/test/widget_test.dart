import 'package:airclone/src/rclone/models/provider.dart';
import 'package:airclone/src/rclone/models/rclone_file.dart';
import 'package:airclone/src/rclone/models/remote.dart';
import 'package:airclone/src/ui/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('humanSize', () {
    test('bytes, KB, MB boundaries', () {
      expect(humanSize(-1), '—');
      expect(humanSize(0), '0 B');
      expect(humanSize(1023), '1023 B');
      expect(humanSize(1024), '1.0 KB');
      expect(humanSize(1536), '1.5 KB');
      expect(humanSize(10 * 1024 * 1024), '10 MB');
    });
  });

  group('RcloneFile.fromJson', () {
    test('parses an lsjson entry', () {
      final f = RcloneFile.fromJson(const {
        'Path': 'Work/report.pdf',
        'Name': 'report.pdf',
        'Size': 2100,
        'MimeType': 'application/pdf',
        'IsDir': false,
        'ModTime': '2026-01-02T03:04:05Z',
      });
      expect(f.name, 'report.pdf');
      expect(f.path, 'Work/report.pdf');
      expect(f.size, 2100);
      expect(f.isDir, isFalse);
      expect(f.modTime, isNotNull);
    });

    test('directory has size -1 default and tolerates missing fields', () {
      final d = RcloneFile.fromJson(const {'Name': 'designs', 'IsDir': true});
      expect(d.isDir, isTrue);
      expect(d.size, -1);
      expect(d.modTime, isNull);
    });
  });

  group('Remote.listParams', () {
    test('builds fs + remote params', () {
      const r = Remote(name: 'gdrive', type: 'drive', fs: 'gdrive:');
      final p = r.listParams('Work/Q1');
      expect(p['fs'], 'gdrive:');
      expect(p['remote'], 'Work/Q1');
    });

    test('equality keys on name + fs', () {
      const a = Remote(name: 'gdrive', type: 'drive', fs: 'gdrive:');
      const b = Remote(name: 'gdrive', type: 'drive', fs: 'gdrive:');
      expect(a, equals(b));
    });
  });

  group('Provider.fromJson', () {
    final p = RcloneProvider.fromJson(const {
      'Name': 's3',
      'Description': 'Amazon S3 Compliant Storage Providers',
      'Options': [
        {
          'Name': 'provider',
          'Help': 'Choose your S3 provider.',
          'Type': 'string',
          'Advanced': false,
          'Hide': 0,
        },
        {
          'Name': 'secret_access_key',
          'Help': 'AWS Secret Access Key.',
          'Type': 'string',
          'IsPassword': true,
          'Sensitive': true,
        },
        {
          'Name': 'chunk_size',
          'Help': 'Chunk size to use.',
          'Type': 'SizeSuffix',
          'Advanced': true,
        },
        {'Name': 'hidden_opt', 'Help': 'internal', 'Hide': 1},
        {
          'Name': 'acl',
          'Help': 'Canned ACL.',
          'Type': 'string',
          'Examples': [
            {'Value': 'private', 'Help': 'Owner only'},
            {'Value': 'public-read', 'Help': 'Public'},
          ],
        },
      ],
    });

    test('parses name, description, and option count', () {
      expect(p.name, 's3');
      expect(p.options.length, 5);
    });

    test('splits standard vs advanced and hides Hide!=0', () {
      // standard = provider, secret_access_key, acl (chunk_size is advanced, hidden_opt hidden)
      expect(
        p.standardOptions.map((o) => o.name),
        containsAll(['provider', 'secret_access_key', 'acl']),
      );
      expect(p.standardOptions.any((o) => o.name == 'hidden_opt'), isFalse);
      expect(p.advancedOptions.map((o) => o.name), ['chunk_size']);
    });

    test('option type flags', () {
      final secret = p.options.firstWhere((o) => o.name == 'secret_access_key');
      expect(secret.isPassword, isTrue);
      final chunk = p.options.firstWhere((o) => o.name == 'chunk_size');
      expect(chunk.isInt, isTrue);
      final acl = p.options.firstWhere((o) => o.name == 'acl');
      expect(acl.isSelect, isTrue);
      expect(acl.examples.first.value, 'private');
    });
  });
}
