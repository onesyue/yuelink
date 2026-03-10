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
    for (final match in scalarPattern.allMatches(overwrite)) {
      final key = match.group(1)!;
      final value = match.group(2)!;
      // Skip list-type keys — handled separately
      if (key == 'rules' || key == 'proxies' || key == 'proxy-groups') {
        continue;
      }
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
      config = config.replaceFirstMapped(
        RegExp(r'^(proxies:\s*\n)', multiLine: true),
        (m) {
          // Find end of proxies block and append
          return '${m.group(1)}$customProxies\n';
        },
      );
    }

    return config;
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
