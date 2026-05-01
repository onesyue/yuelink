import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/app_strings.dart';
import '../../../shared/app_notifier.dart';
import '../../../theme.dart';
import 'smart_select_provider.dart';
import 'smart_select_result.dart';

/// Show the Smart Select bottom sheet.
///
/// Automatically starts a delay test if no result exists yet.
/// Both the Nodes page and any other caller can use this.
void showSmartSelectSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _SmartSelectSheet(),
  );
}

class _SmartSelectSheet extends ConsumerStatefulWidget {
  const _SmartSelectSheet();

  @override
  ConsumerState<_SmartSelectSheet> createState() => _SmartSelectSheetState();
}

class _SmartSelectSheetState extends ConsumerState<_SmartSelectSheet> {
  /// Whether to automatically apply the top-ranked node when the test finishes.
  bool _autoApply = false;

  /// Guard: true once auto-apply has fired for the current test run.
  /// Prevents double-trigger on multiple rebuilds near the isTesting→false edge.
  bool _applied = false;

  @override
  void initState() {
    super.initState();
    // Delegate startup to initialize(): loads cache, decides whether to
    // auto-refresh or just show the cached result immediately.
    Future.microtask(() {
      if (!mounted) return;
      ref.read(smartSelectProvider.notifier).initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(smartSelectProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // ── Auto-apply listener ──────────────────────────────────────────────────
    // Fires when test transitions from running → done with a valid result.
    // Uses ref.listen (not watch) so the callback runs on change only,
    // without causing an extra rebuild of the sheet itself.
    ref.listen<SmartSelectState>(smartSelectProvider, (prev, next) {
      // Reset the per-run guard when a fresh test starts.
      if (prev?.isTesting == false && next.isTesting) {
        _applied = false;
        return;
      }

      // Edge: isTesting just flipped to false with a non-empty result.
      if (!_autoApply) return;
      if (_applied) return;
      if (prev?.isTesting != true || next.isTesting) return;
      final top = next.result?.top;
      if (top == null || top.isEmpty) return;
      if (!mounted) return;

      _applied = true;
      _triggerAutoApply(top.first);
    });

    return Container(
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc900 : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom +
            16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHandle(isDark),
          _buildHeader(context, state, isDark),
          _buildAutoApplyToggle(isDark),
          const SizedBox(height: 4),
          _buildBody(context, state, isDark),
        ],
      ),
    );
  }

  // ── Auto-apply ───────────────────────────────────────────────────────────

  /// Apply [best] after a brief info toast.
  /// Checks [mounted] before each async step — sheet dismissal cancels the apply.
  Future<void> _triggerAutoApply(ScoredNode best) async {
    if (!mounted) return;
    AppNotifier.info('自动切换到 ${best.name}...');
    // Brief pause so the user sees the notification before the sheet closes.
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return; // User dismissed the sheet during the delay → abort.
    await ref.read(smartSelectProvider.notifier).applyNode(best);
    if (mounted) Navigator.of(context).pop();
  }

  // ── Drag handle ──────────────────────────────────────────────────────────

  Widget _buildHandle(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.15)
              : Colors.black.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────

  Widget _buildHeader(
      BuildContext context, SmartSelectState state, bool isDark) {
    final cache = state.cache;
    // Show age label when a cached result is visible and not actively refreshing.
    final showCacheAge = cache != null && !state.isTesting;
    // Show a "refreshing" badge when background-refreshing a stale cache.
    final showRefreshing = state.isTesting && cache != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
      child: Row(
        children: [
          Icon(
            Icons.auto_awesome_rounded,
            size: 18,
            color: isDark ? YLColors.zinc300 : YLColors.zinc700,
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '智能选线',
                style: YLText.titleMedium.copyWith(
                  color: isDark ? YLColors.zinc100 : YLColors.zinc800,
                ),
              ),
              if (showCacheAge)
                Text(
                  '上次测速 · ${cache.ageLabel}',
                  style: YLText.caption.copyWith(
                    color: cache.isFresh
                        ? YLColors.connected
                        : YLColors.zinc400,
                    fontSize: 11,
                  ),
                )
              else if (showRefreshing)
                Text(
                  '正在后台刷新...',
                  style: YLText.caption.copyWith(
                    color: YLColors.zinc400,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
          const Spacer(),
          if (!state.isTesting)
            TextButton(
              onPressed: () {
                // Reset guard so the new run can auto-apply again.
                _applied = false;
                ref.read(smartSelectProvider.notifier).runTest();
              },
              style: TextButton.styleFrom(
                foregroundColor: isDark ? YLColors.zinc300 : YLColors.zinc700,
                textStyle: YLText.caption
                    .copyWith(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.refresh_rounded, size: 14),
                  const SizedBox(width: 4),
                  Text(state.result != null ? '重测' : '开始测速'),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Auto-apply toggle row ─────────────────────────────────────────────────

  Widget _buildAutoApplyToggle(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 16, 4),
      child: Row(
        children: [
          Icon(
            Icons.auto_fix_high_rounded,
            size: 14,
            color: _autoApply
                ? (isDark ? YLColors.zinc300 : YLColors.zinc600)
                : YLColors.zinc400,
          ),
          const SizedBox(width: 6),
          Text(
            '测完自动应用最优节点',
            style: YLText.caption.copyWith(
              color: _autoApply
                  ? (isDark ? YLColors.zinc300 : YLColors.zinc600)
                  : YLColors.zinc400,
            ),
          ),
          const Spacer(),
          Transform.scale(
            scale: 0.80,
            alignment: Alignment.centerRight,
            child: Switch.adaptive(
              value: _autoApply,
              onChanged: (v) => setState(() {
                _autoApply = v;
                // Reset guard so toggling back on allows a fresh auto-apply.
                if (v) _applied = false;
              }),
              activeTrackColor: isDark ? YLColors.zinc600 : YLColors.zinc300,
              thumbColor: WidgetStatePropertyAll(isDark ? YLColors.zinc300 : YLColors.zinc700),
            ),
          ),
        ],
      ),
    );
  }

  // ── Body ─────────────────────────────────────────────────────────────────

  Widget _buildBody(
      BuildContext context, SmartSelectState state, bool isDark) {
    if (state.isTesting) {
      // testedCount == 0: no group has finished yet.
      //   → result (if any) is from the previous cache — apply stays enabled.
      // testedCount  > 0: a live partial result is available from this run
      //   → apply is disabled until the full test completes.
      final isLivePartial = state.testedCount > 0 && state.result != null;

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTesting(state, isDark),
          if (state.result != null && state.result!.top.isNotEmpty)
            _buildResult(context, state.result!, isDark,
                isPartial: isLivePartial),
        ],
      );
    }
    if (state.error != null) return _buildError(state.error!, isDark);
    if (state.result != null) return _buildResult(context, state.result!, isDark);
    return _buildIdle(isDark);
  }

  // Testing progress
  Widget _buildTesting(SmartSelectState state, bool isDark) {
    final progress = state.totalCount > 0
        ? state.testedCount / state.totalCount
        : 0.0;
    final pct = (progress * 100).toInt();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress > 0 ? progress : null,
              minHeight: 4,
              backgroundColor:
                  isDark ? YLColors.zinc700 : YLColors.zinc200,
              color: isDark ? YLColors.zinc300 : YLColors.zinc700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            state.totalCount > 0
                ? '正在测速  ${state.testedCount} / ${state.totalCount}  ($pct%)'
                : '正在准备测速...',
            style: YLText.caption.copyWith(color: YLColors.zinc500),
          ),
        ],
      ),
    );
  }

