// Does rclone 1.75.1 expose the OAuth URL and a cancel as first-class RC methods?
// If so, the whole stderr-capture subsystem is unnecessary.
import "dart:convert";
import "dart:ffi";
import "dart:io";

final DynamicLibrary crt = DynamicLibrary.open("ucrtbase.dll");
final Pointer<Uint8> Function(int) cMalloc = crt.lookupFunction<
    Pointer<Uint8> Function(IntPtr), Pointer<Uint8> Function(int)>("malloc");

final class RpcResult extends Struct {
  external Pointer<Uint8> output;
  @Int32()
  external int status;
}

Pointer<Uint8> toC(String s) {
  final b = utf8.encode(s);
  final p = cMalloc(b.length + 1);
  for (var i = 0; i < b.length; i++) {
    p[i] = b[i];
  }
  p[b.length] = 0;
  return p;
}

String fromC(Pointer<Uint8> p) {
  if (p == nullptr) return "";
  var n = 0;
  while (p[n] != 0) {
    n++;
  }
  return utf8.decode(p.asTypedList(n), allowMalformed: true);
}

Future<void> main(List<String> args) async {
  final lib = DynamicLibrary.open(args[0]);
  lib.lookupFunction<Void Function(), void Function()>("RcloneInitialize")();
  final rpc = lib.lookupFunction<
      RpcResult Function(Pointer<Uint8>, Pointer<Uint8>),
      RpcResult Function(Pointer<Uint8>, Pointer<Uint8>)>("RcloneRPC");

  (int, String) call(String m, Object body) {
    final r = rpc(toC(m), toC(body is String ? body : jsonEncode(body)));
    return (r.status, fromC(r.output));
  }

  final scratch = "${Directory.current.path.replaceAll("\\", "/")}/probe2.conf";
  call("config/setpath", {"path": scratch});

  // Is the method even registered?
  final listed = call("rc/list", {});
  for (final m in ["config/oauthstatus", "config/oauthstop"]) {
    stdout.writeln("[probe] rc/list contains $m: ${listed.$2.contains(m)}");
  }

  final before = call("config/oauthstatus", {});
  stdout.writeln("[probe] status before any flow: ${before.$1} ${before.$2.replaceAll("\n", " ")}");

  final create = call("config/create", {
    "name": "oauthprobe",
    "type": "drive",
    "parameters": {
      "config_shared_client_id": "true",
      "config_is_local": "true",
      "config_auth_no_browser": "true",
    },
    "opt": {"nonInteractive": true, "obscure": true},
    "_async": true,
  });
  stdout.writeln("[probe] config/create -> ${create.$1} ${create.$2.replaceAll("\n", " ")}");
  final jobid = (jsonDecode(create.$2) as Map)["jobid"];

  String? url;
  for (var i = 0; i < 50; i++) {
    final s = call("config/oauthstatus", {});
    final m = jsonDecode(s.$2) as Map<String, dynamic>;
    if (m["status"] == "running") {
      url = m["authUrl"] as String?;
      stdout.writeln("[probe] oauthstatus RUNNING after ${i * 200} ms");
      stdout.writeln("[probe] authUrl = $url");
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  if (url == null) {
    stdout.writeln("[probe] RESULT: FAIL - oauthstatus never reported running");
    exit(1);
  }

  // Is the listener actually up on that URL?
  try {
    final sock = await Socket.connect("127.0.0.1", 53682,
        timeout: const Duration(seconds: 2));
    stdout.writeln("[probe] port 53682 is LISTENING");
    await sock.close();
  } catch (e) {
    stdout.writeln("[probe] port 53682 not reachable: $e");
  }

  final stop = call("config/oauthstop", {});
  stdout.writeln("[probe] config/oauthstop -> ${stop.$1} ${stop.$2.replaceAll("\n", " ")}");

  for (var i = 0; i < 25; i++) {
    final js = call("job/status", {"jobid": jobid});
    final m = jsonDecode(js.$2) as Map<String, dynamic>;
    if (m["finished"] == true) {
      stdout.writeln("[probe] job finished after stop, ${i * 200} ms");
      stdout.writeln("[probe] job error  = ${m["error"]}");
      stdout.writeln("[probe] job output = ${jsonEncode(m["output"])}");
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  final after = call("config/oauthstatus", {});
  stdout.writeln("[probe] status after stop: ${after.$2.replaceAll("\n", " ")}");

  try {
    final s2 = await Socket.connect("127.0.0.1", 53682,
        timeout: const Duration(seconds: 1));
    stdout.writeln("[probe] port STILL listening after stop (bad)");
    await s2.close();
  } catch (_) {
    stdout.writeln("[probe] port 53682 released after stop (good)");
  }

  final stopAgain = call("config/oauthstop", {});
  stdout.writeln("[probe] oauthstop when idle -> ${stopAgain.$1} ${stopAgain.$2.replaceAll("\n", " ")}");
  stdout.writeln("[probe] RESULT: PASS");
  exit(0);
}
