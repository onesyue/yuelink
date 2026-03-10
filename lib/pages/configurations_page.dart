import 'package:flutter/material.dart';
import '../theme.dart';

/// Modern Configuration Management Page (Vercel/Tailwind style)
class ConfigurationsPage extends StatelessWidget {
  const ConfigurationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          SliverAppBar.large(
            expandedHeight: 120.0,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            title: Text(
              'Profiles',
              style: YLText.display.copyWith(
                color: isDark ? YLColors.zinc50 : YLColors.zinc900,
                fontSize: 28,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.add_rounded),
                onPressed: () {
                  // TODO: Show import options (URL, File, Clipboard)
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
          
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                
                // Quick Import Input
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Paste subscription URL here...',
                    prefixIcon: const Icon(Icons.link_rounded, size: 20),
                    suffixIcon: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: FilledButton(
                        onPressed: () {},
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          minimumSize: const Size(0, 32),
                        ),
                        child: const Text('Import'),
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 32),
                const YLSectionLabel('Active Profile'),
                
                _buildProfileCard(
                  context: context,
                  name: 'YueLink Premium Sub',
                  url: 'https://api.yuelink.com/sub/xxx',
                  updatedAt: 'Updated 2 hours ago',
                  nodeCount: 42,
                  isActive: true,
                ),
                
                const SizedBox(height: 32),
                const YLSectionLabel('All Profiles'),
                
                _buildProfileCard(
                  context: context,
                  name: 'Backup Nodes (Self-hosted)',
                  url: 'Local File',
                  updatedAt: 'Updated 3 days ago',
                  nodeCount: 5,
                  isActive: false,
                ),
                const SizedBox(height: 16),
                _buildProfileCard(
                  context: context,
                  name: 'Test Subscription',
                  url: 'https://test.com/sub',
                  updatedAt: 'Update failed',
                  nodeCount: 0,
                  isActive: false,
                  hasError: true,
                ),
                
                const SizedBox(height: 100), 
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard({
    required BuildContext context,
    required String name,
    required String url,
    required String updatedAt,
    required int nodeCount,
    required bool isActive,
    bool hasError = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return YLSurface(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status Indicator
              Padding(
                padding: const EdgeInsets.only(top: 6.0, right: 12.0),
                child: YLStatusDot(
                  color: isActive 
                      ? YLColors.connected 
                      : (hasError ? YLColors.error : YLColors.zinc300),
                  glow: isActive,
                ),
              ),
              
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: YLText.titleMedium.copyWith(
                        color: hasError ? YLColors.error : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      url,
                      style: YLText.caption.copyWith(color: YLColors.zinc500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              
              // Actions Menu
              IconButton(
                icon: const Icon(Icons.more_vert_rounded, size: 20),
                color: YLColors.zinc400,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {},
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 16),
          
          // Footer Stats & Actions
          Row(
            children: [
              Icon(
                hasError ? Icons.error_outline_rounded : Icons.cloud_sync_rounded, 
                size: 14, 
                color: hasError ? YLColors.error : YLColors.zinc400
              ),
              const SizedBox(width: 6),
              Text(
                updatedAt,
                style: YLText.caption.copyWith(
                  color: hasError ? YLColors.error : YLColors.zinc500,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? YLColors.zinc800 : YLColors.zinc100,
                  borderRadius: BorderRadius.circular(YLRadius.sm),
                ),
                child: Text(
                  '$nodeCount Nodes',
                  style: YLText.caption.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (!isActive) ...[
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 28),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: const Text('Use'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
