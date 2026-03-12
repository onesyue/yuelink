// Sub-page: Proxy Providers — delegates to the existing ProxyProviderPage.
export '../../../pages/proxy_provider_page.dart' show ProxyProviderPage;

// Alias for use from Settings module.
// ignore_for_file: unused_import
import '../../../pages/proxy_provider_page.dart';
import 'package:flutter/material.dart';

/// Thin wrapper so settings module can import ProxyProvidersSubPage.
class ProxyProvidersSubPage extends ProxyProviderPage {
  const ProxyProvidersSubPage({super.key});
}
