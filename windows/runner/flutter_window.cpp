#include "flutter_window.h"

#include <flutter/encodable_value.h>

#include <optional>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {

constexpr char kWindowsChannelName[] = "com.mel0ny.linkup/windows";
constexpr wchar_t kRunRegistryPath[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr wchar_t kAutoStartValueName[] = L"LinkUp";

std::optional<bool> GetEnabledArgument(
    const flutter::EncodableValue* arguments) {
  if (arguments == nullptr) {
    return std::nullopt;
  }

  const auto* map = std::get_if<flutter::EncodableMap>(arguments);
  if (map == nullptr) {
    return std::nullopt;
  }

  const auto iterator = map->find(flutter::EncodableValue("enabled"));
  if (iterator == map->end()) {
    return std::nullopt;
  }

  if (const auto* value = std::get_if<bool>(&iterator->second)) {
    return *value;
  }

  return std::nullopt;
}

UINT GetTrayEventCode(LPARAM lparam) {
  return LOWORD(static_cast<DWORD_PTR>(lparam));
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
                             bool start_hidden)
    : project_(project), start_hidden_(start_hidden) {}

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
  RegisterWindowsChannel();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    if (!this->start_hidden_) {
      this->Show();
    }
  });

  if (start_hidden_) {
    InitializeTray();
  }

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  DisposeTray();

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  windows_channel_.reset();

  Win32Window::OnDestroy();
}

void FlutterWindow::RegisterWindowsChannel() {
  windows_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kWindowsChannelName,
          &flutter::StandardMethodCodec::GetInstance());

  windows_channel_->SetMethodCallHandler(
      [this](
          const flutter::MethodCall<flutter::EncodableValue>& call,
          std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
              result) {
        HandleWindowsMethodCall(call, std::move(result));
      });
}

void FlutterWindow::HandleWindowsMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method_name = call.method_name();

  if (method_name == "setCloseToTrayEnabled") {
    const auto enabled = GetEnabledArgument(call.arguments());
    if (!enabled.has_value()) {
      result->Error("invalid_args", "Missing enabled flag.");
      return;
    }
    close_to_tray_enabled_ = enabled.value();
    if (close_to_tray_enabled_) {
      InitializeTray();
    } else if (!start_hidden_) {
      DisposeTray();
    }
    result->Success(flutter::EncodableValue(close_to_tray_enabled_));
    return;
  }

  if (method_name == "setAutoStartEnabled") {
    const auto enabled = GetEnabledArgument(call.arguments());
    if (!enabled.has_value()) {
      result->Error("invalid_args", "Missing enabled flag.");
      return;
    }
    SetAutoStartEnabled(enabled.value());
    result->Success(flutter::EncodableValue(GetAutoStartEnabled()));
    return;
  }

  if (method_name == "getAutoStartEnabled") {
    result->Success(flutter::EncodableValue(GetAutoStartEnabled()));
    return;
  }

  if (method_name == "showMainWindow") {
    ShowMainWindow();
    result->Success();
    return;
  }

  if (method_name == "hideMainWindow") {
    HideMainWindow();
    result->Success();
    return;
  }

  if (method_name == "initializeTray") {
    result->Success(flutter::EncodableValue(InitializeTray()));
    return;
  }

  if (method_name == "disposeTray") {
    DisposeTray();
    result->Success();
    return;
  }

  result->NotImplemented();
}

bool FlutterWindow::InitializeTray() {
  if (tray_initialized_ || GetHandle() == nullptr) {
    return true;
  }

  tray_icon_data_ = {};
  tray_icon_data_.cbSize = sizeof(NOTIFYICONDATAW);
  tray_icon_data_.hWnd = GetHandle();
  tray_icon_data_.uID = IDI_APP_ICON;
  tray_icon_data_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  tray_icon_data_.uCallbackMessage = kTrayCallbackMessage;
  tray_icon_data_.hIcon =
      LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(tray_icon_data_.szTip, L"LinkUp");

  if (!Shell_NotifyIconW(NIM_ADD, &tray_icon_data_)) {
    return false;
  }

  tray_icon_data_.uVersion = NOTIFYICON_VERSION_4;
  Shell_NotifyIconW(NIM_SETVERSION, &tray_icon_data_);
  tray_initialized_ = true;
  return true;
}

void FlutterWindow::DisposeTray() {
  if (!tray_initialized_) {
    return;
  }

  Shell_NotifyIconW(NIM_DELETE, &tray_icon_data_);
  tray_icon_data_ = {};
  tray_initialized_ = false;
}

