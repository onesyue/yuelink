import 'package:flutter/material.dart';

import '../../i18n/app_strings.dart';
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
        title: Text(S.of(context).iosGuideTitle),
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
              Text(S.of(context).iosGuideIntro, style: YLText.body),
              const SizedBox(height: 20),
              _MethodCard(
                surface: surface,
                isDark: isDark,
                title: S.of(context).iosGuideMethodAltstoreTitle,
                tag: S.of(context).iosGuideMethodAltstoreTag,
                tagColor: const Color(0xFF22C55E),
                pros: [
                  S.of(context).iosGuideMethodAltstoreProVpn,
                  S.of(context).iosGuideMethodAltstoreProFree,
                  S.of(context).iosGuideMethodAltstoreProDevice,
                ],
                cons: [
                  S.of(context).iosGuideMethodAltstoreCon7d,
                  S.of(context).iosGuideMethodAltstoreConLimit,
                ],
                howto: S.of(context).iosGuideMethodAltstoreHowto,
              ),
              const SizedBox(height: 12),
              _MethodCard(
                surface: surface,
                isDark: isDark,
                title: S.of(context).iosGuideMethodTrollTitle,
                tag: S.of(context).iosGuideMethodTrollTag,
                tagColor: const Color(0xFFEF4444),
                pros: [S.of(context).iosGuideMethodTrollProForever],
                cons: [
                  S.of(context).iosGuideMethodTrollConVpn,
                  S.of(context).iosGuideMethodTrollConFail,
                  S.of(context).iosGuideMethodTrollConDevice,
                ],
                howto: S.of(context).iosGuideMethodTrollHowto,
              ),
              const SizedBox(height: 12),
              _MethodCard(
                surface: surface,
                isDark: isDark,
                title: S.of(context).iosGuideMethodIpaTitle,
                tag: S.of(context).iosGuideMethodIpaTag,
                tagColor: const Color(0xFFF59E0B),
                pros: [S.of(context).iosGuideMethodIpaProSigned],
                cons: [
                  S.of(context).iosGuideMethodIpaConRevoke,
                  S.of(context).iosGuideMethodIpaConTamper,
                ],
                howto: S.of(context).iosGuideMethodIpaHowto,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.check_rounded),
                label: Text(S.of(context).iosGuideAck),
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
