import 'dart:io';

import 'package:flutter/material.dart';
import 'l10n/app_localizations.dart';

enum TimeDisplaySource { capturedAt, modifiedAt }

enum AppLanguage { system, zhHans, english }

extension AppLanguageLocale on AppLanguage {
  Locale? get locale {
    switch (this) {
      case AppLanguage.system:
        return null;
      case AppLanguage.zhHans:
        return const Locale('zh');
      case AppLanguage.english:
        return const Locale('en');
    }
  }
}

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
  final AppLanguage appLanguage;
  final WindowsContextMenuSettings windowsContextMenu;

  const ViewerSettings({
    this.useEmbeddedPreview = false,
    this.halfSize = true,
    this.maxCacheSize = 512,
    this.timeDisplaySource = TimeDisplaySource.capturedAt,
    this.appLanguage = AppLanguage.system,
    this.windowsContextMenu = const WindowsContextMenuSettings(),
  });

  ViewerSettings copyWith({
    bool? useEmbeddedPreview,
    bool? halfSize,
    int? maxCacheSize,
    TimeDisplaySource? timeDisplaySource,
    AppLanguage? appLanguage,
    WindowsContextMenuSettings? windowsContextMenu,
  }) {
    return ViewerSettings(
      useEmbeddedPreview: useEmbeddedPreview ?? this.useEmbeddedPreview,
      halfSize: halfSize ?? this.halfSize,
      maxCacheSize: maxCacheSize ?? this.maxCacheSize,
      timeDisplaySource: timeDisplaySource ?? this.timeDisplaySource,
      appLanguage: appLanguage ?? this.appLanguage,
      windowsContextMenu: windowsContextMenu ?? this.windowsContextMenu,
    );
  }
}

class SettingsPage extends StatefulWidget {
  final ViewerSettings settings;
  final void Function(ViewerSettings?) onClose;
  final WindowsContextMenuToggleHandler? onWindowsContextMenuChanged;
  final ValueChanged<AppLanguage>? onAppLanguageChanged;

  const SettingsPage(
      {super.key,
      required this.settings,
      required this.onClose,
      this.onWindowsContextMenuChanged,
      this.onAppLanguageChanged});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late ViewerSettings _currentSettings;
  bool _isUpdatingWindowsContextMenu = false;

  String _languageLabel(AppLanguage language, AppLocalizations l10n) {
    switch (language) {
      case AppLanguage.system:
        return l10n.languageSystem;
      case AppLanguage.zhHans:
        return l10n.languageChineseSimplified;
      case AppLanguage.english:
        return l10n.languageEnglish;
    }
  }

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

    final l10n = AppLocalizations.of(context)!;

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
            nextState.enabled
                ? l10n.windowsContextMenuEnabledMessage
                : l10n.windowsContextMenuRemovedMessage,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.windowsContextMenuUpdateFailed('$error')),
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
    final l10n = AppLocalizations.of(context)!;

    return ExcludeSemantics(
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.settingsTitle),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              widget.onClose(_currentSettings);
            },
          ),
        ),
        body: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                l10n.languageSectionTitle,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ExcludeSemantics(
              child: Column(
                children: AppLanguage.values
                    .map(
                      (language) => RadioListTile<AppLanguage>(
                        title: Text(_languageLabel(language, l10n)),
                        value: language,
                        groupValue: _currentSettings.appLanguage,
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _currentSettings = _currentSettings.copyWith(
                              appLanguage: value,
                            );
                          });
                          widget.onAppLanguageChanged?.call(value);
                        },
                      ),
                    )
                    .toList(),
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                l10n.previewModeSectionTitle,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ExcludeSemantics(
              child: RadioListTile<bool>(
                title: Text(l10n.embeddedJpegTitle),
                subtitle: Text(l10n.embeddedJpegSubtitle),
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
                title: Text(l10n.loadRawImageTitle),
                subtitle: Text(l10n.loadRawImageSubtitle),
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
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                l10n.rawProcessingSectionTitle,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ExcludeSemantics(
              child: SwitchListTile(
                title: Text(l10n.halfSizeDecodingTitle),
                subtitle: Text(l10n.halfSizeDecodingSubtitle),
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
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                l10n.timeDisplaySectionTitle,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ExcludeSemantics(
              child: RadioListTile<TimeDisplaySource>(
                title: Text(l10n.captureTimeTitle),
                subtitle: Text(l10n.captureTimeSubtitle),
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
                title: Text(l10n.fileModifiedTimeTitle),
                subtitle: Text(l10n.fileModifiedTimeSubtitle),
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
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                l10n.cacheSectionTitle,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              title: Text(l10n.maxCacheSizeTitle),
              subtitle: Text(l10n.cacheSizeMb(_currentSettings.maxCacheSize)),
            ),
            ExcludeSemantics(
              child: Slider(
                value: _currentSettings.maxCacheSize.toDouble(),
                min: 64,
                max: 4096,
                divisions: (4096 - 64) ~/ 64,
                label: l10n.cacheSizeMb(_currentSettings.maxCacheSize),
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
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  l10n.windowsExplorerSectionTitle,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
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
                  title: Text(l10n.windowsContextMenuToggleTitle),
                  subtitle: Text(
                    _currentSettings.windowsContextMenu.enabled
                        ? l10n.windowsContextMenuEnabledSubtitle
                        : l10n.windowsContextMenuDisabledSubtitle,
                  ),
                  value: _currentSettings.windowsContextMenu.enabled,
                  onChanged: _isUpdatingWindowsContextMenu
                      ? null
                      : _handleWindowsContextMenuChanged,
                ),
              ),
              ListTile(
                title: Text(l10n.installScopeTitle),
                subtitle: Text(
                  _currentSettings.windowsContextMenu.enabled
                      ? l10n.installScopeCurrentUser
                      : l10n.installScopeNotInstalled,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
