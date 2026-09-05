import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'core/media_types.dart';
import 'core/preview_filmstrip_size.dart';
import 'core/raw_view_mode.dart';
import 'l10n/app_localizations.dart';
import 'ui/app_theme.dart';
import 'ui/desktop_controls.dart';

enum TimeDisplaySource { capturedAt, modifiedAt }

enum AppLanguage { system, zhHans, english }

const double kDefaultPreviewOverlayOpacity = 0.42;
const double kMinPreviewOverlayOpacity = 0.2;
const double kMaxPreviewOverlayOpacity = 1.0;
const int kPreviewOverlayOpacityDivisions = 80;

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

enum GridAspectRatio { adaptive, ratio1x1, ratio3x2, ratio4x3, ratio16x9 }

extension GridAspectRatioValue on GridAspectRatio {
  bool get isAdaptive => this == GridAspectRatio.adaptive;

  double get aspectRatio {
    switch (this) {
      case GridAspectRatio.adaptive:
        // Used as the placeholder ratio until a thumbnail reports its size.
        return 3 / 2;
      case GridAspectRatio.ratio1x1:
        return 1.0;
      case GridAspectRatio.ratio3x2:
        return 3 / 2;
      case GridAspectRatio.ratio4x3:
        return 4 / 3;
      case GridAspectRatio.ratio16x9:
        return 16 / 9;
    }
  }

