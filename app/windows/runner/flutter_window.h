#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "win32_window.h"

// The registered message a second launch broadcasts to ask the running
// Airclone to show its window (single instance, #54). Carries no data.
UINT AircloneShowWindowMessage();

// The sign-in launch flag. A launch with it starts hidden in the tray.
inline constexpr char kTrayLaunchFlag[] = "--tray";

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

  // `--tray` (#54): never show the window on the first frame; it stays hidden
  // until Dart (the tray's "Open Airclone") or a second launch shows it.
  void SetStartHidden(bool hidden) { start_hidden_ = hidden; }

  // Brings the window back and to the front: from the tray, or because a
  // second launch asked this one to.
  void ShowAndFocus();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // 'airclone/window' (#54): hide/show, start-hidden, the sign-in launch.
  // Dart side: lib/src/state/desktop_window.dart.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      window_channel_;

  bool start_hidden_ = false;
  bool minimize_to_tray_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
