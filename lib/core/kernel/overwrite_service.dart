import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:yaml/yaml.dart';

/// Manages user-defined config overwrite rules.
///
/// The overwrite is a partial YAML snippet that is merged on top of the
/// subscription config before starting the core. This allows users to
/// add custom rules, change DNS settings, etc. without modifying the
/// subscription file itself.
///
/// Merge strategy:
/// - Top-level scalar keys (mode, log-level, etc.) replace subscription values
/// - `rules` overwrite entries are prepended before subscription rules
/// - `proxies` / `proxy-groups` entries are appended
class OverwriteService {
  static const _fileName = 'overwrite.yaml';

  static Future<File> _getFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Load saved overwrite YAML. Returns empty string if not set.
  static Future<String> load() async {
    final file = await _getFile();
    if (!await file.exists()) return '';
    return file.readAsString();
  }

  /// Validate YAML syntax. Returns an error message, or null if valid.
  static String? validate(String yaml) {
    if (yaml.trim().isEmpty) return null;
    try {
      loadYaml(yaml);
      return null;
    } catch (e) {
      // Extract a short, user-facing message from the parse exception
      final msg = e.toString();
      final line = RegExp(r'line (\d+)').firstMatch(msg);
      if (line != null) return 'YAML 语法错误 (第 ${line.group(1)} 行): $msg';
      return 'YAML 语法错误: $msg';
    }
  }

  /// Save overwrite YAML. Throws [FormatException] if YAML is invalid.
  static Future<void> save(String yaml) async {
    final error = validate(yaml);
    if (error != null) throw FormatException(error);
    final file = await _getFile();
    await file.writeAsString(yaml);
  }

  /// Apply overwrite on top of the base config.
  ///
  /// For each top-level key in [overwrite]:
  /// - Scalars → replace the base value
  /// - `rules` list → prepend entries before base rules
  /// - `proxies` / `proxy-groups` lists → append entries
  static String apply(String baseConfig, String overwrite) {
    if (overwrite.trim().isEmpty) return baseConfig;

    var config = baseConfig;

    // Handle scalar key overrides (e.g., mode, log-level, mixed-port)
    final scalarPattern = RegExp(
      r'^([a-z][a-z0-9-]*):\s*(.+)$',
      multiLine: true,
    );
    // Keys that have block children — replacing the top-level line would
    // destroy all child content. These should only be merged, not replaced.
    const blockKeys = {
      'rules', 'proxies', 'proxy-groups', 'dns', 'tun', 'sniffer',
      'hosts', 'tunnels', 'listeners', 'sub-rules',
    };
    for (final match in scalarPattern.allMatches(overwrite)) {
      final key = match.group(1)!;
      final value = match.group(2)!;
      // Skip block-type keys — replacing a scalar line would lose all children
      if (blockKeys.contains(key)) continue;
      final keyRegex = RegExp('^$key:.*\$', multiLine: true);
      if (keyRegex.hasMatch(config)) {
        config = config.replaceAll(keyRegex, '$key: $value');
      } else {
        config += '\n$key: $value\n';
      }
    }

    // Prepend custom rules before existing rules
    final customRules = _extractListBlock(overwrite, 'rules');
    if (customRules.isNotEmpty) {
      config = config.replaceFirstMapped(
        RegExp(r'^(rules:\s*\n)', multiLine: true),
        (m) => '${m.group(1)}$customRules\n',
      );
    }

    // Append custom proxies
    final customProxies = _extractListBlock(overwrite, 'proxies');
    if (customProxies.isNotEmpty) {
      config = _appendToListBlock(config, 'proxies', customProxies);
    }

    // Append custom proxy-groups
    final customGroups = _extractListBlock(overwrite, 'proxy-groups');
    if (customGroups.isNotEmpty) {
      config = _appendToListBlock(config, 'proxy-groups', customGroups);
    }

    // Merge block-type keys: dns, tun, sniffer, hosts, listeners
    // Overwrite entries are injected into the existing block, or appended as
    // a new top-level section if absent.
    for (final blockKey in ['dns', 'tun', 'sniffer', 'hosts', 'listeners']) {
      final customBlock = _extractListBlock(overwrite, blockKey);
      if (customBlock.isNotEmpty) {
        config = _mergeBlockSection(config, blockKey, customBlock);
      }
    }

    return config;
  }

  /// Append entries to an existing YAML list block, or create it if absent.
  static String _appendToListBlock(String config, String key, String entries) {
    final keyPattern = RegExp('^$key:\\s*\\n', multiLine: true);
    final keyMatch = keyPattern.firstMatch(config);
    if (keyMatch != null) {
      // Find the end of the block (next top-level key or EOF) and insert before it
      final afterKey = config.substring(keyMatch.end);
      final nextTopLevel = RegExp(r'^\S', multiLine: true);
      final endMatch = nextTopLevel.firstMatch(afterKey);
      final insertPos =
          endMatch != null ? keyMatch.end + endMatch.start : config.length;
      return '${config.substring(0, insertPos)}$entries\n${config.substring(insertPos)}';
    } else {
      // Section doesn't exist — create it
      return '$config\n$key:\n$entries\n';
    }
  }

  /// Merge a block section (dns, tun, sniffer, etc.) from overwrite into config.
  /// Overwrite child lines are appended into the existing block, or the entire
  /// block is added as a new top-level section if absent in config.
  static String _mergeBlockSection(
      String config, String key, String childLines) {
    final keyPattern = RegExp('^$key:\\s*\\n', multiLine: true);
    final keyMatch = keyPattern.firstMatch(config);
    if (keyMatch != null) {
      // Insert overwrite children at the end of the existing block
      final afterKey = config.substring(keyMatch.end);
      final nextTopLevel = RegExp(r'^\S', multiLine: true);
      final endMatch = nextTopLevel.firstMatch(afterKey);
      final insertPos =
          endMatch != null ? keyMatch.end + endMatch.start : config.length;
      return '${config.substring(0, insertPos)}$childLines\n${config.substring(insertPos)}';
    } else {
      // Section doesn't exist — create it
      return '$config\n$key:\n$childLines\n';
    }
  }

  /// Extract a YAML list block (indented lines) for a given key.
  static String _extractListBlock(String yaml, String key) {
    final keyPattern = RegExp('^$key:', multiLine: true);
    final match = keyPattern.firstMatch(yaml);
    if (match == null) return '';

    final start = match.end;
    final rest = yaml.substring(start);
    final nextTopLevel = RegExp(r'^\S', multiLine: true);
    final endMatch = nextTopLevel.firstMatch(rest);
    final block =
        endMatch != null ? rest.substring(0, endMatch.start) : rest;
    return block.trimRight();
  }
}
