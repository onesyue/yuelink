import 'yaml_helpers.dart';

class PerformanceTransformer {
  const PerformanceTransformer._();

  /// Ensure performance tuning defaults.
  static String ensurePerformance(String config) {
    config = _removeDeprecatedGlobalClientFingerprint(config);
    if (!hasKey(config, 'tcp-concurrent')) {
      config += '\ntcp-concurrent: true\n';
    }
    if (!hasKey(config, 'unified-delay')) {
      config += 'unified-delay: true\n';
    }
    // Keep-alive interval: mihomo upstream default is 30s — matches the
    // mobile carrier NAT floor (~30s) while halving CPU wake-ups / battery
    // drain vs the previous 15s. Clash Verge Rev and mihomo-party both
    // use 30s.
    if (!hasKey(config, 'keep-alive-interval')) {
      config += 'keep-alive-interval: 30\n';
    }
    return config;
  }

  static String _removeDeprecatedGlobalClientFingerprint(String config) {
    return config.replaceAllMapped(
      RegExp(
        r'''^\s*global-client-fingerprint\s*:\s*(?:"[^"]*"|'[^']*'|[^\n#]+)?\s*(?:#.*)?\n?''',
        multiLine: true,
      ),
      (_) => '',
    );
  }
}
