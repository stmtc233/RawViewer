# Windows Startup Check

Build on Windows with `flutter build windows --release`, then run:

```powershell
.\tool\windows_startup_check.ps1 -ExecutablePath .\build\windows\x64\runner\Release\rawviewer.exe
```

The script reports elapsed time from process launch to detection of its first
visible top-level window, with a polling interval of at least 10 ms. It leaves
the app open. This measures window visibility, not image decoding or the exact
time of the first displayed Flutter frame.

Compare old and new release bundles on the same Windows machine, local disk,
and saved window configuration. Close all Raw Viewer windows before each run.
Keep the first run after reboot separate from repeated launches: subsequent
runs benefit from the Windows file cache and do not measure disk-cold startup.
Use several repeated launches to compare medians; do not mix debug builds in.

Check first launch with no saved position, saved normal bounds (including a
secondary monitor), and saved maximized state. The app should appear with
content, restore to its saved normal bounds when unmaximized, and open its
settings with current file associations. Also test opening a file from Explorer.

Only the Windows runner's automatic first-frame show is removed. Windows now
restores geometry using `prepareWindowsWindow` and shows the window using
`showWindowsWindow` after rasterization. Other platform runners and their
window-manager initialization are unchanged. The Windows path intentionally
skips `waitUntilReadyToShow`: the app does not use its taskbar progress or
taskbar visibility APIs. Adding either requires initializing those APIs first.
