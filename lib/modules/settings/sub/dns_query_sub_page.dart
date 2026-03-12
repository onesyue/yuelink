// Sub-page: DNS Query — delegates to the existing DnsQueryPage.
export '../../../pages/settings/dns_query_page.dart' show DnsQueryPage;

// Alias for use from Settings module.
// ignore_for_file: unused_import
import '../../../pages/settings/dns_query_page.dart';
import 'package:flutter/material.dart';

/// Thin wrapper so settings module can import DnsQuerySubPage.
class DnsQuerySubPage extends DnsQueryPage {
  const DnsQuerySubPage({super.key});
}
