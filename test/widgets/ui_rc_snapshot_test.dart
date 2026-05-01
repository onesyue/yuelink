// ignore_for_file: prefer_const_constructors

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/shared/widgets/yl_list.dart';
import 'package:yuelink/theme.dart';

void main() {
  const enabled = bool.fromEnvironment('YUELINK_RC_SCREENSHOTS');
  if (!enabled) {
    testWidgets('RC UI screenshot matrix disabled', (_) async {});
    return;
  }

  const sizes = {
    'iphone_se': Size(320, 568),
    'narrow_360x800': Size(360, 800),
    'tablet_768x1024': Size(768, 1024),
    'desktop_1440x900': Size(1440, 900),
  };
  const scales = [1.0, 1.3, 1.6];
  const brightnesses = {'light': Brightness.light, 'dark': Brightness.dark};
  final pages = _snapshotPages();

  for (final page in pages.entries) {
    for (final size in sizes.entries) {
      for (final scale in scales) {
        for (final theme in brightnesses.entries) {
          testWidgets(
            'RC screenshot ${page.key} ${size.key} ${theme.key} scale $scale',
            (tester) async {
              final outDir = Directory('/tmp/yuelink-ui-rc-screens')
                ..createSync(recursive: true);
              final key = GlobalKey();
              tester.view.physicalSize = size.value;
              tester.view.devicePixelRatio = 1;
              addTearDown(() {
                tester.view.resetPhysicalSize();
                tester.view.resetDevicePixelRatio();
              });

              await tester.pumpWidget(
                RepaintBoundary(
                  key: key,
                  child: MaterialApp(
                    debugShowCheckedModeBanner: false,
                    theme: buildTheme(theme.value),
                    home: MediaQuery(
                      data: MediaQueryData(
                        textScaler: TextScaler.linear(scale),
                      ),
                      child: Builder(builder: page.value),
                    ),
                  ),
                ),
              );
              await tester.pump(const Duration(milliseconds: 50));
              expect(tester.takeException(), isNull);

              await tester.runAsync(() async {
                final boundary =
                    key.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary;
                final image = await boundary.toImage(pixelRatio: 1);
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final file = File(
                  '${outDir.path}/${page.key}_${size.key}_${theme.key}_scale_${scale.toStringAsFixed(1)}.png',
                );
                file.writeAsBytesSync(bytes!.buffer.asUint8List());
                image.dispose();
              });
            },
          );
        }
      }
    }
  }
}

Map<String, WidgetBuilder> _snapshotPages() => {
  'dashboard': (_) => _SnapshotPage(
    title: '首页',
    large: true,
    children: [
      _StatusStrip(),
      _InfoCard(
        title: '当前节点',
        lines: ['悦 · 自动选择', 'Google 正常 · GitHub 正常 · Claude AI 出口受限'],
      ),
    ],
  ),
  'profiles': (_) => _SnapshotPage(
    title: '订阅',
    children: [
      _InfoCard(
        title: '非常长的订阅名称用于验证中文和英文混排不会撑爆布局 YueLink Premium',
        lines: ['已启用 · 18.2 GB / 100 GB', '更新于 2026-05-01 20:10'],
        mono: 'mixed-port: 7890\nproxy-groups: 悦 · 自动选择',
      ),
    ],
  ),
  'plans': (_) => _SnapshotPage(
    title: '订阅套餐',
    children: [
      _PlanCard(
        name: 'YueLink Pro 长周期套餐',
        price: '¥22.00',
        desc: '高速流量 · AI 分组 · Netflix/YouTube/GitHub',
      ),
      _PlanCard(name: '轻量月付', price: '¥9.90', desc: '适合低频使用，不承诺节点已全面稳定'),
    ],
  ),
  'orders': (_) => _SnapshotPage(
    title: '订单记录',
    children: [
      _OrderRow(
        id: '20260501-VERY-LONG-ORDER-NO-ABCDEFG-1234567890',
        status: '待支付',
        amount: '¥22.00',
      ),
      _OrderRow(
        id: '20260430-PAID-00001234567890',
        status: '已完成',
        amount: '¥9.90',
      ),
    ],
  ),
  'checkin': (_) => _SnapshotPage(
    title: '签到日历',
    children: [
      _StatsRow(),
      _InfoCard(title: '2026-05-01', lines: ['已签到 · +50 积分', '连续签到 7 天']),
    ],
  ),
  'settings': (_) => _SnapshotPage(
    title: '偏好设置',
    children: [
      _Section(
        rows: const [
          ('外观', '跟随系统 · 中文'),
          ('连接模式', '规则模式 · TUN 可用'),
          ('自动更新', 'Release channel'),
        ],
      ),
    ],
  ),
  'overwrite': (_) => _SnapshotPage(
    title: '配置覆写',
    children: [
      _InfoCard(
        title: '自定义规则',
        lines: ['prepend rules · 2 条'],
        mono: 'rules:\n  - DOMAIN-SUFFIX,openai.com,AI\n  - MATCH,悦 · 自动选择',
      ),
    ],
  ),
  'repair': (_) => _SnapshotPage(
    title: '连接修复',
    children: [
      _DiagRow(label: '节点', value: '节点超时', color: YLColors.error),
      _DiagRow(label: 'DNS', value: '正常', color: YLColors.connected),
      _DiagRow(
        label: 'Claude',
        value: 'AI 出口受限 403',
        color: YLColors.connecting,
      ),
      _DiagRow(label: 'Reality', value: '认证失败', color: YLColors.error),
    ],
  ),
  'modules': (_) => _SnapshotPage(
    title: '规则模块',
    children: [
      _InfoCard(
        title: 'OpenAI fallback ruleset module',
        lines: ['MITM · rewrite · script', '35 条规则 · 已启用'],
      ),
    ],
  ),
  'announcements': (_) => _SnapshotPage(
    title: '最新公告',
    children: [
      _InfoCard(
        title: 'YueLink UI 修复 + 遥测增强 RC',
        lines: ['2026-05-01', '节点池仍在治理中，不宣传全面稳定。'],
      ),
    ],
  ),
};

