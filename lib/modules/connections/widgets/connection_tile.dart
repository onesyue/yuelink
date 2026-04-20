import 'package:flutter/material.dart';

import '../../../domain/models/connection.dart';
import '../../../theme.dart';
import 'connection_detail_sheet.dart';
import 'network_badge.dart';

class ConnectionTile extends StatelessWidget {
  final ActiveConnection connection;
  final VoidCallback onClose;

  const ConnectionTile({
    super.key,
    required this.connection,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasSpeed = connection.curDownloadSpeed > 0 || connection.curUploadSpeed > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc900 : Colors.white,
        borderRadius: BorderRadius.circular(YLRadius.lg),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha:0.05) : Colors.black.withValues(alpha:0.03),
          width: 1,
        ),
        boxShadow: YLShadow.card(context),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(YLRadius.lg),
          onTap: () => _showDetail(context),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                NetworkBadge(network: connection.network),
                const SizedBox(width: 14),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        connection.target,
                        style: YLText.titleMedium.copyWith(fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: (isDark ? Colors.white : YLColors.primary).withValues(alpha:0.1),
                                borderRadius: BorderRadius.circular(YLRadius.sm),
                              ),
                              child: Text(
                                connection.chains.isNotEmpty
                                    ? connection.chains.join(' → ')
                                    : connection.rule,
                                style: YLText.caption.copyWith(color: isDark ? Colors.white : YLColors.primary, fontSize: 10),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          if (connection.processName.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                connection.processName,
                                style: YLText.caption.copyWith(color: YLColors.zinc500, fontSize: 11),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (hasSpeed)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              const Icon(Icons.south_rounded, size: 12, color: YLColors.connected),
                              const SizedBox(width: 2),
                              Text(
                                _formatSpeed(connection.curDownloadSpeed),
                                style: YLText.mono.copyWith(fontSize: 11, color: YLColors.connected),
                              ),
                              const SizedBox(width: 12),
                              Icon(Icons.north_rounded, size: 12, color: Colors.blue.shade500),
                              const SizedBox(width: 2),
                              Text(
                                _formatSpeed(connection.curUploadSpeed),
                                style: YLText.mono.copyWith(fontSize: 11, color: Colors.blue.shade500),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),

                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      connection.durationText,
                      style: YLText.mono.copyWith(color: YLColors.zinc500, fontSize: 11),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      borderRadius: BorderRadius.circular(YLRadius.pill),
                      onTap: onClose,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: YLColors.errorLight.withValues(alpha:isDark ? 0.1 : 0.5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close_rounded, size: 14, color: YLColors.error),
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

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ConnectionDetailSheet(connection: connection),
    );
  }

  String _formatSpeed(int bps) {
    if (bps < 1024) return '$bps B/s';
    if (bps < 1024 * 1024) {
      return '${(bps / 1024).toStringAsFixed(0)} KB/s';
    }
    return '${(bps / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
}
