/// App-wide constants.
class AppConstants {
  AppConstants._();

  static const appName = 'YueLink';
  static const appBrand = 'Yue.to';
  static const appVersion = '0.0.2-alpha';
  static const packageName = 'com.yueto.yuelink';

  static const configFileName = 'yuelink.yaml';
  static const userAgent = 'clash.meta';

  /// Default test URL for latency testing.
  static const defaultTestUrl = 'https://www.gstatic.com/generate_204';
  static const defaultTestTimeout = 5000; // ms

  /// Default ports (aligned with standard mihomo config).
  static const defaultMixedPort = 7890;
  static const defaultApiPort = 9090;
}
