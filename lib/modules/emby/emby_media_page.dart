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

  /// IncludeItemTypes for this library's content query.
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

// ── Page ──────────────────────────────────────────────────────────────────────

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
  String? _selectedId;
  bool _loadingLibs = true;
  bool _loadingItems = false;
  String? _error;
  String _query = '';

  /// Per-library item cache with LRU eviction (max 5 libraries).
  /// Dart's default Map (LinkedHashMap) maintains insertion order, so
  /// remove + re-insert moves a key to the end (most recently used).
  static const _maxCachedLibraries = 5;
  final Map<String, List<_Item>> _itemsCache = {};

  List<_Item>? get _items =>
      _selectedId != null ? _itemsCache[_selectedId] : null;

  List<_Item> get _filteredItems {
    final items = _items;
    if (items == null) return const [];
    if (_query.isEmpty) return items;
    final q = _query.toLowerCase();
    return items
        .where((i) => i.name.toLowerCase().contains(q))
        .toList();
  }

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
      // Emby already returns Views sorted by each library's SortName field.
      // Use server order directly — no client-side sort needed.
      // To change display order, set SortName on the Emby server
      // (e.g. "00_电影", "01_电视剧", "02_动漫").
      final libs = (data['Items'] as List<dynamic>)
          .map((e) => _Library.fromJson(e as Map<String, dynamic>))
          .toList();
      setState(() {
        _libraries = libs;
        _loadingLibs = false;
        if (libs.isNotEmpty) {
          _selectedId = libs.first.id;
          _loadItems(libs.first.id);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingLibs = false;
        _error = '获取媒体库失败\n$e';
      });
    }
  }

  Future<void> _loadItems(String libraryId) async {
    // Return cached data instantly; touch LRU order.
    if (_itemsCache.containsKey(libraryId)) {
      // Move to end (most recently used)
      final cached = _itemsCache.remove(libraryId)!;
      _itemsCache[libraryId] = cached;
      setState(() => _loadingItems = false);
      return;
    }
    setState(() => _loadingItems = true);
    final lib = _libraries?.firstWhere((l) => l.id == libraryId,
        orElse: () => _Library(id: libraryId, name: '', type: ''));
    try {
      final data = await _api.get('/emby/Users/${widget.userId}/Items', {
        'parentId': libraryId,
        'Limit': '2000',
        'SortBy': 'SortName',
        'SortOrder': 'Ascending',
        'Fields': 'ImageTags,BackdropImageTags,Overview,CommunityRating,Genres,RunTimeTicks',
        'Recursive': 'true',
        'IncludeItemTypes': lib?.includeItemTypes ?? 'Movie,Series',
      });
      if (!mounted) return;
      final items = (data['Items'] as List<dynamic>)
          .map((e) => _Item.fromJson(e as Map<String, dynamic>))
          .toList();
      setState(() {
        _itemsCache[libraryId] = items;
        // Evict oldest (first) entries when over LRU limit
        while (_itemsCache.length > _maxCachedLibraries) {
          _itemsCache.remove(_itemsCache.keys.first);
        }
        _loadingItems = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingItems = false);
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
            style: TextStyle(color: EmbyTheme.textPrimary(context), fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              _itemsCache.clear();
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
        child: Text('暂无媒体库', style: TextStyle(color: EmbyTheme.textSecondary(context))),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildLibraryTabs(),
        _buildSearchBar(),
        Expanded(child: _buildItemsArea()),
      ],
    );
  }

  Widget _buildLibraryTabs() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        itemCount: _libraries!.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final lib = _libraries![i];
          final selected = lib.id == _selectedId;
          return GestureDetector(
            onTap: () {
              if (_selectedId == lib.id) return;
              setState(() {
                _selectedId = lib.id;
                _query = '';
              });
              _loadItems(lib.id);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: selected ? EmbyTheme.pillSelected(context) : EmbyTheme.pillUnselected(context),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(lib.icon,
                      size: 13,
                      color: selected ? EmbyTheme.pillSelectedText(context) : EmbyTheme.textSecondary(context)),
                  const SizedBox(width: 5),
                  Text(
                    lib.name,
                    style: TextStyle(
                      color: selected ? EmbyTheme.pillSelectedText(context) : EmbyTheme.pillUnselectedText(context),
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: TextField(
        onChanged: (v) => setState(() => _query = v),
        style: TextStyle(color: EmbyTheme.textPrimary(context), fontSize: 14),
        decoration: InputDecoration(
          hintText: '搜索...',
          hintStyle: TextStyle(color: EmbyTheme.textSecondary(context), fontSize: 14),
          prefixIcon: Icon(Icons.search_rounded, color: EmbyTheme.textSecondary(context), size: 18),
          suffixIcon: _query.isNotEmpty
              ? GestureDetector(
                  onTap: () => setState(() => _query = ''),
                  child: Icon(Icons.close_rounded, color: EmbyTheme.textSecondary(context), size: 18),
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

  Widget _buildItemsArea() {
    if (_loadingItems) return _buildSkeletonGrid();

    final items = _filteredItems;
    if (items.isEmpty) {
      return Center(
        child: Text(
          _query.isNotEmpty ? '无匹配结果' : '暂无内容',
          style: TextStyle(color: EmbyTheme.textTertiary(context)),
        ),
      );
    }
    final screenWidth = MediaQuery.of(context).size.width;
    final cols = screenWidth > 1200 ? 7 : screenWidth > 900 ? 5 : screenWidth > 600 ? 4 : 3;
    final hPad = screenWidth > 900 ? (screenWidth - 900) / 2 + 16 : 12.0;
    return RefreshIndicator(
      color: EmbyTheme.textSecondary(context),
      backgroundColor: EmbyTheme.appBarBg(context),
      onRefresh: () async {
        _itemsCache.remove(_selectedId);
        setState(() => _query = '');
        if (_selectedId != null) await _loadItems(_selectedId!);
      },
      child: GridView.builder(
        padding: EdgeInsets.fromLTRB(hPad, 4, hPad, 24),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          childAspectRatio: 2 / 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) => _buildItemCard(items[i]),
      ),
    );
  }

  Widget _buildItemCard(_Item item) {
    return GestureDetector(
      onTap: () => _openItem(item),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (item.hasPoster)
              EmbyImage(
                api: _api,
                itemId: item.id,
                fit: BoxFit.cover,
                width: 200,
                placeholder: _posterPlaceholder(item),
              )
            else
              _posterPlaceholder(item),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.year != null) ...[
                      const SizedBox(height: 2),
                      Text('${item.year}',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 10)),
                    ],
                  ],
                ),
              ),
            ),
          ],
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
            size: 36,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              item.name,
              style: TextStyle(color: EmbyTheme.textTertiary(context), fontSize: 11),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ── Skeleton loading ─────────────────────────────────────────────

  Widget _buildSkeleton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shimmer = isDark ? const Color(0xFF27272A) : const Color(0xFFE4E4E7);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Skeleton pills
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            itemCount: 4,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, __) => Container(
              width: 72,
              decoration: BoxDecoration(
                color: shimmer,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        // Skeleton grid
        Expanded(child: _buildSkeletonGrid()),
      ],
    );
  }

  Widget _buildSkeletonGrid() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shimmer = isDark ? const Color(0xFF27272A) : const Color(0xFFE4E4E7);
    final screenWidth = MediaQuery.of(context).size.width;
    final cols = screenWidth > 1200 ? 7 : screenWidth > 900 ? 5 : screenWidth > 600 ? 4 : 3;
    final hPad = screenWidth > 900 ? (screenWidth - 900) / 2 + 16 : 12.0;
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(hPad, 4, hPad, 24),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        childAspectRatio: 2 / 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: cols * 3,
      itemBuilder: (_, __) => Container(
        decoration: BoxDecoration(
          color: shimmer,
          borderRadius: BorderRadius.circular(6),
        ),
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
