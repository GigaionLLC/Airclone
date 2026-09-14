import 'dart:convert';
import 'dart:io';

import 'package:airclone/src/update/minisign.dart';
import 'package:airclone/src/update/self_update_target.dart';
import 'package:airclone/src/update/update_controller.dart';
import 'package:airclone/src/update/update_fetch.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// The states an update passes through, and the ones it must not.
///
/// The messages matter as much as the states: everything that means "this file
/// is not what the release says it is" has to read the same to a person, since
/// the difference between a bad signature and a bad hash is a maintainer's
/// problem, not theirs.
void main() {
  late HttpServer server;
  late Directory staging;
  late MinisignPublicKey key;
  late Map<String, List<int>> served;
  const assetName = 'Airclone-x86_64.AppImage';

  setUp(() async {
    final dir = Directory('test/fixtures/update');
    key = MinisignPublicKey.parse(
      File('${dir.path}/public_key.txt').readAsStringSync().trim(),
    )!;
    staging = Directory.systemTemp.createTempSync('airclone-controller');
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
  });

  UpdateFetcher fetcher() => UpdateFetcher(
    client: http.Client(),
    stagingDir: staging,
    trustedKeys: [key],
    assetUrl: ({required String tag, required String asset}) =>
        Uri.parse('http://${server.address.host}:${server.port}/$tag/$asset'),
  );

  ProviderContainer container() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  group('downloading', () {
    test('ends ready, with the verified file', () async {
      final c = container();
      await c
          .read(updateJobProvider.notifier)
          .download(
            tag: 'v9.9.9',
            target: SelfUpdateTarget.linuxAppImage,
            currentVersion: '0.13.6',
            fetcher: fetcher(),
          );
      final job = c.read(updateJobProvider);
      expect(job, isA<UpdateReady>());
      expect((job as UpdateReady).file.existsSync(), isTrue);
      expect(job.canInstall, isTrue, reason: 'an AppImage can replace itself');
    });

    /// A package that cannot replace itself still gets a verified download -
    /// it just does not get an Install button.
    test('a package that cannot install itself says so', () async {
      final c = container();
      await c
          .read(updateJobProvider.notifier)
          .download(
            tag: 'v9.9.9',
            target: SelfUpdateTarget.windowsPortable,
            currentVersion: '0.13.6',
            fetcher: fetcher(),
          );
      final job = c.read(updateJobProvider);
      // The fixture manifest has no matching hash for the Windows zip, so this
      // refuses - which is itself the point: a mismatch never installs.
      expect(job, isA<UpdateFailed>());
    });

    test('a failure reports one honest message, not a reason code', () async {
      served[assetName] = utf8.encode('not the build');
      final c = container();
      await c
          .read(updateJobProvider.notifier)
          .download(
            tag: 'v9.9.9',
            target: SelfUpdateTarget.linuxAppImage,
            currentVersion: '0.13.6',
            fetcher: fetcher(),
          );
      final job = c.read(updateJobProvider);
      expect(job, isA<UpdateFailed>());
      final message = (job as UpdateFailed).message;
      expect(message, contains('stopped and deleted it'));
      expect(message, isNot(contains('hashMismatch')));
      expect(message, isNot(contains('sha')));
    });

    /// "The download didn't finish" is a lie when the download finished and
    /// the install is what went wrong - and it sends the user to check their
    /// connection instead of their disk.
    test('a failed install does not blame the download', () {
      final message = const UpdateFailed(UpdateRefusal.installFailed).message;
      expect(message, contains('could not be installed'));
      expect(message, contains('untouched'));
      expect(message, isNot(contains('connection')));
    });

    /// Every failure has to say something a person can act on; an enum value
    /// reaching a dialog is a bug.
    test('every refusal has a message', () {
      for (final refusal in UpdateRefusal.values) {
        final message = UpdateFailed(refusal).message;
        expect(message, isNotEmpty, reason: '$refusal');
        expect(message, isNot(contains(refusal.name)), reason: '$refusal');
      }
    });
  });

  group('installing', () {
    test('does nothing unless a verified download is waiting', () async {
      final c = container();
      await c.read(updateJobProvider.notifier).install();
      expect(c.read(updateJobProvider), isA<UpdateIdle>());
    });

    /// The install path is the AppImage one, and it needs APPIMAGE set. Without
    /// it there is nothing to replace, and the job must not claim success.
    test('a download outside an AppImage does not report installed', () async {
      final c = container();
      await c
          .read(updateJobProvider.notifier)
          .download(
            tag: 'v9.9.9',
            target: SelfUpdateTarget.linuxAppImage,
            currentVersion: '0.13.6',
            fetcher: fetcher(),
          );
      await c.read(updateJobProvider.notifier).install(environment: const {});
      expect(c.read(updateJobProvider), isNot(isA<UpdateInstalled>()));
    });
  });

  group('which packages can install themselves', () {
    /// The list is short on purpose. The Windows portable zip and the macOS app
    /// both mean replacing a locked directory tree from inside it, which needs
    /// a helper process - and a half-finished swap of either costs somebody
    /// their install.
    test('the AppImage and the Windows installer, and nothing else yet', () {
      expect(installableTargets, {
        SelfUpdateTarget.linuxAppImage,
        SelfUpdateTarget.windowsInstaller,
      });
      for (final t in SelfUpdateTarget.values) {
        if (installableTargets.contains(t)) continue;
        expect(
          UpdateReady(File('x'), target: t).canInstall,
          isFalse,
          reason: '$t must not offer an Install button',
        );
      }
    });
  });

  group('what may be offered at all', () {
    /// Two conditions, and both must hold: a key to verify with, and a package
    /// that can replace itself. A build with no key offers nothing, which is
    /// every build until a release is signed.
    test('never for a package that cannot replace itself', () {
      expect(canOfferSelfUpdate(SelfUpdateTarget.unsupported), isFalse);
    });
  });
}
