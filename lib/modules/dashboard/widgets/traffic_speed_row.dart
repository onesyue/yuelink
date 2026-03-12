import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/core_provider.dart';
import '../../../theme.dart';

// Isolated consumer so only the two speed numbers rebuild every traffic tick
// rather than rebuilding the entire HeroCard.
//
// Two-row layout eliminates any possibility of text overlap regardless of
// card width. Color convention: ↓ download = accent, ↑ upload = connected.
class TrafficSpeedRow extends ConsumerWidget {
  const TrafficSpeedRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final traffic = ref.watch(trafficProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_downward_rounded, size: 13, color: YLColors.accent),
            const SizedBox(width: 4),
            Text(
              traffic.downFormatted,
              style: YLText.mono.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_upward_rounded, size: 13, color: YLColors.connected),
            const SizedBox(width: 4),
            Text(
              traffic.upFormatted,
              style: YLText.mono.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ],
    );
  }
}
