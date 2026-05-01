import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../theme.dart';

/// Drop-in replacement for `CircularProgressIndicator` at content-loading
/// surfaces. Renders a shimmer gradient over a stack of rounded-corner
/// placeholder bars sized like the real content, so the user sees "stuff
/// is coming" instead of a plain spinner.
///
/// Two convenience constructors:
///  - `YLSkeleton.lines(count: 3)` — tile list
///  - `YLSkeleton.card(height: 160)` — single card
class YLSkeleton extends StatelessWidget {
  const YLSkeleton._({
    required this.children,
    required this.padding,
  });

  /// Stack of skeleton list-tile rows (avatar + two lines), `count` of them.
  factory YLSkeleton.lines({int count = 4}) {
    return YLSkeleton._(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: List.generate(count, (i) => const _SkeletonRow()),
    );
  }

  /// Single full-width card placeholder.
  factory YLSkeleton.card({double height = 140}) {
    return YLSkeleton._(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [_SkeletonBlock(height: height)],
    );
  }

  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? YLColors.zinc800 : YLColors.zinc200;
    final highlight = isDark ? YLColors.zinc700 : YLColors.zinc100;
    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      period: const Duration(milliseconds: 1200),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(YLRadius.lg),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(YLRadius.xl),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: 0.65,
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
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

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }
}
