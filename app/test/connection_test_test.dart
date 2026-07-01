import 'package:airclone/src/rclone/models/remote.dart';
import 'package:airclone/src/rclone/rclone_client.dart';
import 'package:airclone/src/ui/connection_test_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drives operations/about and operations/list responses per test.
class _FakeClient implements RcloneClient {
  _FakeClient({this.aboutThrows = false, this.listThrows = false, this.about});
  final bool aboutThrows;
  final bool listThrows;
  final Map<String, dynamic>? about;
  final calls = <String>[];

  @override
  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    calls.add(method);
    if (method == 'operations/about') {
      if (aboutThrows) throw RcloneException('operations/about', 'no about');
      return about ?? const {};
    }
    if (method == 'operations/list') {
      if (listThrows) {
        throw RcloneException('operations/list', 'permission denied');
      }
      return const {'list': []};
    }
    return const {};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _r = Remote(name: 'gd', type: 'drive', fs: 'gd:');

void main() {
  test('about with free/total → reachable with usage', () async {
    final res = await testRemoteConnection(
      _FakeClient(about: const {'free': 1024, 'total': 4096}),
      _r,
    );
    expect(res.ok, isTrue);
    expect(res.message, contains('free of'));
  });

  test('about without usage numbers → reachable (no usage)', () async {
    final res = await testRemoteConnection(_FakeClient(about: const {}), _r);
    expect(res.ok, isTrue);
    expect(res.message, 'Reachable.');
  });

  test('about unsupported → falls back to a root list', () async {
    final client = _FakeClient(aboutThrows: true);
    final res = await testRemoteConnection(client, _r);
    expect(res.ok, isTrue);
    expect(client.calls, ['operations/about', 'operations/list']);
    expect(res.message, contains('no usage info'));
  });

  test('about + list both fail → surfaces the real error', () async {
    final res = await testRemoteConnection(
      _FakeClient(aboutThrows: true, listThrows: true),
      _r,
    );
    expect(res.ok, isFalse);
    expect(res.message, 'permission denied');
  });
}
