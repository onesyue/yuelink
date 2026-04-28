import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/kernel/core_manager.dart';
import '../../i18n/app_strings.dart';
import 'emby_client.dart';
import 'widgets/player_settings_panel.dart';

const _pipChannel = MethodChannel('com.yueto.yuelink/pip');

/// Netflix-style native video player for Emby content.
class EmbyPlayerPage extends StatefulWidget {
  final String serverUrl;
  final String accessToken;
  final String userId;
  final String streamUrl;
  final String itemId;
  final String title;
  final String? subtitle;

  /// 上一集回调（null = 没有上一集，不显示按钮）
  final VoidCallback? onPrevious;

  /// 下一集回调（null = 没有下一集，不显示按钮）
  final VoidCallback? onNext;

  const EmbyPlayerPage({
    super.key,
    required this.serverUrl,
    required this.accessToken,
    required this.userId,
    required this.streamUrl,
    required this.itemId,
    required this.title,
    this.subtitle,
    this.onPrevious,
    this.onNext,
  });

  @override
  State<EmbyPlayerPage> createState() => _EmbyPlayerPageState();
}

class _EmbyPlayerPageState extends State<EmbyPlayerPage> with WidgetsBindingObserver {
  // Session-wide subtitle font size (persists while app is running).
  static double _savedFontSize = 40.0;

  static bool _mediaKitReady = false;
  late final Player _player;
  late final VideoController _controller;
  late final EmbyClient _api;

  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<Tracks>? _tracksSub;
  StreamSubscription<Duration>? _positionSub;
  Timer? _progressTimer;

  bool _loading = true;
  String? _error;
  double _playbackRate = 1.0;
  double _subtitleFontSize = _savedFontSize;

  // Fit mode: default fill（铺满不丢内容）, cycle fill → contain → cover
  static const _fitModes = [BoxFit.fill, BoxFit.contain, BoxFit.cover];
  static const _fitLabels = ['铺满', '适应', '裁切'];
  int _fitIndex = 0;
  BoxFit get _currentFit => _fitModes[_fitIndex];

  // Lock screen
  bool _locked = false;

  // Emby playback-session tracking.
  final String _sessionId =
      DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  bool _playbackStarted = false;

