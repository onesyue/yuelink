import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/kernel/core_manager.dart';
import 'emby_client.dart';

/// Netflix-style native video player for Emby content.
class EmbyPlayerPage extends StatefulWidget {
  final String serverUrl;
  final String accessToken;
  final String userId;
  final String streamUrl;
  final String itemId;
  final String title;
  final String? subtitle;

  const EmbyPlayerPage({
    super.key,
    required this.serverUrl,
    required this.accessToken,
    required this.userId,
    required this.streamUrl,
    required this.itemId,
    required this.title,
    this.subtitle,
  });

  @override
  State<EmbyPlayerPage> createState() => _EmbyPlayerPageState();
}

class _EmbyPlayerPageState extends State<EmbyPlayerPage> {
  // Session-wide subtitle font size (persists while app is running).
  static double _savedFontSize = 22.0;

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

  // Emby playback-session tracking.
  final String _sessionId =
      DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  bool _playbackStarted = false;

  List<Map<String, dynamic>> _embyAudio = [];
  List<Map<String, dynamic>> _embySubs = [];

  @override
  void initState() {
    super.initState();
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
  void dispose() {
    _progressTimer?.cancel();
    _bufferingSub?.cancel();
    _tracksSub?.cancel();
    _positionSub?.cancel();
    if (_playbackStarted) _reportStop(); // fire-and-forget before close
    _player.dispose();
    _api.close();
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
      if (!Platform.isIOS) {
        final mixedPort = CoreManager.instance.mixedPort;
        final np = _player.platform as NativePlayer;
        if (mixedPort > 0) {
          await np.setProperty('http-proxy', 'http://127.0.0.1:$mixedPort');
        }
        await np.setProperty('tls-verify', 'no');
      }
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
      if (totalTicks != null && totalTicks > 0 && posTicks / totalTicks > 0.95)
        return;
      if (!mounted) return;
      final resume = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1C1C1E),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('继续上次播放',
              style: TextStyle(color: Colors.white, fontSize: 16)),
          content: Text(_formatPosition(posSeconds),
              style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('重新开始',
                  style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child:
                  const Text('继续', style: TextStyle(color: Colors.redAccent)),
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
    _progressTimer = Timer.periodic(const Duration(seconds: 10), (_) {
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

  Future<void> _reportStop() async {
    await _api.post('/emby/Sessions/Playing/Stopped', {
      'ItemId': widget.itemId,
      'MediaSourceId': widget.itemId,
      'PositionTicks': _positionTicks,
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
      builder: (_) => _SettingsPanel(
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

  // ── UI ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: MaterialVideoControlsTheme(
        normal: MaterialVideoControlsThemeData(
          seekOnDoubleTap: true,
          volumeGesture: true,
          brightnessGesture: true,
          topButtonBar: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (widget.subtitle != null)
                    Text(widget.subtitle!,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
            if (_playbackRate != 1.0)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('${_playbackRate}x',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 11)),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.tune_rounded,
                  color: Colors.white, size: 22),
              onPressed: _showSettings,
            ),
          ],
          bottomButtonBar: const [
            MaterialPlayOrPauseButton(),
            MaterialPositionIndicator(),
            Spacer(),
            MaterialFullscreenButton(),
          ],
          seekBarPositionColor: Colors.red,
          seekBarBufferColor: Colors.white24,
          seekBarColor: Colors.white12,
          seekBarThumbColor: Colors.red,
          seekBarThumbSize: 14.0,
          seekBarHeight: 3.5,
          seekBarMargin:
              const EdgeInsets.only(bottom: 56, left: 16, right: 16),
        ),
        fullscreen: const MaterialVideoControlsThemeData(),
        child: Stack(
          children: [
            Video(
              controller: _controller,
              controls: MaterialVideoControls,
              subtitleViewConfiguration: SubtitleViewConfiguration(
                style: TextStyle(
                    fontSize: _subtitleFontSize,
                    color: Colors.white,
                    backgroundColor: const Color(0x99000000),
                    height: 1.4),
                textAlign: TextAlign.center,
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 60),
              ),
            ),
            if (_loading)
              const Center(
                  child: CircularProgressIndicator(color: Colors.white54)),
            if (_error != null) _buildError(),
          ],
        ),
      ),
    );
  }

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
            const Text('播放失败',
                style: TextStyle(
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
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Netflix-style unified settings panel ─────────────────────────────────────

class _SettingsPanel extends StatefulWidget {
  final Player player;
  final List<Map<String, dynamic>> embyAudio;
  final List<Map<String, dynamic>> embySubs;
  final String serverUrl;
  final String itemId;
  final String accessToken;
  final double currentRate;
  final double subtitleFontSize;
  final ValueChanged<double> onRateChanged;
  final ValueChanged<double> onSubtitleSizeChanged;

  const _SettingsPanel({
    required this.player,
    required this.embyAudio,
    required this.embySubs,
    required this.serverUrl,
    required this.itemId,
    required this.accessToken,
    required this.currentRate,
    required this.subtitleFontSize,
    required this.onRateChanged,
    required this.onSubtitleSizeChanged,
  });

  @override
  State<_SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<_SettingsPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  late double _currentSize;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _currentSize = widget.subtitleFontSize;
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.45,
      decoration: const BoxDecoration(
        color: Color(0xF01C1C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          TabBar(
            controller: _tab,
            indicatorColor: Colors.red,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            labelStyle:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 14),
            dividerHeight: 0.5,
            dividerColor: Colors.white12,
            tabs: const [
              Tab(text: '音频'),
              Tab(text: '字幕'),
              Tab(text: '速度'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _buildAudioTab(),
                _buildSubtitleTab(),
                _buildSpeedTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Audio tab ─────────────────────────────────────────────────────────

  Widget _buildAudioTab() {
    final embedded = widget.player.state.tracks.audio;
    final real = embedded.length > 2 ? embedded.sublist(2) : <AudioTrack>[];
    if (real.isEmpty) {
      return const Center(
          child: Text('无可用音轨', style: TextStyle(color: Colors.white38)));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: real.length,
      itemBuilder: (_, i) {
        final track = real[i];
        final selected = widget.player.state.track.audio == track;
        return _OptionTile(
          label: _audioLabel(track, i),
          selected: selected,
          onTap: () {
            widget.player.setAudioTrack(track);
            Navigator.pop(context);
          },
        );
      },
    );
  }

  String _audioLabel(AudioTrack track, int index) {
    if (index < widget.embyAudio.length) {
      final s = widget.embyAudio[index];
      final parts = <String>[
        s['DisplayLanguage'] as String? ?? s['Language'] as String? ?? '',
        s['DisplayTitle'] as String? ?? s['Title'] as String? ?? '',
        (s['Codec'] as String? ?? '').toUpperCase(),
        if (s['Channels'] is int) '${s['Channels']}ch',
      ].where((s) => s.isNotEmpty);
      if (parts.isNotEmpty) return parts.join(' · ');
    }
    return track.title ?? track.language ?? '音轨 ${index + 1}';
  }

  // ── Subtitle tab ──────────────────────────────────────────────────────

  Widget _buildSubtitleTab() {
    // Subtitle size presets.
    const sizes = <String, double>{'小': 16, '中': 22, '大': 30, '特大': 40};
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // Track selection.
        _OptionTile(
          label: '关闭',
          selected:
              widget.player.state.track.subtitle == SubtitleTrack.no(),
          onTap: () {
            widget.player.setSubtitleTrack(SubtitleTrack.no());
            Navigator.pop(context);
          },
        ),
        for (int i = 0; i < widget.embySubs.length; i++)
          _OptionTile(
            label: _subLabel(i),
            selected: false,
            onTap: () {
              _applySubtitle(i);
              Navigator.pop(context);
            },
          ),
        if (widget.embySubs.isEmpty)
          for (int i = 2;
              i < widget.player.state.tracks.subtitle.length;
              i++)
            _OptionTile(
              label: widget.player.state.tracks.subtitle[i].title ??
                  widget.player.state.tracks.subtitle[i].language ??
                  '字幕 ${i - 1}',
              selected: widget.player.state.track.subtitle ==
                  widget.player.state.tracks.subtitle[i],
              onTap: () {
                widget.player
                    .setSubtitleTrack(widget.player.state.tracks.subtitle[i]);
                Navigator.pop(context);
              },
            ),
        // ── Subtitle size ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
          child: Row(
            children: [
              const Text('字幕大小',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(width: 16),
              ...sizes.entries.map((e) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () {
                        widget.onSubtitleSizeChanged(e.value);
                        setState(() => _currentSize = e.value);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _currentSize == e.value
                              ? Colors.red
                              : Colors.white12,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(e.key,
                            style: TextStyle(
                              color: _currentSize == e.value
                                  ? Colors.white
                                  : Colors.white54,
                              fontSize: 13,
                              fontWeight: _currentSize == e.value
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            )),
                      ),
                    ),
                  )),
            ],
          ),
        ),
      ],
    );
  }

  String _subLabel(int i) {
    final s = widget.embySubs[i];
    final parts = <String>[
      s['DisplayLanguage'] as String? ?? s['Language'] as String? ?? '',
      s['DisplayTitle'] as String? ?? s['Title'] as String? ?? '',
      if ((s['Codec'] as String? ?? '').isNotEmpty) '(${s['Codec']})',
    ].where((s) => s.isNotEmpty);
    return parts.isNotEmpty ? parts.join(' ') : '字幕 ${i + 1}';
  }

  Future<void> _applySubtitle(int i) async {
    final sub = widget.embySubs[i];
    final idx = sub['Index'] as int;
    final codec = (sub['Codec'] as String?) ?? 'srt';
    final fmt = codec == 'ass' ? 'ass' : 'srt';
    await widget.player.setSubtitleTrack(SubtitleTrack.uri(
      '${widget.serverUrl}/Videos/${widget.itemId}/Subtitles/$idx/Stream.$fmt'
      '?api_key=${widget.accessToken}',
      title: sub['Title'] as String? ?? '',
      language: sub['Language'] as String?,
    ));
  }

  // ── Speed tab ─────────────────────────────────────────────────────────

  Widget _buildSpeedTab() {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: speeds
          .map((r) => _OptionTile(
                label: r == 1.0 ? '正常' : '${r}x',
                selected: widget.currentRate == r,
                onTap: () {
                  widget.onRateChanged(r);
                  Navigator.pop(context);
                },
              ))
          .toList(),
    );
  }
}

// ── Shared option tile ────────────────────────────────────────────────────────

class _OptionTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _OptionTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? Colors.red : Colors.transparent,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white70,
                    fontSize: 15,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.normal,
                  )),
            ),
            if (selected)
              const Icon(Icons.check_rounded, color: Colors.white, size: 20),
          ],
        ),
      ),
    );
  }
}
