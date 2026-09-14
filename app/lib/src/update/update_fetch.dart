/// Downloading an update, and refusing it unless it proves itself.
///
/// THE ORDER MATTERS, and it is the whole design:
///
///   1. fetch the release's `SHA256SUMS` and its `.minisig`;
///   2. verify the SIGNATURE over the manifest, before a single hash in it is
///      believed;
///   3. check the signed comment names the release being installed, so a
///      genuine but OLDER manifest cannot be replayed;
///   4. look up THIS asset's hash BY NAME, because a manifest legitimately
///      carries a hash for every asset and "some hash in the file" would let
///      one platform's build be installed as another's;
///   5. stream the asset to a temporary file, hashing as it goes, and compare.
///
/// A failure at any step deletes what was downloaded and returns a reason. There
/// is no path here that installs something unverified, and no "could not check,
/// carry on".
///
/// The download is streamed rather than held in memory: these files are 100-200
/// MB, and a file manager that needs a spare 200 MB of RAM to update itself is
/// not one anybody should run.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'minisign.dart';
import 'sums.dart';
import 'update_trust.dart';
import 'version_compare.dart';

/// Why an update was refused. Every one of these is a refusal to install; the
/// UI says the same thing for most of them, and the log says which.
enum UpdateRefusal {
  /// This build has no signing key, so nothing could be verified.
  notConfigured,

  /// The manifest, the signature or the asset could not be fetched.
  network,

  /// A file was larger than this has any business downloading.
  tooLarge,

  /// The signature did not verify, or was not signed by a trusted key.
  badSignature,

  /// The signature is good, but for a different release than the one being
  /// installed - a replayed manifest.
  wrongRelease,

  /// The manifest does not mention the file this package needs.
  unknownAsset,

  /// The download does not match the hash the signed manifest gives for it.
  hashMismatch,

  /// Nowhere to put it.
  cannotWrite,
}

/// A download that proved itself: the file, and what it proved.
class VerifiedUpdate {
  const VerifiedUpdate({
    required this.file,
    required this.tag,
    required this.sha256,
    required this.trustedComment,
  });

  final File file;
  final String tag;
  final String sha256;

  /// The signed comment, which named this release.
  final String trustedComment;
}

/// Either a verified file or a reason it was refused.
class UpdateOutcome {
  const UpdateOutcome.verified(VerifiedUpdate this.update)
    : refusal = null,
      detail = null;
  const UpdateOutcome.refused(UpdateRefusal this.refusal, {this.detail})
    : update = null;

  final VerifiedUpdate? update;
  final UpdateRefusal? refusal;

  /// For the diagnostics log - never for a dialog.
  final String? detail;

  bool get ok => update != null;
}

/// Size limits. A server that disagrees is not one to keep reading from: an
/// unbounded download is a way to fill somebody's disk, and these are generous
/// against what a release actually carries (the largest asset is under 200 MB).
const int kManifestMaxBytes = 1024 * 1024;
const int kSignatureMaxBytes = 16 * 1024;
const int kAssetMaxBytes = 512 * 1024 * 1024;

/// Downloads and verifies one release asset.
class UpdateFetcher {
  UpdateFetcher({
    required this.client,
    required this.stagingDir,
    List<MinisignPublicKey>? trustedKeys,
    Uri Function({required String tag, required String asset})? assetUrl,
  }) : trustedKeys = trustedKeys ?? updateTrustedKeys(),
       assetUrl = assetUrl ?? releaseAssetUrl;

  final http.Client client;

  /// Where the partial download lives. Never the install directory: nothing
  /// unverified is written anywhere the app might later run from.
  final Directory stagingDir;

  final List<MinisignPublicKey> trustedKeys;
  final Uri Function({required String tag, required String asset}) assetUrl;

  /// Fetch [assetName] from release [tag] and verify it.
  ///
  /// [currentVersion] is what is running: the release must be strictly newer,
  /// checked again HERE rather than trusted from the caller, because this is
  /// the last point before a file is handed to an installer.
  Future<UpdateOutcome> fetchAndVerify({
    required String tag,
    required String assetName,
    required String currentVersion,
    void Function(int received, int? total)? onProgress,
  }) async {
    if (trustedKeys.isEmpty) {
      return const UpdateOutcome.refused(UpdateRefusal.notConfigured);
    }
    if (!isNewerAppVersion(candidate: tag, current: currentVersion)) {
      return const UpdateOutcome.refused(
        UpdateRefusal.wrongRelease,
        detail: 'not newer than the running version',
      );
    }

    final manifest = await _getText(
      assetUrl(tag: tag, asset: 'SHA256SUMS'),
      kManifestMaxBytes,
    );
    if (manifest.refusal != null) {
      return UpdateOutcome.refused(manifest.refusal!, detail: manifest.detail);
    }
    final signature = await _getText(
      assetUrl(tag: tag, asset: 'SHA256SUMS.minisig'),
      kSignatureMaxBytes,
    );
    if (signature.refusal != null) {
      return UpdateOutcome.refused(
        signature.refusal!,
        detail: signature.detail,
      );
    }

    final verdict = await verifyMinisign(
      payload: utf8.encode(manifest.text!),
      signatureText: signature.text!,
      trusted: trustedKeys,
    );
    if (!verdict.ok) {
      return UpdateOutcome.refused(
        UpdateRefusal.badSignature,
        detail: '${verdict.refusal}',
      );
    }

    // The tag is inside the signed comment, so this is the check that makes a
    // replayed older manifest useless: it is genuinely signed, and it says so.
    if (!verdict.trustedComment!.contains(tag)) {
      return UpdateOutcome.refused(
        UpdateRefusal.wrongRelease,
        detail: 'signed comment "${verdict.trustedComment}" is not about $tag',
      );
    }

    final expected = hashForAsset(manifest.text!, assetName);
    if (expected == null) {
      return const UpdateOutcome.refused(UpdateRefusal.unknownAsset);
    }

    return _download(
      url: assetUrl(tag: tag, asset: assetName),
      assetName: assetName,
      expectedHash: expected,
      tag: tag,
      trustedComment: verdict.trustedComment!,
      onProgress: onProgress,
    );
  }

