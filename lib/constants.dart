import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Version string from pubspec.yaml (single source of truth).
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.version;
});

/// App-wide constants.
class AppConstants {
  AppConstants._();

  static const appName = 'YueLink';
  static const appBrand = 'Yue.to';
  static const packageName = 'com.yueto.yuelink';

  static const configFileName = 'yuelink.yaml';
  static const userAgent = 'clash.meta';

  /// Default test URL for latency testing.
  static const defaultTestUrl = 'https://www.gstatic.com/generate_204';
  static const defaultTestTimeout = 5000; // ms

  /// Default ports (aligned with standard mihomo config).
  static const defaultMixedPort = 7890;
  static const defaultApiPort = 9090;

  /// YueOps operations API base URL.
  static const yueOpsBaseUrl = 'https://ops.yue.to';
}
