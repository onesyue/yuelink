import 'package:flutter/material.dart';

class ConfigurationsPage extends StatelessWidget {
  const ConfigurationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 动态获取当前主题模式
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 现代 Zinc 色系背景
    final scaffoldBg = isDark ? const Color(0xFF09090B) : const Color(0xFFF4F4F5);
    final textColor = isDark ? const Color(0xFFFAFAFA) : const Color(0xFF18181B);

    return Scaffold(
      backgroundColor: scaffoldBg,
      body: CustomScrollView(
        // 增加 AlwaysScrollableScrollPhysics 确保内容较少时也能触发滚动回弹
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          // 使用 Material 3 的大标题 AppBar
          SliverAppBar.large(
            expandedHeight: 140.0,
            backgroundColor: scaffoldBg,
            surfaceTintColor: Colors.transparent,
            title: Text(
              '配置管理',
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
          
          // 页面主体内容
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildSectionTitle('当前使用', isDark),
                const SizedBox(height: 12),
                _buildActiveProfileCard(context, isDark),
                
                const SizedBox(height: 32),
                
                _buildSectionTitle('所有配置', isDark),
                const SizedBox(height: 12),
                
                // 列表项展示
                _buildProfileListItem(
                  context: context,
                  name: 'YueLink 默认订阅',
                  subtitle: '24 节点 • 12小时前更新',
                  isActive: true,
                  isDark: isDark,
                ),
                const SizedBox(height: 12),
                _buildProfileListItem(
                  context: context,
                  name: '备用线路 (自建)',
                  subtitle: '5 节点 • 2天前更新',
                  isActive: false,
                  isDark: isDark,
                ),
                const SizedBox(height: 12),
                _buildProfileListItem(
                  context: context,
                  name: '测试订阅',
                  subtitle: '0 节点 • 获取失败',
                  isActive: false,
                  hasError: true,
                  isDark: isDark,
                ),
                
                // 底部留白，防止被 FAB 遮挡
                const SizedBox(height: 100), 
              ]),
            ),
          ),
        ],
      ),
      
      // 现代化的悬浮添加按钮
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // TODO: 触发添加订阅逻辑
        },
        backgroundColor: isDark ? const Color(0xFFFAFAFA) : const Color(0xFF18181B),
        foregroundColor: isDark ? const Color(0xFF18181B) : Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          '添加订阅', 
          style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5),
        ),
      ),
    );
  }

  // 小节标题组件
  Widget _buildSectionTitle(String title, bool isDark) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: isDark ? const Color(0xFFA1A1AA) : const Color(0xFF71717A),
        letterSpacing: 0.5,
      ),
    );
  }

  // 激活状态的配置卡片（高亮渐变设计 + 涟漪效果）
  Widget _buildActiveProfileCard(BuildContext context, bool isDark) {
    // 动态获取主题的主色调
    final primaryColor = Theme.of(context).colorScheme.primary;
    
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primaryColor.withOpacity(0.8),
            primaryColor,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(isDark ? 0.15 : 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            // TODO: 点击卡片查看详情
          },
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // 状态标签
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
                          SizedBox(width: 6),
                          Text(
                            '已连接', 
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    // 更多操作按钮
                    IconButton(
                      icon: const Icon(Icons.more_horiz_rounded, color: Colors.white),
                      onPressed: () {},
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  'YueLink 默认订阅',
                  style: TextStyle(
                    color: Colors.white, 
                    fontSize: 24, 
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.cloud_sync_rounded, color: Colors.white, size: 14),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '12小时前更新', 
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        '24 节点', 
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 普通配置列表项（支持暗黑模式 + 涟漪效果）
  Widget _buildProfileListItem({
    required BuildContext context,
    required String name, 
    required String subtitle, 
    required bool isActive,
    bool hasError = false,
    required bool isDark,
  }) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    
    // 动态颜色计算
    final cardBg = isDark ? const Color(0xFF18181B) : Colors.white;
    final borderColor = isActive 
        ? primaryColor 
        : (hasError 
            ? Colors.red.withOpacity(0.5) 
            : (isDark ? const Color(0xFF27272A) : const Color(0xFFE4E4E7)));
            
    final iconBg = isActive 
        ? primaryColor.withOpacity(0.1) 
        : (hasError 
            ? Colors.red.withOpacity(0.1) 
            : (isDark ? const Color(0xFF27272A) : const Color(0xFFF4F4F5)));
            
    final iconColor = isActive 
        ? primaryColor 
        : (hasError 
            ? Colors.red 
            : (isDark ? const Color(0xFFA1A1AA) : const Color(0xFFA1A1AA)));

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: isActive ? 2.0 : 1.0),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            // TODO: 点击进入配置详情
          },
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // 左侧图标
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    hasError ? Icons.error_outline_rounded : Icons.description_rounded,
                    color: iconColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                
                // 中间文本信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: hasError 
                              ? Colors.red 
                              : (isDark ? const Color(0xFFFAFAFA) : const Color(0xFF18181B)),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: hasError 
                              ? Colors.red.withOpacity(0.7) 
                              : (isDark ? const Color(0xFFA1A1AA) : const Color(0xFF71717A)),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // 右侧操作区
                if (!isActive)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    child: IconButton(
                      icon: Icon(
                        Icons.play_circle_fill_rounded, 
                        color: hasError 
                            ? Colors.red.withOpacity(0.3) 
                            : (isDark ? const Color(0xFF3F3F46) : const Color(0xFFD4D4D8)), 
                        size: 36,
                      ),
                      onPressed: () {
                        // TODO: 切换到该配置
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
