import 'dart:io';

import 'package:airclone/src/webui/webui_param_guards.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two allowlisted RC methods whose PARAMETERS carried the danger, found by an
/// adversarial pass over the Web UI's authorization surface. Both reachable by
/// the single admin session today; the threat is a stolen session, which is the
/// exact case the allowlist exists for.
///
/// `serve/start`'s every safety rule lived in `ServeController`, which in the
/// Web UI runs IN THE BROWSER. A direct POST to `/api/rc` skipped all of them:
///
///     {method: 'serve/start', params: {type: 'webdav', fs: '/', addr: ':8080'}}
///
/// republished the host's root, unauthenticated, on every interface.
///
/// `operations/copyurl` makes the HOST fetch a URL. From a browser session that
/// reaches cloud instance metadata, the host's own services and its private
/// network, and writes the answer somewhere the session can read.
void main() {
  group('serve/start', () {
    /// The exploit as reported. Must never pass.
    test('the reported payload is refused', () {
      expect(
        serveStartViolation({'type': 'webdav', 'fs': '/', 'addr': ':8080'}),
        isNotNull,
      );
    });

    /// Exactly what ServeController sends for a normal loopback serve. If this
    /// fails, the guard has broken the feature it is protecting.
    test('what the app itself sends on loopback still works', () {
      expect(
        serveStartViolation({
          'type': 'webdav',
          'fs': 'gdrive:Photos',
          'addr': '127.0.0.1:8080',
        }),
        isNull,
      );
    });

    test('and on the network, with a username and password', () {
      expect(
        serveStartViolation({
          'type': 'webdav',
          'fs': 'gdrive:Photos',
          'addr': ':8080',
          'user': 'me',
          'pass': 'long-random-secret',
          'read_only': true,
        }),
        isNull,
      );
    });

    group('beyond loopback needs a password', () {
      for (final addr in [':8080', '0.0.0.0:8080', '192.168.1.5:8080']) {
        test('$addr with no credentials is refused', () {
          expect(
            serveStartViolation({'type': 'http', 'fs': 'x:', 'addr': addr}),
            isNotNull,
          );
        });
      }

      test('a username alone is not enough', () {
        expect(
          serveStartViolation({
            'type': 'ftp',
            'fs': 'x:',
            'addr': ':2121',
            'user': 'me',
          }),
          isNotNull,
        );
      });

      test('an empty password is not a password', () {
        expect(
          serveStartViolation({
            'type': 'sftp',
            'fs': 'x:',
            'addr': ':2022',
            'user': 'me',
            'pass': '',
          }),
          isNotNull,
        );
      });
    });

    /// Stricter than the desktop app on purpose. The app lets you put DLNA on
    /// the network after ticking an acknowledgement; a remote session cannot
    /// prove a human ticked anything.
    group('a protocol with no password cannot leave the machine', () {
      test('DLNA on the network is refused, even with credentials', () {
        expect(
          serveStartViolation({
            'type': 'dlna',
            'fs': 'x:',
            'addr': ':8200',
            'user': 'me',
            'pass': 'secret',
          }),
          contains('Airclone app'),
        );
      });

      test('DLNA on loopback is fine', () {
        expect(
          serveStartViolation({
            'type': 'dlna',
            'fs': 'x:',
            'addr': '127.0.0.1:8200',
          }),
          isNull,
        );
      });
    });

    /// The dangerous parameters are the ones nobody thinks to list, which is
    /// why this is a whitelist rather than a denylist.
    group('only the parameters the app sends', () {
      for (final smuggled in ['_config', '_filter', 'rc_user', 'config_pass']) {
        test('$smuggled is refused', () {
          expect(
            serveStartViolation({
              'type': 'webdav',
              'fs': 'x:',
              'addr': '127.0.0.1:8080',
              smuggled: {'BackupDir': 'C:/'},
            }),
            isNotNull,
          );
        });
      }
    });

    test('a protocol the guard has not been taught is refused', () {
      expect(
        serveStartViolation({
          'type': 'some-future-protocol',
          'fs': 'x:',
          'addr': '127.0.0.1:9000',
        }),
        isNotNull,
      );
    });

    test('an address must be given, not left to a default', () {
      expect(serveStartViolation({'type': 'http', 'fs': 'x:'}), isNotNull);
      expect(
        serveStartViolation({'type': 'http', 'fs': 'x:', 'addr': '  '}),
        isNotNull,
      );
    });
  });

  group('what counts as loopback', () {
    /// The whole bug was treating a missing host as "local". It is the
    /// opposite: an empty host listens on every interface.
    test('an empty host is EVERY interface, not local', () {
      expect(isLoopbackListenAddress(':8080'), isFalse);
    });

    test('loopback spellings', () {
      expect(isLoopbackListenAddress('127.0.0.1:8080'), isTrue);
      expect(isLoopbackListenAddress('127.8.8.8:8080'), isTrue);
      expect(isLoopbackListenAddress('localhost:8080'), isTrue);
      expect(isLoopbackListenAddress('LOCALHOST:8080'), isTrue);
      expect(isLoopbackListenAddress('[::1]:8080'), isTrue);
    });

    test('everything else', () {
      expect(isLoopbackListenAddress('0.0.0.0:8080'), isFalse);
      expect(isLoopbackListenAddress('[::]:8080'), isFalse);
      expect(isLoopbackListenAddress('192.168.1.5:8080'), isFalse);
      expect(isLoopbackListenAddress('nas.local:8080'), isFalse);
    });

    test('a list is local only if every entry is', () {
      expect(isLoopbackListenAddress('127.0.0.1:1,[::1]:1'), isTrue);
      expect(isLoopbackListenAddress('127.0.0.1:1,:1'), isFalse);
    });

    /// A socket path is a host filesystem write; the address is not where that
    /// gets granted.
    test('unix sockets and malformed forms are refused outright', () {
      expect(isLoopbackListenAddress('unix:///tmp/x.sock'), isNull);
      expect(isLoopbackListenAddress('/tmp/x.sock'), isNull);
      expect(isLoopbackListenAddress('8080'), isNull);
      expect(isLoopbackListenAddress('[::1'), isNull);
      expect(isLoopbackListenAddress(''), isNull);
    });
  });

  test('the serve password never reaches the log', () {
    final logged = redactServeParams({
      'type': 'webdav',
      'user': 'me',
      'pass': 'long-random-secret',
    });
    expect(logged['pass'], isNot('long-random-secret'));
    expect(logged['user'], 'me', reason: 'only the secret is removed');
    expect(logged.toString(), isNot(contains('long-random-secret')));
  });

  group('copyurl', () {
    /// Resolves exactly as told, so no test depends on real DNS.
    HostLookup resolvesTo(List<String> ips) =>
        (_) async => [for (final ip in ips) InternetAddress(ip)];

    Future<String?> check(String url, [List<String> ips = const ['1.1.1.1']]) =>
        copyUrlViolation({'url': url}, lookup: resolvesTo(ips));

    test('an ordinary public URL is allowed', () async {
      expect(await check('https://example.com/file.zip'), isNull);
    });

    group('the targets that make this an attack', () {
      test('cloud instance metadata', () async {
        expect(
          await check('http://169.254.169.254/latest/meta-data/'),
          isNotNull,
        );
      });

      test('the host itself, the engine included', () async {
        expect(await check('http://127.0.0.1:5572/'), isNotNull);
        expect(await check('http://[::1]:5572/'), isNotNull);
      });

      test('the network behind the host', () async {
        for (final ip in [
          '10.0.0.1',
          '172.16.0.1',
          '192.168.1.1',
          '100.64.0.1',
        ]) {
          expect(await check('http://$ip/'), isNotNull, reason: ip);
        }
      });

      test('IPv6 private, link-local and unspecified', () async {
        for (final ip in ['fd00::1', 'fe80::1', '::']) {
          expect(await check('http://[$ip]/'), isNotNull, reason: ip);
        }
      });

      /// Loopback wearing an IPv6 address. A check that only asks "is this
      /// IPv4 private" waves it through.
      test('IPv4-mapped IPv6 loopback', () async {
        expect(await check('http://[::ffff:127.0.0.1]/'), isNotNull);
      });
    });

    /// THE REASON the check is on resolved addresses. Every one of these names
    /// a public-looking host and lands on something private.
    group('a name that resolves somewhere private', () {
      test('a public name pointed at loopback', () async {
        expect(
          await check('http://totally-public.example/', ['127.0.0.1']),
          isNotNull,
        );
      });

      test('one bad address among several is enough to refuse', () async {
        expect(
          await check('http://mixed.example/', ['93.184.216.34', '10.0.0.5']),
          isNotNull,
        );
      });

      test(
        'a name that does not resolve is refused, not waved through',
        () async {
          final v = await copyUrlViolation({
            'url': 'http://nope.invalid/',
          }, lookup: (_) async => throw const SocketException('no such host'));
          expect(v, isNotNull);
        },
      );
    });

    test('only http and https', () async {
      for (final url in [
        'file:///etc/passwd',
        'ftp://example.com/x',
        'gopher://127.0.0.1:25/',
        'javascript:alert(1)',
      ]) {
        expect(await check(url), isNotNull, reason: url);
      }
    });

    test('malformed input is refused', () async {
      expect(await copyUrlViolation({}), isNotNull);
      expect(await copyUrlViolation({'url': ''}), isNotNull);
      expect(await copyUrlViolation({'url': 42}), isNotNull);
      expect(await check('http:///no-host'), isNotNull);
    });

    /// Naming the address or range would turn the refusal into the very
    /// internal-network oracle this closes.
    test('the refusal does not say what it found', () async {
      final v = await check('http://10.1.2.3:8443/');
      expect(v, isNot(contains('10.1.2.3')));
      expect(v, isNot(contains('8443')));
      expect(v!.toLowerCase(), isNot(contains('10/8')));
    });

    /// Uses the REAL resolver, because encoded IPv4 forms are resolved by the
    /// operating system and that is exactly what a string check cannot see.
    /// Skipped where the platform resolver will not parse them.
    test('encoded loopback forms, through the real resolver', () async {
      for (final url in ['http://127.1/', 'http://2130706433/']) {
        final host = Uri.parse(url).host;
        List<InternetAddress> resolved;
        try {
          resolved = await InternetAddress.lookup(host);
        } catch (_) {
          continue; // this platform's resolver rejects the form outright
        }
        if (resolved.isEmpty) continue;
        expect(
          await copyUrlViolation({'url': url}),
          isNotNull,
          reason: '$url resolved to $resolved and was not refused',
        );
      }
    });
  });

  group('isNonPublicAddress', () {
    test('public addresses are public', () {
      for (final ip in ['1.1.1.1', '93.184.216.34', '2606:4700:4700::1111']) {
        expect(isNonPublicAddress(InternetAddress(ip)), isFalse, reason: ip);
      }
    });

    test('the boundaries of 172.16/12 are exact', () {
      expect(isNonPublicAddress(InternetAddress('172.15.255.255')), isFalse);
      expect(isNonPublicAddress(InternetAddress('172.16.0.0')), isTrue);
      expect(isNonPublicAddress(InternetAddress('172.31.255.255')), isTrue);
      expect(isNonPublicAddress(InternetAddress('172.32.0.0')), isFalse);
    });

    test('and of 100.64/10', () {
      expect(isNonPublicAddress(InternetAddress('100.63.255.255')), isFalse);
      expect(isNonPublicAddress(InternetAddress('100.64.0.0')), isTrue);
      expect(isNonPublicAddress(InternetAddress('100.127.255.255')), isTrue);
      expect(isNonPublicAddress(InternetAddress('100.128.0.0')), isFalse);
    });
  });

  /// A signed-in session could make the host run a program without ever
  /// calling a denied method: create an sftp remote whose `ssh` option is a
  /// command line, or name one inline in `fs`, then list it. These pin the
  /// refusal AND that everything the app itself sends still passes.
  group('program-running options and on-the-fly remotes', () {
    group('config/create and config/update', () {
      for (final key in [
        'ssh',
        'server_command',
        'bearer_token_command',
        'password_command',
        'some_future_command',
        'SSH',
      ]) {
        test('"$key" is refused', () {
          expect(
            rcParamsViolation('config/create', {
              'name': 'x',
              'type': 'sftp',
              'parameters': {'host': 'example.com', key: 'touch /tmp/pwned'},
            }),
            isNotNull,
          );
          expect(
            rcParamsViolation('config/update', {
              'name': 'x',
              'parameters': {key: 'touch /tmp/pwned'},
            }),
            isNotNull,
          );
        });
      }

      test('parameters sent as a JSON string are read too', () {
        expect(
          rcParamsViolation('config/create', {
            'name': 'x',
            'type': 'webdav',
            'parameters': '{"url":"https://a","bearer_token_command":"id"}',
          }),
          isNotNull,
        );
      });

      test('a wrapper remote cannot point at an on-the-fly sftp', () {
        expect(
          rcParamsViolation('config/create', {
            'name': 'x',
            'type': 'alias',
            'parameters': {'remote': ':sftp,host=h,ssh=id:'},
          }),
          isNotNull,
        );
        expect(
          rcParamsViolation('config/create', {
            'name': 'x',
            'type': 'union',
            'parameters': {'upstreams': 'gdrive:a gdrive,ssh=id:b'},
          }),
          isNotNull,
        );
        expect(
          rcParamsViolation('config/create', {
            'name': 'x',
            'type': 'combine',
            'parameters': {'upstreams': "dir=s,ssh='id -a':"},
          }),
          isNotNull,
        );
      });

      /// What the Add Remote flow sends. If this fails the guard broke the
      /// feature.
      test('an ordinary remote still passes', () {
        expect(
          rcParamsViolation('config/create', {
            'name': 'nas',
            'type': 'sftp',
            'parameters': {
              'host': 'nas.lan',
              'user': 'me',
              'pass': 'p,a:s"s',
              'key_file': '~/.ssh/id_ed25519',
            },
            'opt': {'obscure': true, 'nonInteractive': true},
          }),
          isNull,
        );
        expect(
          rcParamsViolation('config/create', {
            'name': 'secret',
            'type': 'crypt',
            'parameters': {'remote': 'gdrive:My Files/vault'},
          }),
          isNull,
        );
        expect(
          rcParamsViolation('config/create', {
            'name': 'u',
            'type': 'union',
            'parameters': {'upstreams': 'a:x b:y:ro'},
          }),
          isNull,
        );
        expect(
          rcParamsViolation('config/create', {
            'name': 'here',
            'type': 'local',
            'parameters': <String, dynamic>{},
          }),
          isNull,
        );
      });
    });

    group('global options on any method', () {
      test('in a _config block', () {
        for (final key in [
          'MetadataMapper',
          'metadata_mapper',
          'PasswordCommand',
        ]) {
          expect(
            rcParamsViolation('sync/copy', {
              'srcFs': 'a:',
              'dstFs': 'b:',
              '_config': {key: 'id'},
            }),
            isNotNull,
            reason: key,
          );
        }
      });

      test('as a flat top-level parameter', () {
        expect(
          rcParamsViolation('operations/list', {
            'fs': 'a:',
            'remote': '',
            'metadata_mapper': 'id',
          }),
          isNotNull,
        );
      });

      test('a name_transform that runs a command', () {
        expect(
          rcParamsViolation('sync/copy', {
            'srcFs': 'a:',
            'dstFs': 'b:',
            '_config': {
              'NameTransform': ['command=/bin/id'],
            },
          }),
          isNotNull,
        );
        expect(
          rcParamsViolation('sync/copy', {
            'srcFs': 'a:',
            'dstFs': 'b:',
            '_config': {
              'NameTransform': ['nfc'],
            },
          }),
          isNull,
        );
      });

      /// The transfer options the app itself puts in _config.
      test('the options the app sends still pass', () {
        expect(
          rcParamsViolation('sync/sync', {
            'srcFs': 'a:',
            'dstFs': 'b:',
            '_async': true,
            '_config': {
              'IgnoreExisting': true,
              'Transfers': 4,
              'MaxDelete': 10,
              'Checksum': true,
            },
            '_filter': {
              'IncludeRule': ['*.jpg'],
            },
          }),
          isNull,
        );
      });
    });

    group('fs values', () {
      for (final bad in [
        ':sftp,host=h,ssh=id:',
        ':sftp:',
        ':webdav,url=http://x:',
        'gdrive,ssh=id:',
        "nas,ssh='id -a':/",
        'nas,server_command=x:',
        ':local,copy_links=true,ssh=x:/',
      ]) {
        test('"$bad" is refused', () {
          expect(fsValueViolation(bad), isNotNull);
          expect(
            rcParamsViolation('operations/list', {'fs': bad, 'remote': ''}),
            isNotNull,
          );
        });
      }

      test('the JSON-object form of fs is refused', () {
        expect(
          rcParamsViolation('operations/list', {
            'fs': {'type': 'sftp', 'ssh': 'id', '_root': '/'},
            'remote': '',
          }),
          isNotNull,
        );
      });

      test('srcFs, dstFs and bisync paths are checked too', () {
        for (final key in ['srcFs', 'dstFs', 'path1', 'path2']) {
          expect(
            rcParamsViolation('sync/copy', {key: ':sftp:'}),
            isNotNull,
            reason: key,
          );
        }
      });

      /// Every shape the app itself sends. `listFsFor` puts copy_links on
      /// local listings, in both of these forms.
      for (final good in [
        'gdrive:',
        'gdrive:Photos/2024',
        'My Drive:a,b:c',
        '/',
        '/home/me/a,b:c',
        'C:/',
        r'C:\Users\me',
        ':local,copy_links=true:C:/',
        ':local,copy_links=true:/',
        ':local:/home',
        'mylocal,copy_links=true:docs',
      ]) {
        test('"$good" passes', () {
          expect(fsValueViolation(good), isNull);
        });
      }

      test('remote is a path, not a remote, and is not inspected', () {
        expect(
          rcParamsViolation('operations/list', {
            'fs': 'gdrive:',
            'remote': 'weird,name:with colon',
          }),
          isNull,
        );
      });
    });
  });
}
