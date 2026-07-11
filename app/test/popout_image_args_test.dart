import 'dart:convert';

import 'package:airclone/src/ui/popout_image_args.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pure coverage for the desktop pop-out image viewer's data plumbing: the
/// JSON payload that rides on `desktop_multi_window`'s
/// WindowConfiguration.arguments (encode/decode + tolerance) and the desktop-
/// only platform gate. No window/engine/channel is involved — the multi-window
/// runtime can't be widget-tested in the harness and is verified end-to-end.
void main() {
  const entries = [
    PopoutImageEntry(url: 'http://127.0.0.1:5000/[fs]/a.png', name: 'a.png'),
    PopoutImageEntry(url: 'http://127.0.0.1:5000/[fs]/b.jpg', name: 'b.jpg'),
    PopoutImageEntry(url: 'http://127.0.0.1:5000/[fs]/c.gif', name: 'c.gif'),
  ];

  group('PopoutImageArgs round-trip', () {
    test('encode -> tryDecode preserves every field', () {
      const args = PopoutImageArgs(
        authorization: 'Basic YWlyY2xvbmU6dG9rZW4=',
        images: entries,
        index: 2,
      );
      final decoded = PopoutImageArgs.tryDecode(args.encode());
      expect(decoded, equals(args));
      expect(decoded!.initialName, 'c.gif');
    });

    test('toJson -> fromJson preserves every field', () {
      const args = PopoutImageArgs(
        authorization: 'Basic zzz',
        images: entries,
        index: 1,
      );
      expect(PopoutImageArgs.fromJson(args.toJson()), equals(args));
    });

    test('a single-image pop-out round-trips too', () {
      const args = PopoutImageArgs(
        authorization: 'Basic one',
        images: [PopoutImageEntry(url: 'http://x/one.png', name: 'one.png')],
      );
      expect(PopoutImageArgs.tryDecode(args.encode()), equals(args));
    });
  });

  group('PopoutImageArgs.fromJson tolerance', () {
    test('tolerates a MISSING sibling list via flat url + name', () {
      final args = PopoutImageArgs.fromJson({
        'authorization': 'Basic k',
        'url': 'http://127.0.0.1/only.png',
        'name': 'only.png',
      });
      expect(args.images, hasLength(1));
      expect(args.images.single.url, 'http://127.0.0.1/only.png');
      expect(args.images.single.name, 'only.png');
      expect(args.index, 0);
    });

    test('accepts "title" as the flat-shape label alias', () {
      final args = PopoutImageArgs.fromJson({
        'url': 'http://127.0.0.1/t.png',
        'title': 'titled.png',
      });
      expect(args.images.single.name, 'titled.png');
    });

    test('missing authorization defaults to empty', () {
      final args = PopoutImageArgs.fromJson({
        'images': [
          {'url': 'http://x/a.png', 'name': 'a.png'},
        ],
      });
      expect(args.authorization, isEmpty);
    });

    test('an out-of-range index is clamped into the list', () {
      final args = PopoutImageArgs.fromJson({
        'authorization': '',
        'index': 99,
        'images': [
          {'url': 'http://x/a.png', 'name': 'a.png'},
          {'url': 'http://x/b.png', 'name': 'b.png'},
        ],
      });
      expect(args.index, 1);
    });
  });

  group('PopoutImageArgs.tryDecode rejects non-pop-out input', () {
    test('empty string (the PRIMARY window) -> null', () {
      expect(PopoutImageArgs.tryDecode(''), isNull);
    });

    test('blank/whitespace -> null', () {
      expect(PopoutImageArgs.tryDecode('   '), isNull);
    });

    test('malformed JSON -> null', () {
      expect(PopoutImageArgs.tryDecode('{not json'), isNull);
    });

    test('valid JSON that is not an object -> null', () {
      expect(PopoutImageArgs.tryDecode('[1,2,3]'), isNull);
    });

    test('an object with no resolvable image -> null', () {
      expect(
        PopoutImageArgs.tryDecode(jsonEncode({'authorization': 'x'})),
        isNull,
      );
    });
  });

  group('isPopoutSupportedOn (desktop-only gate)', () {
    test('true on desktop platforms', () {
      expect(isPopoutSupportedOn(TargetPlatform.windows), isTrue);
      expect(isPopoutSupportedOn(TargetPlatform.macOS), isTrue);
      expect(isPopoutSupportedOn(TargetPlatform.linux), isTrue);
    });

    test('false on mobile / other platforms', () {
      expect(isPopoutSupportedOn(TargetPlatform.android), isFalse);
      expect(isPopoutSupportedOn(TargetPlatform.iOS), isFalse);
      expect(isPopoutSupportedOn(TargetPlatform.fuchsia), isFalse);
    });
  });
}
