#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <optional>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
// desktop_multi_window: register plugins into each pop-out window's engine too
// (the image pop-out needs the plugin channel live in its own engine).
#include "desktop_multi_window/desktop_multi_window_plugin.h"

namespace {

// HKCU\...\Run, the per-user sign-in list. Per user, so no elevation, and it
// is the list Task Manager's Startup tab and Settings > Apps > Startup show.
constexpr wchar_t kRunKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
// The value name. airclone.iss deletes it on uninstall.
constexpr wchar_t kRunValue[] = L"Airclone";

// This executable's own full path. The only program a Run entry written here
// can ever name: nothing from Dart reaches the command string.
std::wstring OwnExecutablePath() {
  std::vector<wchar_t> buf(MAX_PATH);
  for (;;) {
    const DWORD n =
        ::GetModuleFileNameW(nullptr, buf.data(), static_cast<DWORD>(buf.size()));
    if (n == 0) return std::wstring();
    if (n < buf.size()) return std::wstring(buf.data(), n);
    if (buf.size() >= 32768) return std::wstring();
    buf.resize(buf.size() * 2);
  }
}

// `"C:\...\airclone.exe" --tray`. Windows file names cannot contain a double
// quote, so quoting the path is the whole of the escaping it needs; refuse one
// anyway rather than build a command line from something unexpected.
std::wstring RunCommand() {
  const std::wstring exe = OwnExecutablePath();
  if (exe.empty() || exe.find(L'"') != std::wstring::npos) {
    return std::wstring();
  }
  return L"\"" + exe + L"\" --tray";
}

// What the Run value holds now, or empty when there is none.
std::wstring ReadRunValue() {
  DWORD bytes = 0;
  if (::RegGetValueW(HKEY_CURRENT_USER, kRunKey, kRunValue, RRF_RT_REG_SZ,
                     nullptr, nullptr, &bytes) != ERROR_SUCCESS ||
      bytes == 0) {
    return std::wstring();
  }
  std::vector<wchar_t> buf(bytes / sizeof(wchar_t) + 1);
  DWORD size = static_cast<DWORD>(buf.size() * sizeof(wchar_t));
  if (::RegGetValueW(HKEY_CURRENT_USER, kRunKey, kRunValue, RRF_RT_REG_SZ,
                     nullptr, buf.data(), &size) != ERROR_SUCCESS) {
    return std::wstring();
  }
  return std::wstring(buf.data());
}

// On only when the entry starts THIS executable. An entry left by an install
// that has since moved reads as off, and turning the switch on rewrites it.
bool AutostartEnabled() {
  const std::wstring want = RunCommand();
  if (want.empty()) return false;
  const std::wstring have = ReadRunValue();
  return !have.empty() && ::CompareStringOrdinal(have.c_str(), -1, want.c_str(),
                                                 -1, TRUE) == CSTR_EQUAL;
}

bool SetAutostart(bool enabled) {
  if (!enabled) {
    const LSTATUS r =
        ::RegDeleteKeyValueW(HKEY_CURRENT_USER, kRunKey, kRunValue);
    return r == ERROR_SUCCESS || r == ERROR_FILE_NOT_FOUND;
  }
  const std::wstring cmd = RunCommand();
  if (cmd.empty()) return false;
  return ::RegSetKeyValueW(
             HKEY_CURRENT_USER, kRunKey, kRunValue, REG_SZ, cmd.c_str(),
             static_cast<DWORD>((cmd.size() + 1) * sizeof(wchar_t))) ==
         ERROR_SUCCESS;
}

}  // namespace

UINT AircloneShowWindowMessage() {
  static const UINT message = ::RegisterWindowMessageW(L"Airclone.ShowWindow");
  return message;
}

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  // Ensure every window desktop_multi_window creates (each pop-out image
  // viewer) gets the generated plugins registered on ITS engine.
  DesktopMultiWindowSetWindowCreatedCallback([](void *controller) {
    auto *flutter_view_controller =
        reinterpret_cast<flutter::FlutterViewController *>(controller);
    auto *registry = flutter_view_controller->engine();
    RegisterPlugins(registry);
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "airclone/window",
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const std::string& method = call.method_name();
        if (method == "hide") {
          ::ShowWindow(GetHandle(), SW_HIDE);
          result->Success();
        } else if (method == "show") {
          ShowAndFocus();
          result->Success();
        } else if (method == "startedHidden") {
          result->Success(flutter::EncodableValue(start_hidden_));
        } else if (method == "trayHostAvailable") {
          // The notification area is always there on Windows.
          result->Success(flutter::EncodableValue(true));
        } else if (method == "setInterceptClose") {
          // Nothing to do: WM_CLOSE already reaches Dart as an exit request.
          result->Success();
        } else if (method == "autostartEnabled") {
          result->Success(flutter::EncodableValue(AutostartEnabled()));
        } else if (method == "setAutostart") {
          const auto* on = std::get_if<bool>(call.arguments());
          if (on == nullptr) {
            result->Error("bad-args", "setAutostart takes a bool");
            return;
          }
          if (!SetAutostart(*on)) {
            result->Error("registry", "could not change the sign-in entry");
            return;
          }
          result->Success(flutter::EncodableValue(AutostartEnabled()));
        } else {
          result->NotImplemented();
        }
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    // A `--tray` launch keeps the window hidden; the tray shows it.
    if (!start_hidden_) this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::ShowAndFocus() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) return;
  ::ShowWindow(hwnd, ::IsIconic(hwnd) ? SW_RESTORE : SW_SHOW);
  ::SetForegroundWindow(hwnd);
}

void FlutterWindow::OnDestroy() {
  window_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  // A second launch found us running and asked for the window (main.cpp).
  if (message == AircloneShowWindowMessage() && message != 0) {
    ShowAndFocus();
    return 0;
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
