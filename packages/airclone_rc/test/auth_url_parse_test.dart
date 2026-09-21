import 'package:airclone_rc/airclone_rc.dart';
import 'package:test/test.dart';

void main() {
  group('parseAuthUrl', () {
    const state = 'RCoGx_8peU6h6527-4XrcA';
    const url = 'http://127.0.0.1:53682/auth?state=$state';

    test('reads all three wordings rclone uses', () {
      // Captured from rclone 1.75.1 and lib/oauthutil/oauthutil.go.
      for (final line in [
        '2026/09/20 22:25:33 NOTICE: Please go to the following link: $url',
        '2026/09/20 22:25:33 NOTICE: If your browser does not open '
            'automatically go to the following link: $url',
        '2026/09/20 22:25:33 ERROR : Failed to open browser automatically '
            '(exec: "xdg-open": not found) - please go to the following '
            'link: $url',
      ]) {
        expect(parseAuthUrl(line)?.toString(), url, reason: line);
      }
    });

    test('a line with no url yields nothing', () {
      expect(parseAuthUrl('NOTICE: Waiting for code...'), isNull);
      expect(parseAuthUrl(''), isNull);
    });

    test('keeps the state, which is what the listener matches on', () {
      expect(parseAuthUrl('go to $url')!.queryParameters['state'], state);
    });

    test('trailing sentence punctuation is not part of the url', () {
      expect(parseAuthUrl('link: $url.')?.toString(), url);
      expect(parseAuthUrl('link: <$url>')?.toString(), url);
      expect(parseAuthUrl('link: "$url"')?.toString(), url);
    });

    // The security cases. What this returns is handed to the platform URL
    // launcher, and engine output is not a trusted channel: rclone echoes back
    // remote names and server error text at high verbosity, so a line reaching
    // here can contain anything a remote chose to put in it.
    group('refuses anything that is not rclone own loopback listener', () {
      const bad = [
        // Another host entirely.
        'go to http://evil.example:53682/auth?state=x',
        // Right host, wrong port - not the listener rclone bound.
        'go to http://127.0.0.1:8080/auth?state=x',
        // Right host and port, wrong path.
        'go to http://127.0.0.1:53682/evil?state=x',
        // https is not what rclone builds, and accepting it widens the surface
        // for no gain.
        'go to https://127.0.0.1:53682/auth?state=x',
        // A host that merely starts the same way.
        'go to http://127.0.0.1.evil.example:53682/auth?state=x',
        // No state means no flow is waiting on it.
        'go to http://127.0.0.1:53682/auth',
        'go to http://127.0.0.1:53682/auth?state=',
      ];
      for (final line in bad) {
        test(line, () => expect(parseAuthUrl(line), isNull));
      }
    });

    test('credentials cannot be smuggled in front of the host', () {
      // The search is anchored on the whole prefix, so userinfo before the
      // host never produces a match in the first place.
      expect(
        parseAuthUrl('go to http://user:pw@127.0.0.1:53682/auth?state=x'),
        isNull,
      );
    });

    test('an absurdly long line is not scanned', () {
      expect(parseAuthUrl('${'x' * 5000} $url'), isNull);
    });

    test('a line carrying rc credentials yields nothing to echo', () {
      // At -vv rclone dumps request headers. The parser must find no URL here,
      // and it returns a Uri or null - never the line.
      const dump =
          'DEBUG : HTTP REQUEST (req 0xc000123456)\r\n'
          'Authorization: Basic YWlyY2xvbmU6c3VwZXJzZWNyZXQ=';
      expect(parseAuthUrl(dump), isNull);
    });
  });

  group('matchesProvider', () {
    // rclone's own test table, fs/backend_config_test.go.
    const cases = <(String, String, bool)>[
      ('', '', true),
      ('one', 'one', true),
      ('one,two', 'two', true),
      ('one,two,three', 'two', true),
      ('one', 'on', false),
      ('one,two,three', 'tw', false),
      ('!one,two,three', 'two', false),
      ('!one,two,three', 'four', true),
    ];
    for (final (config, provider, want) in cases) {
      test('"$config" vs "$provider" -> $want', () {
        expect(matchesProvider(config, provider), want);
      });
    }

    test('a blank chosen provider keeps every option', () {
      expect(matchesProvider('AWS', ''), isTrue);
    });
  });

  group('RcloneProvider.optionsFor', () {
    final p = RcloneProvider(
      name: 's3',
      description: 'Amazon S3 Compliant Storage Providers',
      options: const [
        ProviderOption(name: 'provider'),
        ProviderOption(name: 'region', provider: 'AWS'),
        ProviderOption(name: 'endpoint', provider: '!AWS'),
      ],
    );

    test('narrows to the chosen provider', () {
      expect(
        p.optionsFor('AWS').map((o) => o.name),
        containsAll(<String>['provider', 'region']),
      );
      expect(
        p.optionsFor('AWS').map((o) => o.name),
        isNot(contains('endpoint')),
      );
    });

    test('a negated list keeps the option for everyone else', () {
      expect(p.optionsFor('Wasabi').map((o) => o.name), contains('endpoint'));
      expect(
        p.optionsFor('Wasabi').map((o) => o.name),
        isNot(contains('region')),
      );
    });
  });
}
