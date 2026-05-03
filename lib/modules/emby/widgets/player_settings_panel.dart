import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../../i18n/app_strings.dart';
import '../../../theme.dart';
import '../emby_client.dart';
import '../playback_rate_state.dart';

/// Netflix-style unified settings panel for the Emby player.
///
/// Was inlined in `emby_player_page.dart` (~370 lines across
/// `_SettingsPanel` + `_OptionTile`). Pulled out so the player page
/// itself focuses on player lifecycle / state machine while the
/// settings sheet evolves on its own — track lists, rate selector,
/// subtitle size slider, and tabbed UI all live here.

// ── Netflix-style unified settings panel ─────────────────────────────────────

class EmbyPlayerSettingsPanel extends StatefulWidget {
  final Player player;
  final List<Map<String, dynamic>> embyAudio;
  final List<Map<String, dynamic>> embySubs;
  final String serverUrl;
  final String itemId;
  final String accessToken;
  final double currentRate;
  final double subtitleFontSize;
  final int initialTab;
  final ValueChanged<double> onRateChanged;
  final ValueChanged<double> onSubtitleSizeChanged;

  const EmbyPlayerSettingsPanel({
    super.key,
    required this.player,
    required this.embyAudio,
    required this.embySubs,
    required this.serverUrl,
    required this.itemId,
    required this.accessToken,
    required this.currentRate,
    required this.subtitleFontSize,
    this.initialTab = 0,
    required this.onRateChanged,
    required this.onSubtitleSizeChanged,
  });

  @override
  State<EmbyPlayerSettingsPanel> createState() =>
      _EmbyPlayerSettingsPanelState();
}

class _EmbyPlayerSettingsPanelState extends State<EmbyPlayerSettingsPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  late double _currentSize;

  @override
  void initState() {
    super.initState();
    _tab = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab,
    );
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
            labelStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
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
      return Center(
        child: Text(
          S.current.embyNoAudioTrack,
          style: const TextStyle(color: Colors.white38),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: real.length,
      itemBuilder: (_, i) {
        final track = real[i];
        final selected = widget.player.state.track.audio == track;
        return _PlayerOptionTile(
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
    const sizes = <String, double>{'小': 24, '中': 32, '大': 40, '特大': 52};
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // Track selection.
        _PlayerOptionTile(
          label: S.current.close,
          selected: widget.player.state.track.subtitle == SubtitleTrack.no(),
          onTap: () {
            widget.player.setSubtitleTrack(SubtitleTrack.no());
            Navigator.pop(context);
          },
        ),
        for (int i = 0; i < widget.embySubs.length; i++)
          _PlayerOptionTile(
            label: _subLabel(i),
            selected: false,
            onTap: () {
              _applySubtitle(i);
              Navigator.pop(context);
            },
          ),
        if (widget.embySubs.isEmpty)
          for (int i = 2; i < widget.player.state.tracks.subtitle.length; i++)
            _PlayerOptionTile(
              label:
                  widget.player.state.tracks.subtitle[i].title ??
                  widget.player.state.tracks.subtitle[i].language ??
                  '字幕 ${i - 1}',
              selected:
                  widget.player.state.track.subtitle ==
                  widget.player.state.tracks.subtitle[i],
              onTap: () {
                widget.player.setSubtitleTrack(
                  widget.player.state.tracks.subtitle[i],
                );
                Navigator.pop(context);
              },
            ),
        // ── Subtitle size ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
          child: Row(
            children: [
              Text(
                S.current.embySubtitleSize,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(width: 16),
              ...sizes.entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () {
                      widget.onSubtitleSizeChanged(e.value);
                      setState(() => _currentSize = e.value);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _currentSize == e.value
                            ? Colors.red
                            : Colors.white12,
                        borderRadius: BorderRadius.circular(YLRadius.sm),
                      ),
                      child: Text(
                        e.key,
                        style: TextStyle(
                          color: _currentSize == e.value
                              ? Colors.white
                              : Colors.white54,
                          fontSize: 13,
                          fontWeight: _currentSize == e.value
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
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

    // 图片字幕（PGS/VOBSUB）用 mpv 内嵌轨道切换
    final bitmapCodecs = {
      'pgssub',
      'dvdsub',
      'hdmv_pgs_subtitle',
      'dvd_subtitle',
      'sup',
    };
    if (bitmapCodecs.contains(codec.toLowerCase())) {
      // 匹配 mpv 内嵌字幕轨（跳过前2个系统轨）
      final embedded = widget.player.state.tracks.subtitle;
      if (i + 2 < embedded.length) {
        await widget.player.setSubtitleTrack(embedded[i + 2]);
      }
      return;
    }

    // 文字字幕：下载内容后加载
    final fmt = codec == 'ass' || codec == 'ssa' ? 'ass' : 'srt';
    final url =
        '${widget.serverUrl}/Videos/${widget.itemId}/Subtitles/$idx/Stream.$fmt'
        '?api_key=${widget.accessToken}';
    final authHeader =
        'MediaBrowser Client="YueLink", Device="Flutter", '
        'DeviceId="yuelink-flutter", Version="1.0", '
        'Token="${widget.accessToken}"';
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final proxyPort = EmbyClient.activeProxyPort;
      if (proxyPort != null) {
        client.findProxy = (_) => 'PROXY 127.0.0.1:$proxyPort';
      } else {
        client.findProxy = (_) => 'DIRECT';
      }
      client.badCertificateCallback = (_, _, _) => true;
      try {
        final request = await client.getUrl(Uri.parse(url));
        request.headers.set('X-Emby-Authorization', authHeader);
        final response = await request.close();
        if (response.statusCode == 200) {
          final data = await response
              .transform(const Utf8Decoder(allowMalformed: true))
              .join();
          if (data.isNotEmpty && !data.contains('<!DOCTYPE')) {
            await widget.player.setSubtitleTrack(
              SubtitleTrack.data(
                data,
                title: sub['Title'] as String? ?? '',
                language: sub['Language'] as String?,
              ),
            );
            return;
          }
        }
      } finally {
        client.close();
      }
    } catch (_) {}
    // Fallback: mpv 内嵌轨道
    final embedded = widget.player.state.tracks.subtitle;
    if (i + 2 < embedded.length) {
      await widget.player.setSubtitleTrack(embedded[i + 2]);
    }
  }

  // ── Speed tab ─────────────────────────────────────────────────────────

  Widget _buildSpeedTab() {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: speeds
          .map(
            (r) => _PlayerOptionTile(
              label: r == 1.0 ? '正常' : formatEmbyPlaybackRate(r),
              selected: embyPlaybackRateEquals(widget.currentRate, r),
              onTap: () {
                widget.onRateChanged(r);
                Navigator.pop(context);
              },
            ),
          )
          .toList(),
    );
  }
}

// ── Shared option tile ────────────────────────────────────────────────────────

class _PlayerOptionTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PlayerOptionTile({
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
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            if (selected)
              const Icon(Icons.check_rounded, color: Colors.white, size: 20),
          ],
        ),
      ),
    );
  }
}
