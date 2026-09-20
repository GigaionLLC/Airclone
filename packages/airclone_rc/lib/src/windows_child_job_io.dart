import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Windows-only: ties every rclone child we spawn to the lifetime of THIS
/// process, so no `rclone.exe` can ever outlive Airclone.
///
/// Windows does not kill child processes when their parent dies. An orderly exit
/// is handled in Dart — `HttpRcloneClient.quit()` stops `rcd`, and the desktop
/// window-close hook calls it (see `ui/app.dart`) — but a *disorderly* one
/// (crash, Task Manager "End task", a killed debug session, a forced sign-out)
/// leaves the daemon running forever. That is not merely a leak: the orphan holds
/// an open handle on `rclone.exe` **inside the install directory**, so the
/// uninstaller cannot delete it and files are left behind in
/// `C:\Program Files\Airclone`. Microsoft Store certification failed the product
/// for precisely that on 2026-07-29 (policy 10.2.7, clean removal). There is also
/// a reap-on-next-launch fallback (`HttpRcloneClient._reapPreviousRcd`), but it
/// only helps if the app is launched again — an uninstall may never launch it.
///
/// Mechanism: one process-wide **Job Object** carrying
/// `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`. Children are assigned to it and the
/// kernel terminates the entire job the instant the last handle to it closes —
/// which the OS does for us when our process dies, however it dies. The handle is
/// therefore held open deliberately for the life of the process and never closed.
/// Nested jobs are supported from Windows 8 (we require 10), so already being
/// inside someone else's job (a runner, a container, Task Scheduler) is fine.
///
/// Best-effort by design: every failure is swallowed and latched, and callers
/// never branch on the result. This is a safety net, not a functional
/// requirement — losing it costs the orphan cleanup, never the feature.
class WindowsChildJob {
  WindowsChildJob._();

  /// `JobObjectExtendedLimitInformation` — the JOBOBJECTINFOCLASS value that
  /// selects [_JobObjectExtendedLimitInformation].
  static const _jobObjectExtendedLimitInformation = 9;

  /// `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`: terminate every process in the job
  /// when its last handle closes. This is the whole point of the class.
  static const _limitKillOnJobClose = 0x00002000;

  /// The minimum access needed to put a process into a job: `PROCESS_SET_QUOTA |
  /// PROCESS_TERMINATE`. We own the child, so this always succeeds.
  static const _processSetQuota = 0x0100;
  static const _processTerminate = 0x0001;

  /// The one job handle for this process. Held open for the process lifetime on
  /// purpose (closing it would kill the children immediately).
  static int? _job;

  /// Latched after any failure so a broken environment doesn't re-attempt the
  /// FFI dance on every spawn.
  static bool _unavailable = false;

  /// Puts [pid] into the kill-on-close job, creating the job on first use.
  /// No-op off Windows, and silent on every error.
  static void adopt(int pid) {
    if (!Platform.isWindows || _unavailable) return;
    try {
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      final job = _job ??= _createJob(kernel32);
      if (job == null) {
        _unavailable = true;
        return;
      }
      final openProcess = kernel32
          .lookupFunction<
            IntPtr Function(Uint32, Int32, Uint32),
            int Function(int, int, int)
          >('OpenProcess');
      final assign = kernel32
          .lookupFunction<
            Int32 Function(IntPtr, IntPtr),
            int Function(int, int)
          >('AssignProcessToJobObject');
      final closeHandle = kernel32
          .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
            'CloseHandle',
          );
      final process = openProcess(_processSetQuota | _processTerminate, 0, pid);
      if (process == 0) return;
      try {
        assign(job, process);
      } finally {
        // Closing our handle to the CHILD is correct and required — the job
        // holds its own reference, so this does not release it from the job.
        closeHandle(process);
      }
    } catch (_) {
      _unavailable = true;
    }
  }

  /// Creates the unnamed job object and arms kill-on-close. Returns null if
  /// either step fails.
  static int? _createJob(DynamicLibrary kernel32) {
    final createJobObject = kernel32
        .lookupFunction<
          IntPtr Function(Pointer<Void>, Pointer<Utf16>),
          int Function(Pointer<Void>, Pointer<Utf16>)
        >('CreateJobObjectW');
    final setInformation = kernel32
        .lookupFunction<
          Int32 Function(IntPtr, Int32, Pointer<Void>, Uint32),
          int Function(int, int, Pointer<Void>, int)
        >('SetInformationJobObject');
    final closeHandle = kernel32
        .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
          'CloseHandle',
        );
    // Unnamed (null name): private to this process, so two running Airclones
    // never share a job and one exiting cannot kill the other's engine.
    final job = createJobObject(nullptr, nullptr);
    if (job == 0) return null;
    final info = calloc<_JobObjectExtendedLimitInformation>();
    try {
      info.ref.basicLimitInformation.limitFlags = _limitKillOnJobClose;
      final ok = setInformation(
        job,
        _jobObjectExtendedLimitInformation,
        info.cast<Void>(),
        sizeOf<_JobObjectExtendedLimitInformation>(),
      );
      if (ok == 0) {
        closeHandle(job);
        return null;
      }
      return job;
    } finally {
      calloc.free(info);
    }
  }
}

/// `JOBOBJECT_BASIC_LIMIT_INFORMATION` (winnt.h). Only `limitFlags` is set; the
/// rest exist so Dart lays the struct out — and computes `sizeOf` — exactly as
/// the Win32 ABI expects, since `SetInformationJobObject` validates the length.
final class _JobObjectBasicLimitInformation extends Struct {
  @Int64()
  external int perProcessUserTimeLimit;
  @Int64()
  external int perJobUserTimeLimit;
  @Uint32()
  external int limitFlags;
  @Size()
  external int minimumWorkingSetSize;
  @Size()
  external int maximumWorkingSetSize;
  @Uint32()
  external int activeProcessLimit;
  @IntPtr()
  external int affinity;
  @Uint32()
  external int priorityClass;
  @Uint32()
  external int schedulingClass;
}

/// `IO_COUNTERS` (winnt.h) — padding, in effect: it sits between the basic limits
/// and the memory limits in the extended struct below.
final class _IoCounters extends Struct {
  @Uint64()
  external int readOperationCount;
  @Uint64()
  external int writeOperationCount;
  @Uint64()
  external int otherOperationCount;
  @Uint64()
  external int readTransferCount;
  @Uint64()
  external int writeTransferCount;
  @Uint64()
  external int otherTransferCount;
}

/// `JOBOBJECT_EXTENDED_LIMIT_INFORMATION` (winnt.h) — the payload for
/// `JobObjectExtendedLimitInformation`.
final class _JobObjectExtendedLimitInformation extends Struct {
  external _JobObjectBasicLimitInformation basicLimitInformation;
  external _IoCounters ioInfo;
  @Size()
  external int processMemoryLimit;
  @Size()
  external int jobMemoryLimit;
  @Size()
  external int peakProcessMemoryUsed;
  @Size()
  external int peakJobMemoryUsed;
}
