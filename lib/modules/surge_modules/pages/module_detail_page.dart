import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/app_strings.dart';
import '../../../theme.dart';
import '../../../domain/surge_modules/module_entity.dart';
import '../providers/module_provider.dart';

/// Detail page for a single module.
class ModuleDetailPage extends ConsumerStatefulWidget {
  final String moduleId;

  const ModuleDetailPage({super.key, required this.moduleId});

  @override
  ConsumerState<ModuleDetailPage> createState() => _ModuleDetailPageState();
}

class _ModuleDetailPageState extends ConsumerState<ModuleDetailPage> {
  bool _refreshing = false;

  ModuleRecord? _findModule(ModuleState state) {
    try {
      return state.modules.firstWhere((m) => m.id == widget.moduleId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      await ref.read(moduleProvider.notifier).refreshModule(widget.moduleId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final s = S.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.moduleDelete),
        content: Text(s.moduleDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: YLColors.error,
            ),
            child: Text(s.confirm),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref.read(moduleProvider.notifier).deleteModule(widget.moduleId);
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final state = ref.watch(moduleProvider);
    final module = _findModule(state);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (module == null) {
      return Scaffold(
        appBar: AppBar(title: Text(s.modulesLabel)),
        body: const Center(child: Text('Module not found')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(module.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        centerTitle: false,
        actions: [
          IconButton(
            icon: _refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            tooltip: s.moduleRefresh,
            onPressed: _refreshing ? null : _refresh,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: s.moduleDelete,
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // ── Header ──────────────────────────────────────────────────
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        module.name,
                        style: YLText.titleMedium.copyWith(
                          color: isDark ? YLColors.zinc100 : YLColors.zinc900,
                        ),
                      ),
                    ),
                    if (module.versionTag != null)
                      _Chip(
                        label: 'v${module.versionTag}',
                        isDark: isDark,
                      ),
                  ],
                ),
                if (module.desc.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    module.desc,
                    style: YLText.body.copyWith(color: YLColors.zinc500),
                  ),
                ],
                if (module.author != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'by ${module.author}',
                    style: YLText.caption.copyWith(color: YLColors.zinc400),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Stats ────────────────────────────────────────────────────
          _SectionTitle(s.moduleRuleCount),
          _SectionCard(
            child: Column(
              children: [
                _StatRow(
                  label: s.moduleRuleCount,
                  value: module.rules.length.toString(),
                  isDark: isDark,
                ),
                if (module.mitmHostnames.isNotEmpty) ...[
                  _Divider(isDark: isDark),
                  _StatRow(
                    label: 'MITM Hostnames',
                    value: '${module.mitmHostnames.length}',
                    isDark: isDark,
                  ),
                ],
                if (module.urlRewrites.isNotEmpty) ...[
                  _Divider(isDark: isDark),
                  _StatRow(
                    label: 'URL Rewrites',
                    value: '${module.urlRewrites.length}',
                    isDark: isDark,
                  ),
                ],
                if (module.headerRewrites.isNotEmpty) ...[
                  _Divider(isDark: isDark),
                  _StatRow(
                    label: 'Header Rewrites',
                    value: '${module.headerRewrites.length}',
                    isDark: isDark,
                  ),
                ],
                if (module.scripts.isNotEmpty) ...[
                  _Divider(isDark: isDark),
                  _StatRow(
                    label: 'Scripts',
                    value: '${module.scripts.length}',
                    isDark: isDark,
                  ),
                ],
                if (module.mapLocals.isNotEmpty) ...[
                  _Divider(isDark: isDark),
                  _StatRow(
                    label: 'Map Local',
                    value: '${module.mapLocals.length}',
                    isDark: isDark,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Active capabilities section ──────────────────────────────
          if (module.rules.isNotEmpty ||
              module.mitmHostnames.isNotEmpty ||
              module.urlRewrites.isNotEmpty ||
              module.headerRewrites.isNotEmpty) ...[
            const _SectionTitle('Currently Active'),
            _SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (module.rules.isNotEmpty) ...[
                    Text(
                      '${module.rules.length} routing rules',
                      style: YLText.body.copyWith(
                        color: isDark ? YLColors.zinc300 : YLColors.zinc700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...module.rules.take(5).map(
                      (r) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          r.raw,
                          style: YLText.mono.copyWith(
                            fontSize: 11,
                            color: YLColors.zinc500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (module.rules.length > 5)
                      Text(
                        '… and ${module.rules.length - 5} more',
                        style: YLText.caption.copyWith(color: YLColors.zinc400),
                      ),
                  ],
                  if (module.mitmHostnames.isNotEmpty) ...[
                    if (module.rules.isNotEmpty) const SizedBox(height: 10),
                    _ActiveRow(
                      icon: Icons.security,
                      label: 'TLS Interception',
                      detail: '${module.mitmHostnames.length} hostnames',
                      isDark: isDark,
                    ),
                  ],
                  if (module.urlRewrites.isNotEmpty) ...[
                    if (module.rules.isNotEmpty || module.mitmHostnames.isNotEmpty)
                      const SizedBox(height: 10),
                    _ActiveRow(
                      icon: Icons.swap_horiz,
                      label: 'URL Rewrite',
                      detail: '${module.urlRewrites.length} rules',
                      isDark: isDark,
                    ),
                  ],
                  if (module.headerRewrites.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _ActiveRow(
                      icon: Icons.tune,
                      label: 'Header Rewrite',
                      detail: '${module.headerRewrites.length} rules',
                      isDark: isDark,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── Not active section (Scripts / Map Local only) ─────────────
          if (module.scripts.isNotEmpty ||
              module.mapLocals.isNotEmpty ||
              module.unsupportedCounts.panelCount > 0) ...[
            _SectionTitle(s.moduleNotActive),
            _SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (module.scripts.isNotEmpty)
                    _UnsupportedRow(
                      label: '${s.moduleScriptDetected}: ${module.scripts.length}',
                      hint: s.moduleFutureVersion,
                      isDark: isDark,
                    ),
                  if (module.mapLocals.isNotEmpty)
                    _UnsupportedRow(
                      label: 'Map Local: ${module.mapLocals.length}',
                      hint: s.moduleFutureVersion,
                      isDark: isDark,
                    ),
                  if (module.unsupportedCounts.panelCount > 0)
                    _UnsupportedRow(
                      label: 'Panels: ${module.unsupportedCounts.panelCount}',
                      hint: s.moduleFutureVersion,
                      isDark: isDark,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── Warnings ─────────────────────────────────────────────────
          if (module.parseWarnings.isNotEmpty) ...[
            const _SectionTitle('Parse Warnings'),
            _SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: module.parseWarnings
                    .map(
                      (w) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          w,
                          style: YLText.caption.copyWith(
                            color: const Color(0xFFF59E0B),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── Metadata ─────────────────────────────────────────────────
          const _SectionTitle('Info'),
          _SectionCard(
            child: Column(
              children: [
                _MetaRow(
                  label: 'Source',
                  value: module.sourceUrl,
                  isDark: isDark,
                  monospace: true,
                ),
                _Divider(isDark: isDark),
                _MetaRow(
                  label: 'Last updated',
                  value: _formatDate(module.updatedAt),
                  isDark: isDark,
                ),
                if (module.lastFetchedAt != null) ...[
                  _Divider(isDark: isDark),
                  _MetaRow(
                    label: 'Last fetched',
                    value: _formatDate(module.lastFetchedAt!),
                    isDark: isDark,
                  ),
                ],
                _Divider(isDark: isDark),
                _MetaRow(
                  label: 'Checksum',
                  value: module.checksum.substring(
                    0,
                    module.checksum.length > 8 ? 8 : module.checksum.length,
                  ),
                  isDark: isDark,
                  monospace: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  static String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: YLText.caption.copyWith(
          letterSpacing: 1.2,
          fontWeight: FontWeight.w600,
          color: YLColors.zinc400,
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final Widget child;
  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc800 : Colors.white,
        borderRadius: BorderRadius.circular(YLRadius.xl),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.08),
          width: 0.5,
        ),
        boxShadow: YLShadow.card(context),
      ),
      child: child,
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;
  const _StatRow(
      {required this.label, required this.value, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: YLText.body.copyWith(
                color: isDark ? YLColors.zinc300 : YLColors.zinc700,
              ),
            ),
          ),
          Text(
            value,
            style: YLText.body.copyWith(
              color: isDark ? YLColors.zinc400 : YLColors.zinc500,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;
  final bool monospace;
  const _MetaRow({
    required this.label,
    required this.value,
    required this.isDark,
    this.monospace = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: YLText.caption.copyWith(color: YLColors.zinc400),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: monospace
                  ? YLText.mono.copyWith(
                      fontSize: 11,
                      color: isDark ? YLColors.zinc300 : YLColors.zinc600,
                    )
                  : YLText.caption.copyWith(
                      color: isDark ? YLColors.zinc300 : YLColors.zinc600,
                    ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String detail;
  final bool isDark;

  const _ActiveRow({
    required this.icon,
    required this.label,
    required this.detail,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: YLColors.connected),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: YLText.body.copyWith(
              color: isDark ? YLColors.zinc300 : YLColors.zinc700,
            ),
          ),
        ),
        Text(
          detail,
          style: YLText.caption.copyWith(color: YLColors.zinc400),
        ),
      ],
    );
  }
}

class _UnsupportedRow extends StatelessWidget {
  final String label;
  final String hint;
  final bool isDark;

  const _UnsupportedRow({
    required this.label,
    required this.hint,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    const warningColor = Color(0xFFF59E0B);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.warning_amber_rounded,
                size: 14, color: warningColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: YLText.body.copyWith(
                    color: isDark ? YLColors.zinc300 : YLColors.zinc700,
                  ),
                ),
                Text(
                  hint,
                  style: YLText.caption.copyWith(color: YLColors.zinc400),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  final bool isDark;
  const _Divider({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 0.5,
      color: isDark
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.black.withValues(alpha: 0.08),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool isDark;
  const _Chip({required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc700 : YLColors.zinc100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: YLText.caption.copyWith(
          color: isDark ? YLColors.zinc400 : YLColors.zinc500,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
