// Sub-page: WebDAV — delegates to the existing WebDavPage.
export '../../../pages/webdav_page.dart' show WebDavPage;

// Alias for use from Settings module.
// ignore_for_file: unused_import
import '../../../pages/webdav_page.dart';
import 'package:flutter/material.dart';

/// Thin wrapper so settings_page.dart can import WebDavSubPage
/// without directly depending on the pages path.
class WebDavSubPage extends WebDavPage {
  const WebDavSubPage({super.key});
}
