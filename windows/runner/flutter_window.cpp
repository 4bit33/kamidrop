#include "flutter_window.h"

#include <shellapi.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {

constexpr UINT kTrayMessage = WM_APP + 1;
constexpr UINT kMenuOpen = 1;
constexpr UINT kMenuExit = 2;

// KamiDrop працює у фоні (друк із системного «Друк»), коли є запис автозапуску:
// його ставить Dart разом із принтерами KamiDrop у Windows (proxy_host.dart).
bool BackgroundEnabled() {
  return ::RegGetValueW(HKEY_CURRENT_USER,
                        L"Software\\Microsoft\\Windows\\CurrentVersion\\Run",
                        L"KamiDrop", RRF_RT_REG_SZ, nullptr, nullptr,
                        nullptr) == ERROR_SUCCESS;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
                             bool background_allowed, bool start_hidden)
    : project_(project),
      background_allowed_(background_allowed),
      start_hidden_(start_hidden) {}

// ponytail: значок не відновлюється після перезапуску explorer.exe
// (потрібна обробка повідомлення TaskbarCreated) — додати, якщо заважатиме.
void FlutterWindow::AddTrayIcon(HWND hwnd) {
  if (tray_added_) return;
  NOTIFYICONDATAW nid = {};
  nid.cbSize = sizeof(nid);
  nid.hWnd = hwnd;
  nid.uID = 1;
  nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  nid.uCallbackMessage = kTrayMessage;
  nid.hIcon = ::LoadIcon(::GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(nid.szTip, L"KamiDrop");
  tray_added_ = ::Shell_NotifyIconW(NIM_ADD, &nid);
}

void FlutterWindow::RemoveTrayIcon(HWND hwnd) {
  if (!tray_added_) return;
  NOTIFYICONDATAW nid = {};
  nid.cbSize = sizeof(nid);
  nid.hWnd = hwnd;
  nid.uID = 1;
  ::Shell_NotifyIconW(NIM_DELETE, &nid);
  tray_added_ = false;
}

void FlutterWindow::ShowFromTray(HWND hwnd) {
  ::ShowWindow(hwnd, ::IsIconic(hwnd) ? SW_RESTORE : SW_SHOW);
  ::SetForegroundWindow(hwnd);
  if (flutter_controller_) flutter_controller_->ForceRedraw();
}

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
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  if (start_hidden_ && BackgroundEnabled()) {
    AddTrayIcon(GetHandle());  // автозапуск: без вікна, лише значок у треї
  } else {
    flutter_controller_->engine()->SetNextFrameCallback([&]() {
      this->Show();
    });
  }

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon(GetHandle());
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Фон і трей — до Flutter: він сам обробляє WM_CLOSE (завершення застосунку).
  switch (message) {
    case WM_CLOSE:
      if (background_allowed_ && BackgroundEnabled()) {
        AddTrayIcon(hwnd);
        ::ShowWindow(hwnd, SW_HIDE);
        return 0;
      }
      break;
    case kShowMessage:
      ShowFromTray(hwnd);
      return 0;
    case kTrayMessage:
      if (lparam == WM_LBUTTONUP) {
        ShowFromTray(hwnd);
      } else if (lparam == WM_RBUTTONUP) {
        const bool uk = PRIMARYLANGID(::GetUserDefaultUILanguage()) == LANG_UKRAINIAN;
        HMENU menu = ::CreatePopupMenu();
        ::AppendMenuW(menu, MF_STRING, kMenuOpen,
                      uk ? L"\u0412\u0456\u0434\u043a\u0440\u0438\u0442\u0438 KamiDrop" : L"Open KamiDrop");
        ::AppendMenuW(menu, MF_STRING, kMenuExit,
                      uk ? L"\u0412\u0438\u0439\u0442\u0438" : L"Quit");
        POINT pt;
        ::GetCursorPos(&pt);
        ::SetForegroundWindow(hwnd);  // інакше меню не закривається кліком повз нього
        const UINT cmd = ::TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON,
                                          pt.x, pt.y, 0, hwnd, nullptr);
        ::DestroyMenu(menu);
        if (cmd == kMenuOpen) {
          ShowFromTray(hwnd);
        } else if (cmd == kMenuExit) {
          ::DestroyWindow(hwnd);
        }
      }
      return 0;
  }

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
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
