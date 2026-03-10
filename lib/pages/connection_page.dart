import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart';
import '../providers/core_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/proxy_provider.dart';
import '../services/app_notifier.dart';
import '../services/core_manager.dart';
import '../services/profile_service.dart';
import '../theme.dart';

/// The main Dashboard page.
/// Priority: Connection Status > Current Node > Real-time Speed > Quick Actions.
class ConnectionPage extends ConsumerWidget {
  const ConnectionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = ref.watch(coreStatusProvider);
    final isConnected = status == CoreStatus.running;
    // 真实状态闭环：启动和停止过程中，都视为 Connecting/Loading 态，防止重复点击
    final isConnecting = status == CoreStatus.starting || status == CoreStatus.stopping;

    return Scaffold(
      body: Stack(
        children: [
          // Subtle background glow when connected
          if (isConnected)
            Positioned(
              top: -100,
              left: -50,
              right: -50,
              child: AnimatedOpacity(
                opacity: isConnected ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 800),
                child: Container(
                  height: 400,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: YLColors.connected.withOpacity(isDark ? 0.15 : 0.08),
                    filter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
                  ),
                ),
              ),
            ),

          CustomScrollView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              // Minimalist Header
              SliverAppBar(
                expandedHeight: 80.0,
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  titlePadding: const EdgeInsets.symmetric(horizontal: YLSpacing.xl, vertical: YLSpacing.lg),
                  title: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      YLStatusDot(
                        color: isConnected 
                            ? YLColors.connected 
                            : (isConnecting ? YLColors.connecting : YLColors.disconnected),
                        glow: isConnected,
                      ),
                      const SizedBox(width: YLSpacing.sm),
                      Text(
                        isConnected 
                            ? 'YueLink Active' 
                            : (status == CoreStatus.starting 
                                ? 'Connecting...' 
                                : (status == CoreStatus.stopping ? 'Disconnecting...' : 'Disconnected')),
                        style: YLText.titleMedium.copyWith(
                          color: isDark ? YLColors.zinc50 : YLColors.zinc900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: YLSpacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: YLSpacing.xxl),
                      
                      // 1. Massive Power Button (The Visual Center)
                      _buildPowerButton(context, ref, status),
                      
                      const SizedBox(height: YLSpacing.massive),

                      // 2. Current Node Info Card (Real State)
                      _buildCurrentNodeCard(context, ref, isConnected),

                      const SizedBox(height: YLSpacing.xl),

                      // 3. Real-time Traffic Stats
                      _buildTrafficStats(context, ref),

                      const SizedBox(height: YLSpacing.xl),

                      // 4. Quick Actions / Modes
                      _buildQuickActions(context, ref),

                      const SizedBox(height: YLSpacing.massive),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPowerButton(BuildContext context, WidgetRef ref, CoreStatus status) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isConnected = status == CoreStatus.running;
    final isConnecting = status == CoreStatus.starting || status == CoreStatus.stopping;

    final buttonColor = isConnected 
        ? YLColors.connected 
        : (isDark ? YLColors.zinc800 : Colors.white);
        
    final iconColor = isConnected 
        ? Colors.white 
        : (isDark ? YLColors.zinc300 : YLColors.zinc700);

    return GestureDetector(
      onTap: isConnecting ? null : () async {
        final actions = ref.read(coreActionsProvider);
        if (isConnected) {
          await actions.stop();
        } else {
          final activeId = ref.read(activeProfileIdProvider);
          if (activeId == null) {
            AppNotifier.warning('请先在配置页选择或添加一个订阅');
            MainShell.switchToTab(context, MainShell.tabConfigurations);
            return;
          }
          final config = await ProfileService.loadConfig(activeId);
          if (config == null) {
            AppNotifier.error('无法读取配置文件');
            return;
          }
          await actions.start(config);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
        width: 140,
        height: 140,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: buttonColor,
          border: Border.all(
            color: isConnected 
                ? YLColors.connected.withOpacity(0.5) 
                : (isDark ? YLColors.zinc700 : YLColors.zinc200),
            width: isConnected ? 0 : 1,
          ),
          boxShadow: [
            if (isConnected)
              BoxShadow(
                color: YLColors.connected.withOpacity(0.4),
                blurRadius: 40,
                spreadRadius: 10,
              )
            else if (!isDark)
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
          ],
        ),
        child: Center(
          child: isConnecting
              ? const CircularProgressIndicator(color: YLColors.primary)
              : Icon(
                  Icons.power_settings_new_rounded,
                  size: 64,
                  color: iconColor,
                ),
        ),
      ),
    );
  }

  Widget _buildCurrentNodeCard(BuildContext context, WidgetRef ref, bool isConnected) {
    String activeNodeName = 'No Active Node';
    String activeNodeGroup = 'Connect to see details';

    if (isConnected) {
      final groups = ref.watch(proxyGroupsProvider);
      if (groups.isNotEmpty) {
        try {
          // Try to find the main PROXIES or GLOBAL group, or fallback to the first Selector
          final mainGroup = groups.firstWhere(
            (g) => g.name == 'PROXIES' || g.name == 'GLOBAL' || g.name == '节点选择' || g.name == 'Proxy',
            orElse: () => groups.firstWhere((g) => g.type == 'Selector', orElse: () => groups.first),
          );
          activeNodeName = mainGroup.now.isNotEmpty ? mainGroup.now : 'Direct / Auto';
          activeNodeGroup = mainGroup.name;
        } catch (_) {
          activeNodeName = 'Connected';
          activeNodeGroup = 'Unknown Group';
        }
      }
    }

    return YLSurface(
      padding: const EdgeInsets.all(YLSpacing.lg),
      onTap: () {
        MainShell.switchToTab(context, MainShell.tabNodes);
      },
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isConnected ? YLColors.connected.withOpacity(0.1) : YLColors.zinc100,
              borderRadius: BorderRadius.circular(YLRadius.lg),
            ),
            child: Icon(
              Icons.public_rounded,
              color: isConnected ? YLColors.connected : YLColors.zinc400,
            ),
          ),
          const SizedBox(width: YLSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activeNodeName,
                  style: YLText.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  activeNodeGroup,
                  style: YLText.caption.copyWith(color: YLColors.zinc500),
                ),
              ],
            ),
          ),
          const SizedBox(width: YLSpacing.sm),
          Icon(Icons.chevron_right_rounded, color: YLColors.zinc400),
        ],
      ),
    );
  }

  Widget _buildTrafficStats(BuildContext context, WidgetRef ref) {
    final traffic = ref.watch(trafficProvider);

    return Row(
      children: [
        Expanded(
          child: YLSurface(
            padding: const EdgeInsets.all(YLSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.arrow_downward_rounded, size: 16, color: YLColors.connected),
                    const SizedBox(width: 6),
                    Text('Download', style: YLText.caption.copyWith(color: YLColors.zinc500)),
                  ],
                ),
                const SizedBox(height: YLSpacing.sm),
                Text(
                  _formatSpeed(traffic.down),
                  style: YLText.titleLarge.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: YLSpacing.lg),
        Expanded(
          child: YLSurface(
            padding: const EdgeInsets.all(YLSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.arrow_upward_rounded, size: 16, color: YLColors.accent),
                    const SizedBox(width: 6),
                    Text('Upload', style: YLText.caption.copyWith(color: YLColors.zinc500)),
                  ],
                ),
                const SizedBox(height: YLSpacing.sm),
                Text(
                  _formatSpeed(traffic.up),
                  style: YLText.titleLarge.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActions(BuildContext context, WidgetRef ref) {
    final routingMode = ref.watch(routingModeProvider);
    final status = ref.watch(coreStatusProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Routing Mode', style: YLText.label.copyWith(color: YLColors.zinc500)),
        const SizedBox(height: YLSpacing.md),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'rule', label: Text('Rule')),
              ButtonSegment(value: 'global', label: Text('Global')),
              ButtonSegment(value: 'direct', label: Text('Direct')),
            ],
            selected: {routingMode},
            onSelectionChanged: (Set<String> newSelection) async {
              final mode = newSelection.first;
              ref.read(routingModeProvider.notifier).state = mode;
              
              if (status == CoreStatus.running) {
                final ok = await CoreManager.instance.api.setRoutingMode(mode);
                if (ok) {
                  AppNotifier.success('已切换至 ${mode.toUpperCase()} 模式');
                } else {
                  AppNotifier.error('模式切换失败');
                }
              }
            },
            showSelectedIcon: false,
          ),
        ),
        const SizedBox(height: YLSpacing.xl),
        
        YLSurface(
          child: Column(
            children: [
              SwitchListTile.adaptive(
                title: const Text('System Proxy', style: YLText.body),
                subtitle: Text('Set as system default proxy', style: YLText.caption.copyWith(color: YLColors.zinc500)),
                value: ref.watch(systemProxyOnConnectProvider),
                onChanged: (val) async {
                  ref.read(systemProxyOnConnectProvider.notifier).state = val;
                  
                  if (status == CoreStatus.running) {
                    if (val) {
                      await ref.read(coreActionsProvider).applySystemProxy();
                      AppNotifier.success('系统代理已开启');
                    } else {
                      await ref.read(coreActionsProvider).clearSystemProxy();
                      AppNotifier.info('系统代理已关闭');
                    }
                  }
                },
                contentPadding: const EdgeInsets.symmetric(horizontal: YLSpacing.lg, vertical: YLSpacing.xs),
              ),
              const Divider(height: 1),
              SwitchListTile.adaptive(
                title: const Text('TUN Mode', style: YLText.body),
                subtitle: Text('Route all traffic via virtual network', style: YLText.caption.copyWith(color: YLColors.zinc500)),
                value: ref.watch(connectionModeProvider) == 'tun',
                onChanged: (val) {
                  ref.read(connectionModeProvider.notifier).state = val ? 'tun' : 'systemProxy';
                  
                  if (status == CoreStatus.running) {
                    AppNotifier.warning('切换 TUN 模式将在下次连接时生效');
                  }
                },
                contentPadding: const EdgeInsets.symmetric(horizontal: YLSpacing.lg, vertical: YLSpacing.xs),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatSpeed(int bps) {
    if (bps < 1024) return '${bps} B/s';
    if (bps < 1024 * 1024) return '${(bps / 1024).toStringAsFixed(1)} KB/s';
    return '${(bps / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
}
