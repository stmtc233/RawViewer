#include "shell_integration.h"

#include <shlobj.h>
#include <windows.h>
#include <shellapi.h>

#include <array>
#include <string>

namespace {

constexpr wchar_t kMenuText[] = L"\x5728RawView\x4E2D\x6253\x5F00";
constexpr wchar_t kSelectionVerbKey[] =
    L"Software\\Classes\\*\\shell\\RawViewOpen";
constexpr wchar_t kDirectoryVerbKey[] =
    L"Software\\Classes\\Directory\\shell\\RawViewOpen";
constexpr wchar_t kDirectoryBackgroundVerbKey[] =
    L"Software\\Classes\\Directory\\Background\\shell\\RawViewOpen";

struct ContextMenuState {
  bool supported;
  bool enabled;
};

struct VerbDefinition {
  const wchar_t* key_path;
  bool multi_select;
  bool background;
};

constexpr std::array<VerbDefinition, 3> kVerbDefinitions = {{
    {kSelectionVerbKey, true, false},
    {kDirectoryVerbKey, true, false},
    {kDirectoryBackgroundVerbKey, false, true},
}};

std::wstring GetExecutablePath() {
  std::wstring path(MAX_PATH, L'\0');

  while (true) {
    const DWORD copied = ::GetModuleFileNameW(nullptr, path.data(),
                                              static_cast<DWORD>(path.size()));
    if (copied == 0) {
      return L"";
    }

    if (copied < path.size() - 1) {
      path.resize(copied);
      return path;
    }

    path.resize(path.size() * 2);
  }
}

std::wstring Quote(const std::wstring& value) {
  return L"\"" + value + L"\"";
}

std::wstring BuildCommand(const std::wstring& executable_path,
                          bool background) {
  if (background) {
    return Quote(executable_path) + L" \"%V\"";
  }
  return Quote(executable_path) + L" \"%1\"";
}

bool SetStringValue(HKEY root, const std::wstring& sub_key,
                    const wchar_t* value_name, const std::wstring& value) {
  HKEY key = nullptr;
  const LONG create_result = ::RegCreateKeyExW(
      root, sub_key.c_str(), 0, nullptr, REG_OPTION_NON_VOLATILE, KEY_SET_VALUE,
      nullptr, &key, nullptr);
  if (create_result != ERROR_SUCCESS) {
    return false;
  }

  const DWORD data_size =
      static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t));
  const LONG set_result = ::RegSetValueExW(
      key, value_name, 0, REG_SZ,
      reinterpret_cast<const BYTE*>(value.c_str()), data_size);
  ::RegCloseKey(key);
  return set_result == ERROR_SUCCESS;
}

bool ReadStringValue(HKEY root, const std::wstring& sub_key,
                     const wchar_t* value_name, std::wstring* value) {
  HKEY key = nullptr;
  const LONG open_result =
      ::RegOpenKeyExW(root, sub_key.c_str(), 0, KEY_QUERY_VALUE, &key);
  if (open_result != ERROR_SUCCESS) {
    return false;
  }

  DWORD type = 0;
  DWORD data_size = 0;
  LONG query_result =
      ::RegQueryValueExW(key, value_name, nullptr, &type, nullptr, &data_size);
  if (query_result != ERROR_SUCCESS ||
      (type != REG_SZ && type != REG_EXPAND_SZ) || data_size == 0) {
    ::RegCloseKey(key);
    return false;
  }

  std::wstring buffer(data_size / sizeof(wchar_t), L'\0');
  query_result = ::RegQueryValueExW(
      key, value_name, nullptr, &type,
      reinterpret_cast<LPBYTE>(buffer.data()), &data_size);
  ::RegCloseKey(key);
  if (query_result != ERROR_SUCCESS) {
    return false;
  }

  const size_t null_index = buffer.find(L'\0');
  if (null_index != std::wstring::npos) {
    buffer.resize(null_index);
  }

  *value = std::move(buffer);
  return true;
}

