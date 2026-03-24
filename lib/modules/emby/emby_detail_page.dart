import 'package:flutter/material.dart';

import 'emby_client.dart';
import 'emby_player_page.dart';
import 'emby_theme.dart';

// ── Models ────────────────────────────────────────────────────────────────────

class _Season {
  final String id;
  final String name;
  _Season({required this.id, required this.name});
  factory _Season.fromJson(Map<String, dynamic> j) =>
      _Season(id: j['Id'] as String, name: j['Name'] as String);
}

class _Episode {
  final String id;
  final String name;
  final int? episodeIndex;
  final int? runTimeTicks;
  final bool hasThumbnail;
  final String? overview;

  _Episode({
    required this.id,
    required this.name,
    this.episodeIndex,
    this.runTimeTicks,
    required this.hasThumbnail,
    this.overview,
  });

  factory _Episode.fromJson(Map<String, dynamic> j) {
    final img = j['ImageTags'] as Map<String, dynamic>?;
    return _Episode(
      id: j['Id'] as String,
      name: j['Name'] as String,
      episodeIndex: j['IndexNumber'] as int?,
      runTimeTicks: j['RunTimeTicks'] as int?,
      hasThumbnail: img?.containsKey('Primary') == true,
      overview: j['Overview'] as String?,
    );
  }

  String get label => episodeIndex != null ? '第$episodeIndex集' : '';

  String get durationLabel {
    if (runTimeTicks == null) return '';
    final min = runTimeTicks! ~/ 600000000;
    if (min >= 60) return '${min ~/ 60}h${(min % 60).toString().padLeft(2, '0')}m';
    return '$min分钟';
  }
}

class _Person {
  final String name;
  final String? role;
  final String type; // Actor, Director, Writer
  final String? id;
  final bool hasImage;

  _Person({
    required this.name,
    this.role,
    required this.type,
    this.id,
    required this.hasImage,
  });

  factory _Person.fromJson(Map<String, dynamic> j) => _Person(
        name: j['Name'] as String,
        role: j['Role'] as String?,
        type: j['Type'] as String? ?? '',
        id: j['Id'] as String?,
        hasImage: (j['PrimaryImageTag'] as String?) != null,
      );
}

class _SimilarItem {
  final String id;
  final String name;
  final String type;
  final int? year;
  final bool hasPoster;

  _SimilarItem({
    required this.id,
    required this.name,
    required this.type,
    this.year,
    required this.hasPoster,
  });

  factory _SimilarItem.fromJson(Map<String, dynamic> j) {
    final img = j['ImageTags'] as Map<String, dynamic>?;
    return _SimilarItem(
      id: j['Id'] as String,
      name: j['Name'] as String,
      type: j['Type'] as String? ?? '',
      year: j['ProductionYear'] as int?,
      hasPoster: img?.containsKey('Primary') == true,
    );
  }
}

// ── Detail page ───────────────────────────────────────────────────────────────

/// Netflix-style detail page for all content types.
///
/// Shows instantly with data from the grid, then lazy-loads:
/// - Series: seasons + episodes
/// - All: cast, similar items
class EmbyDetailPage extends StatefulWidget {
  final EmbyClient api;
  final String serverUrl;
  final String userId;
  final String accessToken;
  final String serverId;
  final String itemId;
  final String itemName;
  final String itemType;
  final int? year;
  final bool hasPoster;
  final bool hasBackdrop;
  final String? overview;
  final double? rating;
  final List<String> genres;
  final String? runtimeLabel;

  const EmbyDetailPage({
    super.key,
    required this.api,
    required this.serverUrl,
    required this.userId,
    required this.accessToken,
    required this.serverId,
    required this.itemId,
    required this.itemName,
    required this.itemType,
    this.year,
    this.hasPoster = false,
    this.hasBackdrop = false,
    this.overview,
    this.rating,
    this.genres = const [],
    this.runtimeLabel,
  });

  @override
  State<EmbyDetailPage> createState() => _EmbyDetailPageState();
}

class _EmbyDetailPageState extends State<EmbyDetailPage> {
  bool get _isSeries => widget.itemType == 'Series';

