// Sub-page: Config Overwrite — delegates to the existing OverwritePage.
export '../../../pages/overwrite_page.dart' show OverwritePage;

// Alias for use from Settings module.
// ignore_for_file: unused_import
import '../../../pages/overwrite_page.dart';
import 'package:flutter/material.dart';

/// Thin wrapper so settings_page.dart can import OverwriteSubPage
/// without directly depending on the pages path.
class OverwriteSubPage extends OverwritePage {
  const OverwriteSubPage({super.key});
}
