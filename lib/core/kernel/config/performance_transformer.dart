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
    // Keep-alive idle: without this, mihomo falls through to the OS
    // default (Linux 7200s, macOS 7200s, Windows 7200s) before sending
    // a single probe, which makes `keep-alive-interval` cosmetic. CVR
    // and mihomo-party ship 600s (10 min) — long enough not to wake
    // mobile radios on idle proxy connections, short enough that dead
    // NAT bindings get noticed before the user perceives them.
    if (!hasKey(config, 'keep-alive-idle')) {
      config += 'keep-alive-idle: 600\n';
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