  // Lazy-loaded data
  List<_Person>? _cast;
  List<_SimilarItem>? _similar;

  // Series-specific
  List<_Season>? _seasons;
  String? _selectedSeasonId;
  List<_Episode>? _episodes;
  bool _loadingEpisodes = false;

  @override
  void initState() {
    super.initState();
    _loadExtra();
    if (_isSeries) _loadSeasons();
  }

  // ── Data loading ──────────────────────────────────────────────────────

  Future<void> _loadExtra() async {
    // Fetch cast + similar in parallel.
    try {
      final futures = await Future.wait([
        widget.api.get('/emby/Items/${widget.itemId}', {
          'Fields': 'People',
        }),
        widget.api.get('/emby/Items/${widget.itemId}/Similar', {
          'Limit': '12',
          'Fields': 'ImageTags',
        }),
      ]);
      if (!mounted) return;
      final detail = futures[0];
      final similarData = futures[1];
      setState(() {
        _cast = (detail['People'] as List<dynamic>?)
                ?.map((e) => _Person.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [];
        _similar = (similarData['Items'] as List<dynamic>?)
                ?.map((e) => _SimilarItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [];
      });
    } catch (_) {}
  }

  String? _seasonError;

  Future<void> _loadSeasons() async {
    setState(() => _seasonError = null);
    try {
      final data = await widget.api.get(
          '/emby/Shows/${widget.itemId}/Seasons',
          {'userId': widget.userId, 'Fields': 'ImageTags'});
      if (!mounted) return;
      final seasons = (data['Items'] as List<dynamic>)
          .map((e) => _Season.fromJson(e as Map<String, dynamic>))
          .toList();
      setState(() {
        _seasons = seasons;
        if (seasons.isNotEmpty) {
          _selectedSeasonId = seasons.first.id;
          _loadEpisodes(seasons.first.id);
        }
      });
    } catch (e) {
      if (mounted) setState(() => _seasonError = '加载失败，点击重试');
    }
  }

  Future<void> _loadEpisodes(String seasonId) async {
    setState(() {
      _loadingEpisodes = true;
      _episodes = null;
    });
    try {
      final data = await widget.api.get(
          '/emby/Shows/${widget.itemId}/Episodes', {
        'seasonId': seasonId,
        'userId': widget.userId,
        'Fields': 'Overview,ImageTags,RunTimeTicks',
      });
      if (!mounted) return;
      setState(() {
        _loadingEpisodes = false;
        _episodes = (data['Items'] as List<dynamic>)
            .map((e) => _Episode.fromJson(e as Map<String, dynamic>))
            .toList();
      });
    } catch (_) {
      if (mounted) setState(() => _loadingEpisodes = false);
    }
  }

  // ── Navigation ────────────────────────────────────────────────────────

  void _play({String? itemId, String? subtitle}) {
    final id = itemId ?? widget.itemId;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EmbyPlayerPage(
          serverUrl: widget.serverUrl,
          accessToken: widget.accessToken,
          streamUrl: widget.api.streamUrl(id),
          itemId: id,
          title: widget.itemName,
          subtitle: subtitle,
        ),
      ),
    );
  }

