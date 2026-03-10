/// App-wide constants.
class AppConstants {
  AppConstants._();

  static const appName = 'YueLink';
  static const appBrand = 'Yue.to';
  static const appVersion = '1.0.0';
  static const packageName = 'com.yueto.yuelink';

  static const configFileName = 'yuelink.yaml';
  static const userAgent = 'YueLink/$appVersion (Clash)';

  /// Default test URL for latency testing.
  static const defaultTestUrl = 'https://www.gstatic.com/generate_204';
  static const defaultTestTimeout = 5000; // ms

  /// Default ports.
  static const defaultHttpPort = 7890;
  static const defaultSocksPort = 7891;
  static const defaultMixedPort = 7893;
  static const defaultApiPort = 9090;
}
