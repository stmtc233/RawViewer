import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/live_photo.dart';
import '../../l10n/app_localizations.dart';

class LivePhotoPreview extends StatefulWidget {
  final String filePath;
  final bool active;
  final bool longPressPlaybackEnabled;
  final int quarterTurns;
  final double bottomInset;
  final Widget child;
  final Future<LivePhotoSource?> Function(String) sourceLoader;

  const LivePhotoPreview({
    super.key,
    required this.filePath,
    required this.active,
    this.longPressPlaybackEnabled = false,
    required this.quarterTurns,
    required this.bottomInset,
    required this.child,
    this.sourceLoader = findLivePhoto,
  });

  @override
  State<LivePhotoPreview> createState() => _LivePhotoPreviewState();
}

class _LivePhotoPreviewState extends State<LivePhotoPreview>
    with WidgetsBindingObserver {
  LivePhotoSource? _source;
  VideoPlayerController? _controller;
  LivePhotoPlaybackFile? _playbackFile;
  Future<bool>? _preparation;
  Future<void> _commands = Future<void>.value();
  bool _playing = false;
  bool _playStarted = false;
  bool _foreground = true;
  bool _hasAdvanced = false;
  bool _loading = false;
  bool _videoVisible = false;
  bool _muted = true;
  bool _playingFromHold = false;
  int _generation = 0;
  int _playRequest = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _discover();
  }

  @override
  void didUpdateWidget(LivePhotoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath ||
        oldWidget.active != widget.active) {
      _release();
      _source = null;
      _discover();
    } else if (!widget.longPressPlaybackEnabled && _playingFromHold) {
      _stop();
    }
  }

  void _startHold() {
    if (_playing) return;
    _playingFromHold = true;
    unawaited(_play());
  }

  void _endHold() {
    if (_playingFromHold) setState(_stop);
  }

  Future<void> _discover() async {
    if (!widget.active) return;
    final generation = _generation;
    final source = await widget.sourceLoader(widget.filePath);
    if (mounted && generation == _generation && widget.active) {
      setState(() => _source = source);
      if (source != null && _foreground) unawaited(_ensurePrepared());
    }
  }

  Future<bool> _ensurePrepared() {
    final source = _source;
    if (source == null || !widget.active || !_foreground) {
      return Future.value(false);
    }
    return _preparation ??= _prepare(source, _generation);
  }

  Future<bool> _prepare(LivePhotoSource source, int generation) async {
    LivePhotoPlaybackFile? playbackFile;
    var transferred = false;
    try {
      playbackFile = await LivePhotoPlaybackFile.prepare(source);
      if (!mounted || generation != _generation) {
        await playbackFile.dispose();
        return false;
      }
      final controller = VideoPlayerController.file(File(playbackFile.path));
      _controller = controller;
      _playbackFile = playbackFile;
      transferred = true;
      await controller.initialize();
      if (!mounted || generation != _generation) return false;
      controller.addListener(_onPlaybackChanged);
      await controller.setVolume(_muted ? 0 : 1);
      if (!mounted || generation != _generation) return false;
      // Mount the texture while the still covers startup and buffering.
      setState(() {});
      return true;
    } catch (_) {
      if (!transferred) await playbackFile?.dispose();
      _failed(generation, notify: _playing);
      return false;
    }
  }

  Future<void> _play() async {
    if (_playing || _source == null || !widget.active || !_foreground) return;
    final generation = _generation;
    final request = ++_playRequest;
    setState(() {
      _playing = true;
      _loading = true;
    });
    if (!await _ensurePrepared()) return;
    if (!mounted || generation != _generation || request != _playRequest) {
      return;
    }
    final controller = _controller!;
    try {
      await _enqueue(() async {
        if (generation != _generation || request != _playRequest) return;
        await controller.setVolume(_muted ? 0 : 1);
        if (generation != _generation || request != _playRequest) return;
        // A retained player has already populated its texture; don't wait for
        // another position poll before showing a replay.
        setState(() {
          _playStarted = true;
          _videoVisible = _hasAdvanced;
          _loading = !_videoVisible;
        });
        await controller.play();
        if (generation != _generation) return;
        if (request != _playRequest) await controller.pause();
      });
    } catch (_) {
      _failed(generation);
    }
  }

  Future<void> _enqueue(Future<void> Function() command) {
    final pending = _commands.then((_) => command());
    _commands = pending.then<void>((_) {}, onError: (Object _) {});
    return pending;
  }

  void _onPlaybackChanged() {
    final value = _controller?.value;
    if (!mounted || value == null) return;
    if (value.hasError) {
      _failed(_generation, notify: _playing);
    } else if (_playStarted && value.isCompleted) {
      setState(_stop);
    } else if (_playStarted &&
        !_videoVisible &&
        value.isInitialized &&
        value.isPlaying &&
        !value.isBuffering &&
        value.position > Duration.zero) {
      // Initialization only guarantees metadata, not a populated texture.
      setState(() {
        _videoVisible = true;
        _hasAdvanced = true;
        _loading = false;
      });
    }
  }

  void _failed(int generation, {bool notify = true}) {
    if (!mounted || generation != _generation) return;
    setState(_release);
    if (!notify) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(AppLocalizations.of(context)!.livePhotoPlaybackFailed),
    ));
  }

  Future<void> _toggleMute() async {
    final generation = _generation;
    setState(() => _muted = !_muted);
    try {
      await _controller?.setVolume(_muted ? 0 : 1);
    } catch (_) {
      _failed(generation);
    }
  }

  void _stop() {
    _playRequest++;
    _playing = false;
    _playStarted = false;
    _loading = false;
    _videoVisible = false;
    _playingFromHold = false;
    final controller = _controller;
    final generation = _generation;
    if (controller == null || !controller.value.isInitialized) return;
    unawaited(_enqueue(() async {
      if (generation != _generation) return;
      await controller.pause();
      if (generation != _generation) return;
      await controller.seekTo(Duration.zero);
    }).catchError((Object _) => _failed(generation)));
  }

  void _release() {
    _generation++;
    _playRequest++;
    _playing = false;
    _playStarted = false;
    _loading = false;
    _videoVisible = false;
    _playingFromHold = false;
    _hasAdvanced = false;
    _preparation = null;
    final commands = _commands;
    _commands = Future<void>.value();
    final controller = _controller;
    final playbackFile = _playbackFile;
    _controller = null;
    _playbackFile = null;
    controller?.removeListener(_onPlaybackChanged);
    unawaited(() async {
      try {
        try {
          await commands;
          await controller?.dispose();
        } finally {
          await playbackFile?.dispose();
        }
      } catch (error) {
        debugPrint('Live Photo cleanup failed: $error');
      }
    }());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state != AppLifecycleState.resumed) {
      setState(_release);
    } else if (_source == null) {
      _discover();
    } else {
      unawaited(_ensurePrepared());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final playing = _playing;
    final canHold =
        widget.longPressPlaybackEnabled && widget.active && _source != null;
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onLongPressStart: canHold ? (_) => _startHold() : null,
          onLongPressEnd: canHold ? (_) => _endHold() : null,
          onLongPressCancel: canHold ? _endHold : null,
          child: widget.child,
        ),
        if (_controller?.value.isInitialized ?? false)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _videoVisible ? 1 : 0,
                duration: _videoVisible
                    ? const Duration(milliseconds: 120)
                    : Duration.zero,
                child: RotatedBox(
                  quarterTurns: widget.quarterTurns,
                  child: Center(
                      child: AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio,
                    child: VideoPlayer(_controller!),
                  )),
                ),
              ),
            ),
          ),
        if (widget.active && _source != null)
          Positioned(
            left: 16,
            bottom: widget.bottomInset + 12,
            child: Material(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: playing ? l10n!.stopLivePhoto : l10n!.playLivePhoto,
                  onPressed: playing ? () => setState(_stop) : _play,
                  icon: _loading
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(playing ? Icons.stop : Icons.motion_photos_on,
                          color: Colors.white),
                ),
                IconButton(
                  tooltip: _muted ? l10n.unmuteLivePhoto : l10n.muteLivePhoto,
                  onPressed: _toggleMute,
                  icon: Icon(_muted ? Icons.volume_off : Icons.volume_up,
                      color: Colors.white),
                ),
              ]),
            ),
          ),
      ],
    );
  }
}
