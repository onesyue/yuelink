import 'package:flutter/material.dart';

import '../../../theme.dart';

/// Placeholder page for CA certificate installation guide.
///
/// Phase 1 will add the actual certificate generation and installation flow.
class CertGuidePage extends StatelessWidget {
  const CertGuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('MITM Certificate'),
        centerTitle: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.security_outlined,
                size: 72,
                color: isDark ? YLColors.zinc700 : YLColors.zinc300,
              ),
              const SizedBox(height: 24),
              Text(
                'MITM Certificate',
                style: YLText.titleMedium.copyWith(
                  color: isDark ? YLColors.zinc200 : YLColors.zinc800,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Certificate installation will be available when the MITM engine is enabled in a future update.',
                textAlign: TextAlign.center,
                style: YLText.body.copyWith(
                  color: YLColors.zinc500,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
