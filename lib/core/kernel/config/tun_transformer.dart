import 'dart:io';

import '../../../constants.dart';
import 'scalar_transformers.dart';
import 'yaml_helpers.dart';
import 'yaml_indent_detector.dart';

class TunTransformer {
  const TunTransformer._();

  static final _reEnableTrue = RegExp(r'\benable:\s*true');

  /// Disable TUN on desktop platforms where system proxy is used instead.
  static String disableTun(String config) {
    if (!hasKey(config, 'tun')) return config;
    final range = YamlIndentDetector.findTopLevelSection(config, 'tun');
    if (range == null) return config;

    final tunSection = config.substring(range.start, range.end);
    if (!_reEnableTrue.hasMatch(tunSection)) return config;

    final newSection = tunSection.replaceFirst(_reEnableTrue, 'enable: false');
    return config.substring(0, range.start) +
        newSection +
        config.substring(range.end);
  }

  /// Inject desktop-safe TUN configuration for macOS/Windows/Linux.
  static String ensureDesktopTun(
    String config,
    String stack, {
    List<String> bypassAddresses = const [],
    List<String> bypassProcesses = const [],
  }) {
    final normalizedStack = switch (stack) {
      'system' => 'system',
      'gvisor' => 'gvisor',
      _ => 'mixed',
    };

    if (hasKey(config, 'tun')) {
      config = _removeSection(config, 'tun');
    }

    final defaultMode = ScalarTransformers.defaultFindProcessMode();
    if (hasKey(config, 'find-process-mode')) {
      config = replaceScalar(config, 'find-process-mode', defaultMode);
    } else {
      config += '\nfind-process-mode: $defaultMode\n';
    }

    config = _ensureFakeIpForTun(config);
    config = _ensureProcessBypassRules(config, bypassProcesses);

    final buf = StringBuffer()
      ..write('$config\ntun:\n')
      ..write('  enable: true\n')
      ..write('  stack: $normalizedStack\n');
    if (Platform.isWindows || Platform.isLinux) {
      buf.write('  device: YueLink\n');
    }
    buf
      ..write('  auto-route: true\n')
      ..write('  auto-detect-interface: true\n')
      ..write('  strict-route: ${Platform.isWindows ? 'true' : 'false'}\n')
      ..write('  dns-hijack:\n')
      ..write('    - any:53\n')
      ..write('    - tcp://any:53\n')
      ..write('  mtu: ${AppConstants.defaultTunMtu}\n');

    if (bypassAddresses.isNotEmpty) {
      buf.write('  route-exclude-address:\n');
      for (final addr in bypassAddresses) {
        buf.write('    - $addr\n');
      }
    }

    return buf.toString();
  }

  /// Inject Android-safe TUN configuration with the VpnService file descriptor.
  static String injectTunFd(String config, int fd) {
    if (hasKey(config, 'tun')) {
      config = _removeSection(config, 'tun');
    }

    if (hasKey(config, 'find-process-mode')) {
      config = replaceScalar(config, 'find-process-mode', 'off');
    }

    return '$config\ntun:\n'
        '  enable: true\n'
        '  stack: gvisor\n'
        '  file-descriptor: $fd\n'
        '  inet4-address:\n'
        '    - 172.19.0.1/30\n'
        '  mtu: ${AppConstants.defaultTunMtu}\n'
        '  auto-route: false\n'
        '  auto-detect-interface: false\n'
        '  dns-hijack:\n'
        '    - any:53\n';
  }

  static String _ensureFakeIpForTun(String config) {
    if (!hasKey(config, 'dns')) {
      return config;
    }

    final range = YamlIndentDetector.findTopLevelSection(config, 'dns');
    if (range == null) return config;

    var dnsSection = config.substring(range.start, range.end);

    final enhancedRe = RegExp(r'enhanced-mode:\s*\S+');
    if (enhancedRe.hasMatch(dnsSection)) {
      dnsSection = dnsSection.replaceFirst(
        enhancedRe,
        'enhanced-mode: fake-ip',
      );
    } else {
      final indent = YamlIndentDetector.detectChildIndent(
        bodyOf(dnsSection),
        allowTabs: false,
      );
      dnsSection = dnsSection.replaceFirst(
        'dns:\n',
        'dns:\n${indent}enhanced-mode: fake-ip\n',
      );
    }

    if (!dnsSection.contains('fake-ip-range')) {
      final indent = YamlIndentDetector.detectChildIndent(
        bodyOf(dnsSection),
        allowTabs: false,
      );
      dnsSection = dnsSection.replaceFirst(
        'enhanced-mode: fake-ip\n',
        'enhanced-mode: fake-ip\n${indent}fake-ip-range: 198.18.0.1/16\n',
      );
    }

    return config.substring(0, range.start) +
        dnsSection +
        config.substring(range.end);
  }

  static String _ensureProcessBypassRules(
    String config,
    List<String> processNames,
  ) {
    final cleaned = processNames
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty && !p.contains('\n') && !p.contains(','))
        .toSet()
        .toList(growable: false);
    if (cleaned.isEmpty) return config;

    final rulesRange = YamlIndentDetector.findTopLevelSection(
      config,
      'rules',
      requireBlockHeader: true,
    );
    if (rulesRange == null) return config;

    final rulesBody = config.substring(rulesRange.bodyStart);
    final ruleIndent = YamlIndentDetector.detectListItemIndent(
      rulesBody,
      allowTabs: true,
    );

    var injection = '';
    for (final proc in cleaned) {
      final rule = 'PROCESS-NAME,$proc,DIRECT';
      if (!rulesBody.contains(rule)) {
        injection += '$ruleIndent- "$rule"\n';
      }
    }
    if (injection.isEmpty) return config;

    return config.substring(0, rulesRange.bodyStart) +
        injection +
        config.substring(rulesRange.bodyStart);
  }

  static String _removeSection(String config, String key) {
    final range = YamlIndentDetector.findTopLevelSection(config, key);
    if (range == null) return config;
    return config.substring(0, range.start) + config.substring(range.end);
  }
}
