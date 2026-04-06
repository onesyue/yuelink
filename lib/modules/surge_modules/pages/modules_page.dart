import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_strings.dart';
import '../../../theme.dart';
import '../providers/module_provider.dart';
import '../widgets/add_module_sheet.dart';
import '../widgets/module_card.dart';
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
                        horizontal: 16, vertical: 12),
                    children: [
                      // Header summary
                      if (activeCount > 0) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            '$activeCount active module${activeCount > 1 ? 's' : ''} · $totalRules rules injected',
                            style: YLText.caption.copyWith(
                              color: YLColors.zinc500,
                              letterSpacing: 0.3,
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

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.extension_outlined,
              size: 64,
              color: isDark ? YLColors.zinc700 : YLColors.zinc300,
            ),
            const SizedBox(height: 16),
            Text(
              s.modulesEmpty,
              style: YLText.titleMedium.copyWith(
                color: isDark ? YLColors.zinc400 : YLColors.zinc500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add a .sgmodule URL to inject rules\ninto your proxy config.',
              textAlign: TextAlign.center,
              style: YLText.caption.copyWith(color: YLColors.zinc400),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: Text(s.moduleAddUrl),
            ),
          ],
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
