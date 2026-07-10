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
    return a == "--run-task" || a == "--run-due" ||
           a.rfind("--run-task=", 0) == 0;
  });
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  std::vector<std::string> command_line_arguments = GetCommandLineArguments();
  const bool headless = ContainsHeadlessFlag(command_line_arguments);

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
