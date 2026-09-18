# Changelog

## Unreleased

- 新增 14 种相机 RAW 扩展名（CRW、NRW、PEF、RAW、RWL、3FR、FFF、IIQ、ERF、DCR、MRW、MOS、SR2、SRF），RAW 支持从 9 种扩展到 23 种。
- 新增 GIF 与 BMP 常规格式，并在 Windows/macOS 文件关联、文件选择器和 Windows 安装器中同步注册。
- 多帧图片（APNG、GIF）在预览中默认播放，可暂停并逐帧查看；缩略图与胶片条始终只解码第一帧。
- 不在支持列表内的格式（如 TIFF、AVIF）仍不提供支持：它们依赖系统解码器，并非所有支持平台都可用。

## 0.1.0 - 2026-09-09

首个功能完整预览版本。

- 新增目录浏览、热文件夹监控、最近打开记录和单文件打开。
- 新增按拍摄时间/评分排序、评分、未评分筛选和 RAW/JPEG 分组展示。
- 新增 EXIF 侧栏、元数据搜索、拍摄时间显示和 RGB 直方图。
- 新增动态照片与 HDR 预览，支持覆盖层透明度、HDR 快速切换和声音控制。
- 新增多帧 PNG 逐帧导航与缓存。
- 新增可调整胶片条、概览地图、缩放/旋转、双击复位和更细致的预览加载策略。
- 完善 RAW 内嵌 JPEG、解码 RAW 与配对 JPEG 的显示模式切换。
- 新增中英文设置、窗口状态恢复、更新检查、Windows 右键菜单和文件关联支持。
- 完善 Windows x64/ARM64、macOS Universal、Linux 和 Android 的构建与发布流程；项目保留 iOS 适配能力，但当前暂不考虑对 iOS 提供正式支持。

### Known limitations

- HDR 显示效果取决于设备和系统显示能力；Windows 和 Linux 使用 SDR 回退。
- RAW 格式的实际支持范围取决于随版本集成的 LibRaw 能力。
