#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <shellapi.h>

#include <memory>
#include <string>
#include <vector>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project,
                         std::vector<std::string> initial_open_paths = {});
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  static LRESULT CALLBACK FlutterViewWindowProc(HWND hwnd, UINT message,
                                                WPARAM wparam, LPARAM lparam,
                                                UINT_PTR subclass_id,
                                                DWORD_PTR ref_data);

  void ConfigureOpenPathChannel();
  void HandleDropFiles(HDROP drop);
  void HandleOpenPaths(const std::vector<std::string>& paths);
  std::vector<std::string> ConsumePendingOpenPaths();

  // The project to run.
  flutter::DartProject project_;

  std::vector<std::string> pending_open_paths_;
  bool open_path_listener_ready_ = false;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      open_path_channel_;
  HWND flutter_content_window_ = nullptr;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
