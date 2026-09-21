// stderr-capture probe for librclone.dll on Windows, driven through dart:ffi --
// the same mechanism Phase B of the guided-remote-setup plan proposes.
//
// Three modes, because Go on Windows does not use the C runtime fd table:
//   crt           : _pipe + _dup2(w, 2) before loading the dll  (the plan as written)
//   setstd-before : CreatePipe + SetStdHandle(STD_ERROR) before loading the dll
//   setstd-after  : load + RcloneInitialize first, then SetStdHandle
//
// Usage: dart win_harness.dart <librclone.dll> <mode>
import "dart:convert";
import "dart:ffi";
import "dart:io";

const int stdErrorHandle = 0xFFFFFFF4;

final DynamicLibrary k32 = DynamicLibrary.open("kernel32.dll");
final DynamicLibrary crt = DynamicLibrary.open("ucrtbase.dll");

final int Function(Pointer<IntPtr>, Pointer<IntPtr>, Pointer<Void>, int)
    createPipe = k32.lookupFunction<
        Int32 Function(Pointer<IntPtr>, Pointer<IntPtr>, Pointer<Void>, Uint32),
        int Function(Pointer<IntPtr>, Pointer<IntPtr>, Pointer<Void>,
            int)>("CreatePipe");
final int Function(int, int) setStdHandle = k32.lookupFunction<
    Int32 Function(Uint32, IntPtr), int Function(int, int)>("SetStdHandle");
final int Function() getLastError = k32.lookupFunction<
    Uint32 Function(), int Function()>("GetLastError");
final int Function(int) getStdHandle = k32.lookupFunction<
    IntPtr Function(Uint32), int Function(int)>("GetStdHandle");
final int Function(int, Pointer<Void>, int, Pointer<Uint32>, Pointer<Uint32>,
    Pointer<Uint32>) peekNamedPipe = k32.lookupFunction<
        Int32 Function(IntPtr, Pointer<Void>, Uint32, Pointer<Uint32>,
            Pointer<Uint32>, Pointer<Uint32>),
        int Function(int, Pointer<Void>, int, Pointer<Uint32>, Pointer<Uint32>,
            Pointer<Uint32>)>("PeekNamedPipe");
final int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>)
    readFile = k32.lookupFunction<
        Int32 Function(IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>,
            Pointer<Void>),
        int Function(int, Pointer<Uint8>, int, Pointer<Uint32>,
            Pointer<Void>)>("ReadFile");

final Pointer<Uint8> Function(int) cMalloc = crt.lookupFunction<
    Pointer<Uint8> Function(IntPtr), Pointer<Uint8> Function(int)>("malloc");
final int Function(Pointer<Int32>, int, int) cPipe = crt.lookupFunction<
    Int32 Function(Pointer<Int32>, Uint32, Int32),
    int Function(Pointer<Int32>, int, int)>("_pipe");
final int Function(int, int) cDup2 = crt.lookupFunction<
    Int32 Function(Int32, Int32), int Function(int, int)>("_dup2");
final int Function(int) cGetOsHandle = crt.lookupFunction<
    IntPtr Function(Int32), int Function(int)>("_get_osfhandle");

final class RpcResult extends Struct {
  external Pointer<Uint8> output;
  @Int32()
  external int status;
}

Pointer<Uint8> toC(String s) {
  final bytes = utf8.encode(s);
  final p = cMalloc(bytes.length + 1);
  for (var i = 0; i < bytes.length; i++) {
    p[i] = bytes[i];
  }
  p[bytes.length] = 0;
  return p;
}

String fromC(Pointer<Uint8> p) {
  if (p == nullptr) return "(null)";
  var n = 0;
  while (p[n] != 0) {
    n++;
  }
  return utf8.decode(p.asTypedList(n), allowMalformed: true);
}

int readHandle = 0;
final StringBuffer captured = StringBuffer();

void pump() {
  if (readHandle == 0) return;
  final avail = cMalloc(4).cast<Uint32>();
  final got = cMalloc(4).cast<Uint32>();
  final buf = cMalloc(65536);
  while (true) {
    avail.value = 0;
    final ok = peekNamedPipe(
        readHandle, nullptr, 0, nullptr, avail, nullptr);
    if (ok == 0) { stdout.writeln("[harness] PeekNamedPipe failed, GetLastError=${getLastError()}"); break; }
    if (avail.value == 0) break;
    final want = avail.value > 65535 ? 65535 : avail.value;
    got.value = 0;
    if (readFile(readHandle, buf, want, got, nullptr) == 0) break;
    if (got.value == 0) break;
    final text = utf8.decode(buf.asTypedList(got.value), allowMalformed: true);
    captured.write(text);
    stdout.write("[fd2] $text");
  }
}

