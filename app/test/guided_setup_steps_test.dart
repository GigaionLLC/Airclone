/// The curated layer, checked against what rclone actually offers.
///
/// The recipes name rclone options by hand. That is the whole point of them —
/// and the obvious way for them to rot, because a renamed option would leave a
/// field that silently writes nothing. So every name is checked against a real
/// `config/providers` capture from the rclone version this app ships against.
library;

import 'dart:convert';
import 'dart:io';

import 'package:airclone_rc/airclone_rc.dart';
import 'package:airclone/src/state/add_remote_controller.dart';
import 'package:airclone/src/state/remote_setup_recipes.dart';
import 'package:airclone/src/ui/add_remote/guided_steps.dart';
import 'package:flutter_test/flutter_test.dart';

/// `config/providers` from rclone v1.75.1, trimmed to the backends under test.
Map<String, RcloneProvider> loadFixture() {
  final raw = File(
    'test/fixtures/config_flows/provider_options.json',
  ).readAsStringSync();
  final json = jsonDecode(raw) as Map<String, dynamic>;
  final providers = json['providers'] as Map<String, dynamic>;
  return {
    for (final entry in providers.entries)
      entry.key: RcloneProvider.fromJson({
        'Name': entry.key,
        'Description': (entry.value as Map)['Description'],
        'Options': (entry.value as Map)['Options'],
      }),
  };
}

