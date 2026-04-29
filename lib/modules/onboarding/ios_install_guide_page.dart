import 'package:flutter/material.dart';

import '../../i18n/app_strings.dart';
import '../../shared/widgets/yl_scaffold.dart';
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
    final s = S.of(context);

    return YLLargeTitleScaffold(
      title: s.iosGuideTitle,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            YLSpacing.lg,
            0,
            YLSpacing.lg,
            YLSpacing.xl,
          ),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              if (errorContext != null) ...[
                _ErrorBanner(message: errorContext!),
                const SizedBox(height: YLSpacing.lg),
              ],
              Text(
                s.iosGuideIntro,
                style: YLText.body.copyWith(
                  fontSize: 15,
                  height: 1.5,
                  color: isDark ? YLColors.zinc300 : YLColors.zinc700,
                ),
              ),
              const SizedBox(height: YLSpacing.xl),
              _MethodCard(
                isDark: isDark,
                title: s.iosGuideMethodAltstoreTitle,
                tag: s.iosGuideMethodAltstoreTag,
                tagColor: const Color(0xFF22C55E),
                pros: [
                  s.iosGuideMethodAltstoreProVpn,
                  s.iosGuideMethodAltstoreProFree,
                  s.iosGuideMethodAltstoreProDevice,
                ],
                cons: [
                  s.iosGuideMethodAltstoreCon7d,
                  s.iosGuideMethodAltstoreConLimit,
                ],
                howto: s.iosGuideMethodAltstoreHowto,
              ),
              const SizedBox(height: YLSpacing.md),
              _MethodCard(
                isDark: isDark,
                title: s.iosGuideMethodTrollTitle,
                tag: s.iosGuideMethodTrollTag,
                tagColor: const Color(0xFFEF4444),
                pros: [s.iosGuideMethodTrollProForever],
                cons: [
                  s.iosGuideMethodTrollConVpn,
                  s.iosGuideMethodTrollConFail,
                  s.iosGuideMethodTrollConDevice,
                ],
                howto: s.iosGuideMethodTrollHowto,
              ),
              const SizedBox(height: YLSpacing.md),
              _MethodCard(
                isDark: isDark,
                title: s.iosGuideMethodIpaTitle,
                tag: s.iosGuideMethodIpaTag,
                tagColor: const Color(0xFFF59E0B),
                pros: [s.iosGuideMethodIpaProSigned],
                cons: [
                  s.iosGuideMethodIpaConRevoke,
                  s.iosGuideMethodIpaConTamper,
                ],
                howto: s.iosGuideMethodIpaHowto,
              ),
              const SizedBox(height: YLSpacing.xl),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.check_rounded),
                label: Text(s.iosGuideAck),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: YLSpacing.md),
                ),
              ),
            ]),
          ),
        ),
      ],
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
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFEF4444),
            size: 20,
          ),
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
  final bool isDark;
  final String title;
  final String tag;
  final Color tagColor;
  final List<String> pros;
  final List<String> cons;
  final String howto;

  const _MethodCard({
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
    final surface = isDark ? YLColors.zinc900 : Colors.white;
    return ClipRRect(
      borderRadius: BorderRadius.circular(YLRadius.lg),
      child: Container(
        color: surface,
        padding: const EdgeInsets.fromLTRB(
          YLSpacing.lg,
          YLSpacing.md,
          YLSpacing.lg,
          YLSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: YLText.titleLarge.copyWith(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: tagColor.withValues(alpha: isDark ? 0.20 : 0.14),
                    borderRadius: BorderRadius.circular(YLRadius.pill),
                  ),
                  child: Text(
                    tag,
                    style: YLText.caption.copyWith(
                      color: tagColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: YLSpacing.md),
            ...pros.map(
              (p) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  p,
                  style: YLText.body.copyWith(fontSize: 14, height: 1.45),
                ),
              ),
            ),
            ...cons.map(
              (c) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  c,
                  style: YLText.body.copyWith(fontSize: 14, height: 1.45),
                ),
              ),
            ),
            const SizedBox(height: YLSpacing.sm),
            Text(
              howto,
              style: YLText.caption.copyWith(
                fontSize: 12,
                color: isDark ? YLColors.zinc400 : YLColors.zinc500,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
