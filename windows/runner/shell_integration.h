#ifndef RUNNER_SHELL_INTEGRATION_H_
#define RUNNER_SHELL_INTEGRATION_H_

#include <flutter/encodable_value.h>

#include <string>

flutter::EncodableMap GetWindowsContextMenuState();
bool SetWindowsContextMenuEnabled(bool enabled, std::string* error_message);

#endif  // RUNNER_SHELL_INTEGRATION_H_