void FlutterWindow::ShowTrayMenu() {
  HMENU tray_menu = CreatePopupMenu();
  if (tray_menu == nullptr) {
    return;
  }

  AppendMenuW(tray_menu, MF_STRING, ID_TRAY_SHOW_WINDOW,
              L"\x663E\x793A\x4E3B\x7A97\x53E3");
  AppendMenuW(tray_menu, MF_STRING, ID_TRAY_RECONNECT,
              L"\x7ACB\x5373\x91CD\x8FDE");
  AppendMenuW(tray_menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(tray_menu, MF_STRING, ID_TRAY_EXIT, L"\x9000\x51FA");

  POINT cursor_point;
  GetCursorPos(&cursor_point);
  SetForegroundWindow(GetHandle());
  TrackPopupMenu(tray_menu,
                 TPM_BOTTOMALIGN | TPM_LEFTALIGN | TPM_RIGHTBUTTON,
                 cursor_point.x, cursor_point.y, 0, GetHandle(), nullptr);
  DestroyMenu(tray_menu);
}

void FlutterWindow::ShowMainWindow() {
  start_hidden_ = false;
  InitializeTray();
  ShowWindow(GetHandle(), SW_RESTORE);
  ShowWindow(GetHandle(), SW_SHOW);
  SetForegroundWindow(GetHandle());
}

void FlutterWindow::HideMainWindow() {
  InitializeTray();
  ShowWindow(GetHandle(), SW_HIDE);
}

void FlutterWindow::ExitApplication() {
  is_exiting_ = true;
  DisposeTray();
  SetQuitOnClose(true);
  Destroy();
}

bool FlutterWindow::SetAutoStartEnabled(bool enabled) {
  HKEY key = nullptr;
  const auto open_result = RegCreateKeyExW(
      HKEY_CURRENT_USER, kRunRegistryPath, 0, nullptr, REG_OPTION_NON_VOLATILE,
      KEY_SET_VALUE | KEY_QUERY_VALUE, nullptr, &key, nullptr);
  if (open_result != ERROR_SUCCESS) {
    return false;
  }

  LSTATUS status = ERROR_SUCCESS;
  if (enabled) {
    const auto command = GetAutoStartCommand();
    status = RegSetValueExW(
        key, kAutoStartValueName, 0, REG_SZ,
        reinterpret_cast<const BYTE*>(command.c_str()),
        static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
  } else {
    status = RegDeleteValueW(key, kAutoStartValueName);
    if (status == ERROR_FILE_NOT_FOUND) {
      status = ERROR_SUCCESS;
    }
  }

  RegCloseKey(key);
  return status == ERROR_SUCCESS;
}

bool FlutterWindow::GetAutoStartEnabled() const {
  DWORD type = 0;
  wchar_t buffer[4096];
  DWORD buffer_size = sizeof(buffer);
  const auto status = RegGetValueW(
      HKEY_CURRENT_USER, kRunRegistryPath, kAutoStartValueName, RRF_RT_REG_SZ,
      &type, buffer, &buffer_size);
  return status == ERROR_SUCCESS;
}

std::wstring FlutterWindow::GetAutoStartCommand() const {
  std::vector<wchar_t> buffer(MAX_PATH);
  DWORD copied = 0;

  while (true) {
    copied = GetModuleFileNameW(nullptr, buffer.data(),
                                static_cast<DWORD>(buffer.size()));
    if (copied == 0) {
      return L"";
    }
    if (copied < buffer.size() - 1) {
      break;
    }
    buffer.resize(buffer.size() * 2);
  }

  const std::wstring executable_path(buffer.data(), copied);
  return L"\"" + executable_path + L"\" --start-hidden";
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

  switch (message) {
    case WM_CLOSE:
      if (close_to_tray_enabled_ && !is_exiting_) {
        HideMainWindow();
        return 0;
      }
      break;

    case kTrayCallbackMessage:
      switch (GetTrayEventCode(lparam)) {
        case WM_LBUTTONDBLCLK:
        case WM_LBUTTONUP:
          ShowMainWindow();
          return 0;
        case WM_RBUTTONUP:
        case WM_CONTEXTMENU:
          ShowTrayMenu();
          return 0;
      }
      break;

    case WM_COMMAND:
      switch (LOWORD(wparam)) {
        case ID_TRAY_SHOW_WINDOW:
          ShowMainWindow();
          return 0;
        case ID_TRAY_RECONNECT:
          if (windows_channel_) {
            windows_channel_->InvokeMethod(
                "onTrayReconnect",
                std::make_unique<flutter::EncodableValue>());
          }
          return 0;
        case ID_TRAY_EXIT:
          ExitApplication();
          return 0;
      }
      break;

    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