class _SnapshotPage extends StatelessWidget {
  const _SnapshotPage({
    required this.title,
    required this.children,
    this.large = false,
  });

  final String title;
  final List<Widget> children;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? YLColors.zinc950 : YLColors.zinc50,
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          itemBuilder: (_, i) {
            if (i == 0) {
              return Text(
                title,
                style: (large ? YLText.display : YLText.pageTitle).copyWith(
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              );
            }
            return children[i - 1];
          },
          separatorBuilder: (_, index) => const SizedBox(height: 10),
          itemCount: children.length + 1,
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.lines, this.mono});
  final String title;
  final List<String> lines;
  final String? mono;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return YLSurface(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: YLText.rowTitle.copyWith(fontWeight: FontWeight.w600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          for (final line in lines)
            Text(
              line,
              style: YLText.rowSubtitle.copyWith(color: YLColors.zinc500),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          if (mono != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? YLColors.zinc950 : YLColors.zinc100,
                borderRadius: BorderRadius.circular(YLRadius.md),
              ),
              child: Text(
                mono!,
                style: YLText.monoSmall,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.name,
    required this.price,
    required this.desc,
  });
  final String name;
  final String price;
  final String desc;

  @override
  Widget build(BuildContext context) {
    return YLSurface(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: YLText.rowTitle.copyWith(fontWeight: FontWeight.w600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            price,
            style: YLText.price.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(
            desc,
            style: YLText.rowSubtitle.copyWith(color: YLColors.zinc500),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 42,
            width: double.infinity,
            child: FilledButton(
              onPressed: () {},
              child: const Text(
                '购买套餐',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({
    required this.id,
    required this.status,
    required this.amount,
  });
  final String id;
  final String status;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return YLListTile(
      title: id,
      subtitle: '2026-05-01 20:10',
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            amount,
            style: YLText.rowTitle.copyWith(fontWeight: FontWeight.w600),
          ),
          Text(
            status,
            style: YLText.badge.copyWith(color: YLColors.connecting),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.rows});
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return YLSurface(
      padding: EdgeInsets.zero,
      child: Column(
        children: rows
            .map((r) => YLListTile(title: r.$1, subtitle: r.$2))
            .toList(),
      ),
    );
  }
}

class _StatusStrip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const items = [
      ('节点', true),
      ('Google', true),
      ('GitHub', true),
      ('YouTube', true),
      ('Netflix', true),
      ('Claude', false),
      ('ChatGPT', false),
    ];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: items.map((item) {
        final ok = item.$2;
        return Chip(
          label: Text(item.$1, style: YLText.badge),
          visualDensity: VisualDensity.compact,
          avatar: Icon(
            Icons.circle,
            size: 8,
            color: ok ? YLColors.connected : YLColors.connecting,
          ),
        );
      }).toList(),
    );
  }
}

class _StatsRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Expanded(
          child: _StatBox(label: '本月签到', value: '20'),
        ),
        SizedBox(width: 8),
        Expanded(
          child: _StatBox(label: '连续', value: '7'),
        ),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return YLSurface(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: YLText.stat.copyWith(fontWeight: FontWeight.w700)),
          Text(
            label,
            style: YLText.rowSubtitle.copyWith(color: YLColors.zinc500),
          ),
        ],
      ),
    );
  }
}

class _DiagRow extends StatelessWidget {
  const _DiagRow({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return YLListTile(
      title: label,
      subtitle: value,
      trailing: Icon(Icons.circle, size: 10, color: color),
    );
  }
}