  void _openSimilar(_SimilarItem item) {
    // Navigate to a new detail page for the similar item.
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EmbyDetailPage(
          api: widget.api,
          serverUrl: widget.serverUrl,
          userId: widget.userId,
          accessToken: widget.accessToken,
          serverId: widget.serverId,
          itemId: item.id,
          itemName: item.name,
          itemType: item.type,
          year: item.year,
          hasPoster: item.hasPoster,
        ),
      ),
    );
  }

  // ── UI ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Detail page is always dark (Netflix pattern) — backdrop images
    // need dark background regardless of the app's theme mode.
    // Always dark — backdrop needs dark background (Netflix pattern).
    // Use Builder to get the inner dark-themed context for EmbyTheme calls.
    return Theme(
      data: ThemeData.dark(),
      child: Builder(builder: (ctx) => Scaffold(
        backgroundColor: EmbyTheme.scaffoldBg(ctx),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: CustomScrollView(
              slivers: [
            SliverToBoxAdapter(child: _buildBackdrop(ctx)),
            SliverToBoxAdapter(child: _buildInfo(ctx)),
            if (widget.overview != null && widget.overview!.isNotEmpty)
              SliverToBoxAdapter(child: _buildOverview()),
            if (_isSeries) ...[
              SliverToBoxAdapter(child: _buildSeasonTabs(ctx)),
              _buildEpisodeList(),
            ],
            if (_cast != null && _cast!.isNotEmpty)
              SliverToBoxAdapter(child: _buildCastSection()),
            if (_similar != null && _similar!.isNotEmpty)
              SliverToBoxAdapter(child: _buildSimilarSection()),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
          ),
        ),
      )),
    );
  }

  // ── Backdrop ──────────────────────────────────────────────────────────

  Widget _buildBackdrop(BuildContext ctx) {
    return Stack(
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: widget.hasBackdrop
              ? EmbyImage(
                  api: widget.api,
                  itemId: widget.itemId,
                  url: widget.api.backdropUrl(widget.itemId, width: 800),
                  fit: BoxFit.cover,
                  width: 800,
                  placeholder: Container(color: const Color(0xFF27272A)),
                )
              : widget.hasPoster
                  ? EmbyImage(
                      api: widget.api,
                      itemId: widget.itemId,
                      fit: BoxFit.cover,
                      width: 400,
                      placeholder: Container(color: const Color(0xFF27272A)),
                    )
                  : Container(color: const Color(0xFF27272A)),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  EmbyTheme.gradientEnd(context).withValues(alpha: 0.3),
                  EmbyTheme.gradientEnd(context).withValues(alpha: 0.9),
                  EmbyTheme.gradientEnd(context),
                ],
                stops: const [0.0, 0.5, 0.85, 1.0],
              ),
            ),
          ),
        ),
        Positioned(
          top: MediaQuery.of(ctx).padding.top + 4,
          left: 4,
          child: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(ctx),
          ),
        ),
      ],
    );
  }

  // ── Info section ──────────────────────────────────────────────────────

  Widget _buildInfo(BuildContext ctx) {
    final metaParts = <String>[
      if (widget.year != null) '${widget.year}',
      if (widget.runtimeLabel != null && widget.runtimeLabel!.isNotEmpty)
        widget.runtimeLabel!,
      if (widget.rating != null) '★ ${widget.rating!.toStringAsFixed(1)}',
      ...widget.genres.take(3),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.itemName,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  height: 1.2)),
          if (metaParts.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: metaParts
                  .map((t) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(t,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
                      ))
                  .toList(),
            ),
          ],
          if (!_isSeries) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _play(
                  subtitle: [
                    if (widget.year != null) '${widget.year}',
                    if (widget.runtimeLabel != null &&
                        widget.runtimeLabel!.isNotEmpty)
                      widget.runtimeLabel!,
                  ].join(' · '),
                ),
                icon: const Icon(Icons.play_arrow_rounded, size: 22),
                label: const Text('播放'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  textStyle: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Overview ──────────────────────────────────────────────────────────

  Widget _buildOverview() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Text(widget.overview!,
          style: const TextStyle(
              color: Colors.white60, fontSize: 13, height: 1.6)),
    );
  }

  // ── Cast section ──────────────────────────────────────────────────────

  Widget _buildCastSection() {
    final directors =
        _cast!.where((p) => p.type == 'Director').map((p) => p.name);
    final actors = _cast!.where((p) => p.type == 'Actor').take(20).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (directors.isNotEmpty) ...[
            Text('导演: ${directors.join(', ')}',
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(height: 8),
          ],
          if (actors.isNotEmpty) ...[
            const Text('演员',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            SizedBox(
              height: 100,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: actors.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) => _buildActorChip(actors[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActorChip(_Person p) {
    return SizedBox(
      width: 70,
      child: Column(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: const Color(0xFF2A2A2E),
            backgroundImage: p.hasImage && p.id != null
                ? NetworkImage(
                    '${widget.serverUrl}/emby/Items/${p.id}/Images/Primary'
                    '?maxWidth=100&api_key=${widget.accessToken}')
                : null,
            child: !p.hasImage
                ? const Icon(Icons.person_rounded,
                    color: Colors.white24, size: 24)
                : null,
          ),
          const SizedBox(height: 6),
          Text(p.name,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center),
          if (p.role != null && p.role!.isNotEmpty)
            Text(p.role!,
                style: const TextStyle(color: Colors.white30, fontSize: 9),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center),
        ],
      ),
    );
  }

  // ── Similar section ───────────────────────────────────────────────────

  Widget _buildSimilarSection() {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('相似推荐',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 180,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _similar!.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _buildSimilarCard(_similar![i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimilarCard(_SimilarItem item) {
    return GestureDetector(
      onTap: () => _openSimilar(item),
      child: SizedBox(
        width: 110,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 110,
                height: 150,
                child: item.hasPoster
                    ? EmbyImage(
                        api: widget.api,
                        itemId: item.id,
                        fit: BoxFit.cover,
                        width: 200,
                        placeholder: _posterPlaceholder(),
                      )
                    : _posterPlaceholder(),
              ),
            ),
            const SizedBox(height: 4),
            Text(item.name,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _posterPlaceholder() {
    return Container(
      color: const Color(0xFF27272A),
      child: const Icon(Icons.movie_outlined, color: Colors.white24, size: 28),
    );
  }

  // ── Season tabs (series only) ─────────────────────────────────────────

  Widget _buildSeasonTabs(BuildContext ctx) {
    if (_seasonError != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Center(
          child: GestureDetector(
            onTap: _loadSeasons,
            child: Text(_seasonError!,
                style: const TextStyle(color: Colors.white38, fontSize: 13)),
          ),
        ),
      );
    }
    if (_seasons == null || _seasons!.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 20),
        child: Center(
            child: CircularProgressIndicator(color: Colors.white54)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: SizedBox(
        height: 36,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: _seasons!.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final s = _seasons![i];
            final selected = s.id == _selectedSeasonId;
            return GestureDetector(
              onTap: () {
                if (_selectedSeasonId == s.id) return;
                setState(() => _selectedSeasonId = s.id);
                _loadEpisodes(s.id);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: selected ? EmbyTheme.pillSelected(context) : EmbyTheme.pillUnselected(context),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(s.name,
                    style: TextStyle(
                      color: selected ? EmbyTheme.pillSelectedText(context) : EmbyTheme.pillUnselectedText(context),
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal,
                      fontSize: 13,
                    )),
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Episode list (series only) ────────────────────────────────────────

  Widget _buildEpisodeList() {
    if (_loadingEpisodes) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.only(top: 30),
          child: Center(
              child: CircularProgressIndicator(color: Colors.white54)),
        ),
      );
    }
    final eps = _episodes;
    if (eps == null || eps.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (_, i) => _buildEpisodeTile(eps[i]),
        childCount: eps.length,
      ),
    );
  }

  Widget _buildEpisodeTile(_Episode ep) {
    return InkWell(
      onTap: () => _play(
        itemId: ep.id,
        subtitle: [ep.label, if (ep.durationLabel.isNotEmpty) ep.durationLabel]
            .join(' · '),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 140,
                height: 79,
                child: ep.hasThumbnail
                    ? EmbyImage(
                        api: widget.api,
                        itemId: ep.id,
                        fit: BoxFit.cover,
                        width: 300,
                        placeholder: _thumbPlaceholder(),
                      )
                    : _thumbPlaceholder(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ep.label.isNotEmpty ? '${ep.label}  ${ep.name}' : ep.name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (ep.durationLabel.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(ep.durationLabel,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11)),
                  ],
                  if (ep.overview != null && ep.overview!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(ep.overview!,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11, height: 1.4),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumbPlaceholder() {
    return Container(
      color: const Color(0xFF27272A),
      child: const Icon(Icons.play_circle_outline_rounded,
          color: Colors.white24, size: 28),
    );
  }
}
