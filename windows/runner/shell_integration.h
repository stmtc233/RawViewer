#ifndef RUNNER_SHELL_INTEGRATION_H_
#define RUNNER_SHELL_INTEGRATION_H_

#include <flutter/encodable_value.h>

#include <string>
#include <vector>

flutter::EncodableMap GetWindowsContextMenuState();
bool SetWindowsContextMenuEnabled(bool enabled, const std::wstring& menu_text,
                                  std::string* error_message);
flutter::EncodableMap GetWindowsFileAssociationState();
bool SetWindowsFileAssociations(
    const std::vector<std::string>& extensions,
    std::string* error_message);

#endif  // RUNNER_SHELL_INTEGRATION_H_
