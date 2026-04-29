import 'package:flutter/material.dart';

import '../../../theme.dart';

class NetworkBadge extends StatelessWidget {
  final String network;
  const NetworkBadge({super.key, required this.network});

  @override
  Widget build(BuildContext context) {
    final isUdp = network.toLowerCase() == 'udp';
    final color = isUdp ? YLColors.connecting : Colors.blue.shade500;

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(YLRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        network.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
          color: color,
        ),
      ),
    );
  }
}
