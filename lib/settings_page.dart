import 'dart:io';

import 'package:flutter/material.dart';

enum TimeDisplaySource { capturedAt, modifiedAt }

class WindowsContextMenuSettings {
  final bool supported;
  final bool enabled;

  const WindowsContextMenuSettings({
    this.supported = false,
    this.enabled = false,
  });

  WindowsContextMenuSettings copyWith({
    bool? supported,
    bool? enabled,
  }) {
    return WindowsContextMenuSettings(
      supported: supported ?? this.supported,
      enabled: enabled ?? this.enabled,
    );
  }

  factory WindowsContextMenuSettings.fromPlatformMap(
    Map<Object?, Object?>? values,
  ) {
    return WindowsContextMenuSettings(
      supported: values?['supported'] == true,
      enabled: values?['enabled'] == true,
    );
  }
}

typedef WindowsContextMenuToggleHandler = Future<WindowsContextMenuSettings>
    Function(bool enabled);

class ViewerSettings {
  final bool useEmbeddedPreview;
  final bool halfSize;
  final int maxCacheSize; // in MB
  final TimeDisplaySource timeDisplaySource;
  final WindowsContextMenuSettings windowsContextMenu;

  const ViewerSettings({
    this.useEmbeddedPreview = false,
    this.halfSize = true,
    this.maxCacheSize = 512,
    this.timeDisplaySource = TimeDisplaySource.capturedAt,
    this.windowsContextMenu = const WindowsContextMenuSettings(),
  });

  ViewerSettings copyWith({
    bool? useEmbeddedPreview,
    bool? halfSize,
    int? maxCacheSize,
    TimeDisplaySource? timeDisplaySource,
    WindowsContextMenuSettings? windowsContextMenu,
  }) {
    return ViewerSettings(
      useEmbeddedPreview: useEmbeddedPreview ?? this.useEmbeddedPreview,
      halfSize: halfSize ?? this.halfSize,
      maxCacheSize: maxCacheSize ?? this.maxCacheSize,
      timeDisplaySource: timeDisplaySource ?? this.timeDisplaySource,
      windowsContextMenu: windowsContextMenu ?? this.windowsContextMenu,
    );
  }
}

class SettingsPage extends StatefulWidget {
  final ViewerSettings settings;
  final void Function(ViewerSettings?) onClose;
  final WindowsContextMenuToggleHandler? onWindowsContextMenuChanged;

  const SettingsPage(
      {super.key,
      required this.settings,
      required this.onClose,
      this.onWindowsContextMenuChanged});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late ViewerSettings _currentSettings;
  bool _isUpdatingWindowsContextMenu = false;

  @override
  void initState() {
    super.initState();
    _currentSettings = widget.settings;
  }

  bool get _showWindowsContextMenuSection =>
      Platform.isWindows && widget.onWindowsContextMenuChanged != null;

  Future<void> _handleWindowsContextMenuChanged(bool enabled) async {
    final onWindowsContextMenuChanged = widget.onWindowsContextMenuChanged;
    if (onWindowsContextMenuChanged == null || _isUpdatingWindowsContextMenu) {
      return;
    }

    setState(() {
      _isUpdatingWindowsContextMenu = true;
    });

    try {
      final nextState = await onWindowsContextMenuChanged(enabled);
      if (!mounted) {
        return;
      }

      setState(() {
        _currentSettings = _currentSettings.copyWith(
          windowsContextMenu: nextState,
        );
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextState.enabled ? '已启用“在RawView中打开”右键菜单' : '已移除“在RawView中打开”右键菜单',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('更新 Windows 右键菜单失败：$error'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingWindowsContextMenu = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Settings'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              widget.onClose(_currentSettings);
            },
          ),
        ),
        body: ListView(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Preview Mode',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ExcludeSemantics(
              child: RadioListTile<bool>(
                title: const Text('Embedded JPEG'),
                subtitle: const Text('Fast preview, lower quality'),
                value: true,
                groupValue: _currentSettings.useEmbeddedPreview,
                onChanged: (value) {
                  setState(() {
                    _currentSettings =
                        _currentSettings.copyWith(useEmbeddedPreview: value);
                  });
                },
              ),
            ),
            ExcludeSemantics(
              child: RadioListTile<bool>(
                title: const Text('Load RAW Image'),
                subtitle: const Text('High quality, slower'),
                value: false,
                groupValue: _currentSettings.useEmbeddedPreview,
                onChanged: (value) {
                  setState(() {
                    _currentSettings =
                        _currentSettings.copyWith(useEmbeddedPreview: value);
                  });
                },
              ),
            ),
            const Divider(),
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'RAW Processing',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ExcludeSemantics(
              child: SwitchListTile(
                title: const Text('Half Size Decoding'),
                subtitle: const Text(
                    'Faster decoding, 50% resolution. Disable for full resolution.'),
                value: _currentSettings.halfSize,
                onChanged: (value) {
                  setState(() {
                    _currentSettings =
                        _currentSettings.copyWith(halfSize: value);
                  });
                },
              ),
            ),
            const Divider(),
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Time Display',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ExcludeSemantics(
              child: RadioListTile<TimeDisplaySource>(
                title: const Text('Capture Time'),
                subtitle:
                    const Text('Prefer EXIF or RAW metadata capture time'),
                value: TimeDisplaySource.capturedAt,
                groupValue: _currentSettings.timeDisplaySource,
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _currentSettings =
                        _currentSettings.copyWith(timeDisplaySource: value);
                  });
                },
              ),
            ),
            ExcludeSemantics(
              child: RadioListTile<TimeDisplaySource>(
                title: const Text('File Modified Time'),
                subtitle:
                    const Text('Use file system last modified time directly'),
                value: TimeDisplaySource.modifiedAt,
                groupValue: _currentSettings.timeDisplaySource,
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _currentSettings =
                        _currentSettings.copyWith(timeDisplaySource: value);
                  });
                },
              ),
            ),
            const Divider(),
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Cache',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              title: const Text('Max Cache Size'),
              subtitle: Text('${_currentSettings.maxCacheSize} MB'),
            ),
            ExcludeSemantics(
              child: Slider(
                value: _currentSettings.maxCacheSize.toDouble(),
                min: 64,
                max: 4096,
                divisions: (4096 - 64) ~/ 64,
                label: '${_currentSettings.maxCacheSize} MB',
                onChanged: (value) {
                  setState(() {
                    _currentSettings =
                        _currentSettings.copyWith(maxCacheSize: value.toInt());
                  });
                },
              ),
            ),
            if (_showWindowsContextMenuSection) ...[
              const Divider(),
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Windows Explorer',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              ExcludeSemantics(
                child: SwitchListTile(
                  secondary: _isUpdatingWindowsContextMenu
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.desktop_windows),
                  title: const Text('显示“在RawView中打开”'),
                  subtitle: Text(
                    _currentSettings.windowsContextMenu.enabled
                        ? '已安装到当前用户。支持文件、多个文件、文件夹，以及文件夹空白处右键打开。'
                        : '启用后可在资源管理器中通过右键“在RawView中打开”直接打开文件、多个文件、文件夹或当前目录。',
                  ),
                  value: _currentSettings.windowsContextMenu.enabled,
                  onChanged: _isUpdatingWindowsContextMenu
                      ? null
                      : _handleWindowsContextMenuChanged,
                ),
              ),
              ListTile(
                title: const Text('安装范围'),
                subtitle: Text(
                  _currentSettings.windowsContextMenu.enabled
                      ? '当前用户（HKCU）'
                      : '未安装',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
