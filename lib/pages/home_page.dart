import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/traffic.dart';
import '../providers/core_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/proxy_provider.dart';
import '../services/profile_service.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  DateTime? _connectedSince;
  Timer? _uptimeTimer;

  @override
  void dispose() {
    _uptimeTimer?.cancel();
    super.dispose();
  }

  void _startUptimeTimer() {
    _connectedSince = DateTime.now();
    _uptimeTimer?.cancel();
    _uptimeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _stopUptimeTimer() {
    _uptimeTimer?.cancel();
    _uptimeTimer = null;
    _connectedSince = null;
  }

  String get _uptimeText {
    if (_connectedSince == null) return '';
    final diff = DateTime.now().difference(_connectedSince!);
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    final s = diff.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(coreStatusProvider);
    final traffic = ref.watch(trafficProvider);
    final isMock = ref.watch(isMockModeProvider);
    final isRunning = status == CoreStatus.running;
    final isTransitioning =
        status == CoreStatus.starting || status == CoreStatus.stopping;

    // Keep traffic polling alive
    if (isRunning) ref.watch(trafficPollingProvider);

    // Track uptime
    ref.listen(coreStatusProvider, (prev, next) {
      if (next == CoreStatus.running) {
        _startUptimeTimer();
      } else if (next == CoreStatus.stopped) {
        _stopUptimeTimer();
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // Mock mode banner
              if (isMock)
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.science_outlined,
                          size: 16, color: Colors.amber.shade700),
                      const SizedBox(width: 6),
                      Text('开发模式 · 模拟数据',
                          style: TextStyle(
                              fontSize: 12, color: Colors.amber.shade700)),
                    ],
                  ),
                ),

              const Spacer(),

              // Status orb
              _StatusOrb(
                  isRunning: isRunning, isTransitioning: isTransitioning),
              const SizedBox(height: 24),

              // Status text
              Text(
                isTransitioning
                    ? (status == CoreStatus.starting ? '连接中...' : '断开中...')
                    : (isRunning ? '已连接' : '未连接'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isRunning
                          ? Colors.green
                          : Theme.of(context).colorScheme.onSurface,
                    ),
              ),

              // Uptime
              if (isRunning && _connectedSince != null) ...[
                const SizedBox(height: 4),
                Text(_uptimeText,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant)),
              ],

              const SizedBox(height: 8),

              // Active node info (when connected)
              if (isRunning) ...[
                _ActiveNodeInfo(),
                const SizedBox(height: 6),
                _ActiveProfileName(),
              ],

              // Selected profile hint (when disconnected)
              if (!isRunning && !isTransitioning)
                _DisconnectedHint(),

              const SizedBox(height: 24),

              // Traffic stats
              if (isRunning) _TrafficCard(traffic: traffic),

              const Spacer(),

              // Connect button
              SizedBox(
                width: 200,
                height: 56,
                child: FilledButton(
                  onPressed:
                      isTransitioning ? null : () => _toggle(context, ref),
                  style: FilledButton.styleFrom(
                    backgroundColor: isRunning
                        ? Colors.red.shade400
                        : Theme.of(context).colorScheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isTransitioning)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          ),
                        ),
                      Text(
                        isTransitioning
                            ? (status == CoreStatus.starting
                                ? '连接中'
                                : '断开中')
                            : (isRunning ? '断开连接' : '连接'),
                        style: const TextStyle(fontSize: 18),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    final actions = ref.read(coreActionsProvider);
    final status = ref.read(coreStatusProvider);
    final isMock = ref.read(isMockModeProvider);

    HapticFeedback.mediumImpact();

    if (status == CoreStatus.running) {
      await actions.stop();
      return;
    }

    if (isMock) {
      await actions.start('');
      return;
    }

    final activeId = ref.read(activeProfileIdProvider);
    if (activeId == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先在「配置」页面添加订阅')),
        );
      }
      return;
    }

    final config = await ProfileService.loadConfig(activeId);
    if (config == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('配置文件不存在，请更新订阅')),
        );
      }
      return;
    }
    final ok = await actions.start(config);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('启动失败，请检查配置')),
      );
    }
  }
}

class _ActiveNodeInfo extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(proxyGroupsProvider);
    // Find the main selector group
    final mainGroup = groups.isEmpty
        ? null
        : groups.firstWhere(
            (g) => g.name == '节点选择' || g.type == 'Selector',
            orElse: () => groups.first,
          );

    if (mainGroup == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.near_me,
              size: 14, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Text(mainGroup.now,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _ActiveProfileName extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMock = ref.watch(isMockModeProvider);
    if (isMock) {
      return Text('模拟模式',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant));
    }
    final profiles = ref.watch(profilesProvider);
    final activeId = ref.watch(activeProfileIdProvider);
    final name = profiles.whenOrNull(
      data: (list) => list.where((p) => p.id == activeId).firstOrNull?.name,
    );
    if (name == null) return const SizedBox.shrink();
    return Text(name,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant));
  }
}

class _DisconnectedHint extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(profilesProvider);
    final activeId = ref.watch(activeProfileIdProvider);
    final isMock = ref.watch(isMockModeProvider);

    if (isMock) {
      return Text('点击连接启动模拟模式',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant));
    }

    return profiles.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (list) {
        if (list.isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('请先在「配置」页面添加订阅',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          );
        }
        final active =
            list.where((p) => p.id == activeId).firstOrNull ?? list.first;
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.description_outlined,
                  size: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(active.name,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color:
                          Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        );
      },
    );
  }
}

class _StatusOrb extends StatelessWidget {
  final bool isRunning;
  final bool isTransitioning;

  const _StatusOrb({required this.isRunning, required this.isTransitioning});

  @override
  Widget build(BuildContext context) {
    final color = isTransitioning
        ? Colors.orange
        : isRunning
            ? Colors.green
            : Theme.of(context).colorScheme.outline;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color, width: 3),
        boxShadow: isRunning
            ? [
                BoxShadow(
                  color: Colors.green.withValues(alpha: 0.3),
                  blurRadius: 24,
                  spreadRadius: 4,
                )
              ]
            : null,
      ),
      child: Icon(
        isRunning ? Icons.power_settings_new : Icons.power_off_outlined,
        size: 48,
        color: color,
      ),
    );
  }
}

class _TrafficCard extends StatelessWidget {
  final Traffic traffic;

  const _TrafficCard({required this.traffic});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TrafficColumn(
              icon: Icons.arrow_upward,
              iconColor: Colors.blue,
              value: traffic.upFormatted,
              label: '上传',
            ),
            const SizedBox(width: 48),
            _TrafficColumn(
              icon: Icons.arrow_downward,
              iconColor: Colors.green,
              value: traffic.downFormatted,
              label: '下载',
            ),
          ],
        ),
      ),
    );
  }
}

class _TrafficColumn extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _TrafficColumn({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.bodyMedium),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
