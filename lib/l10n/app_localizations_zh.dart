// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Raw Viewer';

  @override
  String get settingsTitle => '设置';

  @override
  String get languageSectionTitle => '语言';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get languageChineseSimplified => '简体中文';

  @override
  String get languageEnglish => 'English';

  @override
  String get rawPreviewSourceSectionTitle => 'RAW 预览来源';

  @override
  String get fastPreviewTitle => '快速预览';

  @override
  String get fastPreviewSubtitle => '先显示缓存的快速预览，再继续使用快速预览层。通常优先使用内嵌预览，缺失时回退到快速 RAW 处理。';

  @override
  String get decodedRawPreviewTitle => 'RAW 解码图像';

  @override
  String get decodedRawPreviewSubtitle => '先显示缓存的快速预览，再解码 RAW 作为最终图像。';

  @override
  String get rawProcessingSectionTitle => 'RAW 处理';

  @override
  String get halfSizeRawDecodeTitle => '半尺寸 RAW 解码';

  @override
  String get halfSizeRawDecodeSubtitle => '将 RAW 最终图像按 50% 分辨率解码以提升速度。关闭后使用完整分辨率。';

  @override
  String get timeDisplaySectionTitle => '时间显示';

  @override
  String get captureTimeTitle => '拍摄时间';

  @override
  String get captureTimeSubtitle => '优先使用 EXIF 或 RAW 元数据中的拍摄时间';

  @override
  String get fileModifiedTimeTitle => '文件修改时间';

  @override
  String get fileModifiedTimeSubtitle => '直接使用文件系统中的最后修改时间';

  @override
  String get cacheSectionTitle => '缓存';

  @override
  String get maxCacheSizeTitle => '最大缓存大小';

  @override
  String cacheSizeMb(int size) {
    return '$size MB';
  }

  @override
  String get windowsExplorerSectionTitle => 'Windows 资源管理器';

  @override
  String get windowsContextMenuMenuText => '在 RawView 中打开';

  @override
  String get windowsContextMenuToggleTitle => '显示“在 RawView 中打开”';

  @override
  String get windowsContextMenuEnabledSubtitle =>
      '已安装到当前用户。支持文件、多个文件、文件夹，以及文件夹空白处右键打开。';

  @override
  String get windowsContextMenuDisabledSubtitle =>
      '启用后可在资源管理器中通过右键“在 RawView 中打开”直接打开文件、多个文件、文件夹或当前目录。';

  @override
  String get installScopeTitle => '安装范围';

  @override
  String get installScopeCurrentUser => '当前用户（HKCU）';

  @override
  String get installScopeNotInstalled => '未安装';

  @override
  String get windowsContextMenuEnabledMessage => '已启用“在 RawView 中打开”右键菜单';

  @override
  String get windowsContextMenuRemovedMessage => '已移除“在 RawView 中打开”右键菜单';

  @override
  String windowsContextMenuUpdateFailed(String error) {
    return '更新 Windows 右键菜单失败：$error';
  }

  @override
  String get homeEmptyState => '打开或拖放 RAW 与图片文件/文件夹';

  @override
  String fileSelectionTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个文件',
      one: '1 个文件',
    );
    return '$_temp0';
  }

  @override
  String folderSelectionTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个文件夹',
      one: '1 个文件夹',
    );
    return '$_temp0';
  }

  @override
  String get fastPreviewShortLabel => 'FAST';

  @override
  String get rawShortLabel => 'RAW';

  @override
  String get imageShortLabel => 'IMG';
}