  String get label {
    switch (this) {
      case GridAspectRatio.adaptive:
        return 'Adaptive';
      case GridAspectRatio.ratio1x1:
        return '1:1';
      case GridAspectRatio.ratio3x2:
        return '3:2';
      case GridAspectRatio.ratio4x3:
        return '4:3';
      case GridAspectRatio.ratio16x9:
        return '16:9';
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

class FileAssociationSettings {
  final bool supported;
  final bool requiresSystemSettings;
  final Map<String, bool> bindings;

  const FileAssociationSettings({
    this.supported = false,
    this.requiresSystemSettings = false,
    this.bindings = const <String, bool>{},
  });

  bool isBound(String extension) => bindings[extension] == true;

  FileAssociationSettings copyWith({
    bool? supported,
    bool? requiresSystemSettings,
    Map<String, bool>? bindings,
  }) {
    return FileAssociationSettings(
      supported: supported ?? this.supported,
      requiresSystemSettings:
          requiresSystemSettings ?? this.requiresSystemSettings,
      bindings: bindings ?? this.bindings,
    );
  }

  factory FileAssociationSettings.fromPlatformMap(
    Map<Object?, Object?>? values,
  ) {
    final rawBindings = values?['bindings'];
    final bindings = <String, bool>{};
    if (rawBindings is Map) {
      for (final extension in supportedExtensions) {
        bindings[extension] = rawBindings[extension] == true;
      }
    }
    return FileAssociationSettings(
      supported: values?['supported'] == true,
      requiresSystemSettings: values?['requiresSystemSettings'] == true,
      bindings: bindings,
    );
  }
}

typedef FileAssociationChangeHandler = Future<FileAssociationSettings> Function(
    Set<String> extensions);

class ViewerSettings {
  // Which image the preview shows for RAW files. Chosen from the preview's own
  // top-right switch rather than this settings page, and persisted.
  final RawViewMode rawViewMode;
  // Controls the decoded RAW layer only. This does not affect the thumbnail
  // layer shown first while browsing RAW files.
  final bool useHalfSizeRawDecode;
  final int maxCacheSize; // in MB
  final TimeDisplaySource timeDisplaySource;
  final AppLanguage appLanguage;
  final GridAspectRatio gridAspectRatio;
  // Applies to discrete mouse-wheel page changes. Touch and trackpad
  // navigation remain directly controlled by the PageView.
  final bool pageSwitchAnimationEnabled;
  // Resting opacities for tools/overview, the top bar, and the filmstrip.
  final double previewOverlayOpacity;
  final double previewToolbarOpacity;
  final double previewFilmstripOpacity;
  final double previewFilmstripHeight;
  final WindowsContextMenuSettings windowsContextMenu;
  final FileAssociationSettings fileAssociations;

  const ViewerSettings({
    this.rawViewMode = RawViewMode.decodedRaw,
    this.useHalfSizeRawDecode = true,
    this.maxCacheSize = 512,
    this.timeDisplaySource = TimeDisplaySource.capturedAt,
    this.appLanguage = AppLanguage.system,
    this.gridAspectRatio = GridAspectRatio.ratio3x2,
    this.pageSwitchAnimationEnabled = true,
    this.previewOverlayOpacity = kDefaultPreviewOverlayOpacity,
    this.previewToolbarOpacity = kDefaultPreviewOverlayOpacity,
    this.previewFilmstripOpacity = kDefaultPreviewOverlayOpacity,
    this.previewFilmstripHeight = kPreviewFilmstripHeight,
    this.windowsContextMenu = const WindowsContextMenuSettings(),
    this.fileAssociations = const FileAssociationSettings(),
  });

  ViewerSettings copyWith({
    RawViewMode? rawViewMode,
    bool? useHalfSizeRawDecode,
    int? maxCacheSize,
    TimeDisplaySource? timeDisplaySource,
    AppLanguage? appLanguage,
    GridAspectRatio? gridAspectRatio,
    bool? pageSwitchAnimationEnabled,
    double? previewOverlayOpacity,
    double? previewToolbarOpacity,
    double? previewFilmstripOpacity,
    double? previewFilmstripHeight,
    WindowsContextMenuSettings? windowsContextMenu,
    FileAssociationSettings? fileAssociations,
  }) {
    return ViewerSettings(
      rawViewMode: rawViewMode ?? this.rawViewMode,
      useHalfSizeRawDecode: useHalfSizeRawDecode ?? this.useHalfSizeRawDecode,
      maxCacheSize: maxCacheSize ?? this.maxCacheSize,
      timeDisplaySource: timeDisplaySource ?? this.timeDisplaySource,
      appLanguage: appLanguage ?? this.appLanguage,
      gridAspectRatio: gridAspectRatio ?? this.gridAspectRatio,
      pageSwitchAnimationEnabled:
          pageSwitchAnimationEnabled ?? this.pageSwitchAnimationEnabled,
      previewOverlayOpacity:
          previewOverlayOpacity ?? this.previewOverlayOpacity,
      previewToolbarOpacity:
          previewToolbarOpacity ?? this.previewToolbarOpacity,
      previewFilmstripOpacity:
          previewFilmstripOpacity ?? this.previewFilmstripOpacity,
      previewFilmstripHeight:
          previewFilmstripHeight ?? this.previewFilmstripHeight,
      windowsContextMenu: windowsContextMenu ?? this.windowsContextMenu,
      fileAssociations: fileAssociations ?? this.fileAssociations,
    );
  }
}

class SettingsPage extends StatefulWidget {
  final ViewerSettings settings;
  final VoidCallback onClose;
  final ValueChanged<ViewerSettings> onSettingsChanged;
  final WindowsContextMenuToggleHandler? onWindowsContextMenuChanged;
  final FileAssociationChangeHandler? onFileAssociationsChanged;
  final Future<void> Function()? onOpenDefaultAppsSettings;
  final Future<FileAssociationSettings> Function()? onRefreshFileAssociations;

  const SettingsPage({
    super.key,
    required this.settings,
    required this.onClose,
    required this.onSettingsChanged,
    this.onWindowsContextMenuChanged,
    this.onFileAssociationsChanged,
    this.onOpenDefaultAppsSettings,
    this.onRefreshFileAssociations,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with WidgetsBindingObserver {
  late ViewerSettings _currentSettings;
  bool _isUpdatingWindowsContextMenu = false;
  bool _isUpdatingFileAssociations = false;

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
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshFileAssociations());
    }
  }

  void _updateSettings(ViewerSettings settings) {
    setState(() {
      _currentSettings = settings;
    });
    widget.onSettingsChanged(settings);
  }

  bool get _showWindowsContextMenuSection =>
      Platform.isWindows && widget.onWindowsContextMenuChanged != null;

  bool get _showFileAssociationSection =>
      (widget.onFileAssociationsChanged != null ||
          widget.onOpenDefaultAppsSettings != null) &&
      _currentSettings.fileAssociations.supported;

  List<Widget> _withDividers(List<Widget> children) {
    return [
      for (var index = 0; index < children.length; index++) ...[
        if (index > 0) const Divider(height: 1),
        children[index],
      ],
    ];
  }

  Widget _buildOpacityRow({
    required String key,
    required String title,
    String? subtitle,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final percent = l10n.previewOverlayOpacityPercent((value * 100).round());
    return DesktopSettingsRow(
      key: ValueKey(key),
      title: title,
      subtitle: subtitle,
      control: SizedBox(
        width: 190,
        child: Row(
          children: [
            Expanded(
              child: Slider(
                value: value,
                min: kMinPreviewOverlayOpacity,
                max: kMaxPreviewOverlayOpacity,
                divisions: kPreviewOverlayOpacityDivisions,
                label: percent,
                onChanged: onChanged,
              ),
            ),
            SizedBox(
              width: 42,
              child: Text(
                percent,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: RawViewerColors.text,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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

      _updateSettings(
        _currentSettings.copyWith(windowsContextMenu: nextState),
      );

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

  Future<void> _handleFileAssociationChanged(
    String extension,
    bool enabled,
  ) async {
    final nextBindings = Map<String, bool>.from(
      _currentSettings.fileAssociations.bindings,
    )..[extension] = enabled;
    await _updateFileAssociations({
      for (final supportedExtension in supportedExtensions)
        if (nextBindings[supportedExtension] == true) supportedExtension,
    });
  }

  Future<void> _updateFileAssociations(Set<String> extensions) async {
    final onFileAssociationsChanged = widget.onFileAssociationsChanged;
    if (onFileAssociationsChanged == null || _isUpdatingFileAssociations) {
      return;
    }

    setState(() {
      _isUpdatingFileAssociations = true;
    });

    try {
      final nextState = await onFileAssociationsChanged(extensions);
      if (!mounted) return;
      _updateSettings(_currentSettings.copyWith(fileAssociations: nextState));
    } catch (error) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.fileAssociationsUpdateFailed('$error'))),
      );
      await _refreshFileAssociations();
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingFileAssociations = false;
        });
      }
    }
  }

  Future<void> _refreshFileAssociations() async {
    final refresh = widget.onRefreshFileAssociations;
    if (refresh == null) return;
    try {
      final nextState = await refresh();
      if (!mounted) return;
      _updateSettings(_currentSettings.copyWith(fileAssociations: nextState));
    } on Exception {
      // Preserve the last known state if the platform is temporarily unavailable.
    }
  }

  Future<void> _openDefaultAppsSettings() async {
    final open = widget.onOpenDefaultAppsSettings;
    if (open == null || _isUpdatingFileAssociations) return;
    setState(() => _isUpdatingFileAssociations = true);
    try {
      await open();
      await _refreshFileAssociations();
    } catch (error) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.fileAssociationsUpdateFailed('$error'))),
      );
    } finally {
      if (mounted) setState(() => _isUpdatingFileAssociations = false);
    }
  }

