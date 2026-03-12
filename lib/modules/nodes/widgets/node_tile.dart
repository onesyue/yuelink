import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_strings.dart';
import '../../../shared/app_notifier.dart';
import '../../../theme.dart';
import '../providers/node_providers.dart';
import '../providers/nodes_providers.dart';

/// A single proxy node row.
///
/// Accepts only the node [name] and its parent [groupName]. All per-node
/// state (delay, selected, testing) is watched internally via family providers
/// so that rebuilds are isolated to this tile only — the parent [GroupCard]
/// does not need to rebuild when a delay result arrives for this node.
class NodeTile extends ConsumerStatefulWidget {
  const NodeTile({
    super.key,
    required this.name,
    required this.groupName,
  });

  final String name;
  final String groupName;

  @override
  ConsumerState<NodeTile> createState() => _NodeTileState();
}

class _NodeTileState extends ConsumerState<NodeTile> {
  bool _isSwitching = false;

  Future<void> _handleSelect() async {
    final isSelected =
        ref.read(groupSelectedNodeProvider(widget.groupName)) == widget.name;
    if (_isSwitching || isSelected) return;
    setState(() => _isSwitching = true);
    final s = S.of(context);
    final ok = await ref
        .read(proxyGroupsProvider.notifier)
        .changeProxy(widget.groupName, widget.name);
    if (mounted) {
      setState(() => _isSwitching = false);
      if (ok) {
        AppNotifier.success(s.switchedTo(widget.name));
      } else {
        AppNotifier.error(s.switchFailed);
      }
    }
  }

  Widget _buildName(BuildContext context, bool isSelected, bool isDark) {
    final query =
        ref.watch(nodeSearchQueryProvider).trim().toLowerCase();
    final name = widget.name;
    final baseStyle = YLText.body.copyWith(
      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
      color: isSelected
          ? (isDark ? Colors.white : YLColors.primary)
          : (isDark ? Colors.white : Colors.black),
    );
    if (query.isEmpty) {
      return Text(name,
          style: baseStyle, maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    final lower = name.toLowerCase();
    final idx = lower.indexOf(query);
    if (idx < 0) {
      return Text(name,
          style: baseStyle, maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    return Text.rich(
      TextSpan(
        children: [
          if (idx > 0) TextSpan(text: name.substring(0, idx)),
          TextSpan(
            text: name.substring(idx, idx + query.length),
            style: baseStyle.copyWith(
              color: YLColors.connected,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (idx + query.length < name.length)
            TextSpan(text: name.substring(idx + query.length)),
        ],
        style: baseStyle,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Granular watches — only this tile rebuilds when its delay/selected/testing changes.
    final delay = ref.watch(nodeDelayProvider(widget.name));
    final isSelected =
        ref.watch(groupSelectedNodeProvider(widget.groupName)) == widget.name;
    final isTesting = ref.watch(nodeIsTestingProvider(widget.name));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _handleSelect,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: YLSpacing.md, vertical: YLSpacing.sm),
          color: isSelected
              ? (isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : YLColors.primary.withValues(alpha: 0.05))
              : Colors.transparent,
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: _isSwitching
                    ? const CupertinoActivityIndicator(radius: 7)
                    : (isSelected
                        ? Icon(Icons.check_rounded,
                            color: isDark ? Colors.white : YLColors.primary,
                            size: 18)
                        : null),
              ),
              const SizedBox(width: YLSpacing.xs),
              Expanded(
                child: _buildName(context, isSelected, isDark),
              ),
              const SizedBox(width: YLSpacing.sm),
              InkWell(
                onTap: isTesting
                    ? null
                    : () => ref.read(delayTestProvider).testDelay(widget.name),
                borderRadius: BorderRadius.circular(YLRadius.sm),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: YLDelayBadge(delay: delay, testing: isTesting),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
