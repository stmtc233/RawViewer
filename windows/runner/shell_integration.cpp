#include "shell_integration.h"

#include <shlobj.h>
#include <windows.h>
#include <shellapi.h>

#include <array>
#include <cctype>
#include <set>
#include <string>
#include <vector>

namespace {

constexpr wchar_t kSelectionVerbKey[] =
    L"Software\\Classes\\*\\shell\\RawViewOpen";
constexpr wchar_t kDirectoryVerbKey[] =
    L"Software\\Classes\\Directory\\shell\\RawViewOpen";
constexpr wchar_t kDirectoryBackgroundVerbKey[] =
    L"Software\\Classes\\Directory\\Background\\shell\\RawViewOpen";

constexpr std::array<const wchar_t*, 13> kFileAssociationExtensions = {{
    L"arw", L"cr2", L"cr3", L"dng", L"nef", L"orf", L"raf",
    L"rw2", L"srw", L"jpg", L"jpeg", L"png", L"webp",
}};

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

std::wstring FileAssociationProgId(const wchar_t* extension) {
  return std::wstring(L"RawViewer.") + extension;
}

std::wstring FileAssociationExtensionKey(const wchar_t* extension) {
  return std::wstring(L"Software\\Classes\\.") + extension;
}

std::wstring FileAssociationProgIdKey(const wchar_t* extension) {
  return std::wstring(L"Software\\Classes\\") +
         FileAssociationProgId(extension);
}

std::wstring FileAssociationCommand(const std::wstring& executable_path) {
  return Quote(executable_path) + L" \"%1\"";
}

std::string NarrowExtension(const wchar_t* extension) {
  std::string result;
  for (const auto* character = extension; *character != L'\0'; ++character) {
    result.push_back(static_cast<char>(*character));
  }
  return result;
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
               const std::wstring& executable_path,
               const std::wstring& menu_text) {
  const std::wstring command =
      BuildCommand(executable_path, definition.background);
  const std::wstring icon_value = Quote(executable_path);

  if (!SetStringValue(HKEY_CURRENT_USER, definition.key_path, nullptr,
                      menu_text)) {
    return false;
  }
  if (!SetStringValue(HKEY_CURRENT_USER, definition.key_path, L"MUIVerb",
                      menu_text)) {
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

bool IsFileAssociationInstalled(const wchar_t* extension,
                                const std::wstring& executable_path) {
  std::wstring prog_id;
  if (!ReadStringValue(HKEY_CURRENT_USER,
                       FileAssociationExtensionKey(extension), nullptr,
                       &prog_id) ||
      _wcsicmp(prog_id.c_str(), FileAssociationProgId(extension).c_str()) !=
          0) {
    return false;
  }

  std::wstring command;
  if (!ReadStringValue(
          HKEY_CURRENT_USER,
          FileAssociationProgIdKey(extension) + L"\\shell\\open\\command",
          nullptr, &command)) {
    return false;
  }

  return _wcsicmp(command.c_str(),
                  FileAssociationCommand(executable_path).c_str()) == 0;
}

bool WriteFileAssociation(const wchar_t* extension,
                          const std::wstring& executable_path) {
  const auto prog_id = FileAssociationProgId(extension);
  const auto prog_id_key = FileAssociationProgIdKey(extension);
  if (!SetStringValue(HKEY_CURRENT_USER, prog_id_key, nullptr,
                      L"Raw Viewer image")) {
    return false;
  }
  if (!SetStringValue(HKEY_CURRENT_USER, prog_id_key + L"\\DefaultIcon",
                      nullptr, Quote(executable_path) + L",0")) {
    return false;
  }
  if (!SetStringValue(HKEY_CURRENT_USER,
                      prog_id_key + L"\\shell\\open\\command", nullptr,
                      FileAssociationCommand(executable_path))) {
    return false;
  }
  return SetStringValue(HKEY_CURRENT_USER,
                        FileAssociationExtensionKey(extension), nullptr,
                        prog_id);
}

bool RemoveFileAssociation(const wchar_t* extension) {
  std::wstring current_prog_id;
  const auto extension_key = FileAssociationExtensionKey(extension);
  if (ReadStringValue(HKEY_CURRENT_USER, extension_key, nullptr,
                      &current_prog_id) &&
      _wcsicmp(current_prog_id.c_str(),
               FileAssociationProgId(extension).c_str()) == 0) {
    HKEY key = nullptr;
    const LONG open_result = ::RegOpenKeyExW(
        HKEY_CURRENT_USER, extension_key.c_str(), 0, KEY_SET_VALUE, &key);
    if (open_result != ERROR_SUCCESS) {
      return open_result == ERROR_FILE_NOT_FOUND;
    }
    const LONG delete_result = ::RegDeleteValueW(key, nullptr);
    ::RegCloseKey(key);
    if (delete_result != ERROR_SUCCESS && delete_result != ERROR_FILE_NOT_FOUND) {
      return false;
    }
  }

  const LONG delete_prog_id_result =
      ::RegDeleteTreeW(HKEY_CURRENT_USER,
                       FileAssociationProgIdKey(extension).c_str());
  return delete_prog_id_result == ERROR_SUCCESS ||
         delete_prog_id_result == ERROR_FILE_NOT_FOUND;
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

bool SetWindowsContextMenuEnabled(bool enabled, const std::wstring& menu_text,
                                  std::string* error_message) {
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
    if (!WriteVerb(definition, executable_path, menu_text)) {
      if (error_message != nullptr) {
        *error_message = "Failed to write Windows Explorer context menu registry entries.";
      }
      return false;
    }
  }

  NotifyShellChanged();
  return true;
}

flutter::EncodableMap GetWindowsFileAssociationState() {
  const std::wstring executable_path = GetExecutablePath();
  flutter::EncodableMap bindings;
  for (const auto* extension : kFileAssociationExtensions) {
    bindings.emplace(
        flutter::EncodableValue("." + NarrowExtension(extension)),
        flutter::EncodableValue(
            !executable_path.empty() &&
            IsFileAssociationInstalled(extension, executable_path)));
  }
  return flutter::EncodableMap{
      {flutter::EncodableValue("supported"), flutter::EncodableValue(true)},
      {flutter::EncodableValue("bindings"), flutter::EncodableValue(bindings)},
  };
}

bool SetWindowsFileAssociations(const std::vector<std::string>& extensions,
                                std::string* error_message) {
  const std::wstring executable_path = GetExecutablePath();
  if (executable_path.empty()) {
    if (error_message != nullptr) {
      *error_message = "Unable to resolve the current executable path.";
    }
    return false;
  }

  std::set<std::string> selected;
  for (auto extension : extensions) {
    if (!extension.empty() && extension.front() == '.') {
      extension.erase(extension.begin());
    }
    for (auto& character : extension) {
      character = static_cast<char>(std::tolower(
          static_cast<unsigned char>(character)));
    }
    selected.insert(extension);
  }

  for (const auto* extension : kFileAssociationExtensions) {
    const std::string extension_utf8 = NarrowExtension(extension);
    const bool should_install = selected.find(extension_utf8) != selected.end();
    const bool success = should_install
                             ? WriteFileAssociation(extension, executable_path)
                             : RemoveFileAssociation(extension);
    if (!success) {
      if (error_message != nullptr) {
        *error_message =
            "Failed to update Windows file association registry entries.";
      }
      return false;
    }
  }

  NotifyShellChanged();
  return true;
}
