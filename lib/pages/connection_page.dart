import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/core_provider.dart';
import '../theme.dart';

/// The main Dashboard page.
/// Focuses on the primary connection switch, real-time traffic, and quick actions.
class ConnectionPage extends ConsumerWidget {
  const ConnectionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = ref.watch(coreStatusProvider);
    final isConnected = status == CoreStatus.running;
    final isConnecting = status == CoreStatus.starting;

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
                  titlePadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  title: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      YLStatusDot(
                        color: isConnected 
                            ? YLColors.connected 
                            : (isConnecting ? YLColors.connecting : YLColors.disconnected),
                        glow: isConnected,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isConnected ? 'YueLink Active' : (isConnecting ? 'Connecting...' : 'Disconnected'),
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
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 40),
                      
                      // Massive Power Button (The Visual Center)
                      _buildPowerButton(context, ref, status),
                      
                      const SizedBox(height: 60),

                      // Real-time Traffic Stats
                      _buildTrafficStats(context, ref),

                      const SizedBox(height: 32),

                      // Current Node Info Card
                      _buildCurrentNodeCard(context, isConnected),

                      const SizedBox(height: 32),

                      // Quick Actions / Modes
                      _buildQuickActions(context, ref),

                      const SizedBox(height: 60),
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
    final isConnecting = status == CoreStatus.starting;

    final buttonColor = isConnected 
        ? YLColors.connected 
        : (isDark ? YLColors.zinc800 : Colors.white);
        
    final iconColor = isConnected 
        ? Colors.white 
        : (isDark ? YLColors.zinc300 : YLColors.zinc700);

    return GestureDetector(
      onTap: isConnecting ? null : () async {
        final actions = ref.read(coreActionsProvider);
        // TODO: Pass actual config yaml from active profile
        await actions.toggle(''); 
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

  Widget _buildTrafficStats(BuildContext context, WidgetRef ref) {
    final traffic = ref.watch(trafficProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        Expanded(
          child: YLSurface(
            padding: const EdgeInsets.all(20),
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
                const SizedBox(height: 8),
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
        const SizedBox(width: 16),
        Expanded(
          child: YLSurface(
            padding: const EdgeInsets.all(20),
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
                const SizedBox(height: 8),
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

  Widget _buildCurrentNodeCard(BuildContext context, bool isConnected) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return YLSurface(
      padding: const EdgeInsets.all(20),
      onTap: () {
        // TODO: Navigate to Proxies page
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
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isConnected ? '🇭🇰 Hong Kong 01 - Premium' : 'No Active Node',
                  style: YLText.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  isConnected ? 'Auto Select • Hysteria2' : 'Connect to see details',
                  style: YLText.caption.copyWith(color: YLColors.zinc500),
                ),
              ],
            ),
          ),
          if (isConnected)
            const YLDelayBadge(delay: 34),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded, color: YLColors.zinc400),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context, WidgetRef ref) {
    final routingMode = ref.watch(routingModeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Routing Mode', style: YLText.label.copyWith(color: YLColors.zinc500)),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'rule', label: Text('Rule')),
              ButtonSegment(value: 'global', label: Text('Global')),
              ButtonSegment(value: 'direct', label: Text('Direct')),
            ],
            selected: {routingMode},
            onSelectionChanged: (set) {
              ref.read(routingModeProvider.notifier).state = set.first;
              // TODO: Apply to core if running
            },
            showSelectedIcon: false,
          ),
        ),
        const SizedBox(height: 24),
        
        YLSurface(
          child: Column(
            children: [
              SwitchListTile.adaptive(
                title: const Text('System Proxy', style: YLText.body),
                subtitle: Text('Set as system default proxy', style: YLText.caption.copyWith(color: YLColors.zinc500)),
                value: ref.watch(systemProxyOnConnectProvider),
                onChanged: (val) {
                  ref.read(systemProxyOnConnectProvider.notifier).state = val;
                },
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              ),
              const Divider(height: 1),
              SwitchListTile.adaptive(
                title: const Text('TUN Mode', style: YLText.body),
                subtitle: Text('Route all traffic via virtual network', style: YLText.caption.copyWith(color: YLColors.zinc500)),
                value: ref.watch(connectionModeProvider) == 'tun',
                onChanged: (val) {
                  ref.read(connectionModeProvider.notifier).state = val ? 'tun' : 'systemProxy';
                },
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
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
