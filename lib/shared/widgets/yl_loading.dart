import 'package:flutter/cupertino.dart';

/// Unified loading indicator across all platforms.
///
/// Uses Cupertino "spokes" spinner everywhere for visual consistency.
/// Telegram and many cross-platform apps adopt this pattern because it
/// feels less intrusive than the Material rotating arc — it conveys
/// "working" without demanding attention.
class YLLoading extends StatelessWidget {
  final double? size;
  final Color? color;

  const YLLoading({super.key, this.size, this.color});

  @override
  Widget build(BuildContext context) {
    return CupertinoActivityIndicator(
      radius: (size ?? 20) / 2,
      color: color,
    );
  }
}
