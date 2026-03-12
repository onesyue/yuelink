// Sub-page: Running Config — delegates to the existing RunningConfigPage.
export '../../../pages/settings/running_config_page.dart' show RunningConfigPage;

// Alias for use from Settings module.
// ignore_for_file: unused_import
import '../../../pages/settings/running_config_page.dart';
import 'package:flutter/material.dart';

/// Thin wrapper so settings module can import RunningConfigSubPage.
class RunningConfigSubPage extends RunningConfigPage {
  const RunningConfigSubPage({super.key});
}