  // Error state
  Widget _buildError(String error, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded, color: YLColors.error, size: 32),
          const SizedBox(height: 8),
          Text(
            error,
            style: YLText.body.copyWith(color: YLColors.zinc500),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => ref.read(smartSelectProvider.notifier).runTest(),
            style: FilledButton.styleFrom(
              backgroundColor: isDark ? YLColors.zinc700 : YLColors.zinc800,
            ),
            child: Text(S.current.retry),
          ),
        ],
      ),
    );
  }

  // Idle state (no result yet, not testing)
  Widget _buildIdle(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        children: [
          Icon(Icons.speed_rounded,
              size: 40,
              color: isDark ? YLColors.zinc600 : YLColors.zinc300),
          const SizedBox(height: 12),
          Text(
            '测试所有节点延迟，自动推荐最优节点',
            style: YLText.body.copyWith(color: YLColors.zinc500),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // Results.
  // [isPartial] = true when called during testing (groups still running).
  // In partial mode the "一键应用" button is hidden to avoid premature apply.
  Widget _buildResult(
      BuildContext context, SmartSelectResult result, bool isDark,
      {bool isPartial = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Stats row
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Row(
            children: [
              _Stat(
                label: isPartial ? '已响应' : '已测试',
                value: '${result.totalTested}',
                isDark: isDark,
              ),
              const SizedBox(width: 20),
              _Stat(
                label: S.current.available,
                value: '${result.totalAvailable}',
                color: result.totalAvailable > 0
                    ? YLColors.connected
                    : YLColors.error,
                isDark: isDark,
              ),
            ],
          ),
        ),

        if (result.top.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Text(
              '所有节点均无响应',
              style: YLText.body.copyWith(color: YLColors.zinc500),
            ),
          )
        else ...[
          // Top 3 node cards
          ...result.top.asMap().entries.map(
                (e) => _NodeCard(
                  rank: e.key + 1,
                  node: e.value,
                  isDark: isDark,
                  onApply: isPartial
                      ? null  // disabled during partial — results may change
                      : () {
                          ref
                              .read(smartSelectProvider.notifier)
                              .applyNode(e.value);
                          Navigator.of(context).pop();
                        },
                ),
              ),
          const SizedBox(height: 4),

          // One-click apply best — hidden while partial or empty
          if (!isPartial && result.top.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    ref
                        .read(smartSelectProvider.notifier)
                        .applyNode(result.top.first);
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                  label: Text('${S.current.applyBestNode}${result.top.first.name}'),
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        isDark ? YLColors.zinc700 : YLColors.zinc800,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(YLRadius.lg),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final bool isDark;

  const _Stat({
    required this.label,
    required this.value,
    this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: YLText.caption.copyWith(color: YLColors.zinc500),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: YLText.caption.copyWith(
            fontWeight: FontWeight.w700,
            color: color ?? (isDark ? YLColors.zinc200 : YLColors.zinc700),
          ),
        ),
      ],
    );
  }
}

class _NodeCard extends StatelessWidget {
  final int rank;
  final ScoredNode node;
  final bool isDark;
  // null during partial testing — button is shown but disabled.
  final VoidCallback? onApply;

  const _NodeCard({
    required this.rank,
    required this.node,
    required this.isDark,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final rankColors = [
      const Color(0xFFFFD700), // Gold
      const Color(0xFFC0C0C0), // Silver
      const Color(0xFFCD7F32), // Bronze
    ];
    final rankColor = rank <= 3 ? rankColors[rank - 1] : YLColors.zinc400;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? YLColors.zinc800 : YLColors.zinc50,
          borderRadius: BorderRadius.circular(YLRadius.lg),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.07)
                : Colors.black.withValues(alpha: 0.07),
            width: 0.5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // Rank badge
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: rankColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(YLRadius.sm),
                ),
                alignment: Alignment.center,
                child: Text(
                  '#$rank',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: rankColor,
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Node info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      node.name,
                      style: YLText.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isDark ? YLColors.zinc100 : YLColors.zinc800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (node.region != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        node.region!,
                        style: YLText.caption.copyWith(
                          color: YLColors.zinc500,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Delay badge
              YLDelayBadge(delay: node.delay),
              const SizedBox(width: 10),

              // Apply button — dimmed when disabled (partial result)
              Opacity(
                opacity: onApply != null ? 1.0 : 0.4,
                child: GestureDetector(
                  onTap: onApply,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isDark ? YLColors.zinc700 : YLColors.zinc200,
                      borderRadius: BorderRadius.circular(YLRadius.sm),
                    ),
                    child: Text(
                      '应用',
                      style: YLText.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isDark ? YLColors.zinc200 : YLColors.zinc700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
