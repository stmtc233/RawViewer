import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import '../../l10n/app_localizations.dart';
import '../../lru_cache.dart';

class DirectoryBrowser extends StatefulWidget {
  const DirectoryBrowser({
    super.key,
    required this.directoryPath,
    required this.onOpenDirectory,
    required this.builder,
  });

  final String directoryPath;
  final Future<void> Function(String) onOpenDirectory;
  final Widget Function(BuildContext, List<String>) builder;

  @override
  State<DirectoryBrowser> createState() => _DirectoryBrowserState();
}

class _DirectoryBrowserState extends State<DirectoryBrowser> {
  final _cache = LruCache<String, List<String>>(10000,
      sizeOf: (directories) => directories.length + 1);
  List<String> _directories = const [];
  Object? _error;
  int _generation = 0;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _loadDirectories();
  }

  @override
  void didUpdateWidget(DirectoryBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.directoryPath != widget.directoryPath) {
      _directories = _cache.get(widget.directoryPath) ?? const [];
      _error = null;
      _loadDirectories();
    }
  }

  Future<void> _loadDirectories() async {
    final directoryPath = widget.directoryPath;
    final generation = ++_generation;
    try {
      final entries = await Directory(directoryPath).list().toList();
      final directories = entries
          .whereType<Directory>()
          .map((directory) => directory.path)
          .toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      if (!mounted || generation != _generation) return;
      _cache.put(directoryPath, directories);
      setState(() {
        _directories = directories;
        _error = null;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = error);
    }
  }

  Future<void> _open(String directory) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await widget.onOpenDirectory(directory);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final parent = path.dirname(widget.directoryPath);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: l10n.parentDirectory,
              icon: const Icon(Icons.arrow_upward),
              onPressed: _opening || parent == widget.directoryPath
                  ? null
                  : () => _open(parent),
            ),
            Expanded(
              child: Text(widget.directoryPath,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            IconButton(
              tooltip: l10n.refreshDirectories,
              icon: const Icon(Icons.refresh),
              onPressed: _loadDirectories,
            ),
          ],
        ),
        const Divider(height: 1),
        if (_error != null)
          Text(l10n.loadDirectoryFailedMessage('$_error'),
              maxLines: 2, overflow: TextOverflow.ellipsis),
        Expanded(
          child: widget.builder(context, _directories),
        ),
      ],
    );
  }
}
