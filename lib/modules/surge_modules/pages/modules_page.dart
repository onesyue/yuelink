import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/app_strings.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/yl_scaffold.dart';
import '../../../theme.dart';
import '../providers/mitm_provider.dart';
import '../providers/module_provider.dart';
import '../widgets/add_module_sheet.dart';
import '../widgets/module_card.dart';
import 'cert_guide_page.dart';
import 'module_detail_page.dart';

/// Main modules list page.
class ModulesPage extends ConsumerWidget {
  const ModulesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final state = ref.watch(moduleProvider);

    final activeCount = state.modules.where((m) => m.enabled).length;
    final totalRules = state.modules
        .where((m) => m.enabled)
        .fold<int>(0, (sum, m) => sum + m.rules.length);
    final totalMitmHostnames = state.modules
        .where((m) => m.enabled)
        .fold<int>(0, (sum, m) => sum + m.mitmHostnames.length);

    final List<Widget> bodyChildren = [];

    if (state.isLoading && state.modules.isEmpty) {
      // Centered spinner while initial load is in flight.
      bodyChildren.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: YLSpacing.massive),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    } else if (state.modules.isEmpty) {
      bodyChildren.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: YLSpacing.xxl),
          child: _EmptyState(onAdd: () => _showAddSheet(context, ref)),
        ),
      );
    } else {
      // MITM Engine card (always shown when modules exist)
      bodyChildren.add(
        _MitmEngineCard(hasMitmHostnames: totalMitmHostnames > 0),
      );
      bodyChildren.add(const SizedBox(height: YLSpacing.md));

      // Header summary
      if (activeCount > 0) {
        bodyChildren.add(
          Padding(
            padding: const EdgeInsets.only(bottom: YLSpacing.md),
            child: Text(
              '$activeCount active module${activeCount > 1 ? 's' : ''} · $totalRules rules injected'
              '${totalMitmHostnames > 0 ? ' · $totalMitmHostnames MITM hostnames' : ''}',
              style: YLText.caption.copyWith(
                color: YLColors.zinc500,
                letterSpacing: 0,
              ),
            ),
          ),
        );
      }

      // Error banner
      if (state.error != null) {
        bodyChildren.add(_ErrorBanner(error: state.error!));
        bodyChildren.add(const SizedBox(height: YLSpacing.md));
      }

      // Module list
      for (final module in state.modules) {
        bodyChildren.add(
          Padding(
            padding: const EdgeInsets.only(bottom: YLSpacing.sm + 2),
            child: ModuleCard(
              module: module,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ModuleDetailPage(moduleId: module.id),
                ),
              ),
            ),
          ),
        );
      }
    }

    return Scaffold(
      // The scaffold backgroung+FAB are managed by YLLargeTitleScaffold's
      // inner Scaffold; we wrap that one in another to host the FAB.
      // But to keep things simple we drop the FAB into the scrollable body
      // by using a Stack via the bottomBar slot — instead, mount FAB on
      // the outer Scaffold below.
      body: _ScaffoldWithFab(
        showFab: state.modules.isNotEmpty,
        onFabPressed: () => _showAddSheet(context, ref),
        child: YLLargeTitleScaffold(
          title: s.modulesLabel,
          maxContentWidth: kYLSecondaryContentWidth,
          actions: [
            if (state.modules.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: s.moduleAddUrl,
                onPressed: () => _showAddSheet(context, ref),
              ),
          ],
          onRefresh: () => ref.read(moduleProvider.notifier).refreshAll(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                YLSpacing.lg,
                0,
                YLSpacing.lg,
                YLSpacing.xl,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate(bodyChildren),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddSheet(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const AddModuleSheet(),
    );
  }
}

/// Overlay scaffold that paints a floating "+" FAB on top of the
/// large-title scaffold — kept here so we can have a real Scaffold
/// hosting the FAB without disturbing the YLLargeTitleScaffold's own
/// background tokens.
class _ScaffoldWithFab extends StatelessWidget {
  final bool showFab;
  final VoidCallback onFabPressed;
  final Widget child;

  const _ScaffoldWithFab({
    required this.showFab,
    required this.onFabPressed,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: child),
        if (showFab)
          Positioned(
            right: YLSpacing.lg,
            bottom: YLSpacing.lg,
            child: FloatingActionButton(
              onPressed: onFabPressed,
              child: const Icon(Icons.add),
            ),
          ),
      ],
    );
  }
}

// ── MITM Engine Card ──────────────────────────────────────────────────────────

