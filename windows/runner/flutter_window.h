#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  // |background_allowed|: this is the primary instance, so closing the window
  // may hide it to the tray. |start_hidden|: launched at sign-in, no window.
  explicit FlutterWindow(const flutter::DartProject& project,
                         bool background_allowed = false,
                         bool start_hidden = false);

  // Posted by a second instance to bring the running one to the front.
  static constexpr UINT kShowMessage = WM_APP + 2;
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void AddTrayIcon(HWND hwnd);
  void RemoveTrayIcon(HWND hwnd);
  void ShowFromTray(HWND hwnd);

  // The project to run.
  flutter::DartProject project_;

  bool background_allowed_;
  bool start_hidden_;
  bool tray_added_ = false;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
