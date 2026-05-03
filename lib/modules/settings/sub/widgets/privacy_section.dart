import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/settings_service.dart';
import '../../../../i18n/app_strings.dart';
import '../../../../shared/telemetry.dart';
import '../../../../theme.dart';
import '../../widgets/primitives.dart';
import '../telemetry_preview_page.dart';

/// Privacy section — anonymous telemetry toggle + event preview link.
/// Self-contained: loads `getTelemetryEnabled` in initState and writes
/// through `Telemetry.setEnabled`.
class PrivacySection extends ConsumerStatefulWidget {
  const PrivacySection({super.key});

  @override
  ConsumerState<PrivacySection> createState() => _PrivacySectionState();
}

class _PrivacySectionState extends ConsumerState<PrivacySection> {
  bool _telemetryEnabled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final telemetry = await SettingsService.getTelemetryEnabled();
    if (mounted) setState(() => _telemetryEnabled = telemetry);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.06);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GsGeneralSectionTitle(s.privacy),
        SettingsCard(
          child: Column(
            children: [
              YLSettingsRow(
                title: s.telemetryTitle,
                description: s.telemetrySubtitle,
                trailing: CupertinoSwitch(
                  value: _telemetryEnabled,
                  activeTrackColor: YLColors.connected,
                  onChanged: (v) {
                    setState(() => _telemetryEnabled = v);
                    Telemetry.setEnabled(v);
                  },
                ),
              ),
              Divider(height: 1, thickness: 0.5, color: dividerColor),
              YLInfoRow(
                label: s.telemetryViewEvents,
                trailing: YLSettingsValueButton(label: s.isEn ? 'Open' : '打开'),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const TelemetryPreviewPage(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
