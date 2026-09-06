#include <windows.h>
#include <shlobj.h>
#include <shellapi.h>
#include <shlwapi.h>

#include <iostream>
#include <stdexcept>
#include <string>

namespace {

int notifications = 0;
int writes = 0;

void RecordShellChange(LONG, UINT, LPCVOID, LPCVOID) {
  ++notifications;
}

LSTATUS RecordRegistryWrite(HKEY key, LPCWSTR name, DWORD reserved, DWORD type,
                            const BYTE* data, DWORD size) {
  ++writes;
  return ::RegSetValueExW(key, name, reserved, type, data, size);
}

void Require(bool condition, const char* message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

// All registry access is redirected to a disposable, process-local HKCU tree.
class IsolatedRegistry {
 public:
  IsolatedRegistry() {
    path_ = L"Software\\RawViewerShellCheck-" +
            std::to_wstring(::GetCurrentProcessId()) + L"-" +
            std::to_wstring(::GetTickCount64());
    Require(::RegCreateKeyExW(HKEY_CURRENT_USER, path_.c_str(), 0, nullptr,
                             REG_OPTION_NON_VOLATILE, KEY_ALL_ACCESS, nullptr,
                             &key_, nullptr) == ERROR_SUCCESS,
            "Cannot create test registry");
    if (::RegOverridePredefKey(HKEY_CURRENT_USER, key_) != ERROR_SUCCESS) {
      ::RegCloseKey(key_);
      ::RegDeleteTreeW(HKEY_CURRENT_USER, path_.c_str());
      throw std::runtime_error("Cannot isolate HKCU");
    }
  }

  ~IsolatedRegistry() {
    ::RegOverridePredefKey(HKEY_CURRENT_USER, nullptr);
    ::RegCloseKey(key_);
    ::RegDeleteTreeW(HKEY_CURRENT_USER, path_.c_str());
  }

 private:
  HKEY key_ = nullptr;
  std::wstring path_;
};

}  // namespace

// Exercise the production implementation, but never send real Shell refreshes.
#define SHChangeNotify RecordShellChange
#define RegSetValueExW RecordRegistryWrite
#include "../../windows/runner/shell_integration.cpp"
#undef RegSetValueExW
#undef SHChangeNotify

namespace {

void CheckSync(const std::wstring& label, bool expect_change) {
  notifications = 0;
  writes = 0;
  std::string error;
  const bool success = SetWindowsContextMenuEnabled(true, label, &error);
  Require(success, error.c_str());
  Require(notifications == (expect_change ? 1 : 0),
          "Unexpected Shell refresh count");
  Require(expect_change ? writes > 0 : writes == 0,
          "Unexpected registry writes");
  Require(QueryContextMenuState().enabled, "Context menu is not installed");
}

void CheckRepair(const std::wstring& path, const wchar_t* name,
                 const std::wstring& expected, const std::wstring& label) {
  Require(SetStringValue(HKEY_CURRENT_USER, path, name, L"stale"),
          "Cannot seed stale registry value");
  CheckSync(label, true);
  std::wstring actual;
  Require(ReadStringValue(HKEY_CURRENT_USER, path, name, &actual) &&
              actual == expected,
          "Stale registry value was not repaired");
  CheckSync(label, false);
}

}  // namespace

int main() {
  try {
    IsolatedRegistry registry;
    const std::wstring label = L"Open in RawView";
    CheckSync(label, true);
    // No in-memory sync cache: another launch sees the same persisted values.
    CheckSync(label, false);
    const std::wstring translated = L"\u5728 RawView \u4e2d\u6253\u5f00";
    CheckSync(translated, true);
    CheckSync(translated, false);

    const auto executable = GetExecutablePath();
    for (const auto& definition : kVerbDefinitions) {
      CheckRepair(definition.key_path, nullptr, translated, translated);
      CheckRepair(definition.key_path, L"MUIVerb", translated, translated);
      CheckRepair(definition.key_path, L"Icon", Quote(executable), translated);
      CheckRepair(std::wstring(definition.key_path) + L"\\command", nullptr,
                  BuildCommand(executable, definition.background), translated);
      if (definition.multi_select) {
        CheckRepair(definition.key_path, L"MultiSelectModel", L"Player",
                    translated);
      }
      Require(::RegDeleteTreeW(HKEY_CURRENT_USER, definition.key_path) ==
                  ERROR_SUCCESS,
              "Cannot remove test verb");
      CheckSync(translated, true);
      CheckSync(translated, false);
    }

    std::string error;
    notifications = 0;
    const bool success =
        SetWindowsContextMenuEnabled(false, translated, &error);
    Require(success, error.c_str());
    Require(notifications == 1 && !QueryContextMenuState().enabled,
            "Disabling the context menu failed");
    CheckSync(translated, true);
    CheckSync(translated, false);
    std::cout << "Windows Shell checks passed.\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
