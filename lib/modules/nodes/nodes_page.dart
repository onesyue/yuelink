import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/proxy.dart';
import '../../l10n/app_strings.dart';
import '../../providers/core_provider.dart';
import '../../core/kernel/core_manager.dart';
import '../../core/storage/settings_service.dart';
import '../../shared/app_notifier.dart';
import '../../theme.dart';
import 'providers/nodes_providers.dart';
import 'widgets/group_card.dart';
import 'widgets/group_list_section.dart';

export 'providers/nodes_providers.dart';
export 'providers/node_providers.dart';

class NodesPage extends ConsumerStatefulWidget {
  const NodesPage({super.key});

  @override
  ConsumerState<NodesPage> createState() => _NodesPageState();
}

class _NodesPageState extends ConsumerState<NodesPage> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(proxyGroupsProvider.notifier).refresh());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final status = ref.watch(coreStatusProvider);
    final groups = ref.watch(proxyGroupsProvider);
    final routingMode = ref.watch(routingModeProvider);

    // ── Offline state ──────────────────────────────────────────────────────
    if (status != CoreStatus.running) {
      final offlineGroups = ref.watch(offlineProxyGroupsProvider);
      return Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics()),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                        YLSpacing.xl, YLSpacing.xl, YLSpacing.xl, YLSpacing.md),
                    child: Column(
                      children: [
                        Icon(Icons.router_outlined,
                            size: 64, color: YLColors.zinc300),
                        const SizedBox(height: YLSpacing.xl),
                        Text(s.notConnectedHintProxy,
                            style: YLText.titleLarge),
                        const SizedBox(height: YLSpacing.sm),
                        Text(
                          s.connectToViewProxiesDesc,
                          style:
                              YLText.body.copyWith(color: YLColors.zinc500),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                offlineGroups.when(
                  data: (gs) {
                    if (gs.isEmpty) {
                      return const SliverToBoxAdapter(
                          child: SizedBox.shrink());
                    }
                    return SliverList(
                      delegate: SliverChildListDelegate([
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                              YLSpacing.xl, 0, YLSpacing.xl, YLSpacing.md),
                          child: _OfflinePreviewBanner(s.offlinePreview),
                        ),
                        ...gs.map((g) => Padding(
                              padding: const EdgeInsets.fromLTRB(
                                  YLSpacing.xl,
                                  0,
                                  YLSpacing.xl,
                                  YLSpacing.lg),
                              child: _ReadOnlyGroupCard(group: g),
                            )),
                      ]),
                    );
                  },
                  loading: () =>
                      const SliverToBoxAdapter(child: SizedBox.shrink()),
                  error: (_, __) =>
                      const SliverToBoxAdapter(child: SizedBox.shrink()),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          ),
        ),
      );
    }

    // ── Loading ────────────────────────────────────────────────────────────
    if (groups.isEmpty) {
      return const Scaffold(
        body: Center(child: CupertinoActivityIndicator(radius: 14)),
      );
    }

    // ── Unified running UI — identical structure for ALL routing modes ─────
    //
    // Routing mode (rule / global / direct) ONLY affects:
    //   • Which groups appear (global mode prepends the GLOBAL group)
    //   • A small informational banner for non-rule modes
    //   • Actual proxy behaviour via the REST API (handled elsewhere)
    //
    // The card layout — strategy group card → node card grid — never changes.

    final sortMode = ref.watch(nodeSortModeProvider);
    final viewMode = ref.watch(nodeViewModeProvider);
    final searchQuery = ref.watch(nodeSearchQueryProvider);

    // Global mode: prepend GLOBAL group so user can pick which group handles
    // all traffic; other groups still shown so selections can be made.
    final globalGroup = ref.watch(globalGroupProvider);
    final displayGroups = routingMode == 'global' && globalGroup != null
        ? [globalGroup, ...groups]
        : List<ProxyGroup>.from(groups);

    final bool showBanner = routingMode != 'rule';
    final int listCount = displayGroups.length + (showBanner ? 1 : 0);

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              // ── App bar: all controls available in every routing mode ──
              SliverAppBar(
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                pinned: true,
                actions: [
                  _CompactRoutingMode(),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.sort_rounded),
                    iconSize: 20,
                    tooltip: _sortModeLabel(s, sortMode),
                    onPressed: () {
                      final modes = NodeSortMode.values;
                      final next =
                          modes[(sortMode.index + 1) % modes.length];
                      ref.read(nodeSortModeProvider.notifier).state = next;
                    },
                  ),
                  IconButton(
                    icon: Icon(viewMode == NodeViewMode.card
                        ? Icons.view_list_rounded
                        : Icons.grid_view_rounded),
                    iconSize: 20,
                    tooltip: viewMode == NodeViewMode.card
                        ? s.nodeViewList
                        : s.nodeViewCard,
                    onPressed: () {
                      ref.read(nodeViewModeProvider.notifier).state =
                          viewMode == NodeViewMode.card
                              ? NodeViewMode.list
                              : NodeViewMode.card;
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: () =>
                        ref.read(proxyGroupsProvider.notifier).refresh(),
                  ),
                  const SizedBox(width: YLSpacing.sm),
                ],
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(44),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                        YLSpacing.xl, 0, YLSpacing.xl, YLSpacing.sm),
                    child: _NodeSearchBar(controller: _searchController),
                  ),
                ),
              ),

              // ── Group list ─────────────────────────────────────────────
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                    YLSpacing.xl, YLSpacing.sm, YLSpacing.xl, 0),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      if (showBanner && index == 0) {
                        return Padding(
                          padding:
                              const EdgeInsets.only(bottom: YLSpacing.lg),
                          child: _ModeBanner(
                            icon: routingMode == 'global'
                                ? Icons.public_rounded
                                : Icons.link_rounded,
                            text: routingMode == 'global'
                                ? s.globalModeDesc
                                : s.directModeDesc,
                          ),
                        );
                      }
                      final groupIndex = showBanner ? index - 1 : index;
                      final group = displayGroups[groupIndex];
                      return Padding(
                        padding:
                            const EdgeInsets.only(bottom: YLSpacing.lg),
                        child: viewMode == NodeViewMode.list
                            ? GroupListSection(
                                group: group,
                                sortMode: sortMode,
                                searchQuery: searchQuery,
                              )
                            : GroupCard(
                                group: group,
                                sortMode: sortMode,
                                searchQuery: searchQuery,
                              ),
                      );
                    },
                    childCount: listCount,
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
      ),
    );
  }
}

