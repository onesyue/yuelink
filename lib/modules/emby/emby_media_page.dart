import 'package:flutter/material.dart';

import '../../i18n/app_strings.dart';
import '../../shared/friendly_error.dart';
import 'emby_client.dart';
import 'emby_detail_page.dart';
import 'emby_theme.dart';
import 'library_grid_pages.dart';
import 'models/emby_models.dart';

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
  final _searchController = TextEditingController();
  List<EmbyLibrary>? _libraries;
  bool _loadingLibs = true;
  String? _error;
  String _query = '';

  /// Preview cache: most recent 20 items per library (for horizontal rows).
  /// LRU eviction: max 5 libraries cached to bound memory (each library → 20 posters).
  static const _maxCachedLibraries = 5;
  final Map<String, List<EmbyItem>> _previewCache = {};
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
    _searchController.dispose();
    _previewCache.clear();
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
          .map((e) => EmbyLibrary.fromJson(e as Map<String, dynamic>))
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
        _error = '${S.current.embyGetFailed}\n${_friendlyMediaError(e)}';
      });
    }
  }

  String _friendlyMediaError(Object e) {
    final raw = e.toString().toLowerCase();
    if (raw.contains('127.0.0.1') &&
        (raw.contains('connection refused') ||
            raw.contains('errno = 111') ||
            raw.contains('errno = 61'))) {
      return S.current.mineEmbyNeedsVpn;
    }
    return friendlyError(e);
  }

  /// Track libraries where the primary preview query returned empty so we
  /// don't show a stale "loading" spinner forever.  `null` = not tried yet,
  /// `true` = load error (show retry button).
  final Map<String, bool> _previewError = {};

  Future<void> _loadPreview(EmbyLibrary lib) async {
    if (_previewCache.containsKey(lib.id)) return;
    setState(() {
      _loadingPreviews.add(lib.id);
      _previewError.remove(lib.id);
    });
    try {
      List<EmbyItem> items;
      if (lib.isCollectionLibrary) {
        items = await _fetchItems(lib.id, {
          'Limit': '20',
          'SortBy': 'SortName',
          'SortOrder': 'Ascending',
          'Fields':
              'ImageTags,BackdropImageTags,Overview,CommunityRating,Genres,ChildCount',
          'IncludeItemTypes': 'BoxSet',
        });
      } else {
        // Primary attempt: typed query (Movie/Series/etc.)
        items = await _fetchItems(lib.id, {
          'Limit': '20',
          'SortBy': 'DateCreated,SortName',
          'SortOrder': 'Descending',
          'Fields':
              'ImageTags,BackdropImageTags,Overview,CommunityRating,Genres,RunTimeTicks',
          'Recursive': 'true',
          'IncludeItemTypes': lib.includeItemTypes,
        });
        // Fallback: if typed query returned empty, retry without
        // IncludeItemTypes filter.  This catches libraries whose content
        // hasn't been scanned yet (Emby returns Folder items) or libraries
        // with non-standard item types.
        if (items.isEmpty) {
          items = await _fetchItems(lib.id, {
            'Limit': '20',
            'SortBy': 'DateCreated,SortName',
            'SortOrder': 'Descending',
            'Fields':
                'ImageTags,BackdropImageTags,Overview,CommunityRating,Genres,RunTimeTicks',
            'Recursive': 'true',
          });
        }
      }
      if (!mounted) return;
      setState(() {
        _previewCache[lib.id] = items;
        // LRU eviction: keep at most _maxCachedLibraries entries.
        while (_previewCache.length > _maxCachedLibraries) {
          _previewCache.remove(_previewCache.keys.first);
        }
        _loadingPreviews.remove(lib.id);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _previewCache[lib.id] = const [];
        _previewError[lib.id] = true;
        _loadingPreviews.remove(lib.id);
      });
    }
  }

  Future<List<EmbyItem>> _fetchItems(
    String parentId,
    Map<String, String> extra,
  ) async {
    final data = await _api.get('/emby/Users/${widget.userId}/Items', {
      'parentId': parentId,
      ...extra,
    });
    return (data['Items'] as List<dynamic>)
        .map((e) => EmbyItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Navigation ────────────────────────────────────────────────────────

  void _openItem(EmbyItem item) {
    if (item.type == 'BoxSet') {
      // BoxSet: open a grid showing the collection's child movies/series.
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BoxSetGridPage(
            api: _api,
            boxSetId: item.id,
            boxSetName: item.name,
            userId: widget.userId,
            onItemTap: _openItem,
          ),
        ),
      );
      return;
    }
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

  void _openLibraryGrid(EmbyLibrary lib) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LibraryGridPage(
          api: _api,
          lib: lib,
          userId: widget.userId,
          onItemTap: _openItem,
        ),
      ),
    );
  }

  // ── UI ────────────────────────────────────────────────────────────────

  void _refresh() {
    _previewCache.clear();
    _loadingPreviews.clear();
    _previewError.clear();
    _searchController.clear();
    setState(() => _query = '');
    _loadLibraries();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.08);
    final hasContent =
        !_loadingLibs &&
        _error == null &&
        _libraries != null &&
        _libraries!.isNotEmpty;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Compact action bar — title removed per user feedback
          //    (mine / dashboard also have no top title; bottom-nav
          //    already labels the tab). Keeps back + refresh actions.
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
              child: SizedBox(
                height: 44,
                child: Row(
                  children: [
                    if (Navigator.canPop(context))
                      IconButton(
                        constraints: const BoxConstraints.tightFor(
                          width: 40,
                          height: 40,
                        ),
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 20,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                    const Spacer(),
                    IconButton(
                      constraints: const BoxConstraints.tightFor(
                        width: 40,
                        height: 40,
                      ),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.refresh_rounded),
                      iconSize: 20,
                      color: EmbyTheme.textSecondary(context),
                      onPressed: _refresh,
                    ),
                  ],
                ),
              ),
            ),
          ),
          // ── 搜索栏（融入 header，无分隔线）──────────────────────────
          if (hasContent) _buildSearchBar(),
          Container(height: 0.5, color: dividerColor),
          // ── 内容区 ─────────────────────────────────────────────────
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loadingLibs) return _buildSkeleton();
    if (_error != null) return _buildError(_error!);
    if (_libraries == null || _libraries!.isEmpty) {
      return Center(
        child: Text(
          S.of(context).embyNoLibrary,
          style: TextStyle(color: EmbyTheme.textSecondary(context)),
        ),
      );
    }
    return _query.isNotEmpty ? _buildSearchResults() : _buildNetflixRows();
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
    // Collect first item with backdrop for Hero Banner —
    // only from real media libraries (movies/tvshows), never from collections.
    EmbyItem? heroItem;
    for (final lib in _libraries!) {
      if (!lib.isMediaLibrary) continue;
      final items = _previewCache[lib.id];
      if (items != null) {
        final candidate =
            items.where((i) => i.hasBackdrop).firstOrNull ??
            items.where((i) => i.hasPoster).firstOrNull;
        if (candidate != null && heroItem == null) heroItem = candidate;
      }
    }

    return RefreshIndicator(
      color: EmbyTheme.textSecondary(context),
      onRefresh: () async {
        _previewCache.clear();
        _loadingPreviews.clear();
        _previewError.clear();
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

  Widget _buildHeroBanner(EmbyItem item) {
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
                url: _api.backdropUrl(item.id, width: 1920),
                fit: BoxFit.cover,
                width: 800,
                isBackdrop: true,
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
                        Text(
                          '${item.year}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      if (item.year != null && item.rating != null)
                        const Text(
                          '  ·  ',
                          style: TextStyle(color: Colors.white38),
                        ),
                      if (item.rating != null)
                        Text(
                          '★ ${item.rating!.toStringAsFixed(1)}',
                          style: const TextStyle(
                            color: Colors.amber,
                            fontSize: 13,
                          ),
                        ),
                      if (item.runtimeLabel.isNotEmpty) ...[
                        const Text(
                          '  ·  ',
                          style: TextStyle(color: Colors.white38),
                        ),
                        Text(
                          item.runtimeLabel,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (item.overview != null && item.overview!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      item.overview!,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                        height: 1.4,
                      ),
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
                      label: Text(S.current.embyPlay),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
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

  Widget _buildLibraryRow(EmbyLibrary lib) {
    final items = _previewCache[lib.id];
    final loading = _loadingPreviews.contains(lib.id);
    final hasItems = items != null && items.isNotEmpty;
    final hasError = _previewError[lib.id] == true;
    final rowHeight = _posterHeight;

    // Always show the library row — never hide.  Empty or error states
    // are displayed inline so the user knows the library exists.

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header (always visible) ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 12, 10),
          child: Row(
            children: [
              Icon(lib.icon, size: 16, color: EmbyTheme.textSecondary(context)),
              const SizedBox(width: 6),
              Text(
                lib.name,
                style: TextStyle(
                  color: EmbyTheme.textPrimary(context),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (hasItems)
                GestureDetector(
                  onTap: () => _openLibraryGrid(lib),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        S.current.viewAll,
                        style: TextStyle(
                          color: EmbyTheme.textSecondary(context),
                          fontSize: 13,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: EmbyTheme.textSecondary(context),
                      ),
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
              : hasError
              ? _buildRowError(lib)
              : !hasItems
              ? _buildRowEmpty()
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (_, i) =>
                      _buildRowPoster(items[i], height: rowHeight),
                ),
        ),
      ],
    );
  }

  Widget _buildRowPoster(EmbyItem item, {required double height}) {
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
                  width: height > 200 ? 480 : 300,
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
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
                            Text(
                              '${item.year}',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 10,
                              ),
                            ),
                          if (item.rating != null) ...[
                            if (item.year != null) const SizedBox(width: 6),
                            Text(
                              '★${item.rating!.toStringAsFixed(1)}',
                              style: const TextStyle(
                                color: Colors.amber,
                                fontSize: 10,
                              ),
                            ),
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

  Widget _posterPlaceholder(EmbyItem item) {
    return Container(
      color: EmbyTheme.placeholder(context),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            item.type == 'BoxSet'
                ? Icons.collections_bookmark_outlined
                : item.type == 'Series'
                ? Icons.tv_outlined
                : Icons.movie_outlined,
            color: EmbyTheme.textTertiary(context),
            size: 28,
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              item.name,
              style: TextStyle(
                color: EmbyTheme.textTertiary(context),
                fontSize: 10,
              ),
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
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _query = v),
        style: TextStyle(color: EmbyTheme.textPrimary(context), fontSize: 13),
        decoration: InputDecoration(
          hintText: S.current.embySearchHint,
          hintStyle: TextStyle(
            color: EmbyTheme.textSecondary(context),
            fontSize: 13,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: EmbyTheme.textSecondary(context),
            size: 16,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 36,
            minHeight: 36,
          ),
          suffixIcon: _query.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                  child: Icon(
                    Icons.close_rounded,
                    color: EmbyTheme.textSecondary(context),
                    size: 16,
                  ),
                )
              : null,
          filled: true,
          fillColor: EmbyTheme.pillUnselected(context),
          contentPadding: const EdgeInsets.symmetric(vertical: 6),
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
    final results = <EmbyItem>[];
    for (final items in _previewCache.values) {
      results.addAll(items.where((i) => i.name.toLowerCase().contains(q)));
    }
    if (results.isEmpty) {
      return Center(
        child: Text(
          S.current.embyNoResults,
          style: TextStyle(color: EmbyTheme.textTertiary(context)),
        ),
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

  // ── Empty / error states for library rows ──────────────────────────

  Widget _buildRowEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inbox_outlined,
            color: EmbyTheme.textTertiary(context),
            size: 28,
          ),
          const SizedBox(height: 6),
          Text(
            S.current.embyNoContent,
            style: TextStyle(
              color: EmbyTheme.textTertiary(context),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRowError(EmbyLibrary lib) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: EmbyTheme.textTertiary(context),
            size: 28,
          ),
          const SizedBox(height: 6),
          Text(
            S.of(context).embyLoadFailed,
            style: TextStyle(
              color: EmbyTheme.textTertiary(context),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {
              _previewCache.remove(lib.id);
              _previewError.remove(lib.id);
              _loadPreview(lib);
            },
            child: Text(
              S.of(context).embyTapRetry,
              style: TextStyle(
                color: EmbyTheme.textSecondary(context),
                fontSize: 12,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
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
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          SizedBox(
            height: 180,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 5,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, _) => Container(
                width: 120,
                decoration: BoxDecoration(
                  color: shimmer,
                  borderRadius: BorderRadius.circular(6),
                ),
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
      separatorBuilder: (_, _) => const SizedBox(width: 10),
      itemBuilder: (_, _) => Container(
        width: 120,
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
            Icon(
              Icons.wifi_off_rounded,
              color: EmbyTheme.textTertiary(context),
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(color: EmbyTheme.textSecondary(context)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: _loadLibraries,
              style: OutlinedButton.styleFrom(
                foregroundColor: EmbyTheme.textSecondary(context),
                side: BorderSide(color: EmbyTheme.textTertiary(context)),
              ),
              child: Text(S.current.retry),
            ),
          ],
        ),
      ),
    );
  }
}
