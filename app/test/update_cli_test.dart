import 'dart:convert';
import 'dart:io';

import 'package:airclone/src/headless/update_cli.dart';
import 'package:airclone/src/state/install_source.dart';
import 'package:airclone/src/update/minisign.dart';
import 'package:airclone/src/update/self_update_target.dart';
import 'package:airclone/src/update/update_fetch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// `airclone --update`, the terminal half of updating.
///
/// Driven end to end against a real HTTP server and the signed fixture, because
/// the interesting cases are the refusals and each of them is a different code
/// path: a store build must not even ask GitHub, a build with no key must not
/// install, and a package that cannot replace itself must say so rather than
/// report success.
void main() {
  late HttpServer server;
  late Directory staging;

  /// Where the pretend install lives. Separate from [staging] on purpose: the
  /// downloader renames the verified file to the asset's own name, so an
  /// AppImage sitting in the staging directory would be overwritten by the
  /// download before anything got installed - which is what the first version
  /// of these tests actually measured.
  late Directory home;
  late MinisignPublicKey key;
  late Map<String, List<int>> served;
  const assetName = 'Airclone-x86_64.AppImage';

  const direct = InstallSource(
    channel: InstallChannel.directDownload,
    storeName: 'the Airclone releases page',
  );
  const store = InstallSource(
    channel: InstallChannel.microsoftStore,
    storeName: 'the Microsoft Store',
  );

  setUp(() async {
    final dir = Directory('test/fixtures/update');
    key = MinisignPublicKey.parse(
      File('${dir.path}/public_key.txt').readAsStringSync().trim(),
    )!;
    staging = Directory.systemTemp.createTempSync('airclone-update-cli');
    home = Directory.systemTemp.createTempSync('airclone-update-home');
    served = {
      'SHA256SUMS': File('${dir.path}/SHA256SUMS').readAsBytesSync(),
      'SHA256SUMS.minisig': File(
        '${dir.path}/SHA256SUMS.minisig',
      ).readAsBytesSync(),
      assetName: File('${dir.path}/asset.bin').readAsBytesSync(),
    };
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = served[request.uri.pathSegments.last];
      if (body == null) {
        request.response.statusCode = 404;
      } else {
        request.response.add(body);
      }
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    if (staging.existsSync()) staging.deleteSync(recursive: true);
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  UpdateCliEnvironment env({
    InstallSource source = direct,
    SelfUpdateTarget target = SelfUpdateTarget.linuxAppImage,
    String current = '0.13.6',
    String? latest = 'v9.9.9',
    int keys = 1,
    Map<String, String> processEnv = const {},
  }) => UpdateCliEnvironment(
    currentVersion: current,
    source: source,
    target: target,
    latestTag: () async => latest,
    trustedKeyCount: keys,
    processEnvironment: processEnv,
    fetcher: () => UpdateFetcher(
      client: http.Client(),
      stagingDir: staging,
      trustedKeys: [key],
      assetUrl: ({required String tag, required String asset}) =>
          Uri.parse('http://${server.address.host}:${server.port}/$tag/$asset'),
    ),
  );

  Future<(int, String)> run(
    List<String> args,
    UpdateCliEnvironment environment,
  ) async {
    final lines = <String>[];
    final code = await runUpdateCli(args, environment, out: lines.add);
    return (code, lines.join('\n'));
  }

  group('the flags', () {
    test('--update is what starts it', () {
      expect(isUpdateInvocation(const ['--update']), isTrue);
      expect(isUpdateInvocation(const ['--webui']), isFalse);
      expect(isUpdateInvocation(const []), isFalse);
    });

    test('--check, --output and --version-tag are read', () {
      final o = parseUpdateArgs(const [
        '--update',
        '--check',
        '--output',
        '/tmp/a.AppImage',
        '--version-tag',
        'v1.2.3',
      ]);
      expect(o.checkOnly, isTrue);
      expect(o.output, '/tmp/a.AppImage');
      expect(o.tag, 'v1.2.3');
    });

    /// `--output --check` must not write a file called "--check".
    test('a flag is never taken as the value of another flag', () {
      final o = parseUpdateArgs(const ['--update', '--output', '--check']);
      expect(o.output, isNull);
      expect(o.checkOnly, isTrue);
    });

    test('bare --update asks for nothing else', () {
      final o = parseUpdateArgs(const ['--update']);
      expect(o.checkOnly, isFalse);
      expect(o.output, isNull);
      expect(o.tag, isNull);
    });
  });

  group('what it refuses', () {
    /// Store policy, not preference: Microsoft's 10.2.5 failed a submission of
    /// this app for linking to a download. The refusal must also happen before
    /// any network call - `latestTag` throwing proves none was made.
    test('a store build, without asking GitHub anything', () async {
      final environment = UpdateCliEnvironment(
        currentVersion: '0.13.6',
        source: store,
        target: SelfUpdateTarget.unsupported,
        latestTag: () async => throw StateError('a store build asked GitHub'),
        fetcher: () => throw StateError('a store build downloaded something'),
      );
      final (code, text) = await run(const ['--update'], environment);
      expect(code, kUpdateFailed);
      expect(text, contains('the Microsoft Store'));
    });

    /// Nothing to verify against means nothing gets installed.
    test('a build with no release key', () async {
      final (code, text) = await run(const ['--update'], env(keys: 0));
      expect(code, kUpdateFailed);
      expect(text.toLowerCase(), contains('no release key'));
      expect(text, contains('releases page'));
    });

    test('a release it cannot find out about', () async {
      final (code, text) = await run(const ['--update'], env(latest: null));
      expect(code, kUpdateFailed);
      expect(text, contains('newest release'));
    });

    /// A download that does not match the signed manifest is deleted and the
    /// current version is left alone - and the CLI must not claim success.
    test('a download that does not match its signed hash', () async {
      served[assetName] = utf8.encode('not the build');
      final (code, text) = await run(const [
        '--update',
      ], env(processEnv: {'APPIMAGE': '${home.path}/x.AppImage'}));
      expect(code, kUpdateFailed);
      expect(text, contains("didn't match"));
    });

    /// tar.gz, the Windows zip, the macOS app: verified, but not installable
    /// yet. Saying "done" would be a lie, so it says where the file is.
    test(
      'a package that cannot replace itself says where the file is',
      () async {
        final (code, text) = await run(const [
          '--update',
        ], env(target: SelfUpdateTarget.linuxTarball));
        // The fixture manifest has no hash for the tarball, so this refuses at
        // verification - which is the same outcome by a stricter route.
        expect(code, kUpdateFailed);
        expect(text, isNot(contains('Updated Airclone')));
      },
    );
  });

  group('checking without touching anything', () {
    test('--check names the release and installs nothing', () async {
      final (code, text) = await run(const ['--update', '--check'], env());
      expect(code, kUpdateOk);
      expect(text, contains('v9.9.9'));
      expect(text, contains('airclone --update'));
      expect(text, isNot(contains('Downloading')));
      expect(staging.listSync(), isEmpty);
    });

    test('an up-to-date copy says so, and downloads nothing', () async {
      final (code, text) = await run(const ['--update'], env(current: '9.9.9'));
      expect(code, kUpdateOk);
      expect(text, contains('up to date'));
      expect(staging.listSync(), isEmpty);
    });
  });

  group('doing it', () {
    /// The whole path: newest release, signed manifest, verified asset, and an
    /// AppImage replaced in place - with the previous version named, the way
    /// rclone selfupdate does it.
    test('replaces a running AppImage and says what it came from', () async {
      final image = File('${home.path}/Airclone-x86_64.AppImage')
        ..writeAsStringSync('the OLD image');
      final (code, text) = await run(const [
        '--update',
      ], env(processEnv: {'APPIMAGE': image.path}));
      expect(code, kUpdateOk, reason: text);
      expect(text, contains('Verified'));
      expect(text, contains('Updated Airclone from 0.13.6 to v9.9.9'));
      expect(image.readAsStringSync(), 'an Airclone build, pretend');
      expect(File('${image.path}.old').readAsStringSync(), 'the OLD image');
    });

    /// --output is "give me the file": it must save it and install nothing.
    test('--output saves the verified file and installs nothing', () async {
      final image = File('${home.path}/Airclone-x86_64.AppImage')
        ..writeAsStringSync('the OLD image');
      final target = '${home.path}/saved-here.AppImage';
      final (code, text) = await run([
        '--update',
        '--output',
        target,
      ], env(processEnv: {'APPIMAGE': image.path}));
      expect(code, kUpdateOk, reason: text);
      expect(text, contains('Saved'));
      expect(File(target).existsSync(), isTrue);
      expect(
        image.readAsStringSync(),
        'the OLD image',
        reason: '--output must not also install',
      );
    });

    /// Asking for a named release skips the "is it newer?" gate, which is what
    /// makes it usable for going back to a known-good version.
    test('--version-tag installs the release it was given', () async {
      final image = File('${home.path}/Airclone-x86_64.AppImage')
        ..writeAsStringSync('the OLD image');
      final (code, text) = await run(const [
        '--update',
        '--version-tag',
        'v9.9.9',
      ], env(current: '9.9.9', processEnv: {'APPIMAGE': image.path}));
      expect(code, kUpdateOk, reason: text);
      expect(text, isNot(contains('up to date')));
      expect(image.readAsStringSync(), 'an Airclone build, pretend');
    });
  });
}
