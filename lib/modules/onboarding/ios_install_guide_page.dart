import 'package:flutter/material.dart';

import '../../theme.dart';

/// iOS 安装方式说明页 — 在两种场景下出现：
/// 1. 设置页主动入口（用户想换安装方式时查阅）
/// 2. 检测到 PacketTunnel 启动后秒断（巨魔 entitlement 问题）时强制弹
///
/// 内容三件事：
///   - 三种主流方式对比（巨魔 / AltStore / SideStore）
///   - 巨魔红框警告：可装但 VPN 不工作（Apple system trust 不通过）
///   - AltStore / SideStore 自签每 7 天要重签的提示
class IOSInstallGuidePage extends StatelessWidget {
  /// 来自连接错误的诊断标记，非空时顶部显示警告条幅。
  final String? errorContext;

  const IOSInstallGuidePage({super.key, this.errorContext});

  static Future<void> push(BuildContext context, {String? errorContext}) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => IOSInstallGuidePage(errorContext: errorContext),
        fullscreenDialog: errorContext != null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? YLColors.zinc950 : YLColors.zinc100;
    final surface = isDark ? YLColors.zinc900 : Colors.white;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('iOS 安装方式'),
        backgroundColor: bg,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (errorContext != null) _ErrorBanner(message: errorContext!),
              if (errorContext != null) const SizedBox(height: 16),
              const Text(
                'iOS 上的 YueLink 通过侧载安装。三种方式各有取舍，连接 VPN 的可用性差异很大。',
                style: YLText.body,
              ),
              const SizedBox(height: 20),
              _MethodCard(
                surface: surface,
                isDark: isDark,
                title: 'AltStore / SideStore',
                tag: '推荐',
                tagColor: const Color(0xFF22C55E),
                pros: const [
                  '✅ VPN 完全可用（系统信任 entitlement）',
                  '✅ 免费，用 Apple ID 自签',
                  '✅ 支持各代设备',
                ],
                cons: const [
                  '⚠️ 自签 7 天到期，到期前需重签（电脑端 AltServer / SideServer）',
                  '⚠️ 一个免费 Apple ID 同时只能装 3 个 App',
                ],
                howto:
                    '电脑端装 AltServer / SideServer → iPhone 装 AltStore / SideStore App → '
                    '把 YueLink IPA 拖入电脑端工具或 AltStore 内导入 → 设置 → 通用 → '
                    'VPN 与设备管理 → 信任开发者证书',
              ),
              const SizedBox(height: 12),
              _MethodCard(
                surface: surface,
                isDark: isDark,
                title: 'TrollStore（巨魔）',
                tag: '不推荐用 VPN',
                tagColor: const Color(0xFFEF4444),
                pros: const [
                  '✅ 安装后永久有效，不需要重签',
                ],
                cons: const [
                  '🚫 VPN（NetworkExtension）几乎不工作',
                  '🚫 系统启动 PacketTunnel 后立刻丢弃，表现为"提示连接成功但实际无网络"',
                  '🚫 仅特定旧版 iOS 漏洞设备能装',
                ],
                howto:
                    '巨魔利用系统漏洞绕过签名校验，但 NetworkExtension 仍依赖 Apple '
                    '签发的 Provisioning Profile —— 巨魔安装的 IPA 拿不到这条信任链，'
                    '系统会让 PacketTunnel 进程"看起来启动"但不放行任何包。'
                    '\n\n如果你只用 YueLink 看 Emby 等不需要 VPN 的功能，巨魔可用；'
                    '需要代理上网请改用 AltStore / SideStore。',
              ),
              const SizedBox(height: 12),
              _MethodCard(
                surface: surface,
                isDark: isDark,
                title: 'IPA 直装 / 第三方分发',
                tag: '风险',
                tagColor: const Color(0xFFF59E0B),
                pros: const [
                  '✅ 部分商业证书签名版本可用',
                ],
                cons: const [
                  '⚠️ 商业证书随时可能被 Apple 撤销，撤销后整批闪退',
                  '⚠️ 第三方分发渠道存在篡改风险',
                ],
                howto: '只接受官方 GitHub Releases 提供的 IPA 自行签名安装，'
                    '不要使用来路不明的"已签名"安装包。',
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.check_rounded),
                label: const Text('我知道了'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(YLRadius.md),
        border: Border.all(color: const Color(0xFFEF4444), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              color: Color(0xFFEF4444), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: YLText.body.copyWith(color: const Color(0xFFEF4444)),
            ),
          ),
        ],
      ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  final Color surface;
  final bool isDark;
  final String title;
  final String tag;
  final Color tagColor;
  final List<String> pros;
  final List<String> cons;
  final String howto;

  const _MethodCard({
    required this.surface,
    required this.isDark,
    required this.title,
    required this.tag,
    required this.tagColor,
    required this.pros,
    required this.cons,
    required this.howto,
  });

  @override
  Widget build(BuildContext context) {
    final border = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(YLRadius.lg),
        border: Border.all(color: border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: YLText.titleLarge.copyWith(fontSize: 17)),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tagColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  tag,
                  style: YLText.caption.copyWith(
                    color: tagColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...pros.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(p, style: YLText.body),
              )),
          ...cons.map((c) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(c, style: YLText.body),
              )),
          const SizedBox(height: 8),
          Text(howto,
              style:
                  YLText.caption.copyWith(color: YLColors.zinc500, height: 1.5)),
        ],
      ),
    );
  }
}