class _MitmEngineCard extends ConsumerWidget {
  final bool hasMitmHostnames;
  const _MitmEngineCard({required this.hasMitmHostnames});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mitm = ref.watch(mitmProvider);
    final engine = mitm.engine;

    final statusColor = engine.running ? YLColors.connected : YLColors.zinc400;
    final statusLabel = engine.running
        ? s.mitmEngineRunning
        : s.mitmEngineStopped;

    return Container(
      decoration:
          YLGlass.surfaceDecoration(
            context,
            elevated: false,
            strong: engine.running,
          ).copyWith(
            border: Border.all(
              color: engine.running
                  ? YLColors.connected.withValues(alpha: 0.25)
                  : (isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.white.withValues(alpha: 0.72)),
              width: 0.5,
            ),
          ),
      padding: const EdgeInsets.symmetric(
        horizontal: YLSpacing.lg,
        vertical: YLSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Row(
            children: [
              Icon(
                Icons.security,
                size: 16,
                color: isDark ? YLColors.zinc300 : YLColors.zinc700,
              ),
              const SizedBox(width: 6),
              Text(
                s.mitmEngine,
                style: YLText.label.copyWith(
                  color: isDark ? Colors.white : YLColors.zinc900,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // Status dot + label
              YLStatusDot(color: statusColor),
              const SizedBox(width: 4),
              Text(
                statusLabel,
                style: YLText.caption.copyWith(color: statusColor),
              ),
            ],
          ),

          // Port info when running
          if (engine.running) ...[
            const SizedBox(height: YLSpacing.xs),
            Text(
              '${s.mitmEnginePort}: ${engine.port}',
              style: YLText.caption.copyWith(color: YLColors.zinc500),
            ),
          ],

          // Error message
          if (mitm.error != null) ...[
            const SizedBox(height: 6),
            Text(
              mitm.error!,
              style: YLText.caption.copyWith(color: YLColors.error),
            ),
          ],

          const SizedBox(height: YLSpacing.sm + 2),
          Divider(
            height: 1,
            thickness: 0.33,
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.06),
          ),
          const SizedBox(height: YLSpacing.sm + 2),

          // Action row
          Row(
            children: [
              // Start / Stop toggle
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: mitm.isLoading
                      ? null
                      : () => engine.running
                            ? ref.read(mitmProvider.notifier).stopEngine()
                            : ref.read(mitmProvider.notifier).startEngine(),
                  icon: mitm.isLoading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          engine.running ? Icons.stop : Icons.play_arrow,
                          size: 16,
                        ),
                  label: Text(
                    engine.running ? s.mitmEngineStop : s.mitmEngineStart,
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: engine.running
                        ? YLColors.error
                        : (isDark ? Colors.white : YLColors.zinc900),
                    side: BorderSide(
                      color: engine.running
                          ? YLColors.error.withValues(alpha: 0.4)
                          : (isDark
                                ? Colors.white.withValues(alpha: 0.12)
                                : Colors.black.withValues(alpha: 0.12)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: YLSpacing.sm),
              // Certificate guide button
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CertGuidePage()),
                ),
                icon: const Icon(Icons.verified_user_rounded, size: 16),
                label: Text(s.mitmCertTitle),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? YLColors.zinc300 : YLColors.zinc600,
                  side: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.black.withValues(alpha: 0.12),
                  ),
                ),
              ),
            ],
          ),

          // MITM hostnames hint
          if (hasMitmHostnames && !engine.running) ...[
            const SizedBox(height: YLSpacing.sm),
            Row(
              children: [
                const Icon(
                  Icons.info_rounded,
                  size: 13,
                  color: YLColors.connecting,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Start the engine to enable MITM hostname routing',
                    style: YLText.caption.copyWith(color: YLColors.connecting),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(YLSpacing.xxl),
        child: YLEmptyState(
          icon: Icons.extension_rounded,
          title: s.modulesEmpty,
          subtitle:
              'Add a .sgmodule URL to inject rules\ninto your proxy config.',
          action: FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: Text(s.moduleAddUrl),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String error;
  const _ErrorBanner({required this.error});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: YLSpacing.lg,
        vertical: YLSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: YLColors.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(YLRadius.lg),
        border: Border.all(
          color: YLColors.error.withValues(alpha: 0.25),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_rounded, size: 16, color: YLColors.error),
          const SizedBox(width: YLSpacing.sm),
          Expanded(
            child: Text(
              error,
              style: YLText.caption.copyWith(color: YLColors.error),
            ),
          ),
        ],
      ),
    );
  }
}