String _sortModeLabel(S s, NodeSortMode mode) {
  switch (mode) {
    case NodeSortMode.defaultOrder:
      return s.sortDefault;
    case NodeSortMode.latencyAsc:
      return s.sortLatencyAsc;
    case NodeSortMode.latencyDesc:
      return s.sortLatencyDesc;
    case NodeSortMode.nameAsc:
      return s.sortNameAsc;
  }
}

// ── Node search bar ────────────────────────────────────────────────────────

class _NodeSearchBar extends ConsumerWidget {
  const _NodeSearchBar({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final query = ref.watch(nodeSearchQueryProvider);
    return SizedBox(
      height: 36,
      child: TextField(
        controller: controller,
        onChanged: (v) =>
            ref.read(nodeSearchQueryProvider.notifier).state = v,
        decoration: InputDecoration(
          hintText: s.searchNodesHint,
          hintStyle: YLText.body.copyWith(
              color: YLColors.zinc400, fontSize: 13),
          prefixIcon: const Icon(Icons.search_rounded,
              size: 16, color: YLColors.zinc400),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 36, minHeight: 36),
          suffixIcon: query.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    controller.clear();
                    ref.read(nodeSearchQueryProvider.notifier).state = '';
                  },
                  child: const Icon(Icons.close_rounded,
                      size: 14, color: YLColors.zinc400),
                )
              : null,
          suffixIconConstraints:
              const BoxConstraints(minWidth: 36, minHeight: 36),
          filled: true,
          fillColor: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.04),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(YLRadius.pill),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(YLRadius.pill),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(YLRadius.pill),
            borderSide: BorderSide(
              color: YLColors.connected.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
        ),
        style: YLText.body.copyWith(fontSize: 13),
      ),
    );
  }
}

// ── Mode banner ────────────────────────────────────────────────────────────

class _ModeBanner extends StatelessWidget {
  const _ModeBanner({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: YLSpacing.lg, vertical: YLSpacing.md),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(YLRadius.lg),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: YLColors.zinc500),
          const SizedBox(width: YLSpacing.sm),
          Expanded(
            child: Text(text,
                style: YLText.caption.copyWith(color: YLColors.zinc500)),
          ),
        ],
      ),
    );
  }
}

// ── Compact Routing Mode (AppBar) ────────────────────────────────────────────