bool WriteVerb(const VerbDefinition& definition,
               const std::wstring& executable_path) {
  const std::wstring command =
      BuildCommand(executable_path, definition.background);
  const std::wstring icon_value = Quote(executable_path);

  if (!SetStringValue(HKEY_CURRENT_USER, definition.key_path, nullptr,
                      kMenuText)) {
    return false;
  }
  if (!SetStringValue(HKEY_CURRENT_USER, definition.key_path, L"MUIVerb",
                      kMenuText)) {
    return false;
  }
  if (!SetStringValue(HKEY_CURRENT_USER, definition.key_path, L"Icon",
                      icon_value)) {
    return false;
  }
  if (definition.multi_select &&
      !SetStringValue(HKEY_CURRENT_USER, definition.key_path,
                      L"MultiSelectModel", L"Player")) {
    return false;
  }

  return SetStringValue(HKEY_CURRENT_USER,
                        std::wstring(definition.key_path) + L"\\command",
                        nullptr, command);
}

bool IsVerbInstalled(const VerbDefinition& definition,
                     const std::wstring& executable_path) {
  std::wstring menu_text;
  if (!ReadStringValue(HKEY_CURRENT_USER, definition.key_path, nullptr,
                       &menu_text) ||
      menu_text != kMenuText) {
    if (!ReadStringValue(HKEY_CURRENT_USER, definition.key_path, L"MUIVerb",
                         &menu_text) ||
        menu_text != kMenuText) {
      return false;
    }
  }

  if (definition.multi_select) {
    std::wstring multi_select_model;
    if (!ReadStringValue(HKEY_CURRENT_USER, definition.key_path,
                         L"MultiSelectModel", &multi_select_model) ||
        _wcsicmp(multi_select_model.c_str(), L"Player") != 0) {
      return false;
    }
  }

  std::wstring command;
  if (!ReadStringValue(HKEY_CURRENT_USER,
                       std::wstring(definition.key_path) + L"\\command",
                       nullptr, &command)) {
    return false;
  }

  const std::wstring expected_command =
      BuildCommand(executable_path, definition.background);
  return _wcsicmp(command.c_str(), expected_command.c_str()) == 0;
}

void NotifyShellChanged() {
  ::SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
}

ContextMenuState QueryContextMenuState() {
  const std::wstring executable_path = GetExecutablePath();
  if (executable_path.empty()) {
    return ContextMenuState{true, false};
  }

  for (const auto& definition : kVerbDefinitions) {
    if (!IsVerbInstalled(definition, executable_path)) {
      return ContextMenuState{true, false};
    }
  }

  return ContextMenuState{true, true};
}

}  // namespace

flutter::EncodableMap GetWindowsContextMenuState() {
  const ContextMenuState state = QueryContextMenuState();
  return flutter::EncodableMap{
      {flutter::EncodableValue("supported"),
       flutter::EncodableValue(state.supported)},
      {flutter::EncodableValue("enabled"),
       flutter::EncodableValue(state.enabled)},
  };
}

bool SetWindowsContextMenuEnabled(bool enabled, std::string* error_message) {
  if (!enabled) {
    for (const auto& definition : kVerbDefinitions) {
      const LONG result =
          ::RegDeleteTreeW(HKEY_CURRENT_USER, definition.key_path);
      if (result != ERROR_SUCCESS && result != ERROR_FILE_NOT_FOUND) {
        if (error_message != nullptr) {
          *error_message = "Failed to remove Windows Explorer context menu registry entries.";
        }
        return false;
      }
    }
    NotifyShellChanged();
    return true;
  }

  const std::wstring executable_path = GetExecutablePath();
  if (executable_path.empty()) {
    if (error_message != nullptr) {
      *error_message = "Unable to resolve the current executable path.";
    }
    return false;
  }

  for (const auto& definition : kVerbDefinitions) {
    if (!WriteVerb(definition, executable_path)) {
      if (error_message != nullptr) {
        *error_message = "Failed to write Windows Explorer context menu registry entries.";
      }
      return false;
    }
  }

  NotifyShellChanged();
  return true;
}
