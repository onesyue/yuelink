/// Check if a top-level YAML key exists at column 0.
bool hasKey(String config, String key) {
  return RegExp('^${RegExp.escape(key)}:', multiLine: true).hasMatch(config);
}

/// Replace the value of a top-level scalar key.
String replaceScalar(String config, String key, String value) {
  return config.replaceAll(
    RegExp('^${RegExp.escape(key)}:.*\$', multiLine: true),
    '$key: $value',
  );
}

/// Strip the header line from a section that still includes its `key:` prefix.
String bodyOf(String section) {
  final firstNewline = section.indexOf('\n');
  if (firstNewline < 0) return '';
  return section.substring(firstNewline + 1);
}
