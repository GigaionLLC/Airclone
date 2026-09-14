import 'dart:convert';
import 'dart:io';

import 'package:airclone/src/update/minisign.dart';
import 'package:airclone/src/update/update_fetch.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Downloading an update, against a server that tries to lie.
///
/// A real HTTP server, a real signature (the fixture generated in Python and
/// cross-checked by the minisign binary in CI) and a real file on disk. What is
/// being tested is the REFUSALS: an update that installs something unverified
/// is worse than no updater at all, so every way of getting a wrong file past
/// this has its own test.
void main() {
  late HttpServer server;
  late Directory staging;
  late String manifest;
  late String signature;
  late MinisignPublicKey key;

  /// The asset the tests download. The signed manifest carries its REAL hash -
  /// dev/update/make-test-fixture.py hashes this very file and signs the result
  /// - so the happy path here is a genuine end-to-end verification, not a
  /// rehearsal of one.
  late List<int> assetBytes;
  late String assetHash;
  const assetName = 'Airclone-x86_64.AppImage';

  /// What the server sends for each path, so a test can swap one out.
  late Map<String, List<int>> served;

  setUp(() async {
    final dir = Directory('test/fixtures/update');
    manifest = File('${dir.path}/SHA256SUMS').readAsStringSync();
    signature = File('${dir.path}/SHA256SUMS.minisig').readAsStringSync();
    key = MinisignPublicKey.parse(
      File('${dir.path}/public_key.txt').readAsStringSync().trim(),
    )!;
    assetBytes = File('${dir.path}/asset.bin').readAsBytesSync();
    assetHash = sha256.convert(assetBytes).toString();
    staging = Directory.systemTemp.createTempSync('airclone-update-test');

    served = {
      'SHA256SUMS': utf8.encode(manifest),
      'SHA256SUMS.minisig': utf8.encode(signature),
      assetName: assetBytes,
    };

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final name = request.uri.pathSegments.last;
      final body = served[name];
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

  UpdateFetcher fetcher({List<MinisignPublicKey>? keys}) => UpdateFetcher(
    client: http.Client(),
    stagingDir: staging,
    trustedKeys: keys ?? [key],
    assetUrl: ({required String tag, required String asset}) =>
        Uri.parse('http://${server.address.host}:${server.port}/$tag/$asset'),
  );

  /// One fetch, against the local server. The fixture manifest is signed, so a
  /// test cannot edit its content and keep it valid - which is the point: to
  /// break something, a test swaps what the SERVER returns, exactly as a
  /// man-in-the-middle would.
  Future<UpdateOutcome> run({
    String tag = 'v9.9.9',
    String asset = assetName,
    String current = '0.13.6',
  }) => fetcher().fetchAndVerify(
    tag: tag,
    assetName: asset,
    currentVersion: current,
  );

  group('what it refuses', () {
    /// The man-in-the-middle case: the manifest and its signature are genuine,
    /// and the bytes are not. Nothing may be installed, and nothing may be left
    /// behind for a later run to find and trust.
    test('an asset that does not match the signed hash', () async {
      served[assetName] = utf8.encode('a different build entirely');
      final outcome = await run();
      expect(outcome.ok, isFalse);
      expect(outcome.refusal, UpdateRefusal.hashMismatch);
      expect(
        staging.listSync(),
        isEmpty,
        reason: 'a refused download must leave nothing on disk',
      );
    });

    /// One byte, at the end, after everything else has matched.
    test('an asset with a single byte appended', () async {
      served[assetName] = [...assetBytes, 0x0a];
      expect((await run()).refusal, UpdateRefusal.hashMismatch);
      expect(staging.listSync(), isEmpty);
    });

    test('a tampered manifest, however good the hash inside it', () async {
      // A hash for an asset the release never had, added to a real manifest.
      // The content is plausible; the signature over it is not.
      served['SHA256SUMS'] = utf8.encode(
        '$manifest$assetHash  airclone-linux-arm64.tar.gz\n',
      );
      final outcome = await run();
      expect(outcome.refusal, UpdateRefusal.badSignature);
      expect(staging.listSync(), isEmpty);
    });

    test('a signature from a key this build does not trust', () async {
      final stranger = MinisignPublicKey.parse(
        base64.encode([
          0x45,
          0x64,
          ...List.filled(8, 9),
          ...List.filled(32, 3),
        ]),
      )!;
      final outcome = await fetcher(keys: [stranger]).fetchAndVerify(
        tag: 'v9.9.9',
        assetName: assetName,
        currentVersion: '0.13.6',
      );
      expect(outcome.refusal, UpdateRefusal.badSignature);
    });

    /// A build with no key must not install anything, and must not even try.
    test('no key at all', () async {
      final outcome = await fetcher(keys: const []).fetchAndVerify(
        tag: 'v9.9.9',
        assetName: assetName,
        currentVersion: '0.13.6',
      );
      expect(outcome.refusal, UpdateRefusal.notConfigured);
    });

    /// THE REPLAY. The signature is genuine and the manifest is untouched - it
    /// is simply for a different release, served by a stale mirror or a cache
    /// that an attacker controls. The tag inside the signed comment is what
    /// catches it.
    test('a genuinely signed manifest for another release', () async {
      final outcome = await run(tag: 'v9.9.10');
      expect(outcome.refusal, UpdateRefusal.wrongRelease);
      expect(outcome.detail, contains('is not about'));
    });

    test('a release that is not newer than what is running', () async {
      final outcome = await run(current: '9.9.9');
      expect(outcome.refusal, UpdateRefusal.wrongRelease);
    });

    /// The manifest carries a hash for every asset in the release, so asking
    /// for a file it does not mention must fail rather than fall back to any
    /// hash that happens to be in there.
    test('an asset the manifest does not mention', () async {
      served['airclone-linux-arm64.tar.gz'] = assetBytes;
      final outcome = await run(asset: 'airclone-linux-arm64.tar.gz');
      expect(outcome.refusal, UpdateRefusal.unknownAsset);
    });

    test('a missing manifest', () async {
      served.remove('SHA256SUMS');
      expect((await run()).refusal, UpdateRefusal.network);
    });

    test('a missing signature', () async {
      served.remove('SHA256SUMS.minisig');
      expect((await run()).refusal, UpdateRefusal.network);
    });

    test('a missing asset', () async {
      served.remove(assetName);
      expect((await run()).refusal, UpdateRefusal.network);
    });

    /// An unbounded download is a way to fill somebody's disk. The cap is
    /// checked as bytes ARRIVE, not only against Content-Length, because a
    /// server can say one thing and send another.
    test('a manifest far larger than any manifest', () async {
      served['SHA256SUMS'] = utf8.encode('x' * (kManifestMaxBytes + 1));
      expect((await run()).refusal, UpdateRefusal.tooLarge);
    });
  });

  group('what it accepts', () {
    test('a signed, matching asset is kept under its real name', () async {
      final outcome = await run();
      expect(outcome.ok, isTrue, reason: 'refused: ${outcome.refusal}');
      final update = outcome.update!;
      expect(update.sha256, assetHash);
      expect(update.tag, 'v9.9.9');
      expect(update.trustedComment, contains('v9.9.9'));
      expect(update.file.path, endsWith(assetName));
      expect(update.file.readAsBytesSync(), assetBytes);
      // Nothing is left half-written: the .part name exists only while a
      // download is unproven.
      expect(
        File(
          '${staging.path}${Platform.pathSeparator}$assetName.part',
        ).existsSync(),
        isFalse,
      );
    });

    test('progress is reported as the bytes arrive', () async {
      var lastReceived = 0;
      final outcome = await fetcher().fetchAndVerify(
        tag: 'v9.9.9',
        assetName: assetName,
        currentVersion: '0.13.6',
        onProgress: (received, total) => lastReceived = received,
      );
      expect(outcome.ok, isTrue);
      expect(lastReceived, assetBytes.length);
    });

    /// A second run over the first one's result must not trip on the file it
    /// left behind.
    test('a repeated download replaces the previous one', () async {
      expect((await run()).ok, isTrue);
      expect((await run()).ok, isTrue);
    });
  });
}
