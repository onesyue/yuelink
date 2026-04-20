import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'qr_scan_page.dart';

import '../../i18n/app_strings.dart';
import '../../main.dart' show deepLinkUrlProvider;
import '../../domain/models/profile.dart';
import '../../core/providers/core_provider.dart';
import 'providers/profiles_providers.dart';
import '../../shared/app_notifier.dart';
import '../../infrastructure/repositories/profile_repository.dart';
import '../../core/kernel/core_manager.dart';
import '../../shared/formatters/subscription_parser.dart';
import '../../theme.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/yl_loading.dart';
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
  ProviderSubscription<String?>? _deepLinkSub;

  @override
  void initState() {
    super.initState();
    // Handle deep links that arrive while this page is active.
    // Store subscription so it is cancelled when the page is disposed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _deepLinkSub = ref.listenManual(deepLinkUrlProvider, (_, url) {
        if (url != null && url.isNotEmpty && mounted) {
          ref.read(deepLinkUrlProvider.notifier).state = null; // consume
          _showAddDialog(context, ref, prefilledUrl: url);
        }
      });
      // listenManual only fires on future changes — also check any URL that
      // was set before this page mounted (e.g. cold-start deep link).
      final pendingUrl = ref.read(deepLinkUrlProvider);
      if (pendingUrl != null && pendingUrl.isNotEmpty) {
        ref.read(deepLinkUrlProvider.notifier).state = null;
        _showAddDialog(context, ref, prefilledUrl: pendingUrl);
      }
    });
  }

  @override
  void dispose() {
    _deepLinkSub?.close();
    super.dispose();
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
                if (Navigator.canPop(context))
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: BackButton(onPressed: () => Navigator.pop(context)),
                  ),
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
                  icon: const Icon(Icons.add, size: 20),
                  tooltip: s.addSubscription,
                  onPressed: () => _autoAddFromClipboard(context, ref),
                  style: IconButton.styleFrom(
                    foregroundColor: isDark ? Colors.white : YLColors.primary,
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 20, color: YLColors.zinc500),
                  tooltip: s.isEn ? 'More' : '更多',
                  onSelected: (action) {
                    switch (action) {
                      case 'export_all':
                        _exportAllProfiles(context, ref);
                      case 'import_files':
                        _importLocalFile(context, ref);
                      case 'scan_qr':
                        _scanQrAndAdd(context, ref);
                    }
                  },
                  itemBuilder: (_) => [
                    if (Platform.isAndroid || Platform.isIOS)
                      PopupMenuItem(
                        value: 'scan_qr',
                        child: _menuItem(Icons.qr_code_scanner, s.scanQrImport),
                      ),
                    PopupMenuItem(
                      value: 'export_all',
                      child: _menuItem(Icons.upload_file_outlined, s.exportAllProfiles),
                    ),
                    PopupMenuItem(
                      value: 'import_files',
                      child: _menuItem(Icons.file_upload_outlined, s.importMultipleFiles),
                    ),
                  ],
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
              loading: () => const Center(child: YLLoading()),
              error: (e, _) => Center(
                child: YLEmptyState(
                  icon: Icons.error_outline,
                  title: s.loadFailed(e.toString()),
                  action: FilledButton.icon(
                    onPressed: () =>
                        ref.read(profilesProvider.notifier).load(),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: Text(s.retry),
                  ),
                ),
              ),
              data: (profiles) {
                if (profiles.isEmpty) {
                  return Center(
                    child: YLEmptyState(
                      icon: Icons.description_outlined,
                      title: s.noProfiles,
                      subtitle: s.addSubscriptionHint,
                    ),
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
                      final card = _ProfileCard(
                        profile: profile,
                        isActive: isActive,
                        onTap: () {
                          if (isActive) return;
                          _confirmSwitchProfile(context, ref, profile);
                        },
                        onUpdate: () => _doUpdateProfile(context, ref, profile),
                        onEdit: () => _showEditDialog(context, ref, profile),
                        onViewConfig: () =>
                            _showConfigViewer(context, profile),
                        onExport: () => _exportProfile(context, ref, profile),
                        onDelete: () =>
                            _confirmDelete(context, ref, profile),
                      );
                      // On mobile, left-swipe reveals a delete action — the
                      // iOS Mail / Gmail convention. Desktop keeps the
                      // existing context-menu Delete row, since swipe
                      // gestures don't apply to mouse-driven UIs.
                      if (!(Platform.isIOS || Platform.isAndroid)) return card;
                      return Dismissible(
                        key: ValueKey('profile_${profile.id}'),
                        direction: DismissDirection.endToStart,
                        background: _SwipeDeleteBackground(),
                        confirmDismiss: (_) async {
                          return await _confirmDeleteSheet(
                              context, ref, profile);
                        },
                        child: card,
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
    final repo = ref.read(profileRepositoryProvider);
    final profiles = await repo.loadProfiles();
    final proxyPort = CoreManager.instance.isRunning
        ? CoreManager.instance.mixedPort
        : null;
    int updated = 0, failed = 0;
    for (final p in profiles) {
      if (p.url.isEmpty) continue;
      try {
        await repo.updateProfile(p, proxyPort: proxyPort);
        updated++;
      } catch (_) {
        failed++;
      }
    }
    AppNotifier.success(s.updateAllResult(updated, failed));
    ref.read(profilesProvider.notifier).load();
  }

  /// Auto-read clipboard for URL, fetch subscription name, and show add dialog.
  Future<void> _autoAddFromClipboard(
      BuildContext context, WidgetRef ref) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    final hasUrl = text.isNotEmpty && text.startsWith('http');

    if (context.mounted) {
      _showAddDialog(
        context,
        ref,
        prefilledUrl: hasUrl ? text : null,
        autoFetchName: hasUrl,
      );
    }
  }

  /// Open QR scanner and pre-fill the add dialog with the scanned URL.
  Future<void> _scanQrAndAdd(BuildContext context, WidgetRef ref) async {
    final s = S.of(context);
    final url = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrScanPage()),
    );
    if (url == null || !context.mounted) return;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      AppNotifier.error(s.scanQrInvalidUrl);
      return;
    }
    _showAddDialog(context, ref, prefilledUrl: url, autoFetchName: true);
  }

  void _confirmSwitchProfile(
      BuildContext context, WidgetRef ref, Profile profile) {
    final s = S.of(context);
    final isRunning = ref.read(coreStatusProvider) == CoreStatus.running;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.switchProfileTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.switchProfileMessage(profile.name)),
            if (isRunning) ...[
              const SizedBox(height: 8),
              Text(
                s.switchProfileReconnectHint,
                style: TextStyle(color: Colors.orange.shade700, fontSize: 13),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(activeProfileIdProvider.notifier).select(profile.id);
            },
            child: Text(s.switchProfileConfirm),
          ),
        ],
      ),
    );
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
      {String? prefilledUrl, bool autoFetchName = false}) {
    final s = S.of(context);
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController(text: prefilledUrl);
    String? fetchedName;
    bool fetchingName = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          // Auto-fetch name when URL is pre-filled
          if (autoFetchName && prefilledUrl != null && !fetchingName && fetchedName == null) {
            fetchingName = true;
            ref.read(profileRepositoryProvider).fetchSubscriptionName(prefilledUrl).then((name) {
              if (ctx.mounted) {
                setDialogState(() {
                  fetchedName = name;
                  fetchingName = false;
                  // Only set if user hasn't typed a name
                  if (name != null && nameCtrl.text.trim().isEmpty) {
                    nameCtrl.text = name;
                  }
                });
              }
            });
          }

          return AlertDialog(
            title: Text(s.addSubscriptionDialogTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: s.nameLabel,
                    hintText: fetchingName
                        ? (s.isEn ? 'Fetching name...' : '正在获取名称...')
                        : s.nameHint,
                    prefixIcon: const Icon(Icons.label_outline),
                    suffixIcon: fetchingName
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
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
                    suffixIcon: (Platform.isAndroid || Platform.isIOS)
                        ? IconButton(
                            icon: const Icon(Icons.qr_code_scanner, size: 20),
                            tooltip: s.scanQrImport,
                            onPressed: () async {
                              final url = await Navigator.push<String>(
                                ctx,
                                MaterialPageRoute(
                                    builder: (_) => const QrScanPage()),
                              );
                              if (url != null && ctx.mounted) {
                                if (url.startsWith('http://') ||
                                    url.startsWith('https://')) {
                                  urlCtrl.text = url;
                                } else {
                                  AppNotifier.error(s.scanQrInvalidUrl);
                                }
                              }
                            },
                          )
                        : null,
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
                  if (url.isEmpty) return;
                  Navigator.pop(ctx); // close dialog first
                  // Name can be empty — ProfileRepository will use header name or URL hostname
                  _doAddProfile(context, ref, name, url);
                },
                child: Text(s.add),
              ),
            ],
          );
        },
      ),
    ).whenComplete(() {
      nameCtrl.dispose();
      urlCtrl.dispose();
    });
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



  /// Save only profile metadata (name, interval) without re-downloading.
  Future<void> _saveProfileMetadata(WidgetRef ref, Profile profile) async {
    try {
      final repo = ref.read(profileRepositoryProvider);
      await repo.saveProfileMetadata(profile);
      ref.read(profilesProvider.notifier).load();
      AppNotifier.success(S.current.saved);
    } catch (e) {
      AppNotifier.error(e.toString());
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
                if (name.isEmpty) return;

                final urlChanged = url != profile.url;
                profile.name = name;
                profile.url = url;
                profile.updateInterval = intervalHours == 0
                    ? const Duration(hours: 24)
                    : Duration(hours: intervalHours);
                Navigator.pop(ctx);
                if (url.isNotEmpty && urlChanged) {
                  // URL changed — re-download subscription
                  _doUpdateProfile(context, ref, profile);
                } else {
                  // Metadata-only change — save index without network
                  _saveProfileMetadata(ref, profile);
                }
              },
              child: Text(s.save),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      nameCtrl.dispose();
      urlCtrl.dispose();
    });
  }

  // ── Import / Export ───────────────────────────────────────────────

  /// Import one or more YAML/YML files as local profiles.
  ///
  /// Supports multi-select: user can pick multiple files in one dialog.
  /// Each file is imported independently — single failures don't block others.
  /// File names (without extension) are used as profile names automatically.
  Future<void> _importLocalFile(BuildContext context, WidgetRef ref) async {
    final s = S.of(context);
    // Use FileType.any because Android doesn't register YAML MIME type —
    // FileType.custom with ['yaml','yml'] causes the picker to show nothing
    // or not open at all on many devices. Filter by extension in code instead.
    final result = await FilePicker.pickFiles(
      type: FileType.any,
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    // Filter to YAML files only (user may have picked non-YAML files)
    final yamlFiles = result.files.where((f) {
      final ext = f.name.toLowerCase();
      return ext.endsWith('.yaml') || ext.endsWith('.yml') || ext.endsWith('.txt');
    }).toList();
    if (yamlFiles.isEmpty) {
      if (context.mounted) AppNotifier.error(s.importLocalFileFailed);
      return;
    }

    // Single file → show name dialog (existing UX)
    if (yamlFiles.length == 1) {
      final file = yamlFiles.first;
      final bytes = file.bytes;
      if (bytes == null) return;
      String content;
      try {
        content = utf8.decode(bytes);
      } catch (_) {
        if (context.mounted) AppNotifier.error(s.importLocalFileFailed);
        return;
      }
      final defaultName = file.name.replaceAll(
          RegExp(r'\.(yaml|yml)$', caseSensitive: false), '');
      if (!context.mounted) return;

      final nameCtrl = TextEditingController(text: defaultName);
      final name = await showDialog<String>(
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
            textInputAction: TextInputAction.done,
            onSubmitted: (v) {
              final n = v.trim();
              Navigator.pop(ctx, n.isEmpty ? defaultName : n);
            },
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
            FilledButton(
              onPressed: () {
                final n = nameCtrl.text.trim();
                Navigator.pop(ctx, n.isEmpty ? defaultName : n);
              },
              child: Text(s.add),
            ),
          ],
        ),
      );
      nameCtrl.dispose();
      if (name == null || !context.mounted) return;
      try {
        final profile = await ref
            .read(profileRepositoryProvider)
            .addLocalProfile(name: name, configContent: content);
        ref.read(profilesProvider.notifier).addLocal(profile);
        AppNotifier.success(s.importLocalFileSuccess);
      } catch (_) {
        if (context.mounted) AppNotifier.error(s.importLocalFileFailed);
      }
      return;
    }

    // Multiple files → batch import, use filenames as names
    final repo = ref.read(profileRepositoryProvider);
    int ok = 0, failed = 0;
    for (final file in yamlFiles) {
      final bytes = file.bytes;
      if (bytes == null) { failed++; continue; }
      try {
        final content = utf8.decode(bytes);
        final name = file.name.replaceAll(
            RegExp(r'\.(yaml|yml)$', caseSensitive: false), '');
        final profile = await repo.addLocalProfile(
          name: name.isEmpty ? s.importLocalNameHint : name,
          configContent: content,
        );
        ref.read(profilesProvider.notifier).addLocal(profile);
        ok++;
      } catch (_) {
        failed++;
      }
    }
    if (context.mounted) AppNotifier.success(s.importAllResult(ok, failed));
  }

  /// Export a single profile's config as {name}.yaml.
  Future<void> _exportProfile(
      BuildContext context, WidgetRef ref, Profile profile) async {
    final s = S.of(context);
    final config =
        await ref.read(profileRepositoryProvider).loadConfig(profile.id);
    if (config == null) {
      AppNotifier.error(s.exportFailed);
      return;
    }
    // Strip characters that are invalid in filenames on Windows/macOS/Linux.
    final safeName =
        profile.name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_');
    try {
      await FilePicker.saveFile(
        dialogTitle: s.exportProfile,
        fileName: '$safeName.yaml',
        bytes: Uint8List.fromList(utf8.encode(config)),
        type: FileType.custom,
        allowedExtensions: ['yaml'],
      );
      AppNotifier.success(s.exportProfileSuccess(profile.name));
    } catch (_) {
      if (context.mounted) AppNotifier.error(s.exportFailed);
    }
  }

  /// Export all profiles as individual YAML files.
  ///
  /// Desktop: user picks a directory, files are written directly.
  /// Mobile: falls back to saving each file individually via save dialog.
  Future<void> _exportAllProfiles(BuildContext context, WidgetRef ref) async {
    final s = S.of(context);
    final profiles = ref.read(profilesProvider).value;
    if (profiles == null || profiles.isEmpty) {
      AppNotifier.info(s.isEn ? 'No subscriptions to export' : '没有可导出的订阅');
      return;
    }

    final repo = ref.read(profileRepositoryProvider);
    final isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;

    if (isDesktop) {
      // Desktop: pick a directory, write all YAML files there
      final dir = await FilePicker.getDirectoryPath(
        dialogTitle: s.exportSelectDir,
      );
      if (dir == null) return;

      int ok = 0;
      final usedNames = <String>{};
      for (final p in profiles) {
        final config = await repo.loadConfig(p.id);
        if (config == null) continue;
        final safeName = _safeFileName(p.name);
        // Deduplicate filenames
        var finalName = safeName;
        var counter = 1;
        while (usedNames.contains(finalName)) {
          finalName = '${safeName}_$counter';
          counter++;
        }
        usedNames.add(finalName);
        try {
          await File('$dir/$finalName.yaml').writeAsString(config);
          ok++;
        } catch (_) {}
      }
      if (context.mounted) AppNotifier.success(s.exportAllDone(ok));
    } else {
      // Mobile: save each file individually (FilePicker.saveFile per profile)
      int ok = 0;
      for (final p in profiles) {
        final config = await repo.loadConfig(p.id);
        if (config == null) continue;
        final safeName = _safeFileName(p.name);
        try {
          await FilePicker.saveFile(
            dialogTitle: '${s.exportProfile}: ${p.name}',
            fileName: '$safeName.yaml',
            bytes: Uint8List.fromList(utf8.encode(config)),
            type: FileType.custom,
            allowedExtensions: ['yaml'],
          );
          ok++;
        } catch (_) {
          // User cancelled or error — continue with next
        }
      }
      if (ok > 0 && context.mounted) {
        AppNotifier.success(s.exportAllDone(ok));
      }
    }
  }

  /// Sanitize profile name for use as a filename.
  /// Preserves emoji and Unicode, strips only filesystem-unsafe characters.
  static String _safeFileName(String name) {
    return name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_').trim();
  }

  // ── Config viewer ─────────────────────────────────────────────────

  void _showConfigViewer(BuildContext context, Profile profile) async {
    final s = S.of(context);
    final config = await ref.read(profileRepositoryProvider).loadConfig(profile.id);
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

/// Small icon+label row for popup menu items.
Widget _menuItem(IconData icon, String label) => Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 10),
        Text(label),
      ],
    );

