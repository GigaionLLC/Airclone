import 'dart:convert';

import 'package:flutter/foundation.dart';

/// One image a pop-out window can show: its authenticated loopback [url] (served
/// by the rcd `--rc-serve` file server) plus a display [name]. The Basic-auth
/// header is shared across siblings and lives on [PopoutImageArgs.authorization]
/// (one rcd session issues a single token), not here.
@immutable
class PopoutImageEntry {
  const PopoutImageEntry({required this.url, required this.name});

  final String url;
  final String name;

  Map<String, dynamic> toJson() => {'url': url, 'name': name};

  factory PopoutImageEntry.fromJson(Map<String, dynamic> json) =>
      PopoutImageEntry(
        url: (json['url'] ?? '') as String,
        name: (json['name'] ?? '') as String,
      );

  @override
  bool operator ==(Object other) =>
      other is PopoutImageEntry && other.url == url && other.name == name;

  @override
  int get hashCode => Object.hash(url, name);

  @override
  String toString() => 'PopoutImageEntry(url: $url, name: $name)';
}

/// The window-creation payload for the desktop pop-out image viewer.
///
/// Ferried as a JSON string through `desktop_multi_window`
/// (`WindowConfiguration.arguments` on creation ->
/// `WindowController.fromCurrentEngine().arguments` in the new engine). The
/// pop-out runs a SEPARATE FlutterEngine with no Riverpod/engine access, so
/// everything it needs to render — the object URL(s) + the auth header — is
/// computed in the main window and passed in here.
///
/// [images] is the (>= 1) set of sibling images the pop-out can page through and
/// [index] is the one shown first, so a single pop-out behaves like Quick Look:
/// prev/next across the folder's images, but each in its own OS window.
@immutable
class PopoutImageArgs {
  const PopoutImageArgs({
    required this.authorization,
    required this.images,
    this.index = 0,
  });

  /// The `Authorization` header value (rcd per-session Basic token) sent with
  /// every image request. Empty when objects are exposed unauthenticated.
  final String authorization;

  /// The sibling images in listing order (always at least one after decode).
  final List<PopoutImageEntry> images;

  /// Index into [images] of the image to show first (kept in range on decode).
  final int index;

  /// Display name of the initially-shown image (used as the OS window title).
  String get initialName =>
      (index >= 0 && index < images.length) ? images[index].name : '';

  Map<String, dynamic> toJson() => {
    'authorization': authorization,
    'index': index,
    'images': [for (final e in images) e.toJson()],
  };

  /// Parses a pop-out payload, TOLERATING a missing sibling list: a minimal
  /// `{url, name/title, authorization}` (no `images` key) still yields a
  /// single-image pop-out. [index] is clamped so a stale/out-of-range value can
  /// never crash the new engine.
  factory PopoutImageArgs.fromJson(Map<String, dynamic> json) {
    final images = <PopoutImageEntry>[];
    final raw = json['images'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          images.add(PopoutImageEntry.fromJson(e.cast<String, dynamic>()));
        }
      }
    }
    // Fallback: no sibling list -> build one entry from the flat top-level
    // fields (accepts either `name` or `title` for the label).
    if (images.isEmpty) {
      final url = (json['url'] ?? '') as String;
      if (url.isNotEmpty) {
        images.add(
          PopoutImageEntry(
            url: url,
            name: (json['name'] ?? json['title'] ?? '') as String,
          ),
        );
      }
    }
    final rawIndex = (json['index'] as num?)?.toInt() ?? 0;
    return PopoutImageArgs(
      authorization: (json['authorization'] ?? '') as String,
      images: images,
      index: images.isEmpty ? 0 : rawIndex.clamp(0, images.length - 1),
    );
  }

  /// Encodes to the compact JSON string handed to
  /// `WindowConfiguration.arguments`.
  String encode() => jsonEncode(toJson());

  /// Inverse of [encode]. Returns null for empty/blank/malformed input, or when
  /// the payload carries no images — e.g. the PRIMARY window, whose arguments
  /// are empty, so main() falls through to a normal launch rather than a pop-out.
  static PopoutImageArgs? tryDecode(String raw) {
    if (raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final args = PopoutImageArgs.fromJson(decoded.cast<String, dynamic>());
      return args.images.isEmpty ? null : args;
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PopoutImageArgs &&
      other.authorization == authorization &&
      other.index == index &&
      listEquals(other.images, images);

  @override
  int get hashCode => Object.hash(authorization, index, Object.hashAll(images));

  @override
  String toString() =>
      'PopoutImageArgs(images: ${images.length}, index: $index)';
}

/// Whether the desktop pop-out (a separate native OS window) is available on
/// [platform]. Desktop-only — mobile keeps the in-app Quick Look overlay.
///
/// Pure so the gate is unit-testable without a platform channel: the UI passes
/// `Theme.of(context).platform`, while main()'s pre-`runApp` dispatch uses
/// `dart:io` Platform (there is no BuildContext yet).
bool isPopoutSupportedOn(TargetPlatform platform) =>
    platform == TargetPlatform.windows ||
    platform == TargetPlatform.macOS ||
    platform == TargetPlatform.linux;
