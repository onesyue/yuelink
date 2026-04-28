import 'package:flutter/material.dart';

import '../../i18n/app_strings.dart';
import 'emby_client.dart';
import 'emby_theme.dart';
import 'models/emby_models.dart';

/// "查看全部" navigation targets for Emby libraries and box-sets.
///
/// Both widgets were previously inlined in `emby_media_page.dart` as
/// `_LibraryGridPage` / `_BoxSetGridPage`; pulling them out frees the
/// media page from ~410 lines of grid layout + filtering + fetch logic.
/// Public class names so the navigator pushes from `emby_media_page`
/// can construct them across the file boundary.

// ── Full Library Grid Page (opens on "查看全部") ──────────────────────────────

class LibraryGridPage extends StatefulWidget {
  final EmbyClient api;
  final EmbyLibrary lib;
  final String userId;
  final void Function(EmbyItem) onItemTap;

  const LibraryGridPage({
    super.key,
    required this.api,
    required this.lib,
    required this.userId,
    required this.onItemTap,
  });

  @override
  State<LibraryGridPage> createState() => _LibraryGridPageState();
}

class _LibraryGridPageState extends State<LibraryGridPage> {
  List<EmbyItem>? _items;
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<List<EmbyItem>> _fetch(Map<String, String> extra) async {
    final data = await widget.api.get(
      '/emby/Users/${widget.userId}/Items',
      {'parentId': widget.lib.id, ...extra},
    );
    return (data['Items'] as List<dynamic>)
        .map((e) => EmbyItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      List<EmbyItem> results;
      if (widget.lib.isCollectionLibrary) {
        results = await _fetch({
          'Limit': '2000',
          'SortBy': 'SortName',
          'SortOrder': 'Ascending',
          'Fields': 'ImageTags,BackdropImageTags,Overview,CommunityRating,Genres,ChildCount',
          'IncludeItemTypes': 'BoxSet',
        });
      } else {
        results = await _fetch({
          'Limit': '2000',
          'SortBy': 'SortName',
          'SortOrder': 'Ascending',
          'Fields': 'ImageTags,BackdropImageTags,Overview,CommunityRating,Genres,RunTimeTicks',
          'Recursive': 'true',
          'IncludeItemTypes': widget.lib.includeItemTypes,
        });
        // Fallback: retry without type filter if typed query was empty
        if (results.isEmpty) {
          results = await _fetch({
            'Limit': '2000',
            'SortBy': 'SortName',
            'SortOrder': 'Ascending',
            'Fields': 'ImageTags,BackdropImageTags,Overview,CommunityRating,Genres,RunTimeTicks',
            'Recursive': 'true',
          });
        }
      }
      if (!mounted) return;
      setState(() {
        _items = results;
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

  List<EmbyItem> get _filtered {
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
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              style: TextStyle(
                  color: EmbyTheme.textPrimary(context), fontSize: 13),
              decoration: InputDecoration(
                hintText: '搜索${widget.lib.name}...',
                hintStyle: TextStyle(
                    color: EmbyTheme.textSecondary(context), fontSize: 13),
                prefixIcon: Icon(Icons.search_rounded,
                    color: EmbyTheme.textSecondary(context), size: 16),
                prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
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
                            _query.isNotEmpty ? S.current.embyNoResults : S.current.embyNoContent,
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
                                      width: 360,
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

// ── BoxSet Detail Grid (shows child movies inside a collection) ──────────────

class BoxSetGridPage extends StatefulWidget {
  final EmbyClient api;
  final String boxSetId;
  final String boxSetName;
  final String userId;
  final void Function(EmbyItem) onItemTap;

  const BoxSetGridPage({
    super.key,
    required this.api,
    required this.boxSetId,
    required this.boxSetName,
    required this.userId,
    required this.onItemTap,
  });

  @override
  State<BoxSetGridPage> createState() => _BoxSetGridPageState();
}

class _BoxSetGridPageState extends State<BoxSetGridPage> {
  List<EmbyItem>? _items;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // Fetch the child items of this BoxSet.
      final data = await widget.api.get(
        '/emby/Users/${widget.userId}/Items',
        {
          'parentId': widget.boxSetId,
          'SortBy': 'SortName',
          'SortOrder': 'Ascending',
          'Fields':
              'ImageTags,BackdropImageTags,Overview,CommunityRating,Genres,RunTimeTicks',
        },
      );
      if (!mounted) return;
      setState(() {
        _items = (data['Items'] as List<dynamic>)
            .map((e) => EmbyItem.fromJson(e as Map<String, dynamic>))
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
        title: Text(widget.boxSetName,
            style: TextStyle(
                color: EmbyTheme.textPrimary(context),
                fontWeight: FontWeight.w600)),
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(
                  color: EmbyTheme.textSecondary(context)))
          : _items == null || _items!.isEmpty
              ? Center(
                  child: Text(S.current.embyNoContent,
                      style:
                          TextStyle(color: EmbyTheme.textTertiary(context))))
              : GridView.builder(
                  padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 24),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    childAspectRatio: 2 / 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _items!.length,
                  itemBuilder: (_, i) {
                    final item = _items![i];
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
                                width: 360,
                              )
                            else
                              Container(
                                  color: EmbyTheme.placeholder(context)),
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
                                        overflow: TextOverflow.ellipsis),
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
    );
  }
}
