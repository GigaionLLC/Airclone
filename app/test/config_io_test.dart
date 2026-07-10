import 'dart:convert';
import 'dart:typed_data';

import 'package:airclone/src/state/config_io.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exhaustive, pure-function coverage for the config-portability I/O seam: format
/// sniffing (all five shapes), INI round-trips (comments / `=` in value / empty
/// section), config-dump JSON, the AES-256-GCM export envelope (seal/open + wrong
/// passphrase + truncation), dependency closure (crypt→base, alias chain, union
/// upstreams, dangling base), and collision-rename merge planning. No I/O, no
/// engine — every function here is deterministic (bar the envelope's random salt,
/// which round-trips).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('detectConfigFormat', () {
    test('rclone-encrypted magic line', () {
      final bytes = [
        ...utf8.encode('RCLONE_ENCRYPT_V0:'),
        1, 2, 3, 4, // binary tail must not trip a UTF-8 decode
      ];
      expect(detectConfigFormat(bytes), ConfigFormat.rcloneEncrypted);
    });

    test('config dump JSON (leading brace, even after whitespace)', () {
      expect(
        detectConfigFormat(utf8.encode('{"drive":{"type":"drive"}}')),
        ConfigFormat.dumpJson,
      );
      expect(
        detectConfigFormat(utf8.encode('\n  {"x":{}}')),
        ConfigFormat.dumpJson,
      );
    });

    test('plaintext rclone INI via a [section] header', () {
      expect(
        detectConfigFormat(utf8.encode('# a comment\n[drive]\ntype = drive\n')),
        ConfigFormat.rcloneIni,
      );
    });

    test('our envelope magic ACFG2', () async {
      final sealed = await sealConfigEnvelope(
        '[x]\ntype = drive\n',
        'pw',
        kdf: _fastKdf,
      );
      expect(detectConfigFormat(sealed), ConfigFormat.aircloneEnvelope);
    });

    test('unknown: empty, prose without a config shape, and raw binary', () {
      expect(detectConfigFormat(const []), ConfigFormat.unknown);
      expect(
        detectConfigFormat(utf8.encode('just some words here')),
        ConfigFormat.unknown,
      );
      // Invalid UTF-8 that matches none of the magics.
      expect(
        detectConfigFormat(const [0xFF, 0xFE, 0x00, 0x01]),
        ConfigFormat.unknown,
      );
    });

    test('a UTF-8 BOM before INI/JSON is tolerated', () {
      expect(
        detectConfigFormat([..._utf8Bom, ...utf8.encode('[drive]\ntype = s3')]),
        ConfigFormat.rcloneIni,
      );
      expect(
        detectConfigFormat([..._utf8Bom, ...utf8.encode('{"a":{}}')]),
        ConfigFormat.dumpJson,
      );
    });
  });

  group('INI parse/serialize', () {
    test('parses sections, tolerating comments and blank lines', () {
      const ini = '''
; a leading comment
# another comment

[Google-Drive]
type = drive
token = {"access_token":"abc"}

[s3-remote]
type = s3
provider = AWS
''';
      final model = parseIni(ini);
      expect(model.keys, ['Google-Drive', 's3-remote']);
      expect(model['Google-Drive']!['type'], 'drive');
      expect(model['s3-remote']!['provider'], 'AWS');
    });

    test('a value containing = is kept whole (only the first = splits)', () {
      final model = parseIni('[r]\ntoken = a=b=c==\n');
      expect(model['r']!['token'], 'a=b=c==');
    });

    test('an empty [section] is a present-but-empty remote', () {
      final model = parseIni('[empty]\n[filled]\nk = v\n');
      expect(model.keys, ['empty', 'filled']);
      expect(model['empty'], isEmpty);
      expect(model['filled'], {'k': 'v'});
    });

    test('keys before any section header are dropped', () {
      final model = parseIni('orphan = 1\n[r]\nk = v\n');
      expect(model.keys, ['r']);
      expect(model['r'], {'k': 'v'});
    });

    test('round-trips through serialize back to an equal model', () {
      final model = parseIni(
        '[Google-Drive]\ntype = drive\ntoken = x=y==\n\n[s3]\ntype = s3\n',
      );
      final reparsed = parseIni(serializeIni(model));
      expect(reparsed, equals(model));
      // Order is preserved on the way out.
      expect(reparsed.keys.toList(), ['Google-Drive', 's3']);
    });

    test('serialize emits stable, deterministic text', () {
      final model = parseIni('[a]\nk1 = v1\nk2 = v2\n');
      expect(serializeIni(model), serializeIni(model));
      expect(serializeIni(model), '[a]\nk1 = v1\nk2 = v2\n\n');
    });
  });

  group('parseDumpJson', () {
    test('maps the JSON object into the shared model, coercing to strings', () {
      const dump = '{"drive":{"type":"drive","x":1},"s3":{"type":"s3"}}';
      final model = parseDumpJson(dump);
      expect(model.keys, ['drive', 's3']);
      expect(model['drive']!['type'], 'drive');
      // A non-string value is coerced so the model stays uniform with parseIni.
      expect(model['drive']!['x'], '1');
    });

    test('throws FormatException on a non-object body', () {
      expect(() => parseDumpJson('[1,2,3]'), throwsFormatException);
    });
  });

  group('encrypted envelope', () {
    test('seal → open round-trips the plaintext', () async {
      const plain = '[drive]\ntype = drive\ntoken = secret==\n';
      final sealed = await sealConfigEnvelope(
        plain,
        'correct horse',
        kdf: _fastKdf,
      );
      expect(await openConfigEnvelope(sealed, 'correct horse'), plain);
    });

    test(
      'the ACFG2 header records the KDF id + params (self-describing)',
      () async {
        final sealed = await sealConfigEnvelope('x', 'pw', kdf: _fastKdf);
        // magic `ACFG2` | kdfId(1=argon2id) | memory(uint32 LE) | iters | par | …
        expect(utf8.decode(sealed.sublist(0, 5)), 'ACFG2');
        expect(sealed[5], 1); // kdfId: Argon2id
        final mem = ByteData.sublistView(
          Uint8List.fromList(sealed.sublist(6, 10)),
        ).getUint32(0, Endian.little);
        expect(mem, _fastKdf.memory);
        expect(sealed[10], _fastKdf.iterations);
        expect(sealed[11], _fastKdf.parallelism);
      },
    );

    test('two seals of the same input differ (random salt/nonce)', () async {
      final a = await sealConfigEnvelope('x', 'pw', kdf: _fastKdf);
      final b = await sealConfigEnvelope('x', 'pw', kdf: _fastKdf);
      expect(a, isNot(equals(b)));
      // …yet both open to the same plaintext.
      expect(await openConfigEnvelope(a, 'pw'), 'x');
      expect(await openConfigEnvelope(b, 'pw'), 'x');
    });

    test(
      'a wrong passphrase throws WrongPassphrase (GCM tag mismatch)',
      () async {
        final sealed = await sealConfigEnvelope(
          'secret',
          'right',
          kdf: _fastKdf,
        );
        expect(
          () => openConfigEnvelope(sealed, 'wrong'),
          throwsA(isA<WrongPassphrase>()),
        );
      },
    );

    test('non-envelope / bad-magic bytes throw CorruptEnvelope', () async {
      expect(
        () => openConfigEnvelope(utf8.encode('not an envelope at all'), 'pw'),
        throwsA(isA<CorruptEnvelope>()),
      );
    });

    test('an old ACFG1-magic blob is rejected as an unsupported version', () {
      // ACFG1 is a pre-release format with no real exports — recognised as our
      // envelope family but refused, not mis-parsed.
      final oldish = [...utf8.encode('ACFG1'), ...List<int>.filled(40, 0)];
      expect(detectConfigFormat(oldish), ConfigFormat.aircloneEnvelope);
      expect(
        () => openConfigEnvelope(oldish, 'pw'),
        throwsA(isA<CorruptEnvelope>()),
      );
    });

    test('truncated envelope bytes throw CorruptEnvelope', () async {
      final sealed = await sealConfigEnvelope('secret', 'pw', kdf: _fastKdf);
      // Keep only the first few header bytes — shorter than a full header.
      final truncated = sealed.sublist(0, 8);
      expect(
        () => openConfigEnvelope(truncated, 'pw'),
        throwsA(isA<CorruptEnvelope>()),
      );
    });

    test(
      'a flipped ciphertext byte (full length) fails authentication',
      () async {
        final sealed = await sealConfigEnvelope('secret', 'pw', kdf: _fastKdf);
        final tampered = List<int>.from(sealed);
        tampered[tampered.length - 1] ^= 0xFF; // corrupt the MAC/ciphertext
        expect(
          () => openConfigEnvelope(tampered, 'pw'),
          throwsA(isA<WrongPassphrase>()),
        );
      },
    );

    test('a tampered header (params bound as AAD) fails to open', () async {
      final sealed = await sealConfigEnvelope('secret', 'pw', kdf: _fastKdf);
      final tampered = List<int>.from(sealed);
      tampered[10] = tampered[10] + 1; // bump the iterations byte in the header
      // The header is the GCM AAD (and drives derivation), so any header edit
      // means the tag no longer verifies → WrongPassphrase, never a silent open.
      expect(
        () => openConfigEnvelope(tampered, 'pw'),
        throwsA(isA<WrongPassphrase>()),
      );
    });
  });

  group('remotePrefix', () {
    test('extracts the remote name from a name:path reference', () {
      expect(remotePrefix('Google-Drive:Photos/2024'), 'Google-Drive');
      expect(remotePrefix('base:'), 'base');
    });

    test('returns null for local/absolute paths and bare names', () {
      expect(remotePrefix('/home/me/data'), isNull); // no colon
      expect(remotePrefix('./relative/dir'), isNull);
      expect(remotePrefix('plainname'), isNull);
      expect(remotePrefix(':leadingcolon'), isNull);
    });
  });

  group('dependencyClosure', () {
    final model = <String, Map<String, String>>{
      'drive': {'type': 'drive'},
      'drive-crypt': {'type': 'crypt', 'remote': 'drive:vault'},
      'alias-a': {'type': 'alias', 'remote': 'alias-b:'},
      'alias-b': {'type': 'alias', 'remote': 'drive-crypt:'},
      's3': {'type': 's3'},
      'combined': {'type': 'union', 'upstreams': 'drive:one s3:two'},
      // `combine` stores `dir=remote:path` entries — the `dir=` label must be
      // stripped so the BASE (s3/drive) is followed, not `images=s3`.
      'combine-remote': {
        'type': 'combine',
        'upstreams': 'images=s3:imagesbucket files=drive:important',
      },
      'local-crypt': {'type': 'crypt', 'remote': '/mnt/disk/enc'},
    };

    test('a crypt pulls in its base remote', () {
      expect(dependencyClosure(model, {'drive-crypt'}), {
        'drive-crypt',
        'drive',
      });
    });

    test('an alias chain is followed transitively to the leaf', () {
      // alias-a → alias-b → drive-crypt → drive
      expect(dependencyClosure(model, {'alias-a'}), {
        'alias-a',
        'alias-b',
        'drive-crypt',
        'drive',
      });
    });

    test('a union pulls in every upstream base', () {
      expect(dependencyClosure(model, {'combined'}), {
        'combined',
        'drive',
        's3',
      });
    });

    test('a combine strips the dir= label and pulls in every base', () {
      // `images=s3:imagesbucket files=drive:important` → bases s3 + drive.
      expect(dependencyClosure(model, {'combine-remote'}), {
        'combine-remote',
        's3',
        'drive',
      });
    });

    test('a crypt over a local path adds no remote dependency', () {
      expect(dependencyClosure(model, {'local-crypt'}), {'local-crypt'});
    });

    test('a dangling base (referenced but not in the model) is tolerated', () {
      final m = {
        'orphan-crypt': {'type': 'crypt', 'remote': 'missing:dir'},
      };
      // No throw; the missing base is simply not added.
      expect(dependencyClosure(m, {'orphan-crypt'}), {'orphan-crypt'});
    });

    test('selecting several remotes merges their closures', () {
      expect(dependencyClosure(model, {'drive-crypt', 'combined'}), {
        'drive-crypt',
        'drive',
        'combined',
        's3',
      });
    });
  });

  group('planImport', () {
    test('a non-colliding remote imports under its own name', () {
      final plan = planImport(
        {
          'existing': {'type': 's3'},
        },
        {
          'fresh': {'type': 'drive'},
        },
      );
      expect(plan, [
        const ImportDecision(
          name: 'fresh',
          type: 'drive',
          collision: false,
          renamedTo: null,
        ),
      ]);
    });

    test('a collision gets a -imported suffix rename', () {
      final plan = planImport(
        {
          'drive': {'type': 'drive'},
        },
        {
          'drive': {'type': 'drive'},
        },
      );
      expect(plan.single.collision, isTrue);
      expect(plan.single.renamedTo, 'drive-imported');
    });

    test('bumps to -imported-2, -3 when the suffixed name is also taken', () {
      final plan = planImport(
        {
          'drive': {'type': 'drive'},
          'drive-imported': {'type': 'drive'}, // the default rename is taken
        },
        {
          'drive': {'type': 'drive'},
        },
      );
      expect(plan.single.renamedTo, 'drive-imported-2');
    });

    test('a rename never steals another incoming remote\'s name', () {
      // `drive` collides with an existing remote, but the default rename target
      // `drive-imported` is ALSO an incoming remote — so the rename must skip it
      // and bump, or the two would land on the same name.
      final plan = planImport(
        {
          'drive': {'type': 'drive'},
        },
        {
          'drive': {'type': 'drive'}, // collides with existing → needs a rename
          'drive-imported': {
            'type': 's3',
          }, // occupies the default rename target
        },
      );
      expect(plan[0].name, 'drive');
      // `drive-imported` is taken by the other incoming remote → bump past it.
      expect(plan[0].renamedTo, 'drive-imported-2');
      // The incoming `drive-imported` doesn't collide with `existing`, so it
      // imports under its own name — and decision[0] was steered clear of it.
      expect(plan[1].name, 'drive-imported');
      expect(plan[1].collision, isFalse);
      expect(plan[1].renamedTo, isNull);
      // No two decisions resolve to the same final name.
      final finals = plan.map((d) => d.renamedTo ?? d.name).toSet();
      expect(finals.length, plan.length);
    });

    test('preserves incoming order and carries each type through', () {
      final plan = planImport(const {}, {
        'a': {'type': 'drive'},
        'b': {'type': 's3'},
      });
      expect(plan.map((d) => d.name), ['a', 'b']);
      expect(plan.map((d) => d.type), ['drive', 's3']);
    });
  });
}

/// The UTF-8 BOM, re-declared here (the library keeps its copy private) so the
/// sniffing tests can prepend it.
const List<int> _utf8Bom = [0xEF, 0xBB, 0xBF];

/// Deliberately tiny Argon2id params so the envelope round-trips don't pay the
/// production memory-hard cost (m=64 MiB) in the test run. The header records
/// them, so `openConfigEnvelope` re-derives correctly regardless.
const _fastKdf = Argon2Params(memory: 64, iterations: 1, parallelism: 1);
