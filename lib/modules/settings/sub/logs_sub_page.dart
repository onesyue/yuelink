// Sub-page: Logs — delegates to the Logs module page.
export '../../logs/logs_page.dart' show LogPage;

// Alias for use from Settings module.
// ignore_for_file: unused_import
import '../../logs/logs_page.dart';
import 'package:flutter/material.dart';

/// Thin wrapper so settings_page.dart can import LogsSubPage
/// without directly depending on the logs module path.
class LogsSubPage extends LogPage {
  const LogsSubPage({super.key});
}
