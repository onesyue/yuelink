import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/settings_service.dart';
import '../../../../i18n/app_strings.dart';
import '../../providers/settings_providers.dart';
import '../../widgets/primitives.dart';

/// Desktop-only: segmented control for close-button behaviour
/// (minimise-to-tray vs. quit-on-close).
///
/// Extracted from `sub/general_settings_page.dart` (Batch ε). Watches
/// `closeBehaviorProvider` directly; no page-level state closure.
class CloseBehaviorRow extends ConsumerWidget {
  const CloseBehaviorRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final behavior = ref.watch(closeBehaviorProvider);
    return YLInfoRow(
      label: s.closeWindowBehavior,
      trailing: YLAdaptiveSegmentedControl<String>(
        semanticLabel: s.closeWindowBehavior,
        selectedValue: behavior,
        segments: [
          YLAdaptiveSegment(value: 'tray', label: s.closeBehaviorTray),
          YLAdaptiveSegment(value: 'exit', label: s.closeBehaviorExit),
        ],
        onChanged: (val) async {
          ref.read(closeBehaviorProvider.notifier).set(val);
          await SettingsService.setCloseBehavior(val);
        },
      ),
    );
  }
}