class _ProfileCard extends StatelessWidget {
  final Profile profile;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onUpdate;
  final VoidCallback onEdit;
  final VoidCallback onViewConfig;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  const _ProfileCard({
    required this.profile,
    required this.isActive,
    required this.onTap,
    required this.onUpdate,
    required this.onEdit,
    required this.onViewConfig,
    required this.onExport,
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
                ? YLColors.primaryDark.withValues(alpha: 0.10)
                : YLColors.primaryLight)
            : (isDark ? YLColors.zinc800 : Colors.white),
        borderRadius: BorderRadius.circular(YLRadius.xl),
        border: Border.all(
          color: isActive
              ? (isDark
                  ? YLColors.primaryDark.withValues(alpha: 0.30)
                  : YLColors.primary.withValues(alpha: 0.20))
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
                        ? (isDark ? YLColors.primaryDark : YLColors.primary)
                        : (isDark ? YLColors.zinc400 : YLColors.zinc500),
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
                        case 'export':
                          onExport();
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
                          value: 'export', child: Text(s.exportProfile)),
                      PopupMenuItem(
                          value: 'copy', child: Text(s.copyLink)),
                      const PopupMenuDivider(),
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


// ── Swipe-to-delete helpers ───────────────────────────────────────────────

/// Red background shown behind a profile row while the user is dragging
/// left to reveal the delete action. Used by Dismissible on mobile.
class _SwipeDeleteBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0xFFE53935),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.centerRight,
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.delete_outline_rounded, color: Colors.white, size: 22),
          SizedBox(width: 6),
          Text(
            "删除",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom-sheet confirmation used by the swipe-to-delete gesture on mobile.
/// Returns true if the user confirmed (profile gets deleted), false or null
/// if they backed out (Dismissible rubber-bands the row back).
Future<bool> _confirmDeleteSheet(
  BuildContext context,
  WidgetRef ref,
  Profile profile,
) async {
  final s = S.of(context);
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final result = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    backgroundColor: isDark ? const Color(0xFF18181B) : Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.confirmDelete,
              style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  )),
          const SizedBox(height: 8),
          Text(s.confirmDeleteMessage(profile.name),
              style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                    color: isDark ? Colors.white70 : Colors.black54,
                  )),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx, true);
              await ref.read(profilesProvider.notifier).delete(profile.id);
              final activeId = ref.read(activeProfileIdProvider);
              if (activeId == profile.id) {
                ref.read(activeProfileIdProvider.notifier).select(null);
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              minimumSize: const Size.fromHeight(48),
            ),
            child: Text(s.delete),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
            child: Text(s.cancel),
          ),
        ],
      ),
    ),
  );
  return result == true;
}
