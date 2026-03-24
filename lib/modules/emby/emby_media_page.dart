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

  /// Per-library item cache — switching tabs is instant on revisit.
  final Map<String, List<_Item>> _itemsCache = {};

  List<_Item>? get _items =>
      _selectedId != null ? _itemsCache[_selectedId] : null;

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
      const order = ['电影', '电视剧', '动漫', '音乐'];
      final libs = (data['Items'] as List<dynamic>)
          .map((e) => _Library.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) {
          final ai = order.indexOf(a.name);
          final bi = order.indexOf(b.name);
          return (ai < 0 ? 999 : ai).compareTo(bi < 0 ? 999 : bi);
        });
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
    // Return cached data instantly.
    if (_itemsCache.containsKey(libraryId)) {
      setState(() => _loadingItems = false);
      return;
    }
    setState(() => _loadingItems = true);
    try {
      final data = await _api.get('/emby/Users/${widget.userId}/Items', {
        'parentId': libraryId,
        'Limit': '200',
        'SortBy': 'SortName',
        'SortOrder': 'Ascending',
        'Fields': 'ImageTags,BackdropImageTags,Overview,CommunityRating,Genres,RunTimeTicks',
        'Recursive': 'true',
        'IncludeItemTypes': 'Movie,Series',
      });
      if (!mounted) return;
      final items = (data['Items'] as List<dynamic>)
          .map((e) => _Item.fromJson(e as Map<String, dynamic>))
          .toList();
      setState(() {
        _itemsCache[libraryId] = items;
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
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            onPressed: () {
              _itemsCache.clear();
              _loadLibraries();
            },
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loadingLibs) {
      return Center(
          child: CircularProgressIndicator(color: EmbyTheme.textSecondary(context)));
    }
    if (_error != null) return _buildError(_error!);
    if (_libraries == null || _libraries!.isEmpty) {
      return const Center(
        child: Text('暂无媒体库', style: TextStyle(color: Colors.white54)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildLibraryTabs(),
        const SizedBox(height: 4),
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
              setState(() => _selectedId = lib.id);
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

  Widget _buildItemsArea() {
    if (_loadingItems) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white54));
    }
    final items = _items;
    if (items == null || items.isEmpty) {
      return const Center(
        child: Text('暂无内容', style: TextStyle(color: Colors.white38)),
      );
    }
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
      itemCount: items.length,
      itemBuilder: (_, i) => _buildItemCard(items[i]),
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
                width: 150,
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
            color: Colors.white24,
            size: 36,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              item.name,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
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
            const Icon(Icons.wifi_off_rounded,
                color: Colors.white38, size: 48),
            const SizedBox(height: 16),
            Text(message,
                style: const TextStyle(color: Colors.white54),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: _loadLibraries,
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
