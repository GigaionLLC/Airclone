import 'package:airclone/src/webui/webui_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isWebUiInvocation', () {
    test('recognises the flag and its =-joined form', () {
      expect(isWebUiInvocation(['--webui']), isTrue);
      expect(isWebUiInvocation(['--webui=1']), isTrue);
      expect(isWebUiInvocation(['--run-due']), isFalse);
      expect(isWebUiInvocation([]), isFalse);
    });

    test('is not fooled by a flag that merely starts the same', () {
      expect(isWebUiInvocation(['--webui-bind']), isFalse);
      expect(isWebUiInvocation(['--webuix']), isFalse);
    });
  });

  group('defaults', () {
    test('binds loopback when nothing is asked for', () {
      final parsed = parseWebUiArgs(['--webui']);
      expect(parsed.ok, isTrue);
      expect(parsed.options.bindAddress, '127.0.0.1');
      expect(parsed.options.port, kDefaultWebUiPort);
      expect(parsed.options.isLoopback, isTrue);
      expect(parsed.options.isAllInterfaces, isFalse);
    });

    test('the flags are inert without --webui', () {
      final parsed = parseWebUiArgs(['--webui-bind', 'all']);
      expect(parsed.options.enabled, isFalse);
    });
  });

  group('bind address', () {
    test('accepts both spellings of every interface', () {
      expect(resolveBindAddress('all'), '0.0.0.0');
      expect(resolveBindAddress('ALL'), '0.0.0.0');
      expect(resolveBindAddress('0.0.0.0'), '0.0.0.0');
    });

    test('maps localhost to loopback', () {
      expect(resolveBindAddress('localhost'), '127.0.0.1');
    });

    test('accepts IPv4 and IPv6 literals', () {
      expect(resolveBindAddress('192.168.1.10'), '192.168.1.10');
      expect(resolveBindAddress('::1'), '::1');
      expect(resolveBindAddress('fe80::1%eth0'), 'fe80::1%eth0');
    });

    test('refuses hostnames, URLs and host:port', () {
      // A hostname would make "which interface am I exposed on?" unanswerable.
      for (final bad in const [
        'example.com',
        'http://127.0.0.1',
        '127.0.0.1:5799',
        // One colon is never a legal IPv6 literal, and this is the likeliest
        // typo of the lot.
        '1:2',
        'not an address',
        '',
      ]) {
        expect(resolveBindAddress(bad), isNull, reason: bad);
      }
    });

    test('refuses out-of-range and zero-padded octets', () {
      expect(resolveBindAddress('999.1.1.1'), isNull);
      expect(resolveBindAddress('1.1.1'), isNull);
      // "010" could be read as octal by something downstream.
      expect(resolveBindAddress('127.0.0.01'), isNull);
    });

    test('a bad address is an error, never a silent fallback', () {
      // The whole point: an operator who asked for one exposure and got another
      // has been misled, so we refuse to start rather than guess.
      final parsed = parseWebUiArgs(['--webui', '--webui-bind', 'example.com']);
      expect(parsed.ok, isFalse);
      expect(parsed.errors.single, contains('example.com'));
      expect(parsed.options.bindAddress, kDefaultWebUiBind);
    });
  });

  group('port', () {
    test('accepts both flag spellings', () {
      expect(
        parseWebUiArgs(['--webui', '--webui-port', '8080']).options.port,
        8080,
      );
      expect(
        parseWebUiArgs(['--webui', '--webui-port=8080']).options.port,
        8080,
      );
    });

    test('rejects out-of-range and non-numeric ports', () {
      for (final bad in const ['0', '65536', '-1', 'eighty']) {
        final parsed = parseWebUiArgs(['--webui', '--webui-port', bad]);
        expect(parsed.ok, isFalse, reason: bad);
      }
    });
  });

  group('exposure', () {
    test('knows loopback from everything else', () {
      expect(const WebUiOptions(bindAddress: '127.0.0.1').isLoopback, isTrue);
      expect(const WebUiOptions(bindAddress: '127.0.1.1').isLoopback, isTrue);
      expect(const WebUiOptions(bindAddress: '::1').isLoopback, isTrue);
      expect(const WebUiOptions(bindAddress: '0.0.0.0').isLoopback, isFalse);
      expect(
        const WebUiOptions(bindAddress: '192.168.1.10').isLoopback,
        isFalse,
      );
    });

    test('an unrecognised address counts as exposed', () {
      // Err toward warning: a missed warning is worse than a spurious one.
      expect(const WebUiOptions(bindAddress: '10.0.0.5').isLoopback, isFalse);
    });
  });

  group('displayUrl', () {
    test('shows an https URL the operator can actually paste', () {
      // https, not http: the server is TLS-only, and handing someone an
      // http:// URL for a port that speaks TLS produces a blank page or a
      // protocol error rather than a warning they could act on.
      expect(
        const WebUiOptions(port: 5799).displayUrl,
        'https://localhost:5799/',
      );
      // 0.0.0.0 is not reachable as typed, so offer the one address that is.
      expect(
        const WebUiOptions(bindAddress: '0.0.0.0', port: 80).displayUrl,
        'https://localhost:80/',
      );
      expect(
        const WebUiOptions(bindAddress: '192.168.1.10', port: 5799).displayUrl,
        'https://192.168.1.10:5799/',
      );
      // IPv6 literals need brackets in a URL or the port is ambiguous.
      expect(
        const WebUiOptions(bindAddress: 'fd00::5', port: 5799).displayUrl,
        'https://[fd00::5]:5799/',
      );
    });
  });
}
