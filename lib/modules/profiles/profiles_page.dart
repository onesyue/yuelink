import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_strings.dart';
import '../../main.dart' show deepLinkUrlProvider;
import '../../domain/models/profile.dart';
import 'providers/profiles_providers.dart';
import '../../shared/app_notifier.dart';
import '../../services/profile_service.dart';
import '../../shared/formatters/subscription_parser.dart';
import '../../theme.dart';
import '../../widgets/loading_overlay.dart';

/// Strip "Exception: " prefix from error strings for user-facing display.
String _friendlyError(Object e) {
  final s = e.toString();
  if (s.startsWith('Exception: ')) return s.substring(11);
  return s;
}

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  @override
  void initState() {
    super.initState();
    // Handle deep links that arrive while this page is active
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.listenManual(deepLinkUrlProvider, (_, url) {
        if (url != null && url.isNotEmpty && mounted) {
          ref.read(deepLinkUrlProvider.notifier).state = null; // consume
          _showAddDialog(context, ref, prefilledUrl: url);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profilesAsync = ref.watch(profilesProvider);
    final activeId = ref.watch(activeProfileIdProvider);

    return Scaffold(
      body: Column(
        children: [
          // ── Top bar ──────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(32, MediaQuery.of(context).padding.top + 16, 32, 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    s.navProfile,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.5,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  tooltip: s.updateAllNow,
                  onPressed: () => _updateAllProfiles(context, ref),
                  style: IconButton.styleFrom(
                    foregroundColor: YLColors.zinc500,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.content_paste, size: 18),
                  tooltip: s.pasteFromClipboard,
                  onPressed: () => _pasteFromClipboard(context, ref),
                  style: IconButton.styleFrom(
                    foregroundColor: YLColors.zinc500,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.folder_open, size: 18),
                  tooltip: s.importLocalFile,
                  onPressed: () => _importLocalFile(context, ref),
                  style: IconButton.styleFrom(
                    foregroundColor: YLColors.zinc500,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add, size: 20),
                  tooltip: s.addSubscription,
                  onPressed: () => _showAddDialog(context, ref),
                  style: IconButton.styleFrom(
                    foregroundColor: isDark ? Colors.white : YLColors.primary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 0.5,
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.06),
          ),

          // ── Content ──────────────────────────────────────────────
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: profilesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => YLEmptyState(
                icon: Icons.error_outline,
                message: s.loadFailed(e.toString()),
                action: FilledButton.icon(
                  onPressed: () =>
                      ref.read(profilesProvider.notifier).load(),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(s.retry),
                ),
              ),
              data: (profiles) {
                if (profiles.isEmpty) {
                  return YLEmptyState(
                    icon: Icons.description_outlined,
                    message: '${s.noProfiles}\n${s.addSubscriptionHint}',
                  );
                }
                final sorted = List<Profile>.from(profiles)
                  ..sort((a, b) {
                    if (a.id == activeId && b.id != activeId) return -1;
                    if (b.id == activeId && a.id != activeId) return 1;
                    return 0;
                  });
                return RefreshIndicator(
                  onRefresh: () => ref.read(profilesProvider.notifier).load(),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                    itemCount: sorted.length,
                    itemBuilder: (context, index) {
                      final profile = sorted[index];
                      final isActive = profile.id == activeId;
                      return _ProfileCard(
                        profile: profile,
                        isActive: isActive,
                        onTap: () {
                          ref
                              .read(activeProfileIdProvider.notifier)
                              .select(profile.id);
                        },
                        onUpdate: () => _doUpdateProfile(context, ref, profile),
                        onEdit: () => _showEditDialog(context, ref, profile),
                        onViewConfig: () =>
                            _showConfigViewer(context, profile),
                        onDelete: () =>
                            _confirmDelete(context, ref, profile),
                      );
                    },
                  ),
                );
              },
            ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _updateAllProfiles(BuildContext context, WidgetRef ref) async {
    final s = S.of(context);
    AppNotifier.info(s.updatingAll);
    final profiles = await ProfileService.loadProfiles();
    int updated = 0, failed = 0;
    for (final p in profiles) {
      if (p.url.isEmpty) continue;
      try {
        await ProfileService.updateProfile(p);
        updated++;
      } catch (_) {
        failed++;
      }
    }
    AppNotifier.success(s.updateAllResult(updated, failed));
    ref.read(profilesProvider.notifier).load();
  }

  Future<void> _importLocalFile(
      BuildContext context, WidgetRef ref) async {
    final s = S.of(context);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['yaml', 'yml'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;

    final content = await File(path).readAsString();
    if (content.trim().isEmpty) {
      AppNotifier.warning(s.importLocalFileFailed);
      return;
    }

    // Use filename (without extension) as default profile name
    final fileName = result.files.first.name;
    final defaultName =
        fileName.replaceAll(RegExp(r'\.(yaml|yml)$'), '');

    if (!context.mounted) return;
    _showImportNameDialog(context, ref, defaultName, content);
  }

  void _showImportNameDialog(BuildContext context, WidgetRef ref,
      String defaultName, String configContent) {
    final s = S.of(context);
    final nameCtrl = TextEditingController(text: defaultName);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.importLocalFile),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: s.nameLabel,
            hintText: s.importLocalNameHint,
            prefixIcon: const Icon(Icons.label_outline),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              _doImportLocal(context, ref, name, configContent);
            },
            child: Text(s.add),
          ),
        ],
      ),
    ).whenComplete(nameCtrl.dispose);
  }

  Future<void> _pasteFromClipboard(
      BuildContext context, WidgetRef ref) async {
    final s = S.of(context);
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty || !text.startsWith('http')) {
      AppNotifier.warning(s.clipboardNoUrl);
      return;
    }
    if (context.mounted) {
      _showAddDialog(context, ref, prefilledUrl: text);
    }
  }

  void _confirmDelete(
      BuildContext context, WidgetRef ref, Profile profile) {
    final s = S.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.confirmDelete),
        content: Text(s.confirmDeleteMessage(profile.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref
                  .read(profilesProvider.notifier)
                  .delete(profile.id);
              final activeId = ref.read(activeProfileIdProvider);
              if (activeId == profile.id) {
                ref
                    .read(activeProfileIdProvider.notifier)
                    .select(null);
              }
            },
            style:
                FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(s.delete),
          ),
        ],
      ),
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref,
      {String? prefilledUrl}) {
    final s = S.of(context);
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController(text: prefilledUrl);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.addSubscriptionDialogTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: s.nameLabel,
                hintText: s.nameHint,
                prefixIcon: const Icon(Icons.label_outline),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlCtrl,
              decoration: InputDecoration(
                labelText: s.urlLabel,
                hintText: 'https://...',
                prefixIcon: const Icon(Icons.link),
              ),
              maxLines: 2,
              textInputAction: TextInputAction.done,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              final url = urlCtrl.text.trim();
              if (name.isEmpty || url.isEmpty) return;
              Navigator.pop(ctx); // close dialog first
              _doAddProfile(context, ref, name, url);
            },
            child: Text(s.add),
          ),
        ],
      ),
    );
  }

  Future<void> _doAddProfile(
      BuildContext context, WidgetRef ref, String name, String url) async {
    final s = S.of(context);
    try {
      final profile = await LoadingOverlay.run(
        context,
        message: s.downloadingSubscription,
        action: () => ref.read(profilesProvider.notifier).add(name: name, url: url),
      );
      ref.read(activeProfileIdProvider.notifier).select(profile.id);
      AppNotifier.success(s.addSuccess);
    } catch (e) {
      AppNotifier.error(s.addFailed(_friendlyError(e)));
    }
  }

  Future<void> _doImportLocal(BuildContext context, WidgetRef ref,
      String name, String configContent) async {
    final s = S.of(context);
    try {
      final profile = await LoadingOverlay.run(
        context,
        message: s.downloadingSubscription,
        action: () async {
          final p = await ProfileService.addLocalProfile(
              name: name, configContent: configContent);
          ref.read(profilesProvider.notifier).addLocal(p);
          return p;
        },
      );
      ref.read(activeProfileIdProvider.notifier).select(profile.id);
      AppNotifier.success(s.importLocalFileSuccess);
    } catch (e) {
      AppNotifier.error(s.addFailed(_friendlyError(e)));
    }
  }

  Future<void> _doUpdateProfile(
      BuildContext context, WidgetRef ref, Profile profile) async {
    final s = S.of(context);
    try {
      await LoadingOverlay.run(
        context,
        message: s.updatingSubscription,
        action: () => ref.read(profilesProvider.notifier).update(profile),
      );
      AppNotifier.success(s.updateSuccess);
    } catch (e) {
      AppNotifier.error(s.updateFailed(_friendlyError(e)));
    }
  }

  void _showEditDialog(
      BuildContext context, WidgetRef ref, Profile profile) {
    final s = S.of(context);
    final nameCtrl = TextEditingController(text: profile.name);
    final urlCtrl = TextEditingController(text: profile.url);
    int intervalHours = profile.updateInterval.inHours;
    const options = [0, 6, 12, 24, 48, 168];
    if (!options.contains(intervalHours)) intervalHours = 24;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: Text(s.editSubscriptionDialogTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: s.nameLabel,
                  prefixIcon: const Icon(Icons.label_outline),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlCtrl,
                decoration: InputDecoration(
                  labelText: s.urlLabel,
                  prefixIcon: const Icon(Icons.link),
                ),
                maxLines: 2,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.update, size: 18, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(s.updateInterval),
                  const Spacer(),
                  DropdownButton<int>(
                    value: intervalHours,
                    underline: const SizedBox.shrink(),
                    items: [
                      DropdownMenuItem(
                          value: 0, child: Text(s.followGlobal)),
                      DropdownMenuItem(value: 6, child: Text(s.hours6)),
                      DropdownMenuItem(
                          value: 12, child: Text(s.hours12)),
                      DropdownMenuItem(
                          value: 24, child: Text(s.hours24)),
                      DropdownMenuItem(
                          value: 48, child: Text(s.hours48)),
                      DropdownMenuItem(value: 168, child: Text(s.days7)),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setStateDialog(() => intervalHours = v);
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(s.cancel),
            ),
            FilledButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                final url = urlCtrl.text.trim();
                if (name.isEmpty || url.isEmpty) return;

                profile.name = name;
                profile.url = url;
                profile.updateInterval = intervalHours == 0
                    ? const Duration(hours: 24)
                    : Duration(hours: intervalHours);
                Navigator.pop(ctx);
                _doUpdateProfile(context, ref, profile);
              },
              child: Text(s.save),
            ),
          ],
        ),
      ),
    );
  }

  void _showConfigViewer(BuildContext context, Profile profile) async {
    final s = S.of(context);
    final config = await ProfileService.loadConfig(profile.id);
    if (!context.mounted) return;

    Navigator.of(context).push(MaterialPageRoute(
      builder: (ctx) => Scaffold(
        appBar: AppBar(
          leading: const BackButton(),
          title: Text(profile.name),
          actions: [
            if (config != null)
              IconButton(
                icon: const Icon(Icons.copy),
                tooltip: s.copyConfig,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: config));
                  AppNotifier.success(s.copiedConfig);
                },
              ),
          ],
        ),
        body: config == null
            ? Center(child: Text(s.noConfig))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  config,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ),
      ),
    ));
  }
}

