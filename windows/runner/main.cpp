#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();
  bool start_hidden = false;
  bool has_file = false;
  for (const auto& arg : command_line_arguments) {
    if (arg == "--background") {
      start_hidden = true;
    } else {
      has_file = true;
    }
  }

  // Один екземпляр: другий запуск лише показує вікно першого (той може сидіти в треї).
  // ponytail: запуск із файлом («Відкрити за допомогою») поки відкриває друге, звичайне
  // вікно без фону; передати файл першому екземпляру (WM_COPYDATA) — разом із тією функцією.
  ::CreateMutexW(nullptr, TRUE, L"KamiDropSingleInstance");
  const bool primary = ::GetLastError() != ERROR_ALREADY_EXISTS;
  if (!primary && !has_file) {
    if (HWND running = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"KamiDrop")) {
      ::PostMessage(running, FlutterWindow::kShowMessage, 0, 0);
    }
    return EXIT_SUCCESS;
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project, primary, primary && start_hidden);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(520, 900);
  if (!window.Create(L"KamiDrop", origin, size)) {
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
