import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_runtime_providers.dart';
import '../../../core/system/private_dns_state.dart';
import '../../../theme.dart';

/// c.P3-1: Dashboard banner that warns when Android system Private DNS
/// is set to **hostname mode** (the only mode that actually bypasses
/// yuelink TUN dns-hijack).
///
/// Shown only on Android + when `mode == hostname`. `opportunistic`
/// (Samsung default) is silent here — surfaces in P4-1 一键诊断 only.
class PrivateDnsBanner extends ConsumerStatefulWidget {
  const PrivateDnsBanner({super.key});

  @override
  ConsumerState<PrivateDnsBanner> createState() => _PrivateDnsBannerState();
}

class _PrivateDnsBannerState extends ConsumerState<PrivateDnsBanner> {
  @override
  void initState() {
    super.initState();
    // Pull on first build (in addition to Notifier.build() microtask) so
    // a rebuilt Dashboard always has fresh state. Cheap — one Settings
    // .Global read on the platform side.
    if (Platform.isAndroid) {
      Future.microtask(() {
        if (!mounted) return;
        ref.read(privateDnsStateProvider.notifier).refresh();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) return const SizedBox.shrink();

    // Re-pull on VPN connect transition so the banner reflects the
    // post-connect Settings.Global state (some users toggle Private DNS
    // right before connecting).
    ref.listen(coreStatusProvider, (prev, next) {
      if (prev != CoreStatus.running && next == CoreStatus.running) {
        ref.read(privateDnsStateProvider.notifier).refresh();
      }
    });

    final dnsState = ref.watch(privateDnsStateProvider);
    if (!dnsState.bypassesTun) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark
        ? Colors.orange.withValues(alpha: 0.3)
        : Colors.orange.withValues(alpha: 0.2);
    final bgColor = isDark
        ? Colors.orange.withValues(alpha: 0.08)
        : Colors.orange.withValues(alpha: 0.05);
    final textColor =
        isDark ? Colors.orange.shade300 : Colors.orange.shade800;

    final specifierLine = (dnsState.specifier?.isNotEmpty ?? false)
        ? '当前 DoT：${dnsState.specifier!}'
        : '已指定 DoT 服务器';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(YLRadius.xl),
        border: Border.all(color: borderColor, width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: Colors.orange.shade700,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '系统 Private DNS（hostname 模式）会绕过 yuelink 的 DNS 分流',
                  style: YLText.caption.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$specifierLine · 建议在「设置 → 网络 → Private DNS」改为 Off 或 Automatic',
                  style: YLText.caption.copyWith(
                    color: textColor.withValues(alpha: 0.85),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
