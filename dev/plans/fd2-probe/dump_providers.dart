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

void main(List<String> args) {
  final lib = DynamicLibrary.open(args[0]);
  lib.lookupFunction<Void Function(), void Function()>("RcloneInitialize")();
  final rpc = lib.lookupFunction<
      RpcResult Function(Pointer<Uint8>, Pointer<Uint8>),
      RpcResult Function(Pointer<Uint8>, Pointer<Uint8>)>("RcloneRPC");
  final r = rpc(toC("config/providers"), toC("{}"));
  final out = fromC(r.output);
  File(args[1]).writeAsStringSync(out);
  final providers = (jsonDecode(out) as Map)["providers"] as List;
  stdout.writeln("backends: ${providers.length}");
  for (final want in ["s3", "b2", "sftp", "webdav", "ftp", "smb", "azureblob", "crypt"]) {
    final p = providers.firstWhere((p) => (p as Map)["Name"] == want) as Map;
    final opts = (p["Options"] as List).cast<Map>();
    final std = opts.where((o) =>
        (o["Advanced"] != true) && (((o["Hide"] ?? 0) as num) == 0));
    stdout.writeln("");
    stdout.writeln("== $want (${opts.length} options, ${std.length} standard)");
    for (final o in std) {
      final req = o["Required"] == true ? " REQUIRED" : "";
      final pw = o["IsPassword"] == true ? " PASSWORD" : "";
      final sens = o["Sensitive"] == true ? " SENSITIVE" : "";
      final prov = (o["Provider"] ?? "") == "" ? "" : " provider=${o["Provider"]}";
      final ex = (o["Examples"] as List?)?.length ?? 0;
      stdout.writeln("   ${o["Name"]}  (${o["Type"]})$req$pw$sens$prov"
          "${ex > 0 ? " examples=$ex" : ""}");
    }
  }
}