class _CompactRoutingMode extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final routingMode = ref.watch(routingModeProvider);
    final status = ref.watch(coreStatusProvider);

    const modes = ['rule', 'global', 'direct'];
    final labels = [s.routeModeRule, s.routeModeGlobal, s.routeModeDirect];

    return SizedBox(
      width: 186,
      height: 32,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(YLRadius.pill),
        ),
        child: Row(
          children: List.generate(modes.length, (i) {
            final isSelected = modes[i] == routingMode;
            return Expanded(
              child: GestureDetector(
                onTap: () async {
                  final mode = modes[i];
                  ref.read(routingModeProvider.notifier).state = mode;
                  await SettingsService.setRoutingMode(mode);
                  if (status == CoreStatus.running) {
                    try {
                      final ok = await CoreManager.instance.api
                          .setRoutingMode(mode);
                      if (ok) {
                        if (mode == 'direct') {
                          try {
                            await CoreManager.instance.api
                                .closeAllConnections();
                          } catch (_) {}
                        }
                        ref.read(proxyGroupsProvider.notifier).refresh();
                        final actual = await CoreManager.instance.api
                            .getRoutingMode();
                        debugPrint(
                            '[RoutingMode] set=$mode, actual=$actual');
                        if (actual != mode) {
                          AppNotifier.warning(
                              '${s.routeModeRule}: $actual ≠ $mode');
                        } else {
                          final modeLabel = mode == 'global'
                              ? s.routeModeGlobal
                              : mode == 'direct'
                                  ? s.routeModeDirect
                                  : s.routeModeRule;
                          AppNotifier.success(
                              '${s.modeSwitched}: $modeLabel');
                        }
                      } else {
                        AppNotifier.error(s.switchModeFailed);
                        ref.read(routingModeProvider.notifier).state =
                            routingMode;
                      }
                    } catch (e) {
                      debugPrint('[RoutingMode] error: $e');
                      AppNotifier.error('${s.switchModeFailed}: $e');
                      ref.read(routingModeProvider.notifier).state =
                          routingMode;
                    }
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (isDark ? YLColors.zinc700 : Colors.white)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(YLRadius.pill),
                    boxShadow: isSelected ? YLShadow.sm(context) : [],
                  ),
                  child: Text(
                    labels[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: YLText.caption.copyWith(
                      fontSize: 11,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: isSelected
                          ? (isDark ? Colors.white : Colors.black)
                          : YLColors.zinc500,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

// ── Offline Preview Banner ──────────────────────────────────────────────────

class _OfflinePreviewBanner extends StatelessWidget {
  final String message;
  const _OfflinePreviewBanner(this.message);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: YLSpacing.lg, vertical: YLSpacing.sm),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.amber.withValues(alpha: 0.10)
            : Colors.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(YLRadius.lg),
        border: Border.all(
          color: Colors.amber.withValues(alpha: 0.25),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 14, color: Colors.amber),
          const SizedBox(width: YLSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: YLText.caption.copyWith(color: Colors.amber.shade700),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Read-Only Group Card (offline preview) ──────────────────────────────────

class _ReadOnlyGroupCard extends StatelessWidget {
  final ProxyGroup group;
  const _ReadOnlyGroupCard({required this.group});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc900 : Colors.white,
        borderRadius: BorderRadius.circular(YLRadius.xl),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.04),
          width: 0.5,
        ),
        boxShadow: YLShadow.card(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(YLSpacing.md),
            child: Row(
              children: [
                const Icon(Icons.expand_more_rounded,
                    size: 20, color: YLColors.zinc400),
                const SizedBox(width: YLSpacing.sm),
                Text(group.name, style: YLText.titleMedium),
                const SizedBox(width: YLSpacing.sm),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDark ? YLColors.zinc800 : YLColors.zinc100,
                    borderRadius: BorderRadius.circular(YLRadius.sm),
                  ),
                  child: Text(
                    group.type,
                    style: YLText.caption.copyWith(
                        fontSize: 10,
                        color: YLColors.zinc500,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                const Spacer(),
                Text(
                  S.of(context).nodesCountLabel(group.all.length),
                  style: YLText.caption.copyWith(color: YLColors.zinc500),
                ),
              ],
            ),
          ),
          if (group.all.isNotEmpty) ...[
            const Divider(height: 0.5),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: YLSpacing.xs),
              child: Column(
                children: List.generate(group.all.length, (i) {
                  final name = group.all[i];
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: YLSpacing.md,
                            vertical: YLSpacing.sm),
                        child: Row(
                          children: [
                            const SizedBox(width: 24),
                            const SizedBox(width: YLSpacing.xs),
                            Expanded(
                              child: Text(
                                name,
                                style: YLText.body.copyWith(
                                    color: isDark
                                        ? Colors.white70
                                        : YLColors.zinc700),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (i < group.all.length - 1)
                        const Divider(height: 1, indent: 48),
                    ],
                  );
                }),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