void main() {
  final fixture = loadFixture();

  group('every recipe names options rclone actually has', () {
    for (final recipe in kSetupRecipes.values) {
      test(recipe.type, () {
        final provider = fixture[recipe.type];
        expect(
          provider,
          isNotNull,
          reason: 'the fixture has no ${recipe.type}; regenerate it',
        );
        final names = {for (final o in provider!.options) o.name};
        for (final field in recipe.fields) {
          expect(
            names,
            contains(field.option),
            reason:
                '${recipe.type}.${field.option} does not exist in rclone '
                '1.75.1 — the field would write nothing',
          );
        }
      });
    }
  });

  group('every curated tile names a backend rclone actually has', () {
    for (final choice in kCuratedClouds) {
      test('${choice.id} -> ${choice.type}', () {
        expect(
          fixture.keys,
          contains(choice.type),
          reason:
              'the backend is spelled differently — note that rclone calls '
              'them "google photos" and "google cloud storage", with spaces',
        );
      });
    }
  });

  test('an S3 brand preset names a provider value rclone knows', () {
    // A preset that does not match one of rclone's own `provider` examples
    // would gate every other option to nothing, leaving an empty form.
    final s3 = fixture['s3']!;
    final providerOption = s3.options.firstWhere((o) => o.name == 'provider');
    // The fixture drops Examples to stay small, so check the gating lists that
    // survive on the other options instead — they enumerate the same names.
    final known = <String>{};
    for (final o in s3.options) {
      if (o.provider.isEmpty) continue;
      known.addAll(o.provider.replaceFirst('!', '').split(','));
    }
    expect(providerOption.name, 'provider');
    for (final choice in kCuratedClouds.where((x) => x.type == 's3')) {
      final value = choice.preset['provider'];
      expect(value, isNotNull, reason: '${choice.id} must preset a provider');
      expect(
        known,
        contains(value),
        reason:
            '${choice.id} presets provider=$value, which rclone does not '
            'list — every gated option would disappear',
      );
    }
  });

  group('field kinds', () {
    test('secrets are chosen by us, not inferred from rclone flags', () {
      // rclone marks these `Sensitive`, not `IsPassword` — trusting its flag
      // would paint a live access key on screen.
      final s3 = kSetupRecipes['s3']!;
      final secret = s3.fields.firstWhere(
        (f) => f.option == 'secret_access_key',
      );
      expect(secret.kind, FieldKind.secret);
      final fromRclone = fixture['s3']!.options.firstWhere(
        (o) => o.name == 'secret_access_key',
      );
      expect(fromRclone.isPassword, isFalse, reason: 'this is the trap');
    });

    test('crypt points at another remote, not at free text', () {
      final crypt = kSetupRecipes['crypt']!;
      expect(
        crypt.fields.firstWhere((f) => f.option == 'remote').kind,
        FieldKind.remote,
      );
    });
  });

  group('guidedFields', () {
    test('uses the recipe when there is one', () {
      final state = AddRemoteState(provider: fixture['b2']);
      final fields = guidedFields(state).map((f) => f.$1.option).toList();
      expect(fields, ['account', 'key']);
    });

    test('falls back to rclone standard options when there is none', () {
      final state = AddRemoteState(provider: fixture['pcloud']);
      final fields = guidedFields(state).map((f) => f.$1.option).toList();
      expect(fields, isNotEmpty);
      // Advanced options stay in Advanced.
      for (final name in fields) {
        final o = fixture['pcloud']!.options.firstWhere((x) => x.name == name);
        expect(o.advanced, isFalse);
      }
    });

    test('narrows the generic form by the chosen provider', () {
      // storj has provider-gated options; picking one must not show the other
      // provider's fields.
      final storj = fixture['storj']!;
      final withGating = storj.options.where((o) => o.provider.isNotEmpty);
      expect(withGating, isNotEmpty, reason: 'fixture should have gating here');
      final existing = AddRemoteState(
        provider: storj,
        values: const {'provider': 'existing'},
      );
      final shown = guidedFields(existing).map((f) => f.$1.option).toSet();
      for (final o in withGating) {
        if (o.advanced || o.hide) continue;
        expect(
          shown.contains(o.name),
          matchesProvider(o.provider, 'existing'),
          reason: '${o.name} is gated to "${o.provider}"',
        );
      }
    });

    test('skips a recipe field this rclone build does not have', () {
      final trimmed = RcloneProvider(
        name: 'b2',
        description: '',
        options: const [ProviderOption(name: 'account')],
      );
      final fields = guidedFields(
        AddRemoteState(provider: trimmed),
      ).map((f) => f.$1.option);
      expect(fields, ['account']);
    });
  });

  group('looksSecret', () {
    test('trusts rclone when rclone says so', () {
      expect(
        looksSecret(const ProviderOption(name: 'pass', isPassword: true)),
        isTrue,
      );
      expect(
        looksSecret(const ProviderOption(name: 'host', sensitive: true)),
        isTrue,
      );
    });

    test('does not trust rclone to always say so', () {
      // The real counter-examples: rclone flags client_secret as NEITHER
      // IsPassword nor Sensitive, and the s3 key pair as Sensitive rather than
      // IsPassword. A question that falls through to the generic renderer must
      // not appear in the clear because rclone forgot to mark it.
      for (final name in [
        'client_secret',
        'secret_access_key',
        'access_key_id',
        'config_token',
        'api_key',
        'key',
        'password2',
        'credentials',
      ]) {
        expect(
          looksSecret(ProviderOption(name: name)),
          isTrue,
          reason: '$name would have been typed in the clear',
        );
      }
    });

    test('does not hide ordinary fields', () {
      for (final name in [
        'host',
        'user',
        'port',
        'region',
        'endpoint',
        'url',
      ]) {
        expect(looksSecret(ProviderOption(name: name)), isFalse, reason: name);
      }
    });
  });

  group('usesOAuth', () {
    test('is detected from the options, not a list of names', () {
      expect(usesOAuth(fixture['drive']), isTrue);
      expect(usesOAuth(fixture['dropbox']), isTrue);
      expect(usesOAuth(fixture['b2']), isFalse);
      expect(usesOAuth(fixture['sftp']), isFalse);
      expect(usesOAuth(null), isFalse);
    });
  });

  group('suggestRemoteName', () {
    test('is friendly and unique', () {
      expect(suggestRemoteName('drive', {}), 'gdrive');
      expect(suggestRemoteName('drive', {'gdrive'}), 'gdrive-2');
      expect(suggestRemoteName('drive', {'gdrive', 'gdrive-2'}), 'gdrive-3');
    });

    test('a backend name with a space becomes a usable remote name', () {
      // `google photos` as a remote name would be ambiguous in `remote:path`.
      expect(suggestRemoteName('google photos', {}), 'gphotos');
      expect(suggestRemoteName('google cloud storage', {}), 'gcs');
    });

    test('an unknown backend falls back to its own name, sanitised', () {
      expect(suggestRemoteName('internetarchive', {}), 'internetarchive');
      expect(suggestRemoteName('Weird Name!', {}), 'weird-name');
    });
  });

  group('search', () {
    test('finds a brand that is not a tile', () {
      final hits = kCuratedClouds.where((x) => cloudMatches(x, 'wasabi'));
      expect(hits, hasLength(1));
      expect(hits.single.type, 's3');
      expect(hits.single.preset['provider'], 'Wasabi');
    });

    test('finds a tile by an alias rather than its label', () {
      expect(
        kCuratedClouds.where((x) => cloudMatches(x, 'nextcloud')).single.type,
        'webdav',
      );
      expect(
        kCuratedClouds.where((x) => cloudMatches(x, 'backblaze')).single.type,
        'b2',
      );
    });

    test('an empty query keeps everything', () {
      expect(
        kCuratedClouds.where((x) => cloudMatches(x, '')).length,
        kCuratedClouds.length,
      );
    });
  });

  group('cloudChoiceFor', () {
    test('recognises a brand by its preset', () {
      expect(
        cloudChoiceFor('s3', values: {'provider': 'Cloudflare'})?.id,
        'r2',
      );
      expect(
        cloudChoiceFor('s3', values: {'provider': 'Wasabi'})?.id,
        'wasabi',
      );
    });

    test('has no curated answer for a brand we did not curate', () {
      // Every s3 tile carries a preset, so an s3 remote on some other provider
      // matches none of them. Null is the honest answer: the UI then calls it
      // by rclone's own backend name rather than mislabelling it "Amazon S3".
      expect(cloudChoiceFor('s3', values: {'provider': 'Ceph'}), isNull);
      expect(cloudChoiceFor('internetarchive'), isNull);
    });

    test('a backend with no preset matches on type alone', () {
      expect(cloudChoiceFor('sftp')?.id, 'sftp');
      expect(cloudChoiceFor('b2')?.id, 'b2');
    });
  });
}