  Widget _buildFileAssociationActions(AppLocalizations l10n) {
    final enabled = !_isUpdatingFileAssociations;

    return Padding(
      key: const ValueKey('file-association-actions'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (_currentSettings.fileAssociations.requiresSystemSettings) ...[
            DesktopCommandButton(
              key: const ValueKey('file-association-system-settings'),
              icon: Icons.open_in_new,
              label: l10n.openDefaultAppsSettings,
              onPressed: enabled ? _openDefaultAppsSettings : null,
            ),
            DesktopIconButton(
              icon: Icons.refresh,
              tooltip: l10n.refreshFileAssociations,
              onPressed: _refreshFileAssociations,
            ),
          ] else ...[
            DesktopCommandButton(
              key: const ValueKey('file-association-enable-all'),
              icon: Icons.done_all,
              label: l10n.fileAssociationsEnableAll,
              onPressed: enabled
                  ? () => unawaited(
                        _updateFileAssociations(
                          Set<String>.of(supportedExtensions),
                        ),
                      )
                  : null,
              emphasized: true,
            ),
            DesktopCommandButton(
              key: const ValueKey('file-association-enable-raw'),
              icon: Icons.camera_alt_outlined,
              label: l10n.fileAssociationsEnableRaw,
              onPressed: enabled
                  ? () => unawaited(
                        _updateFileAssociations(
                          Set<String>.of(rawExtensions),
                        ),
                      )
                  : null,
            ),
            DesktopCommandButton(
              key: const ValueKey('file-association-disable-all'),
              icon: Icons.block_outlined,
              label: l10n.fileAssociationsDisableAll,
              onPressed: enabled
                  ? () => unawaited(_updateFileAssociations(const <String>{}))
                  : null,
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: Column(
        children: [
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              color: RawViewerColors.raisedSurface,
              border: Border(bottom: BorderSide(color: RawViewerColors.border)),
            ),
            child: Row(
              children: [
                DesktopIconButton(
                  icon: Icons.close,
                  tooltip: l10n.closeSettingsTooltip,
                  onPressed: widget.onClose,
                ),
                const SizedBox(width: 10),
                Text(
                  l10n.settingsTitle,
                  style: const TextStyle(
                    color: RawViewerColors.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              children: [
                DesktopSettingsSection(
                  title: l10n.languageSectionTitle,
                  children: _withDividers(
                    AppLanguage.values
                        .map(
                          (language) => DesktopSettingsOption(
                            title: _languageLabel(language, l10n),
                            selected: _currentSettings.appLanguage == language,
                            onTap: () => _updateSettings(
                              _currentSettings.copyWith(appLanguage: language),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                DesktopSettingsSection(
                  title: l10n.gridAspectRatioSectionTitle,
                  children: _withDividers(
                    GridAspectRatio.values
                        .map(
                          (ratio) => DesktopSettingsOption(
                            key: ValueKey('grid-aspect-${ratio.name}'),
                            title: ratio.isAdaptive
                                ? l10n.gridAspectRatioAdaptive
                                : ratio.label,
                            selected: _currentSettings.gridAspectRatio == ratio,
                            onTap: () => _updateSettings(
                              _currentSettings.copyWith(
                                gridAspectRatio: ratio,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                DesktopSettingsSection(
                  title: l10n.navigationSectionTitle,
                  children: [
                    DesktopSettingsRow(
                      key: const ValueKey('page-switch-animation'),
                      title: l10n.pageSwitchAnimationTitle,
                      subtitle: l10n.pageSwitchAnimationSubtitle,
                      control: Switch(
                        value: _currentSettings.pageSwitchAnimationEnabled,
                        onChanged: (value) => _updateSettings(
                          _currentSettings.copyWith(
                            pageSwitchAnimationEnabled: value,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                DesktopSettingsSection(
                  title: l10n.imagePreviewSectionTitle,
                  children: _withDividers([
                    _buildOpacityRow(
                      key: 'preview-toolbar-opacity',
                      title: l10n.previewToolbarOpacityTitle,
                      value: _currentSettings.previewToolbarOpacity,
                      onChanged: (value) => _updateSettings(
                        _currentSettings.copyWith(previewToolbarOpacity: value),
                      ),
                    ),
                    _buildOpacityRow(
                      key: 'preview-filmstrip-opacity',
                      title: l10n.previewFilmstripOpacityTitle,
                      value: _currentSettings.previewFilmstripOpacity,
                      onChanged: (value) => _updateSettings(
                        _currentSettings.copyWith(
                            previewFilmstripOpacity: value),
                      ),
                    ),
                    _buildOpacityRow(
                      key: 'preview-overlay-opacity',
                      title: l10n.previewOverlayOpacityTitle,
                      subtitle: l10n.previewOverlayOpacitySubtitle,
                      value: _currentSettings.previewOverlayOpacity,
                      onChanged: (value) => _updateSettings(
                        _currentSettings.copyWith(previewOverlayOpacity: value),
                      ),
                    ),
                  ]),
                ),
                DesktopSettingsSection(
                  title: l10n.rawProcessingSectionTitle,
                  children: [
                    DesktopSettingsRow(
                      title: l10n.halfSizeRawDecodeTitle,
                      subtitle: l10n.halfSizeRawDecodeSubtitle,
                      control: Switch(
                        value: _currentSettings.useHalfSizeRawDecode,
                        onChanged: (value) => _updateSettings(
                          _currentSettings.copyWith(
                            useHalfSizeRawDecode: value,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                DesktopSettingsSection(
                  title: l10n.timeDisplaySectionTitle,
                  children: _withDividers([
                    DesktopSettingsOption(
                      title: l10n.captureTimeTitle,
                      subtitle: l10n.captureTimeSubtitle,
                      selected: _currentSettings.timeDisplaySource ==
                          TimeDisplaySource.capturedAt,
                      onTap: () => _updateSettings(
                        _currentSettings.copyWith(
                          timeDisplaySource: TimeDisplaySource.capturedAt,
                        ),
                      ),
                    ),
                    DesktopSettingsOption(
                      title: l10n.fileModifiedTimeTitle,
                      subtitle: l10n.fileModifiedTimeSubtitle,
                      selected: _currentSettings.timeDisplaySource ==
                          TimeDisplaySource.modifiedAt,
                      onTap: () => _updateSettings(
                        _currentSettings.copyWith(
                          timeDisplaySource: TimeDisplaySource.modifiedAt,
                        ),
                      ),
                    ),
                  ]),
                ),
                DesktopSettingsSection(
                  title: l10n.cacheSectionTitle,
                  children: [
                    DesktopSettingsRow(
                      title: l10n.maxCacheSizeTitle,
                      control: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: RawViewerColors.canvas,
                          border: Border.all(color: RawViewerColors.border),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          l10n.cacheSizeMb(_currentSettings.maxCacheSize),
                          style: const TextStyle(
                            color: RawViewerColors.text,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                      child: Slider(
                        value: _currentSettings.maxCacheSize.toDouble(),
                        min: 64,
                        max: 4096,
                        divisions: (4096 - 64) ~/ 64,
                        label: l10n.cacheSizeMb(_currentSettings.maxCacheSize),
                        onChanged: (value) => _updateSettings(
                          _currentSettings.copyWith(
                              maxCacheSize: value.toInt()),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_showWindowsContextMenuSection)
                  DesktopSettingsSection(
                    title: l10n.windowsExplorerSectionTitle,
                    children: _withDividers([
                      DesktopSettingsRow(
                        title: l10n.windowsContextMenuToggleTitle,
                        subtitle: _currentSettings.windowsContextMenu.enabled
                            ? l10n.windowsContextMenuEnabledSubtitle
                            : l10n.windowsContextMenuDisabledSubtitle,
                        control: _isUpdatingWindowsContextMenu
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Switch(
                                value:
                                    _currentSettings.windowsContextMenu.enabled,
                                onChanged: _handleWindowsContextMenuChanged,
                              ),
                      ),
                      DesktopSettingsRow(
                        title: l10n.installScopeTitle,
                        control: Text(
                          _currentSettings.windowsContextMenu.enabled
                              ? l10n.installScopeCurrentUser
                              : l10n.installScopeNotInstalled,
                          style: const TextStyle(
                            color: RawViewerColors.mutedText,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ]),
                  ),
                if (_showFileAssociationSection)
                  DesktopSettingsSection(
                    title: l10n.fileAssociationsSectionTitle,
                    children: _withDividers([
                      _buildFileAssociationActions(l10n),
                      for (final extension in supportedExtensions)
                        DesktopSettingsRow(
                          key: ValueKey('file-association-$extension'),
                          title: extension.substring(1).toUpperCase(),
                          subtitle: l10n.fileAssociationFormatSubtitle(
                            extension.substring(1).toUpperCase(),
                          ),
                          control: _currentSettings
                                  .fileAssociations.requiresSystemSettings
                              ? Tooltip(
                                  message: _currentSettings.fileAssociations
                                          .isBound(extension)
                                      ? l10n.fileAssociationDefault
                                      : l10n.fileAssociationNotDefault,
                                  child: Icon(
                                    _currentSettings.fileAssociations
                                            .isBound(extension)
                                        ? Icons.check_circle_outline
                                        : Icons.radio_button_unchecked,
                                    size: 20,
                                  ),
                                )
                              : _isUpdatingFileAssociations
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Switch(
                                      value: _currentSettings.fileAssociations
                                          .isBound(extension),
                                      onChanged: (value) =>
                                          _handleFileAssociationChanged(
                                        extension,
                                        value,
                                      ),
                                    ),
                        ),
                    ]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
