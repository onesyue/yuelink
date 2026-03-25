import 'package:flutter/material.dart';

import 'emby_client.dart';
import 'emby_detail_page.dart';
import 'emby_theme.dart';

// ── Models ────────────────────────────────────────────────────────────────────

class _Library {
  final String id;
  final String name;
  final String type;
  _Library({required this.id, required this.name, required this.type});

  factory _Library.fromJson(Map<String, dynamic> j) => _Library(
        id: j['Id'] as String,
        name: j['Name'] as String,
        type: (j['CollectionType'] as String?) ?? '',
      );

  IconData get icon {
    switch (type) {
      case 'movies':
        return Icons.movie_outlined;
      case 'tvshows':
        return Icons.tv_outlined;
      case 'music':
        return Icons.music_note_outlined;
      default:
        return Icons.folder_outlined;
    }
  }

  String get includeItemTypes {
    switch (type) {
      case 'music':
        return 'MusicAlbum';
      default:
        return 'Movie,Series';
    }
  }
}

class _Item {
  final String id;
  final String name;
  final String type;
  final int? year;
  final bool hasPoster;
  final bool hasBackdrop;
  final String? overview;
  final double? rating;
  final List<String> genres;
  final int? runTimeTicks;

  _Item({
    required this.id,
    required this.name,
    required this.type,
    this.year,
    required this.hasPoster,
    required this.hasBackdrop,
    this.overview,
    this.rating,
    this.genres = const [],
    this.runTimeTicks,
  });

  factory _Item.fromJson(Map<String, dynamic> j) {
    final imgTags = j['ImageTags'] as Map<String, dynamic>?;
    final backdrops = j['BackdropImageTags'] as List<dynamic>?;
    return _Item(
      id: j['Id'] as String,
      name: j['Name'] as String,
      type: j['Type'] as String,
      year: j['ProductionYear'] as int?,
      hasPoster: imgTags?.containsKey('Primary') == true,
      hasBackdrop: backdrops != null && backdrops.isNotEmpty,
      overview: j['Overview'] as String?,
      rating: (j['CommunityRating'] as num?)?.toDouble(),
      genres: (j['Genres'] as List<dynamic>?)?.cast<String>() ?? const [],
      runTimeTicks: j['RunTimeTicks'] as int?,
    );
  }

  String get runtimeLabel {
    if (runTimeTicks == null) return '';
    final min = runTimeTicks! ~/ 600000000;
    if (min >= 60) return '${min ~/ 60}h${(min % 60).toString().padLeft(2, '0')}m';
    return '$min分钟';
  }
}

// ── Netflix-style Media Page ─────────────────────────────────────────────────

class EmbyMediaPage extends StatefulWidget {
  final String serverUrl;
  final String userId;
  final String accessToken;
  final String serverId;

  const EmbyMediaPage({
    super.key,
    required this.serverUrl,
    required this.userId,
    required this.accessToken,
    required this.serverId,
  });

  @override
  State<EmbyMediaPage> createState() => _EmbyMediaPageState();
}

class _EmbyMediaPageState extends State<EmbyMediaPage> {
  late final EmbyClient _api;
  List<_Library>? _libraries;
  bool _loadingLibs = true;
  String? _error;
  String _query = '';

  /// Preview cache: most recent 20 items per library (for horizontal rows).
  final Map<String, List<_Item>> _previewCache = {};
  final Set<String> _loadingPreviews = {};

  @override
  void initState() {
    super.initState();
    _api = EmbyClient(
      serverUrl: widget.serverUrl,
      accessToken: widget.accessToken,
      userId: widget.userId,
    );
    _loadLibraries();
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  // ── Data loading ──────────────────────────────────────────────────────

  Future<void> _loadLibraries() async {
    setState(() {
      _loadingLibs = true;
      _error = null;
    });
    try {
      final data = await _api.get('/emby/Users/${widget.userId}/Views');
      if (!mounted) return;
      final libs = (data['Items'] as List<dynamic>)
          .map((e) => _Library.fromJson(e as Map<String, dynamic>))
          .toList();
      setState(() {
        _libraries = libs;
        _loadingLibs = false;
      });
      // Load preview rows for all libraries in parallel
      for (final lib in libs) {
        _loadPreview(lib);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingLibs = false;
        _error = '获取媒体库失败\n$e';
      });
    }
  }

