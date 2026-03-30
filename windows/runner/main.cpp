#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <thread>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // Group processes launched simultaneously (e.g. from Explorer context menu)
  HANDLE hMutex = ::CreateMutexW(NULL, FALSE, L"RawViewerBatchMutex");
  bool is_primary = (::WaitForSingleObject(hMutex, 0) == WAIT_OBJECT_0);

  HANDLE hMapFile = ::CreateFileMappingW(INVALID_HANDLE_VALUE, NULL, PAGE_READWRITE, 0, sizeof(HWND), L"RawViewerBatchSharedMem");
  HWND* shared_hwnd = nullptr;
  if (hMapFile) {
    shared_hwnd = (HWND*)::MapViewOfFile(hMapFile, FILE_MAP_ALL_ACCESS, 0, 0, sizeof(HWND));
  }

  if (!is_primary) {
    // Secondary instance in the batch
    HWND existing_window = nullptr;
    int retries = 50; // Wait up to 5 seconds for primary to set HWND
    while (retries > 0) {
      if (shared_hwnd && *shared_hwnd != NULL) {
        existing_window = *shared_hwnd;
        break;
      }
      ::Sleep(100);
      retries--;
    }

    if (existing_window && ::IsWindow(existing_window)) {
      std::vector<std::string> command_line_arguments = GetCommandLineArguments();
      std::string paths_str;
      for (size_t i = 0; i < command_line_arguments.size(); ++i) {
        paths_str += command_line_arguments[i];
        paths_str += '\n';
      }
      
      if (!paths_str.empty()) {
        COPYDATASTRUCT cds;
        cds.dwData = 1; // Identifier for paths
        cds.cbData = static_cast<DWORD>(paths_str.size() + 1);
        cds.lpData = (PVOID)paths_str.c_str();

        ::SendMessage(existing_window, WM_COPYDATA, (WPARAM)nullptr, (LPARAM)&cds);
      }
      ::SetForegroundWindow(existing_window);
    }
    
    if (shared_hwnd) ::UnmapViewOfFile(shared_hwnd);
    if (hMapFile) ::CloseHandle(hMapFile);
    ::CloseHandle(hMutex);
    ::CoUninitialize();
    return EXIT_SUCCESS;
  }

  if (shared_hwnd) {
    *shared_hwnd = NULL; // Clear it for now
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();
  const std::vector<std::string> initial_open_paths = command_line_arguments;

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));
  FlutterWindow window(project, initial_open_paths);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"rawviewer", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  if (shared_hwnd) {
    *shared_hwnd = window.GetHandle();
  }

  // Release the batch mutex after 2 seconds, allowing future opens to create a new window
  std::thread([hMutex, hMapFile, shared_hwnd]() {
    ::Sleep(2000);
    if (shared_hwnd) {
      *shared_hwnd = NULL;
      ::UnmapViewOfFile(shared_hwnd);
    }
    if (hMapFile) ::CloseHandle(hMapFile);
    ::ReleaseMutex(hMutex);
    ::CloseHandle(hMutex);
  }).detach();

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