void setupCrtPipe() {
  final fds = cMalloc(8).cast<Int32>();
  final rc = cPipe(fds, 65536, 0);
  stdout.writeln("[harness] _pipe rc=$rc  read_fd=${fds[0]} write_fd=${fds[1]}");
  stdout.writeln("[harness] STD_ERROR before _dup2 = ${getStdHandle(stdErrorHandle)}");
  final d = cDup2(fds[1], 2);
  stdout.writeln("[harness] _dup2(write_fd, 2) rc=$d");
  stdout.writeln("[harness] STD_ERROR after  _dup2 = ${getStdHandle(stdErrorHandle)}");
  stdout.writeln("[harness] write_fd handle      = ${cGetOsHandle(fds[1])}");
  readHandle = cGetOsHandle(fds[0]);
  stdout.writeln("[harness] read handle = $readHandle");
}

void setupSetStdHandlePipe() {
  final hr = cMalloc(8).cast<IntPtr>();
  final hw = cMalloc(8).cast<IntPtr>();
  final ok = createPipe(hr, hw, nullptr, 65536);
  stdout.writeln("[harness] CreatePipe ok=$ok read=${hr.value} write=${hw.value}");
  final before = getStdHandle(stdErrorHandle);
  final s = setStdHandle(stdErrorHandle, hw.value);
  final after = getStdHandle(stdErrorHandle);
  stdout.writeln("[harness] SetStdHandle ok=$s  STD_ERROR was $before now $after");
  readHandle = hr.value;
}

Future<void> main(List<String> args) async {
  final libPath = args.isNotEmpty ? args[0] : "librclone.dll";
  final mode = args.length > 1 ? args[1] : "crt";
  stdout.writeln("[harness] lib=$libPath mode=$mode");

  if (mode == "crt") setupCrtPipe();
  if (mode == "setstd-before") setupSetStdHandlePipe();

  final lib = DynamicLibrary.open(libPath);
  final init = lib.lookupFunction<Void Function(), void Function()>(
      "RcloneInitialize");
  final rpc = lib.lookupFunction<
      RpcResult Function(Pointer<Uint8>, Pointer<Uint8>),
      RpcResult Function(Pointer<Uint8>, Pointer<Uint8>)>("RcloneRPC");
  init();
  stdout.writeln("[harness] RcloneInitialize done");

  if (mode == "setstd-after") setupSetStdHandlePipe();

  RpcResult call(String method, String body) {
    final r = rpc(toC(method), toC(body));
    return r;
  }

  final v = call("core/version", "{}");
  final vs = fromC(v.output);
  stdout.writeln("[harness] core/version status=${v.status} "
      "${vs.length > 140 ? vs.substring(0, 140) : vs}");

  // Keep the real user config untouched.
  final scratch = "${Directory.current.path.replaceAll("\\", "/")}/fd2probe.conf";
  final sp = call("config/setpath", jsonEncode({"path": scratch}));
  stdout.writeln("[harness] config/setpath status=${sp.status} ${fromC(sp.output)}");

  final body = jsonEncode({
    "name": "fd2probe",
    "type": "drive",
    "parameters": {
      "config_shared_client_id": "true",
      "config_is_local": "true",
      "config_auth_no_browser": "true",
    },
    "opt": {"nonInteractive": true, "obscure": true},
    "_async": true,
  });
  final c = call("config/create", body);
  stdout.writeln("[harness] config/create status=${c.status} ${fromC(c.output)}");

  const needle = "127.0.0.1:53682/auth?state=";
  for (var i = 0; i < 150; i++) {
    pump();
    if (captured.toString().contains(needle)) {
      stdout.writeln("");
      stdout.writeln("[harness] RESULT: PASS - auth URL captured after ${i * 100} ms");
      exit(0);
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  stdout.writeln("");
  stdout.writeln("[harness] RESULT: FAIL - no auth URL within 15s "
      "(captured ${captured.length} bytes)");
  exit(1);
}