  Future<void> _loadPreview(_Library lib) async {
    if (_previewCache.containsKey(lib.id)) return;
    setState(() => _loadingPreviews.add(lib.id));
    try {
      final data = await _api.get('/emby/Users/${widget.userId}/Items', {
        'parentId': lib.id,
        'Limit': '20',
        'SortBy': 'DateCreated,SortName',
        'SortOrder': 'Descending',
        'Fields': 'ImageTags,BackdropImageTags,Overview,CommunityRating,Genres,RunTimeTicks',
        'Recursive': 'true',
        'IncludeItemTypes': lib.includeItemTypes,
      });
      if (!mounted) return;
      final items = (data['Items'] as List<dynamic>)
          .map((e) => _Item.fromJson(e as Map<String, dynamic>))
          .toList();
      setState(() {
        _previewCache[lib.id] = items;
        _loadingPreviews.remove(lib.id);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _previewCache[lib.id] = const [];
        _loadingPreviews.remove(lib.id);
      });
    }
  }

  // ── Navigation ────────────────────────────────────────────────────────

  void _openItem(_Item item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EmbyDetailPage(
          api: _api,
          serverUrl: widget.serverUrl,
          userId: widget.userId,
          accessToken: widget.accessToken,
          serverId: widget.serverId,
          itemId: item.id,
          itemName: item.name,
          itemType: item.type,
          year: item.year,
          hasPoster: item.hasPoster,
          hasBackdrop: item.hasBackdrop,
          overview: item.overview,
          rating: item.rating,
          genres: item.genres,
          runtimeLabel: item.runtimeLabel,
        ),
      ),
    );
  }

  void _openLibraryGrid(_Library lib) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _LibraryGridPage(
          api: _api,
          lib: lib,
          userId: widget.userId,
          onItemTap: _openItem,
        ),
      ),
    );
  }

  // ── UI ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EmbyTheme.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: EmbyTheme.appBarBg(context),
        foregroundColor: EmbyTheme.textPrimary(context),
        elevation: 0,
        title: Text('悦视频',
            style: TextStyle(
                color: EmbyTheme.textPrimary(context),
                fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              _previewCache.clear();
              _loadingPreviews.clear();
              setState(() => _query = '');
              _loadLibraries();
            },
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loadingLibs) return _buildSkeleton();
    if (_error != null) return _buildError(_error!);
    if (_libraries == null || _libraries!.isEmpty) {
      return Center(
        child: Text('暂无媒体库',
            style: TextStyle(color: EmbyTheme.textSecondary(context))),
      );
    }
    return Column(
      children: [
        _buildSearchBar(),
        Expanded(
          child: _query.isNotEmpty ? _buildSearchResults() : _buildNetflixRows(),
        ),
      ],
    );
  }

  // ── Responsive breakpoints ──────────────────────────────────────────

  double get _posterHeight {
    final w = MediaQuery.of(context).size.width;
    if (w > 1200) return 280;
    if (w > 900) return 240;
    return 180;
  }

  // ── Netflix-style rows ──────────────────────────────────────────────

  Widget _buildNetflixRows() {
    // Collect first item with backdrop for Hero Banner
    _Item? heroItem;
    for (final lib in _libraries!) {
      final items = _previewCache[lib.id];
      if (items != null) {
        final candidate = items.where((i) => i.hasBackdrop).firstOrNull
            ?? items.where((i) => i.hasPoster).firstOrNull;
        if (candidate != null && heroItem == null) heroItem = candidate;
      }
    }

    return RefreshIndicator(
      color: EmbyTheme.textSecondary(context),
      backgroundColor: EmbyTheme.appBarBg(context),
      onRefresh: () async {
        _previewCache.clear();
        _loadingPreviews.clear();
        await _loadLibraries();
      },
      child: CustomScrollView(
        slivers: [
          // ── Hero Banner ──
          if (heroItem != null)
            SliverToBoxAdapter(child: _buildHeroBanner(heroItem)),
          // ── Library rows ──
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) => _buildLibraryRow(_libraries![i]),
              childCount: _libraries!.length,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  // ── Hero Banner (Netflix featured content) ──────────────────────────

  Widget _buildHeroBanner(_Item item) {
    return GestureDetector(
      onTap: () => _openItem(item),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Backdrop image
            if (item.hasBackdrop)
              EmbyImage(
                api: _api,
                itemId: item.id,
                url: _api.backdropUrl(item.id, width: 1200),
                fit: BoxFit.cover,
                width: 1200,
              )
            else if (item.hasPoster)
              EmbyImage(
                api: _api,
                itemId: item.id,
                fit: BoxFit.cover,
                width: 600,
              ),
            // Bottom gradient
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent],
                    stops: [0.0, 0.6],
                  ),
                ),
              ),
            ),
            // Title + metadata
            Positioned(
              left: 20,
              right: 20,
              bottom: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (item.year != null)
                        Text('${item.year}',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13)),
                      if (item.year != null && item.rating != null)
                        const Text('  ·  ',
                            style: TextStyle(color: Colors.white38)),
                      if (item.rating != null)
                        Text('★ ${item.rating!.toStringAsFixed(1)}',
                            style: const TextStyle(
                                color: Colors.amber, fontSize: 13)),
                      if (item.runtimeLabel.isNotEmpty) ...[
                        const Text('  ·  ',
                            style: TextStyle(color: Colors.white38)),
                        Text(item.runtimeLabel,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13)),
                      ],
                    ],
                  ),
                  if (item.overview != null && item.overview!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      item.overview!,
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 12, height: 1.4),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 12),
                  // Play button
                  SizedBox(
                    height: 36,
                    child: FilledButton.icon(
                      onPressed: () => _openItem(item),
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label: const Text('播放'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        textStyle: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLibraryRow(_Library lib) {
    final items = _previewCache[lib.id];
    final loading = _loadingPreviews.contains(lib.id);
    final hasItems = items != null && items.isNotEmpty;
    final rowHeight = _posterHeight;

    // Hide empty libraries
    if (items != null && items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 12, 10),
          child: Row(
            children: [
              Icon(lib.icon,
                  size: 16, color: EmbyTheme.textSecondary(context)),
              const SizedBox(width: 6),
              Text(
                lib.name,
                style: TextStyle(
                  color: EmbyTheme.textPrimary(context),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (hasItems) ...[
                const SizedBox(width: 6),
                Text(
                  '${items!.length}',
                  style: TextStyle(
                    color: EmbyTheme.textTertiary(context),
                    fontSize: 13,
                  ),
                ),
              ],
              const Spacer(),
              if (hasItems)
                GestureDetector(
                  onTap: () => _openLibraryGrid(lib),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('查看全部',
                          style: TextStyle(
                              color: EmbyTheme.textSecondary(context),
                              fontSize: 13)),
                      Icon(Icons.chevron_right_rounded,
                          size: 18, color: EmbyTheme.textSecondary(context)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        // ── Horizontal poster row ──
        SizedBox(
          height: rowHeight,
          child: loading
              ? _buildRowSkeleton()
              : !hasItems
                  ? Center(
                      child: Text('暂无内容',
                          style: TextStyle(
                              color: EmbyTheme.textTertiary(context),
                              fontSize: 12)))
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: items!.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (_, i) =>
                          _buildRowPoster(items[i], height: rowHeight),
                    ),
        ),
      ],
    );
  }

  Widget _buildRowPoster(_Item item, {required double height}) {
    final posterWidth = height * 2 / 3;
    final titleSize = height > 200 ? 13.0 : 11.0;
    return GestureDetector(
      onTap: () => _openItem(item),
      child: SizedBox(
        width: posterWidth,
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (item.hasPoster)
                EmbyImage(
                  api: _api,
                  itemId: item.id,
                  fit: BoxFit.cover,
                  width: height > 200 ? 300 : 200,
                  placeholder: _posterPlaceholder(item),
                )
              else
                _posterPlaceholder(item),
              // Bottom gradient with title + metadata
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black, Colors.transparent],
                      stops: [0.0, 0.95],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.name,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: titleSize,
                          fontWeight: FontWeight.w500,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          if (item.year != null)
                            Text('${item.year}',
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 10)),
                          if (item.rating != null) ...[
                            if (item.year != null)
                              const SizedBox(width: 6),
                            Text('★${item.rating!.toStringAsFixed(1)}',
                                style: const TextStyle(
                                    color: Colors.amber, fontSize: 10)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _posterPlaceholder(_Item item) {
    return Container(
      color: EmbyTheme.placeholder(context),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            item.type == 'Series' ? Icons.tv_outlined : Icons.movie_outlined,
            color: EmbyTheme.textTertiary(context),
            size: 28,
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              item.name,
              style: TextStyle(
                  color: EmbyTheme.textTertiary(context), fontSize: 10),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ── Search ──────────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: TextField(
        onChanged: (v) => setState(() => _query = v),
        style:
            TextStyle(color: EmbyTheme.textPrimary(context), fontSize: 14),
        decoration: InputDecoration(
          hintText: '搜索所有媒体库...',
          hintStyle: TextStyle(
              color: EmbyTheme.textSecondary(context), fontSize: 14),
          prefixIcon: Icon(Icons.search_rounded,
              color: EmbyTheme.textSecondary(context), size: 18),
          suffixIcon: _query.isNotEmpty
              ? GestureDetector(
                  onTap: () => setState(() => _query = ''),
                  child: Icon(Icons.close_rounded,
                      color: EmbyTheme.textSecondary(context), size: 18),
                )
              : null,
          filled: true,
          fillColor: EmbyTheme.pillUnselected(context),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          isDense: true,
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    final q = _query.toLowerCase();
    final results = <_Item>[];
    for (final items in _previewCache.values) {
      results.addAll(items.where((i) => i.name.toLowerCase().contains(q)));
    }
    if (results.isEmpty) {
      return Center(
        child: Text('无匹配结果',
            style: TextStyle(color: EmbyTheme.textTertiary(context))),
      );
    }
    final screenWidth = MediaQuery.of(context).size.width;
    final cols = screenWidth > 1200
        ? 7
        : screenWidth > 900
            ? 5
            : screenWidth > 600
                ? 4
                : 3;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        childAspectRatio: 2 / 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: results.length,
      itemBuilder: (_, i) => _buildRowPoster(results[i], height: 200),
    );
  }

  // ── Skeleton ────────────────────────────────────────────────────────

  Widget _buildSkeleton() {
    final shimmer = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF27272A)
        : const Color(0xFFE4E4E7);
    return ListView.builder(
      itemCount: 4,
      itemBuilder: (_, i) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
            child: Container(
                width: 80,
                height: 16,
                decoration: BoxDecoration(
                    color: shimmer,
                    borderRadius: BorderRadius.circular(4))),
          ),
          SizedBox(
            height: 180,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 5,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, __) => Container(
                width: 120,
                decoration: BoxDecoration(
                    color: shimmer,
                    borderRadius: BorderRadius.circular(6)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRowSkeleton() {
    final shimmer = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF27272A)
        : const Color(0xFFE4E4E7);
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: 5,
      separatorBuilder: (_, __) => const SizedBox(width: 10),
      itemBuilder: (_, __) => Container(
        width: 120,
        decoration: BoxDecoration(
            color: shimmer, borderRadius: BorderRadius.circular(6)),
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded,
                color: EmbyTheme.textTertiary(context), size: 48),
            const SizedBox(height: 16),
            Text(message,
                style: TextStyle(color: EmbyTheme.textSecondary(context)),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: _loadLibraries,
              style: OutlinedButton.styleFrom(
                foregroundColor: EmbyTheme.textSecondary(context),
                side: BorderSide(color: EmbyTheme.textTertiary(context)),
              ),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Full Library Grid Page (opens on "查看全部") ──────────────────────────────

class _LibraryGridPage extends StatefulWidget {
  final EmbyClient api;
  final _Library lib;
  final String userId;
  final void Function(_Item) onItemTap;

  const _LibraryGridPage({
    required this.api,
    required this.lib,
    required this.userId,
    required this.onItemTap,
  });

  @override
  State<_LibraryGridPage> createState() => _LibraryGridPageState();
}

class _LibraryGridPageState extends State<_LibraryGridPage> {
  List<_Item>? _items;
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final data = await widget.api.get(
        '/emby/Users/${widget.userId}/Items',
        {
          'parentId': widget.lib.id,
          'Limit': '2000',
          'SortBy': 'SortName',
          'SortOrder': 'Ascending',
          'Fields':
              'ImageTags,BackdropImageTags,Overview,CommunityRating,Genres,RunTimeTicks',
          'Recursive': 'true',
          'IncludeItemTypes': widget.lib.includeItemTypes,
        },
      );
      if (!mounted) return;
      setState(() {
        _items = (data['Items'] as List<dynamic>)
            .map((e) => _Item.fromJson(e as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _items = const [];
        _loading = false;
      });
    }
  }

  List<_Item> get _filtered {
    if (_items == null) return const [];
    if (_query.isEmpty) return _items!;
    final q = _query.toLowerCase();
    return _items!.where((i) => i.name.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final cols = screenWidth > 1200
        ? 7
        : screenWidth > 900
            ? 5
            : screenWidth > 600
                ? 4
                : 3;
    final hPad = screenWidth > 900 ? (screenWidth - 900) / 2 + 16 : 12.0;

    return Scaffold(
      backgroundColor: EmbyTheme.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: EmbyTheme.appBarBg(context),
        foregroundColor: EmbyTheme.textPrimary(context),
        elevation: 0,
        title: Text(widget.lib.name,
            style: TextStyle(
                color: EmbyTheme.textPrimary(context),
                fontWeight: FontWeight.w600)),
      ),
      body: Column(
        children: [
          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              style: TextStyle(
                  color: EmbyTheme.textPrimary(context), fontSize: 14),
              decoration: InputDecoration(
                hintText: '搜索${widget.lib.name}...',
                hintStyle: TextStyle(
                    color: EmbyTheme.textSecondary(context), fontSize: 14),
                prefixIcon: Icon(Icons.search_rounded,
                    color: EmbyTheme.textSecondary(context), size: 18),
                filled: true,
                fillColor: EmbyTheme.pillUnselected(context),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                isDense: true,
              ),
            ),
          ),
          // Grid
          Expanded(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(
                        color: EmbyTheme.textSecondary(context)))
                : _filtered.isEmpty
                    ? Center(
                        child: Text(
                            _query.isNotEmpty ? '无匹配结果' : '暂无内容',
                            style: TextStyle(
                                color: EmbyTheme.textTertiary(context))))
                    : GridView.builder(
                        padding: EdgeInsets.fromLTRB(hPad, 4, hPad, 24),
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          childAspectRatio: 2 / 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) {
                          final item = _filtered[i];
                          return GestureDetector(
                            onTap: () => widget.onItemTap(item),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (item.hasPoster)
                                    EmbyImage(
                                      api: widget.api,
                                      itemId: item.id,
                                      fit: BoxFit.cover,
                                      width: 200,
                                    )
                                  else
                                    Container(
                                        color:
                                            EmbyTheme.placeholder(context)),
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 6),
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.bottomCenter,
                                          end: Alignment.topCenter,
                                          colors: [
                                            Colors.black87,
                                            Colors.transparent
                                          ],
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(item.name,
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w500,
                                                  height: 1.2),
                                              maxLines: 2,
                                              overflow:
                                                  TextOverflow.ellipsis),
                                          if (item.year != null) ...[
                                            const SizedBox(height: 2),
                                            Text('${item.year}',
                                                style: const TextStyle(
                                                    color: Colors.white54,
                                                    fontSize: 10)),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