class _ProfileCard extends StatelessWidget {
  final Profile profile;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onUpdate;
  final VoidCallback onEdit;
  final VoidCallback onViewConfig;
  final VoidCallback onDelete;

  const _ProfileCard({
    required this.profile,
    required this.isActive,
    required this.onTap,
    required this.onUpdate,
    required this.onEdit,
    required this.onViewConfig,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sub = profile.subInfo;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isActive
            ? (isDark
                ? YLColors.primary.withValues(alpha: 0.10)
                : YLColors.primaryLight)
            : (isDark ? YLColors.zinc800 : Colors.white),
        borderRadius: BorderRadius.circular(YLRadius.xl),
        border: Border.all(
          color: isActive
              ? YLColors.primary.withValues(alpha: 0.20)
              : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08)),
          width: 0.5,
        ),
        boxShadow: YLShadow.card(context),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(YLRadius.xl),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  Icon(
                    isActive
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                    color: isActive
                        ? YLColors.primary
                        : YLColors.zinc400,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(profile.name,
                        style: YLText.titleMedium),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (action) {
                      switch (action) {
                        case 'update':
                          onUpdate();
                        case 'edit':
                          onEdit();
                        case 'config':
                          onViewConfig();
                        case 'copy':
                          Clipboard.setData(
                              ClipboardData(text: profile.url));
                          AppNotifier.success(s.copiedLink);
                        case 'delete':
                          onDelete();
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                          value: 'update',
                          child: Text(s.updateSubscription)),
                      PopupMenuItem(value: 'edit', child: Text(s.edit)),
                      PopupMenuItem(
                          value: 'config', child: Text(s.viewConfig)),
                      PopupMenuItem(
                          value: 'copy', child: Text(s.copyLink)),
                      PopupMenuItem(
                          value: 'delete',
                          child: Text(s.delete,
                              style:
                                  const TextStyle(color: Colors.red))),
                    ],
                  ),
                ],
              ),

              // Subscription info
              if (profile.hasSubInfo && sub != null) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(YLRadius.sm),
                  child: LinearProgressIndicator(
                    value: sub.usagePercent ?? 0,
                    minHeight: 6,
                    backgroundColor: isDark
                        ? YLColors.zinc700
                        : YLColors.zinc200,
                    color: _usageColor(sub.usagePercent ?? 0),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      s.usageLabel(
                        formatBytes(
                            (sub.upload ?? 0) + (sub.download ?? 0)),
                        formatBytes(sub.total ?? 0),
                      ),
                      style: YLText.caption,
                    ),
                    const Spacer(),
                    if (sub.expire != null)
                      Text(
                        sub.isExpired
                            ? s.expired
                            : s.daysRemaining(
                                sub.daysRemaining ?? 0),
                        style: YLText.caption.copyWith(
                          color: sub.isExpired
                              ? YLColors.error
                              : (sub.daysRemaining != null &&
                                      sub.daysRemaining! < 7)
                                  ? Colors.orange
                                  : YLColors.zinc500,
                        ),
                      ),
                  ],
                ),
              ],

              // Last updated + staleness warning
              if (profile.lastUpdated != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      s.updatedAt(_formatTime(profile.lastUpdated!)),
                      style: YLText.caption.copyWith(
                          color: YLColors.zinc500),
                    ),
                    if (_isStale(profile)) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.warning_amber_rounded,
                          size: 14,
                          color: Colors.orange.shade700),
                      const SizedBox(width: 2),
                      Text(s.needsUpdate,
                          style: YLText.caption.copyWith(
                              color: Colors.orange.shade700)),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _usageColor(double percent) {
    if (percent < 0.5) return Colors.green;
    if (percent < 0.8) return Colors.orange;
    return Colors.red;
  }

  bool _isStale(Profile p) {
    if (p.lastUpdated == null) return false;
    return DateTime.now().difference(p.lastUpdated!) > p.updateInterval;
  }

  String _formatTime(DateTime dt) {
    return '${dt.month}/${dt.day} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}
