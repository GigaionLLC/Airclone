// Walks rclone's interactive config machine and records what it asks, so the
// app tests replay a real transcript instead of an imagined one.
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

late final dynamic Function(String, Object) call;

Map<String, dynamic> walk(String type, Map<String, String> answers,
    {int maxSteps = 8}) {
  final steps = <Map<String, dynamic>>[];
  final name = "capture";
  var res = call("config/create", {
    "name": name,
    "type": type,
    "parameters": <String, String>{},
    "opt": {"nonInteractive": true, "obscure": true},
  }) as Map<String, dynamic>;
  steps.add({"call": "create", "result": res});

  for (var i = 0; i < maxSteps; i++) {
    final state = (res["State"] ?? "") as String;
    final option = res["Option"] as Map<String, dynamic>?;
    if (state.isEmpty || option == null) break;
    final optName = (option["Name"] ?? "") as String;
    // Stop before anything that would block on a real network listener.
    if (state.startsWith("*oauth")) break;
    final answer = answers[optName];
    if (answer == null) break;
    res = call("config/create", {
      "name": name,
      "type": type,
      "parameters": <String, String>{},
      "opt": {
        "nonInteractive": true,
        "continue": true,
        "state": state,
        "result": answer,
      },
    }) as Map<String, dynamic>;
    steps.add({"call": "continue", "answered": optName, "with": answer, "result": res});
  }
  call("config/delete", {"name": name});
  return {"type": type, "steps": steps};
}

void main(List<String> args) {
  final lib = DynamicLibrary.open(args[0]);
  lib.lookupFunction<Void Function(), void Function()>("RcloneInitialize")();
  final rpc = lib.lookupFunction<
      RpcResult Function(Pointer<Uint8>, Pointer<Uint8>),
      RpcResult Function(Pointer<Uint8>, Pointer<Uint8>)>("RcloneRPC");
  call = (String m, Object body) {
    final r = rpc(toC(m), toC(jsonEncode(body)));
    final out = fromC(r.output);
    if (out.trim().isEmpty) return <String, dynamic>{};
    return jsonDecode(out);
  };
  final scratch = "${Directory.current.path.replaceAll("\\", "/")}/capture.conf";
  call("config/setpath", {"path": scratch});

  final out = <String, dynamic>{
    "_source": "Captured from rclone v1.75.1 via librclone by "
        "dev/plans/fd2-probe/capture_flow.dart. Walks stop before any state "
        "that would bind the OAuth listener.",
    "rcloneVersion": "v1.75.1",
    "flows": {
      "drive_declines_shared_id":
          walk("drive", {"config_shared_client_id": "false"}),
      "drive_accepts_shared_id":
          walk("drive", {"config_shared_client_id": "true"}),
      "googlephotos_declines_shared_id":
          walk("google photos", {"config_shared_client_id": "false"}),
      "googlecloudstorage": walk("google cloud storage", {}),
      "dropbox": walk("dropbox", {}),
      "onedrive": walk("onedrive", {}),
      "b2_asks_nothing": walk("b2", {}),
      "sftp_asks_nothing": walk("sftp", {}),
    },
  };
  File(args[1]).writeAsStringSync(
      const JsonEncoder.withIndent(" ").convert(out));
  for (final e in (out["flows"] as Map).entries) {
    final steps = (e.value as Map)["steps"] as List;
    stdout.writeln("${e.key}: ${steps.length} step(s)");
    for (final s in steps) {
      final r = (s as Map)["result"] as Map;
      final opt = r["Option"] as Map?;
      stdout.writeln("   state=${r["State"]} option=${opt?["Name"]} "
          "required=${opt?["Required"]} type=${opt?["Type"]}");
    }
  }
}
