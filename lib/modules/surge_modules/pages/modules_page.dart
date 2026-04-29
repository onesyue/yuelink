import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/app_strings.dart';
import '../../../shared/widgets/empty_state.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: Text(s.modulesLabel),
        centerTitle: false,
        actions: [
          if (state.modules.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: s.moduleAddUrl,
              onPressed: () => _showAddSheet(context, ref),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(moduleProvider.notifier).refreshAll(),
        child: state.isLoading && state.modules.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : state.modules.isEmpty
            ? _EmptyState(onAdd: () => _showAddSheet(context, ref))
            : ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                children: [
                  // MITM Engine card (always shown when modules exist)
                  _MitmEngineCard(hasMitmHostnames: totalMitmHostnames > 0),
                  const SizedBox(height: 12),

                  // Header summary
                  if (activeCount > 0) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        '$activeCount active module${activeCount > 1 ? 's' : ''} · $totalRules rules injected'
                        '${totalMitmHostnames > 0 ? ' · $totalMitmHostnames MITM hostnames' : ''}',
                        style: YLText.caption.copyWith(
                          color: YLColors.zinc500,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ],
                  // Error banner
                  if (state.error != null) ...[
                    _ErrorBanner(error: state.error!),
                    const SizedBox(height: 12),
                  ],
                  // Module list
                  ...state.modules.map(
                    (module) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ModuleCard(
                        module: module,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                ModuleDetailPage(moduleId: module.id),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
      floatingActionButton: state.modules.isEmpty
          ? null
          : FloatingActionButton(
              onPressed: () => _showAddSheet(context, ref),
              child: const Icon(Icons.add),
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
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc900 : Colors.white,
        borderRadius: BorderRadius.circular(YLRadius.lg),
        border: Border.all(
          color: engine.running
              ? YLColors.connected.withValues(alpha: 0.25)
              : (isDark ? YLColors.zinc800 : YLColors.zinc200),
          width: 0.5,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                  color: isDark ? YLColors.zinc200 : YLColors.zinc800,
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
            const SizedBox(height: 4),
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

          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),

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
                        : (isDark ? YLColors.zinc200 : YLColors.zinc800),
                    side: BorderSide(
                      color: engine.running
                          ? YLColors.error.withValues(alpha: 0.4)
                          : (isDark ? YLColors.zinc700 : YLColors.zinc300),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Certificate guide button
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CertGuidePage()),
                ),
                icon: const Icon(Icons.verified_user_outlined, size: 16),
                label: Text(s.mitmCertTitle),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? YLColors.zinc300 : YLColors.zinc600,
                  side: BorderSide(
                    color: isDark ? YLColors.zinc700 : YLColors.zinc300,
                  ),
                ),
              ),
            ],
          ),

          // MITM hostnames hint
          if (hasMitmHostnames && !engine.running) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.info_outline,
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
        padding: const EdgeInsets.all(32),
        child: YLEmptyState(
          icon: Icons.extension_outlined,
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
          const Icon(Icons.error_outline, size: 16, color: YLColors.error),
          const SizedBox(width: 8),
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