  List<Map<String, dynamic>> _embyAudio = [];
  List<Map<String, dynamic>> _embySubs = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subtitleFontSize = _savedFontSize;
    if (!_mediaKitReady) {
      MediaKit.ensureInitialized();
      _mediaKitReady = true;
    }
    _player = Player();
    _controller = VideoController(_player);
    _api = EmbyClient(
      serverUrl: widget.serverUrl,
      accessToken: widget.accessToken,
      userId: widget.userId,
    );
    if (Platform.isAndroid || Platform.isIOS) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    _setupAndPlay();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 后台最小化时自动进入小窗播放（paused = 真正离开，inactive 会被通知栏触发）
    if (state == AppLifecycleState.paused && Platform.isAndroid && _player.state.playing) {
      _pipChannel.invokeMethod('enterPip', {'width': 16, 'height': 9});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fitToastTimer?.cancel();
    _progressTimer?.cancel();
    _bufferingSub?.cancel();
    _tracksSub?.cancel();
    _positionSub?.cancel();
    // Capture position before player is disposed — _positionTicks reads player state.
    final finalTicks = _playbackStarted ? _positionTicks : 0;
    _player.dispose();
    // Chain _api.close() after the stop report so the HTTP request isn't aborted.
    if (_playbackStarted) {
      _reportStop(positionTicks: finalTicks).whenComplete(_api.close);
    } else {
      _api.close();
    }
    if (Platform.isAndroid || Platform.isIOS) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  // ── Playback setup ────────────────────────────────────────────────────

  Future<void> _setupAndPlay() async {
    try {
      final mixedPort = CoreManager.instance.mixedPort;
      final np = _player.platform as NativePlayer;
      if (mixedPort > 0) {
        await np.setProperty('http-proxy', 'http://127.0.0.1:$mixedPort');
      }
      await np.setProperty('tls-verify', 'no');
      // 改善 seek 响应速度 + 缓冲策略
      await np.setProperty('demuxer-seekable-cache', 'yes');
      await np.setProperty('cache', 'yes');
      await np.setProperty('cache-secs', '60');
      await np.setProperty('demuxer-max-bytes', '100MiB');
      await np.setProperty('demuxer-max-back-bytes', '50MiB');
      await np.setProperty('hr-seek', 'yes');
      await np.setProperty('hr-seek-framedrop', 'yes');
      await _player.open(Media(widget.streamUrl, httpHeaders: {
        'X-Emby-Authorization':
            'MediaBrowser Client="YueLink", Device="Flutter", '
                'DeviceId="yuelink-flutter", Version="1.0", '
                'Token="${widget.accessToken}"',
      }));
      _bufferingSub = _player.stream.buffering.listen((b) {
        if (mounted && _loading && !b) setState(() => _loading = false);
      });
      _tracksSub = _player.stream.tracks.listen((_) {
        if (mounted) setState(() {});
      });
      _fetchMediaStreams();
      _checkResume();
      _startProgressReporting();
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = '$e'; });
    }
  }

  // ── Resume detection ──────────────────────────────────────────────────

  Future<void> _checkResume() async {
    try {
      final data = await _api.get(
        '/emby/Users/${widget.userId}/Items/${widget.itemId}',
        {'Fields': 'UserData'},
      );
      final userData = data['UserData'] as Map<String, dynamic>?;
      if (userData == null) return;
      final posTicks = userData['PlaybackPositionTicks'] as int? ?? 0;
      if (posTicks <= 0) return;
      final posSeconds = posTicks ~/ 10000000;
      if (posSeconds < 30) return;
      // Skip if already near the end (> 95% played).
      final totalTicks = data['RunTimeTicks'] as int?;
      if (totalTicks != null && totalTicks > 0 && posTicks / totalTicks > 0.95) {
        return;
      }
      if (!mounted) return;
      final resume = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1C1C1E),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text(S.current.embyResumeTitle,
              style: const TextStyle(color: Colors.white, fontSize: 16)),
          content: Text(_formatPosition(posSeconds),
              style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(S.current.embyRestartBtn,
                  style: const TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child:
                  Text(S.current.embyContinueBtn, style: const TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      );
      if (resume == true && mounted) {
        await _player.seek(Duration(seconds: posSeconds));
      }
    } catch (_) {}
  }

  String _formatPosition(int seconds) {
    final d = Duration(seconds: seconds);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final ts = h > 0 ? '$h:$m:$s' : '$m:$s';
    return '上次播放到 $ts';
  }

  // ── Emby progress reporting ───────────────────────────────────────────

  int get _positionTicks => _player.state.position.inMicroseconds * 10;

  void _startProgressReporting() {
    // Detect first non-zero position → report playback start.
    _positionSub = _player.stream.position.listen((pos) {
      if (!_playbackStarted && pos.inSeconds > 0) {
        _playbackStarted = true;
        _reportStart();
      }
    });
    // Report progress every 10 s.
    // `mounted` guard: `_progressTimer.cancel()` runs in dispose() before
    // `_player.dispose()`, but a tick already scheduled on the event loop
    // can still fire after the State is gone. `_reportProgress()` touches
    // `_player.state.playing`, which throws on a disposed player.
    _progressTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      if (_playbackStarted) _reportProgress();
    });
  }

  Future<void> _reportStart() async {
    await _api.post('/emby/Sessions/Playing', {
      'ItemId': widget.itemId,
      'MediaSourceId': widget.itemId,
      'PositionTicks': _positionTicks,
      'IsPaused': false,
      'IsMuted': false,
      'PlayMethod': 'DirectPlay',
      'PlaySessionId': _sessionId,
    });
  }

  Future<void> _reportProgress() async {
    await _api.post('/emby/Sessions/Playing/Progress', {
      'ItemId': widget.itemId,
      'MediaSourceId': widget.itemId,
      'PositionTicks': _positionTicks,
      'IsPaused': !_player.state.playing,
      'IsMuted': false,
      'PlayMethod': 'DirectPlay',
      'PlaySessionId': _sessionId,
    });
  }

  Future<void> _reportStop({int? positionTicks}) async {
    await _api.post('/emby/Sessions/Playing/Stopped', {
      'ItemId': widget.itemId,
      'MediaSourceId': widget.itemId,
      'PositionTicks': positionTicks ?? _positionTicks,
      'PlayMethod': 'DirectPlay',
      'PlaySessionId': _sessionId,
    });
  }

  // ── Media streams ─────────────────────────────────────────────────────

  Future<void> _fetchMediaStreams() async {
    try {
      final info = await _api.get('/emby/Items/${widget.itemId}',
          {'Fields': 'MediaSources'});
      final sources = info['MediaSources'] as List<dynamic>?;
      if (sources == null || sources.isEmpty) return;
      final streams = (sources.first
              as Map<String, dynamic>)['MediaStreams'] as List<dynamic>? ??
          [];
      if (!mounted) return;
      setState(() {
        _embyAudio = streams
            .where((s) => (s as Map)['Type'] == 'Audio')
            .cast<Map<String, dynamic>>()
            .toList();
        _embySubs = streams
            .where((s) => (s as Map)['Type'] == 'Subtitle')
            .cast<Map<String, dynamic>>()
            .toList();
      });
    } catch (_) {}
  }

  // ── Settings panel ────────────────────────────────────────────────────

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => EmbyPlayerSettingsPanel(
        player: _player,
        embyAudio: _embyAudio,
        embySubs: _embySubs,
        serverUrl: widget.serverUrl,
        itemId: widget.itemId,
        accessToken: widget.accessToken,
        currentRate: _playbackRate,
        subtitleFontSize: _subtitleFontSize,
        onRateChanged: (r) {
          _player.setRate(r);
          setState(() => _playbackRate = r);
        },
        onSubtitleSizeChanged: (size) {
          setState(() {
            _subtitleFontSize = size;
            _savedFontSize = size;
          });
        },
      ),
    );
  }

  // ── Skip ±10s ───────────────────────────────────────────────────────

  void _skipForward() =>
      _player.seek(_player.state.position + const Duration(seconds: 10));
  void _skipBackward() =>
      _player.seek(_player.state.position - const Duration(seconds: 10));

  void _toggleLock() => setState(() => _locked = !_locked);

  // ── UI ────────────────────────────────────────────────────────────────

  // 画面比例 Toast
  String? _fitToast;
  Timer? _fitToastTimer;

  void _cycleFitWithToast() {
    setState(() {
      _fitIndex = (_fitIndex + 1) % _fitModes.length;
      _fitToast = _fitLabels[_fitIndex];
    });
    _fitToastTimer?.cancel();
    _fitToastTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _fitToast = null);
    });
  }

  // 长按 2x 加速
  bool _longPressSpeed = false;
  double _savedRate = 1.0;

  void _onLongPressStart() {
    _savedRate = _playbackRate;
    _player.setRate(2.0);
    setState(() { _longPressSpeed = true; _playbackRate = 2.0; });
  }

  void _onLongPressEnd() {
    _player.setRate(_savedRate);
    setState(() { _longPressSpeed = false; _playbackRate = _savedRate; });
  }

  // 快速切字幕（CC 按钮 → 直接打开字幕 Tab）
  void _quickSubtitle() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => EmbyPlayerSettingsPanel(
        player: _player,
        embyAudio: _embyAudio,
        embySubs: _embySubs,
        serverUrl: widget.serverUrl,
        itemId: widget.itemId,
        accessToken: widget.accessToken,
        currentRate: _playbackRate,
        subtitleFontSize: _subtitleFontSize,
        initialTab: 1, // 字幕 Tab
        onRateChanged: (r) {
          _player.setRate(r);
          setState(() => _playbackRate = r);
        },
        onSubtitleSizeChanged: (size) {
          setState(() {
            _subtitleFontSize = size;
            _savedFontSize = size;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ── 锁定模式 ──
    if (_locked) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Video(controller: _controller, controls: NoVideoControls,
                fit: _currentFit, subtitleViewConfiguration: _subtitleConfig()),
            Positioned.fill(child: GestureDetector(onTap: () {}, behavior: HitTestBehavior.opaque)),
            Positioned(
              right: 20, top: 0, bottom: 0,
              child: Center(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.lock_rounded, color: Colors.white70, size: 28),
                    onPressed: _toggleLock,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // ── 正常模式（YouTube/Netflix 风格）──
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        // 长按 2x 加速（YouTube 风格）— deferToChild 避免拦截亮度/音量垂直滑动
        onLongPressStart: (_) => _onLongPressStart(),
        onLongPressEnd: (_) => _onLongPressEnd(),
        onLongPressCancel: () => _onLongPressEnd(),
        behavior: HitTestBehavior.deferToChild,
        child: MaterialVideoControlsTheme(
          normal: MaterialVideoControlsThemeData(
            seekOnDoubleTap: true,
            volumeGesture: true,
            brightnessGesture: true,
            seekGesture: true,
            horizontalGestureSensitivity: 800,
            // ── 顶栏 ──
            topButtonBar: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.title,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (widget.subtitle != null)
                      Text(widget.subtitle!,
                          style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
              // 倍速标签（非 1x 或长按加速时显示）
              if (_playbackRate != 1.0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
                  child: Text(_longPressSpeed ? '▶▶ 2x' : '${_playbackRate}x',
                      style: const TextStyle(color: Colors.white, fontSize: 11)),
                ),
              // 画面比例（纯图标，YouTube 风格）
              IconButton(
                icon: const Icon(Icons.aspect_ratio_rounded, color: Colors.white, size: 22),
                onPressed: _cycleFitWithToast,
              ),
              // CC 字幕快捷按钮
              IconButton(
                icon: const Icon(Icons.closed_caption_rounded, color: Colors.white, size: 22),
                onPressed: _quickSubtitle,
              ),
              // 设置
              IconButton(
                icon: const Icon(Icons.tune_rounded, color: Colors.white, size: 22),
                onPressed: _showSettings,
              ),
            ],
            // ── 中央控件（Netflix 三按钮）──
            primaryButtonBar: [
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.replay_10_rounded, color: Colors.white, size: 36),
                onPressed: _skipBackward,
              ),
              const SizedBox(width: 32),
              const MaterialPlayOrPauseButton(iconSize: 56.0),
              const SizedBox(width: 32),
              IconButton(
                icon: const Icon(Icons.forward_10_rounded, color: Colors.white, size: 36),
                onPressed: _skipForward,
              ),
              const Spacer(),
            ],
            // ── 底部栏（简洁）──
            bottomButtonBar: [
              if (widget.onPrevious != null)
                IconButton(
                  icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 24),
                  onPressed: widget.onPrevious,
                ),
              if (widget.onNext != null)
                IconButton(
                  icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 24),
                  onPressed: widget.onNext,
                ),
              const MaterialPositionIndicator(),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.lock_open_rounded, color: Colors.white54, size: 20),
                onPressed: _toggleLock,
              ),
            ],
            seekBarPositionColor: Colors.red,
            seekBarBufferColor: Colors.white24,
            seekBarColor: Colors.white12,
            seekBarThumbColor: Colors.red,
            seekBarThumbSize: 14.0,
            seekBarHeight: 3.5,
            seekBarMargin: const EdgeInsets.only(bottom: 56, left: 16, right: 16),
          ),
          fullscreen: const MaterialVideoControlsThemeData(
            volumeGesture: true,
            brightnessGesture: true,
            seekGesture: true,
          ),
          child: Stack(
            children: [
              Video(controller: _controller, controls: MaterialVideoControls,
                  fit: _currentFit, subtitleViewConfiguration: _subtitleConfig()),
              if (_loading)
                const IgnorePointer(child: Center(child: CircularProgressIndicator(color: Colors.white54))),
              if (_error != null) _buildError(),
              // 画面比例 Toast（YouTube 风格，中央短暂显示）
              if (_fitToast != null)
                IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_fitToast!,
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              // 长按 2x 加速提示
              if (_longPressSpeed)
                IgnorePointer(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      margin: const EdgeInsets.only(top: 60),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(S.current.embySpeedUp,
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  SubtitleViewConfiguration _subtitleConfig() => SubtitleViewConfiguration(
        style: TextStyle(
            fontSize: _subtitleFontSize,
            color: Colors.white,
            backgroundColor: const Color(0x99000000),
            height: 1.4),
        textAlign: TextAlign.center,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 60),
      );

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Colors.white38, size: 48),
            const SizedBox(height: 16),
            Text(S.current.embyPlayFailed,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Text(_error!,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () {
                setState(() { _loading = true; _error = null; });
                _setupAndPlay();
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white24),
              ),
              child: Text(S.current.retry),
            ),
          ],
        ),
      ),
    );
  }
}

