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
  static const defaultDesktopTunStack = 'mixed';

  /// TUN MTU used everywhere we own the device (desktop + mobile). Matches
  /// physical Ethernet/Wi-Fi MTU; jumbo frames silently re-fragment or drop
  /// at the kernel socket layer and cost 15-30% throughput.
  static const defaultTunMtu = 1500;
  static const serviceListenHost = '127.0.0.1';
  static const serviceListenPort = 28653;
  static const desktopServiceName = 'YueLinkServiceHelper';
  static const desktopServiceLabel = 'com.yueto.yuelink.service';

  /// YueOps operations API base URL.
  static const yueOpsBaseUrl = 'https://ops.yue.to';
}
