cmake_minimum_required(VERSION 3.14)
project(windows_shell_integration_check LANGUAGES CXX)

# Run after flutter build windows has populated the client wrapper headers.
add_executable(windows_shell_integration_check main.cpp)
target_compile_features(windows_shell_integration_check PRIVATE cxx_std_17)
target_compile_definitions(windows_shell_integration_check PRIVATE NOMINMAX)
target_include_directories(windows_shell_integration_check PRIVATE
  "../../windows/flutter/ephemeral/cpp_client_wrapper/include"
)
target_link_libraries(windows_shell_integration_check PRIVATE
  advapi32 shell32 shlwapi
)
