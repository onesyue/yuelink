import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/platform/vpn_service.dart';
import '../../../../i18n/app_strings.dart';
import '../../../../theme.dart';
import '../../providers/settings_providers.dart';
import '../../widgets/primitives.dart';

/// Android-only split-tunnel section.
///
/// Owns its own app-list state (`_apps` / `_search` / `_loading` /
/// `_loadError`), async installed-app fetch via `VpnService`, and the
/// app-picker modal bottom sheet. Watches `splitTunnelModeProvider` +
/// `splitTunnelAppsProvider`; no page-level state closure.
///
/// Extracted from `sub/general_settings_page.dart` (Batch ζ). Class
/// body copied verbatim; only the top-level prefix `_` was dropped on
/// the public class for cross-library visibility.
class SplitTunnelSection extends ConsumerStatefulWidget {
  const SplitTunnelSection({super.key});

  @override
  ConsumerState<SplitTunnelSection> createState() =>
      _SplitTunnelSectionState();
}

class _SplitTunnelSectionState extends ConsumerState<SplitTunnelSection> {
  List<Map<String, String>>? _apps;
  String _search = '';
  bool _loading = false;
  String? _loadError;

  Future<void> _loadApps() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final apps = await VpnService.getInstalledApps(showSystem: true);
      if (mounted) {
        setState(() {
          _apps = apps;
          _loading = false;
          if (apps.isEmpty) {
            _loadError = S.of(context).isEn
                ? 'No apps found. Your device may restrict app visibility.'
                : '未获取到应用列表，可能受系统权限限制。';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _apps = [];
          _loading = false;
          _loadError = '${S.of(context).loadAppListFailed}: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mode = ref.watch(splitTunnelModeProvider);
    final selectedPkgs = ref.watch(splitTunnelAppsProvider);
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.06);

    return SettingsCard(
      child: Column(
        children: [
          // Mode selector
          YLInfoRow(
            label: s.splitTunnelMode,
            trailing: DropdownButton<SplitTunnelMode>(
              value: mode,
              underline: const SizedBox.shrink(),
              style: YLText.body.copyWith(
                color: isDark ? YLColors.zinc200 : YLColors.zinc700,
              ),
              dropdownColor: isDark ? YLColors.zinc800 : Colors.white,
              items: [
                DropdownMenuItem(
                    value: SplitTunnelMode.all,
                    child: Text(s.splitTunnelModeAll)),
                DropdownMenuItem(
                    value: SplitTunnelMode.whitelist,
                    child: Text(s.splitTunnelModeWhitelist)),
                DropdownMenuItem(
                    value: SplitTunnelMode.blacklist,
                    child: Text(s.splitTunnelModeBlacklist)),
              ],
              onChanged: (v) {
                if (v != null) {
                  ref.read(splitTunnelModeProvider.notifier).set(v);
                }
              },
            ),
          ),
          if (mode != SplitTunnelMode.all) ...[
            Divider(height: 1, thickness: 0.5, color: dividerColor),
            YLSettingsRow(
              title: s.splitTunnelApps,
              description: s.splitTunnelEffectHint,
              trailing: TextButton.icon(
                icon: const Icon(Icons.apps, size: 14),
                label: Text(s.splitTunnelManage),
                onPressed: () async {
                  if (_apps == null) await _loadApps();
                  if (!context.mounted) return;
                  _showAppPicker(context, selectedPkgs);
                },
              ),
            ),
            if (selectedPkgs.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: selectedPkgs
                      .map((pkg) => Chip(
                            label:
                                Text(pkg, style: const TextStyle(fontSize: 11)),
                            deleteIcon: const Icon(Icons.close, size: 14),
                            onDeleted: () => ref
                                .read(splitTunnelAppsProvider.notifier)
                                .remove(pkg),
                          ))
                      .toList(),
                ),
              ),
          ],
        ],
      ),
    );
  }

  void _showAppPicker(BuildContext context, List<String> initialSelected) {
    final s = S.of(context);
    final localSelected = Set<String>.from(initialSelected);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          final apps = _apps ?? [];
          final filtered = _search.isEmpty
              ? List<Map<String, String>>.from(apps)
              : apps
                  .where((a) =>
                      (a['appName'] ?? '').toLowerCase().contains(_search) ||
                      (a['packageName'] ?? '').toLowerCase().contains(_search))
                  .toList();
          filtered.sort((a, b) {
            final aSelected = localSelected.contains(a['packageName']);
            final bSelected = localSelected.contains(b['packageName']);
            if (aSelected != bSelected) return aSelected ? -1 : 1;
            return (a['appName'] ?? '').compareTo(b['appName'] ?? '');
          });

          return DraggableScrollableSheet(
            initialChildSize: 0.85,
            expand: false,
            builder: (_, sc) => Column(
              children: [
                const SizedBox(height: 8),
                Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2))),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    autofocus: false,
                    decoration: InputDecoration(
                      hintText: s.splitTunnelSearchHint,
                      prefixIcon: const Icon(Icons.search, size: 18),
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (v) => setModal(() => _search = v.toLowerCase()),
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : filtered.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.apps_rounded,
                                        size: 40, color: YLColors.zinc400),
                                    const SizedBox(height: 12),
                                    Text(
                                      _loadError ??
                                          (_search.isNotEmpty
                                              ? (S.of(context).isEn
                                                  ? 'No matching apps'
                                                  : '未找到匹配应用')
                                              : (S.of(context).isEn
                                                  ? 'No apps found'
                                                  : '未获取到应用')),
                                      textAlign: TextAlign.center,
                                      style: YLText.body
                                          .copyWith(color: YLColors.zinc500),
                                    ),
                                    if (_loadError != null) ...[
                                      const SizedBox(height: 12),
                                      TextButton(
                                        onPressed: () {
                                          _loadApps()
                                              .then((_) => setModal(() {}));
                                        },
                                        child: Text(S.of(context).isEn
                                            ? 'Retry'
                                            : '重试'),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: sc,
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final app = filtered[i];
                                final pkg = app['packageName'] ?? '';
                                final isSelected = localSelected.contains(pkg);
                                return CheckboxListTile(
                                  dense: true,
                                  title: Text(app['appName'] ?? pkg),
                                  subtitle: Text(pkg,
                                      style: const TextStyle(fontSize: 11)),
                                  value: isSelected,
                                  onChanged: (_) {
                                    setModal(() {
                                      if (localSelected.contains(pkg)) {
                                        localSelected.remove(pkg);
                                      } else {
                                        localSelected.add(pkg);
                                      }
                                    });
                                    ref
                                        .read(splitTunnelAppsProvider.notifier)
                                        .toggle(pkg);
                                  },
                                );
                              },
                            ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