  Future<UpdateOutcome> _download({
    required Uri url,
    required String assetName,
    required String expectedHash,
    required String tag,
    required String trustedComment,
    void Function(int received, int? total)? onProgress,
  }) async {
    File part;
    IOSink sink;
    try {
      if (!stagingDir.existsSync()) stagingDir.createSync(recursive: true);
      // `.part` until it has proved itself. Nothing ever wears the real name
      // unverified, so a crash mid-download cannot leave something an installer
      // would happily run.
      part = File('${stagingDir.path}${Platform.pathSeparator}$assetName.part');
      if (part.existsSync()) part.deleteSync();
      sink = part.openWrite();
    } catch (e) {
      return UpdateOutcome.refused(UpdateRefusal.cannotWrite, detail: '$e');
    }

    final digest = _DigestSink();
    final hasher = sha256.startChunkedConversion(digest);
    var received = 0;

    try {
      final response = await client.send(http.Request('GET', url));
      if (response.statusCode != 200) {
        await sink.close();
        await _cleanUp(part);
        return UpdateOutcome.refused(
          UpdateRefusal.network,
          detail: 'HTTP ${response.statusCode}',
        );
      }
      final declared = response.contentLength;
      if (declared != null && declared > kAssetMaxBytes) {
        await sink.close();
        await _cleanUp(part);
        return const UpdateOutcome.refused(UpdateRefusal.tooLarge);
      }

      await for (final chunk in response.stream) {
        received += chunk.length;
        // Checked as it arrives, not only against Content-Length: a server can
        // say one thing and send another for as long as anyone keeps reading.
        if (received > kAssetMaxBytes) {
          await sink.close();
          await _cleanUp(part);
          return const UpdateOutcome.refused(UpdateRefusal.tooLarge);
        }
        hasher.add(chunk);
        sink.add(chunk);
        onProgress?.call(received, declared);
      }
      await sink.flush();
      await sink.close();
    } catch (e) {
      try {
        await sink.close();
      } catch (_) {}
      await _cleanUp(part);
      return UpdateOutcome.refused(UpdateRefusal.network, detail: '$e');
    }

    hasher.close();
    final actual = digest.value.toString();
    if (actual != expectedHash.toLowerCase()) {
      await _cleanUp(part);
      return UpdateOutcome.refused(
        UpdateRefusal.hashMismatch,
        detail: 'expected $expectedHash, got $actual',
      );
    }

    try {
      final finalPath = '${stagingDir.path}${Platform.pathSeparator}$assetName';
      final finalFile = File(finalPath);
      if (finalFile.existsSync()) finalFile.deleteSync();
      final renamed = part.renameSync(finalPath);
      return UpdateOutcome.verified(
        VerifiedUpdate(
          file: renamed,
          tag: tag,
          sha256: actual,
          trustedComment: trustedComment,
        ),
      );
    } catch (e) {
      await _cleanUp(part);
      return UpdateOutcome.refused(UpdateRefusal.cannotWrite, detail: '$e');
    }
  }

  Future<_TextFetch> _getText(Uri url, int maxBytes) async {
    try {
      final response = await client.send(http.Request('GET', url));
      if (response.statusCode != 200) {
        return _TextFetch.refused(
          UpdateRefusal.network,
          'HTTP ${response.statusCode} for ${url.path}',
        );
      }
      final bytes = <int>[];
      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
        if (bytes.length > maxBytes) {
          return _TextFetch.refused(
            UpdateRefusal.tooLarge,
            '${url.path} over $maxBytes bytes',
          );
        }
      }
      return _TextFetch.text(utf8.decode(bytes, allowMalformed: true));
    } catch (e) {
      return _TextFetch.refused(UpdateRefusal.network, '$e');
    }
  }

  Future<void> _cleanUp(File part) async {
    try {
      if (part.existsSync()) part.deleteSync();
    } catch (_) {
      // Nothing useful to do: the file is named .part and is never installed.
    }
  }
}

class _TextFetch {
  _TextFetch.text(this.text) : refusal = null, detail = null;
  _TextFetch.refused(this.refusal, this.detail) : text = null;

  final String? text;
  final UpdateRefusal? refusal;
  final String? detail;
}

/// Catches the one digest a chunked SHA-256 produces. `package:convert` has an
/// AccumulatorSink for this, but it is not a direct dependency and four lines
/// are cheaper than adding one.
class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
