#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <algorithm>

#include "flutter_window.h"
#include "utils.h"

// True when the forwarded Dart CLI args request a headless background run
// (`--run-task <id>` / `--run-due`). Mirrors the Dart-side scan in
// `lib/src/headless/headless_runner.dart` (isHeadlessInvocation), incl. the
// `--run-task=<id>` joined form.
static bool ContainsHeadlessFlag(const std::vector<std::string> &args) {
  return std::any_of(args.begin(), args.end(), [](const std::string &a) {
    // --webui and --version join the list for the same reason the Linux
    // runner grew one: main.dart branches on them before runApp, so showing a
    // window would flash an empty frame and leave it on screen for the life of
    // a Web UI host that has no UI at all.
    return a == "--run-task" || a == "--run-due" ||
           a.rfind("--run-task=", 0) == 0 || a == "--webui" ||
           a == "--update" || a == "--version" || a == "--help" || a == "-h";
  });
}

static bool HasArg(const std::vector<std::string> &args, const char *want) {
  return std::find(args.begin(), args.end(), want) != args.end();
}

// One windowed Airclone per user session (#54). With "start in the tray at
// sign-in", launching from the Start menu would otherwise start a second app,
// with a second engine and scheduler, beside the hidden one. Instead the second
// launch asks the first to show its window, and exits.
//
// Headless runs (`--run-task`, `--run-due`, `--webui`, ...) never take part:
// the scheduler starts those while the app may well be open, and they must run.
// The handle is deliberately never closed; the OS releases it at exit.
// Debug builds (`flutter run`) stay out of it, so a developer can run one next
// to an installed Airclone.
static bool AnotherWindowedInstanceIsRunning(bool tray_launch) {
#ifdef _DEBUG
  (void)tray_launch;
  return false;
#else
  ::CreateMutexW(nullptr, FALSE, L"Local\\Airclone.GigaionLLC.GUI");
  if (::GetLastError() != ERROR_ALREADY_EXISTS) return false;
  // A sign-in launch finding the app already up has nothing to show.
  if (!tray_launch) {
    // Let the running instance take the foreground: it is answering the user.
    ::AllowSetForegroundWindow(ASFW_ANY);
    ::PostMessageW(HWND_BROADCAST, AircloneShowWindowMessage(), 0, 0);
  }
  return true;
#endif
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  std::vector<std::string> command_line_arguments = GetCommandLineArguments();
  const bool headless = ContainsHeadlessFlag(command_line_arguments);
  const bool tray_launch =
      !headless && HasArg(command_line_arguments, kTrayLaunchFlag);
  if (!headless && AnotherWindowedInstanceIsRunning(tray_launch)) {
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a new console
  // when running with a debugger — but never spawn a console for a headless
  // background run, which would flash an unwanted window.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && !headless &&
      ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  // Always create the window: it hosts the Flutter engine that runs the Dart
  // entrypoint (the rclone engine + task runner), and its message loop below
  // services the platform-channel replies the headless isolate awaits. In
  // headless mode we intentionally never Show() it: the Dart entrypoint returns
  // before runApp, so no first frame is produced and FlutterWindow's frame
  // callback (which is what calls Win32Window::Show()) never fires — the window
  // stays hidden while the run proceeds and Dart exits the process when done.
  FlutterWindow window(project);
  window.SetStartHidden(tray_launch);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"airclone", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
