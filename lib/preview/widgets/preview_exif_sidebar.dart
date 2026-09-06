import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;

import '../../l10n/app_localizations.dart';
import '../../core/exif_sidebar_settings.dart';
import '../../ui/app_theme.dart';
import '../../ui/desktop_controls.dart';
import '../exif_repository.dart';

class PreviewExifSidebar extends StatefulWidget {
  final String filePath;
  final ExifRepository repository;
  final VoidCallback onClose;
  final Set<ExifSection> expandedSections;
  final ValueChanged<Set<ExifSection>>? onExpandedSectionsChanged;

  const PreviewExifSidebar({
    super.key,
    required this.filePath,
    required this.repository,
    required this.onClose,
    this.expandedSections = const {},
    this.onExpandedSectionsChanged,
  });

  @override
  State<PreviewExifSidebar> createState() => _PreviewExifSidebarState();
}

class _PreviewExifSidebarState extends State<PreviewExifSidebar> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _loadTimer;
  ExifMetadata? _metadata;
  int _generation = 0;
  late Set<ExifSection> _expandedSections;

  @override
  void initState() {
    super.initState();
    _expandedSections = Set.of(widget.expandedSections);
    _scheduleLoad();
  }

  @override
  void didUpdateWidget(PreviewExifSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expandedSections != widget.expandedSections) {
      _expandedSections = Set.of(widget.expandedSections);
    }
    if (oldWidget.filePath != widget.filePath ||
        oldWidget.repository != widget.repository) {
      _scheduleLoad();
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    }
  }

  void _scheduleLoad() {
    _loadTimer?.cancel();
    final generation = ++_generation;
    _metadata = null;
    // Only inspect the file the user settles on during rapid navigation.
    _loadTimer = Timer(const Duration(milliseconds: 150), () async {
      ExifMetadata metadata;
      try {
        metadata = await widget.repository.load(widget.filePath);
      } catch (_) {
        metadata = const ExifMetadata(readFailed: true);
      }
      if (mounted && generation == _generation) {
        setState(() => _metadata = metadata);
      }
    });
  }

  @override
  void dispose() {
    _loadTimer?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _sectionTitle(ExifSection section, AppLocalizations l10n) =>
      switch (section) {
        ExifSection.file => l10n.exifFileSection,
        ExifSection.shooting => l10n.exifShootingSection,
        ExifSection.image => l10n.exifImageSection,
        ExifSection.exif => l10n.exifExifSection,
        ExifSection.gps => l10n.exifGpsSection,
        ExifSection.maker => l10n.exifMakerSection,
        ExifSection.thumbnail => l10n.exifThumbnailSection,
        ExifSection.other => l10n.exifOtherSection,
      };

  Map<ExifSection, Map<String, String>> _sections(AppLocalizations l10n) {
    final metadata = _metadata;
    final tags = metadata?.tags ?? const <String, String>{};
    final commonLabels = <String, String>{
      'Image Rating': l10n.exifRating,
      'Image Make': l10n.exifCameraMake,
      'Image Model': l10n.exifCameraModel,
      'EXIF LensMake': l10n.exifLensMake,
      'EXIF LensModel': l10n.exifLensModel,
      'EXIF DateTimeOriginal': l10n.captureTimeTitle,
      'EXIF ExposureTime': l10n.exifExposureTime,
      'EXIF FNumber': l10n.exifAperture,
      'EXIF ISOSpeedRatings': l10n.exifIso,
      'EXIF FocalLength': l10n.exifFocalLength,
      'EXIF FocalLengthIn35mmFilm': l10n.exifFocalLength35mm,
      'EXIF ExposureBiasValue': l10n.exifExposureBias,
      'EXIF ExposureProgram': l10n.exifExposureProgram,
      'EXIF MeteringMode': l10n.exifMeteringMode,
      'EXIF Flash': l10n.exifFlash,
      'EXIF WhiteBalance': l10n.exifWhiteBalance,
      'EXIF ExifImageWidth': l10n.exifWidth,
      'EXIF ExifImageLength': l10n.exifHeight,
      'Image Orientation': l10n.exifOrientation,
      'EXIF ColorSpace': l10n.exifColorSpace,
      'Image Software': l10n.exifSoftware,
      'Image Artist': l10n.exifArtist,
      'Image Copyright': l10n.exifCopyright,
      'EXIF BodySerialNumber': l10n.exifBodySerial,
      'EXIF LensSerialNumber': l10n.exifLensSerial,
    };
    final sections = <ExifSection, Map<String, String>>{
      ExifSection.file: {
        l10n.exifFileName: path.basename(widget.filePath),
        l10n.exifFilePath: widget.filePath,
        l10n.exifFileType:
            path.extension(widget.filePath).replaceFirst('.', '').toUpperCase(),
        if (metadata?.fileSize != null)
          l10n.exifFileSize: _formatSize(metadata!.fileSize!),
        if (metadata?.modifiedAt != null)
          l10n.fileModifiedTimeTitle:
              DateFormat('yyyy-MM-dd HH:mm:ss').format(metadata!.modifiedAt!),
      },
      ExifSection.shooting: {
        for (final entry in commonLabels.entries)
          if (tags.containsKey(entry.key)) entry.value: tags[entry.key]!,
      },
    };
    final keys = tags.keys.toList()..sort();
    for (final key in keys) {
      final group = key.split(' ').first;
      final title = switch (group) {
        'Image' => ExifSection.image,
        'EXIF' => ExifSection.exif,
        'GPS' => ExifSection.gps,
        'MakerNote' => ExifSection.maker,
        'Thumbnail' => ExifSection.thumbnail,
        _ => ExifSection.other,
      };
      sections.putIfAbsent(title, () => {})[key] = tags[key]!;
    }
    return sections;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KiB ($bytes B)';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MiB ($bytes B)';
  }

  String? _number(String key) {
    final value = _metadata?.numericValues[key];
    return value == null
        ? _metadata?.tags[key]
        : NumberFormat('0.##').format(value);
  }

  Widget _compactRow(String label, String value, {bool emphasized = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label,
                style: const TextStyle(
                    color: RawViewerColors.mutedText,
                    fontSize: 11,
                    height: 1.35)),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 4,
            child: Text(value,
                style: TextStyle(
                    color: RawViewerColors.text,
                    fontSize: 12,
                    height: 1.3,
                    fontWeight:
                        emphasized ? FontWeight.w600 : FontWeight.w400)),
          ),
        ],
      ),
    );
  }

  Widget _shootingSummary(AppLocalizations l10n) {
    final tags = _metadata!.tags;
    String withUnit(String? value, String unit) =>
        value == null ? '-' : '$value$unit';
    final aperture = _number('EXIF FNumber');
    final compensation = _number('EXIF ExposureBiasValue');
    final highlights = <(String, String)>[
      (l10n.exifShutterShort, withUnit(tags['EXIF ExposureTime'], ' s')),
      (l10n.exifApertureShort, aperture == null ? '-' : 'f/$aperture'),
      (
        'ISO',
        tags['EXIF ISOSpeedRatings'] ??
            tags['EXIF PhotographicSensitivity'] ??
            '-'
      ),
      (l10n.exifFocalLengthShort, withUnit(_number('EXIF FocalLength'), ' mm')),
      (l10n.exifExposureBiasShort, withUnit(compensation, ' EV')),
      (
        l10n.exifEquivalentShort,
        withUnit(_number('EXIF FocalLengthIn35mmFilm'), ' mm')
      ),
    ];
    final camera = tags['Image Model'] ?? tags['Image Make'];
    final lens = tags['EXIF LensModel'] ??
        tags['MakerNote LensModel'] ??
        tags['MakerNote LensType'];
    final capturedAt = tags['EXIF DateTimeOriginal'] ?? tags['Image DateTime'];
    final width = tags['EXIF ExifImageWidth'] ?? tags['Image ImageWidth'];
    final height = tags['EXIF ExifImageLength'] ?? tags['Image ImageLength'];
    final secondaryFields = <String, String>{
      'EXIF ExposureProgram': l10n.exifExposureProgram,
      'EXIF MeteringMode': l10n.exifMeteringMode,
      'EXIF WhiteBalance': l10n.exifWhiteBalance,
      'EXIF Flash': l10n.exifFlash,
      'EXIF ColorSpace': l10n.exifColorSpace,
    };
    return Column(
      key: const ValueKey('exif-shooting-summary'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (camera != null)
          _compactRow(l10n.exifCameraModel, camera, emphasized: true),
        if (lens != null)
          _compactRow(l10n.exifLensModel, lens, emphasized: true),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            children: [
              for (var row = 0; row < 2; row++)
                Row(
                  children: [
                    for (var column = 0; column < 3; column++)
                      Expanded(
                        child: Container(
                          height: 52,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 5),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: row == 0
                                  ? const BorderSide(
                                      color: RawViewerColors.border)
                                  : BorderSide.none,
                              right: column < 2
                                  ? const BorderSide(
                                      color: RawViewerColors.border)
                                  : BorderSide.none,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                height: 14,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(highlights[row * 3 + column].$1,
                                      style: const TextStyle(
                                          color: RawViewerColors.mutedText,
                                          fontSize: 10)),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Expanded(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(highlights[row * 3 + column].$2,
                                      style: const TextStyle(
                                          color: RawViewerColors.text,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        if (capturedAt != null) _compactRow(l10n.captureTimeTitle, capturedAt),
        if (width != null && height != null)
          _compactRow(l10n.exifDimensions, '$width x $height'),
        for (final entry in secondaryFields.entries)
          if (tags[entry.key] case final String value)
            _compactRow(entry.value, value),
        if (tags['Image Artist'] case final String artist)
          _compactRow(l10n.exifArtist, artist),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _ratingRow(AppLocalizations l10n) {
    final rawRating = _metadata!.tags['Image Rating'];
    final parsed = int.tryParse(rawRating?.trim() ?? '');
    final rating = parsed != null && parsed >= 0 && parsed <= 5 ? parsed : null;
    final status = rawRating == null
        ? l10n.exifRatingMissing
        : rating == null
            ? l10n.exifRatingInvalid
            : rating == 0
                ? l10n.exifRatingUnrated
                : '$rating / 5';
    return Semantics(
      key: const ValueKey('exif-rating'),
      label: '${l10n.exifRating}: $status',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: Text(l10n.exifRating,
                  style: const TextStyle(
                      color: RawViewerColors.mutedText,
                      fontSize: 11,
                      height: 1.6)),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 4,
              child: Wrap(
                spacing: 8,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var star = 1; star <= 5; star++)
                        Icon(
                          star <= (rating ?? 0)
                              ? Icons.star
                              : Icons.star_border,
                          size: 18,
                          color: star <= (rating ?? 0)
                              ? const Color(0xFFE5BD62)
                              : RawViewerColors.mutedText,
                        ),
                    ],
                  ),
                  Text(status,
                      style: const TextStyle(
                          color: RawViewerColors.mutedText, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(ExifSection section, String title, int count,
      {required bool searching}) {
    final expanded = searching || _expandedSections.contains(section);
    return Semantics(
      expanded: expanded,
      child: InkWell(
        onTap: searching
            ? null
            : () {
                setState(() {
                  if (!_expandedSections.add(section)) {
                    _expandedSections.remove(section);
                  }
                });
                widget.onExpandedSectionsChanged
                    ?.call(Set.unmodifiable(_expandedSections));
              },
        child: Container(
          constraints: const BoxConstraints(minHeight: 34),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: RawViewerColors.border)),
          ),
          child: Row(children: [
            Icon(expanded ? Icons.expand_more : Icons.chevron_right, size: 16),
            const SizedBox(width: 5),
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      color: RawViewerColors.mutedText,
                      fontWeight: FontWeight.w600,
                      fontSize: 11)),
            ),
            Text('$count',
                style: const TextStyle(
                    color: RawViewerColors.mutedText, fontSize: 10)),
          ]),
        ),
      ),
    );
  }

  Future<void> _copyMetadata(
      Map<ExifSection, Map<String, String>> sections) async {
    final l10n = AppLocalizations.of(context)!;
    final text = sections.entries
        .where((section) => section.value.isNotEmpty)
        .map((section) =>
            '[${_sectionTitle(section.key, l10n)}]\n${section.value.entries.map((entry) => '${entry.key}: ${entry.value}').join('\n')}')
        .join('\n\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.aboutCopiedMessage)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sections = _sections(l10n);
    final query = _searchController.text.trim().toLowerCase();
    final rows = <Widget>[];
    if (_metadata != null &&
        !_metadata!.readFailed &&
        (query.isEmpty ||
            l10n.exifRating.toLowerCase().contains(query) ||
            'image rating'.contains(query))) {
      rows.add(_ratingRow(l10n));
    }
    if (query.isEmpty && _metadata != null && _metadata!.tags.isNotEmpty) {
      rows.add(_shootingSummary(l10n));
    }
    for (final section in sections.entries) {
      if (query.isEmpty && section.key == ExifSection.shooting) continue;
      final title = _sectionTitle(section.key, l10n);
      final entries = section.value.entries.where((entry) =>
          query.isEmpty ||
          title.toLowerCase().contains(query) ||
          entry.key.toLowerCase().contains(query) ||
          entry.value.toLowerCase().contains(query));
      if (entries.isEmpty) continue;
      rows.add(_sectionHeader(section.key, title, entries.length,
          searching: query.isNotEmpty));
      if (query.isNotEmpty || _expandedSections.contains(section.key)) {
        for (final entry in entries) {
          rows.add(_compactRow(entry.key, entry.value));
        }
      }
    }
    return Material(
      key: const ValueKey('preview-exif-sidebar'),
      color: RawViewerColors.surface,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(left: BorderSide(color: RawViewerColors.border)),
        ),
        child: SafeArea(
          top: false,
          left: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
                child: Row(children: [
                  Expanded(
                    child: Text(l10n.exifTitle,
                        style: const TextStyle(
                            color: RawViewerColors.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                  ),
                  DesktopIconButton(
                    icon: Icons.copy_all_outlined,
                    tooltip: l10n.exifCopyAll,
                    onPressed: _metadata == null
                        ? null
                        : () => _copyMetadata(sections),
                  ),
                  DesktopIconButton(
                    icon: Icons.close,
                    tooltip: l10n.hideExifTooltip,
                    onPressed: widget.onClose,
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(
                      color: RawViewerColors.text, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: l10n.exifSearch,
                    hintStyle:
                        const TextStyle(color: RawViewerColors.mutedText),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    prefixIconConstraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    suffixIconConstraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    isDense: true,
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: l10n.exifClearSearch,
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () => setState(_searchController.clear),
                          ),
                  ),
                ),
              ),
              SizedBox(
                height: 8,
                child: _metadata == null
                    ? const Align(
                        alignment: Alignment.topCenter,
                        child: LinearProgressIndicator(minHeight: 2),
                      )
                    : null,
              ),
              Expanded(
                child: SelectionArea(
                  child: Scrollbar(
                    controller: _scrollController,
                    child: ListView(
                      controller: _scrollController,
                      padding: const EdgeInsets.only(bottom: 16),
                      children: [
                        ...rows,
                        if (_metadata != null &&
                            (_metadata!.readFailed || _metadata!.tags.isEmpty))
                          Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text(
                              _metadata!.readFailed
                                  ? l10n.exifReadFailed
                                  : l10n.exifEmpty,
                              style: const TextStyle(
                                  color: RawViewerColors.mutedText,
                                  fontSize: 12),
                            ),
                          )
                        else if (rows.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text(l10n.exifNoResults),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
