// Sub-page: Connections — delegates to the Connections module page.
export '../../connections/connections_page.dart' show ConnectionsPage;

// Alias for use from Settings module.
// ignore_for_file: unused_import
import '../../connections/connections_page.dart';
import 'package:flutter/material.dart';

/// Thin wrapper so settings_page.dart can import ConnectionsSubPage
/// without directly depending on the connections module path.
class ConnectionsSubPage extends ConnectionsPage {
  const ConnectionsSubPage({super.key});
}
