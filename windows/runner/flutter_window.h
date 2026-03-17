#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <optional>
#include <shellapi.h>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project,
                         bool start_hidden = false);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

  void ShowMainWindow();
  void HideMainWindow();

 private:
  static constexpr UINT kTrayCallbackMessage = WM_APP + 1;

  void RegisterWindowsChannel();
  void HandleWindowsMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  bool InitializeTray();
  void DisposeTray();
  void ShowTrayMenu();
  void ExitApplication();
  bool SetAutoStartEnabled(bool enabled);
  bool GetAutoStartEnabled() const;
  std::wstring GetAutoStartCommand() const;

  // The project to run.
  flutter::DartProject project_;
  bool start_hidden_;
  bool close_to_tray_enabled_ = true;
  bool tray_initialized_ = false;
  bool is_exiting_ = false;
  NOTIFYICONDATAW tray_icon_data_{};

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      windows_channel_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
