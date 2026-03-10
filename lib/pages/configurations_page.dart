import 'package:flutter/material.dart';
// 如果你还需要保留旧的逻辑，可以取消注释下面这行，将旧页面嵌入到新 UI 中
// import 'profile_page.dart'; 

class ConfigurationsPage extends StatelessWidget {
  const ConfigurationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 现代化的 UI 改造方案
    return Scaffold(
      // 使用 Zinc 100 作为全局背景色，显得干净现代
      backgroundColor: const Color(0xFFF4F4F5), 
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // 现代大标题 AppBar
          SliverAppBar(
            expandedHeight: 120.0,
            floating: false,
            pinned: true,
            elevation: 0,
            backgroundColor: const Color(0xFFF4F4F5),
            surfaceTintColor: Colors.transparent,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              title: const Text(
                '配置管理',
                style: TextStyle(
                  color: Color(0xFF18181B), // Zinc 900
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          
          // 页面主体内容
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle('当前使用'),
                  const SizedBox(height: 12),
                  _buildActiveProfileCard(),
                  
                  const SizedBox(height: 32),
                  
                  _buildSectionTitle('所有配置'),
                  const SizedBox(height: 12),
                  // 列表项展示
                  _buildProfileListItem(
                    name: 'YueLink 默认订阅',
                    subtitle: '24 节点 • 12小时前更新',
                    isActive: true,
                  ),
                  const SizedBox(height: 12),
                  _buildProfileListItem(
                    name: '备用线路 (自建)',
                    subtitle: '5 节点 • 2天前更新',
                    isActive: false,
                  ),
                  const SizedBox(height: 12),
                  _buildProfileListItem(
                    name: '测试订阅',
                    subtitle: '0 节点 • 获取失败',
                    isActive: false,
                    hasError: true,
                  ),
                  
                  // 底部留白，防止被 FAB 遮挡
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
      
      // 现代化的悬浮添加按钮
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // TODO: 触发添加订阅逻辑
        },
        backgroundColor: const Color(0xFF18181B), // Zinc 900
        foregroundColor: Colors.white,
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
  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: Color(0xFF71717A), // Zinc 500
        letterSpacing: 0.5,
      ),
    );
  }

  // 激活状态的配置卡片（高亮渐变设计）
  Widget _buildActiveProfileCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3B82F6), Color(0xFF2563EB)], // 现代亮蓝色渐变
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 状态标签
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded, color: Colors.white, size: 14),
                    SizedBox(width: 4),
                    Text(
                      '已连接', 
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              // 更多操作按钮
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onPressed: () {},
                  child: const Padding(
                    padding: EdgeInsets.all(4.0),
                    child: Icon(Icons.more_horiz_rounded, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'YueLink 默认订阅',
            style: TextStyle(
              color: Colors.white, 
              fontSize: 22, 
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.cloud_sync_rounded, color: Colors.white70, size: 16),
              const SizedBox(width: 6),
              const Text(
                '12小时前更新', 
                style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
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
    );
  }

  // 普通配置列表项
  Widget _buildProfileListItem({
    required String name, 
    required String subtitle, 
    required bool isActive,
    bool hasError = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive 
              ? const Color(0xFF3B82F6) 
              : (hasError ? Colors.red.shade200 : const Color(0xFFE4E4E7)), 
          width: isActive ? 2.0 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // 左侧图标
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isActive 
                  ? const Color(0xFFEFF6FF) 
                  : (hasError ? Colors.red.shade50 : const Color(0xFFF4F4F5)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              hasError ? Icons.error_outline_rounded : Icons.description_rounded,
              color: isActive 
                  ? const Color(0xFF3B82F6) 
                  : (hasError ? Colors.red.shade400 : const Color(0xFFA1A1AA)),
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
                    color: hasError ? Colors.red.shade700 : const Color(0xFF18181B),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: hasError ? Colors.red.shade400 : const Color(0xFF71717A),
                  ),
                ),
              ],
            ),
          ),
          
          // 右侧操作区
          if (!isActive)
            IconButton(
              icon: Icon(
                Icons.play_circle_fill_rounded, 
                color: hasError ? Colors.red.shade200 : const Color(0xFFD4D4D8), 
                size: 32,
              ),
              onPressed: () {
                // TODO: 切换到该配置
              },
            ),
        ],
      ),
    );
  }
}
