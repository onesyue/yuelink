import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/env_config.dart';
import '../../../../theme.dart';
import '../../../updater/update_checker.dart';
import '../../widgets/primitives.dart';

/// Updates section — channel selector, auto-check toggle, last-checked
/// timestamp. Self-managing: owns its own `UpdateChecker` state load.
///
/// Gated by `EnvConfig.isStandalone`; returns `SizedBox.shrink()` when
/// running under a store build, so the parent can embed it unconditionally.
class UpdatesSection extends ConsumerStatefulWidget {
  const UpdatesSection({super.key});

  @override
  ConsumerState<UpdatesSection> createState() => _UpdatesSectionState();
}

class _UpdatesSectionState extends ConsumerState<UpdatesSection> {
  String _updateChannel = 'stable';
  bool _autoCheckUpdates = true;
  DateTime? _lastUpdateCheck;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    if (EnvConfig.isStandalone) {
      _load();
    }
  }

  Future<void> _load() async {
    final channel = await UpdateChecker.getChannel();
    final autoCheck = await UpdateChecker.getAutoCheck();
    final lastCheck = await UpdateChecker.getLastCheck();
    if (mounted) {
      setState(() {
        _updateChannel = channel;
        _autoCheckUpdates = autoCheck;
        _lastUpdateCheck = lastCheck;
        _loaded = true;
      });
    }
  }

  String _formatLastChecked(DateTime? dt, {required bool isEn}) {
    if (dt == null) return isEn ? 'Never checked' : '从未检查';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return isEn ? 'Just now' : '刚刚';
    if (diff.inMinutes < 60) {
      return isEn ? '${diff.inMinutes} min ago' : '${diff.inMinutes} 分钟前';
    }
    if (diff.inHours < 24) {
      return isEn ? '${diff.inHours} h ago' : '${diff.inHours} 小时前';
    }
    if (diff.inDays < 30) {
      return isEn ? '${diff.inDays} d ago' : '${diff.inDays} 天前';
    }
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (!EnvConfig.isStandalone) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.06);

    if (!_loaded) {
      // Avoid flicker on first paint — defaults are already safe values,
      // so just render the card with the placeholders.
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GsGeneralSectionTitle(isEn ? 'Updates' : '更新'),
        SettingsCard(
          child: Column(
            children: [
              YLInfoRow(
                label: isEn ? 'Last checked' : '上次检查',
                trailing: YLSettingsValueButton(
                  label: _formatLastChecked(_lastUpdateCheck, isEn: isEn),
                  showChevron: false,
                ),
              ),
              Divider(height: 1, thickness: 0.5, color: dividerColor),
              YLSettingsRow(
                title: isEn ? 'Auto-check updates on startup' : '启动时自动检查更新',
                trailing: CupertinoSwitch(
                  value: _autoCheckUpdates,
                  activeTrackColor: YLColors.connected,
                  onChanged: (v) async {
                    await UpdateChecker.setAutoCheck(v);
                    if (mounted) setState(() => _autoCheckUpdates = v);
                  },
                ),
              ),
              Divider(height: 1, thickness: 0.5, color: dividerColor),
              YLInfoRow(
                label: isEn ? 'Update channel' : '更新通道',
                trailing: YLSettingsValueButton(
                  label: _updateChannel == 'pre'
                      ? (isEn ? 'Pre-release' : '预发布')
                      : (isEn ? 'Stable' : '稳定版'),
                ),
                onTap: _pickChannel,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Future<void> _pickChannel() async {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final picked = await showYLSettingsOptionPicker<String>(
      context: context,
      title: isEn ? 'Update channel' : '更新通道',
      selectedValue: _updateChannel,
      options: [
        YLSettingsOption(
          value: 'stable',
          title: isEn ? 'Stable (stable)' : '稳定版 (stable)',
          subtitle: isEn
              ? 'Only receive formal v* releases'
              : '只接收正式 v* 版本，更稳定',
        ),
        YLSettingsOption(
          value: 'pre',
          title: isEn ? 'Pre-release (pre-release)' : '预发布 (pre-release)',
          subtitle: isEn
              ? 'Get new builds early, may be unstable'
              : '抢先体验新功能，可能有问题',
        ),
      ],
    );
    if (picked != null && picked != _updateChannel) {
      await UpdateChecker.setChannel(picked);
      if (mounted) setState(() => _updateChannel = picked);
    }
  }
}
