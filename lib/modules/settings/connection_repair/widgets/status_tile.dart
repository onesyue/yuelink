import 'package:flutter/material.dart';

import '../../../../core/kernel/core_manager.dart';
import '../../../../shared/widgets/setting_icon.dart';
import '../../../../shared/widgets/yl_list.dart';
import '../../../../theme.dart';

/// Connection status row — shows whether the core is currently running, or
/// surfaces the last failure if the most recent startup attempt did not
/// succeed.
class StatusTile extends StatelessWidget {
  const StatusTile({super.key});

  @override
  Widget build(BuildContext context) {
    final running = CoreManager.instance.isRunning;
    final report = CoreManager.instance.lastReport;
    final lastResult = report?.overallSuccess;

    final IconData icon;
    final Color color;
    final String title;
    String? subtitle;
    if (running) {
      icon = Icons.check_circle_rounded;
      color = YLColors.connected;
      title = '连接正常';
    } else if (lastResult == false) {
      icon = Icons.error_rounded;
      color = YLColors.error;
      title = '上次连接失败';
      subtitle = report?.failureSummary ?? '未知错误';
    } else {
      icon = Icons.radio_button_unchecked_rounded;
      color = YLColors.zinc400;
      title = '未连接';
    }

    return YLListTile(
      leading: YLSettingIcon(icon: icon, color: color),
      title: title,
      subtitle: subtitle,
    );
  }
}
