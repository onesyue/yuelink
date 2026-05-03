import 'yaml_indent_detector.dart';

class ProviderProxyTransformer {
  const ProviderProxyTransformer._();

  /// Force every `proxy-providers` and `rule-providers` entry that
  /// hasn't explicitly chosen a fetch route to use `proxy: DIRECT`.
  static String ensureProviderProxyDirect(String config) {
    config = _injectProxyDirectInBlock(config, 'proxy-providers');
    config = _injectProxyDirectInBlock(config, 'rule-providers');
    return config;
  }

  /// Inject `proxy: DIRECT` into every entry under the named top-level
  /// providers block that doesn't already declare a `proxy:` field.
  static String _injectProxyDirectInBlock(String config, String blockName) {
    final range = YamlIndentDetector.findTopLevelSection(
      config,
      blockName,
      topLevelCommentsEndSection: true,
      requireBlockHeader: true,
    );
    if (range == null) return config;

    final blockStart = range.bodyStart;
    final blockEnd = range.end;
    final body = range.body;
    if (body.trim().isEmpty) return config;

    final entryIndent = YamlIndentDetector.detectChildIndent(
      body,
      fallback: '',
      allowTabs: true,
    );
    if (entryIndent.isEmpty) return config;
    final entryIndentEsc = RegExp.escape(entryIndent);

    final inlineRe = RegExp(
      r'^(' + entryIndentEsc + r')([\w.\-]+):\s*\{([^}]*)\}(\s*)$',
    );
    final blockHeadRe = RegExp(r'^(' + entryIndentEsc + r')([\w.\-]+):\s*$');
    final inlineHasProxy = RegExp(r'(?:^|,)\s*proxy\s*:');

    final lines = body.split('\n');
    final out = <String>[];
    var i = 0;
    var changed = false;

    while (i < lines.length) {
      final line = lines[i];

      final inline = inlineRe.firstMatch(line);
      if (inline != null) {
        final inner = inline.group(3)!;
        if (inlineHasProxy.hasMatch(inner)) {
          out.add(line);
        } else {
          final cleanedInner = inner.replaceAll(RegExp(r',?\s*$'), '');
          final trimmedLeft = cleanedInner.trimLeft();
          final newInner = trimmedLeft.isEmpty
              ? ' proxy: DIRECT '
              : ' ${cleanedInner.trimLeft()}, proxy: DIRECT ';
          out.add(
            '${inline.group(1)}${inline.group(2)}: '
            '{$newInner}${inline.group(4)}',
          );
          changed = true;
        }
        i++;
        continue;
      }

      final blockHead = blockHeadRe.firstMatch(line);
      if (blockHead != null) {
        final children = <String>[];
        var j = i + 1;
        while (j < lines.length) {
          final next = lines[j];
          if (next.isEmpty) {
            children.add(next);
            j++;
            continue;
          }
          final ind = RegExp(r'^[ \t]*').firstMatch(next)!.group(0)!;
          final isBlank = next.trim().isEmpty;
          if (isBlank || ind.length > entryIndent.length) {
            children.add(next);
            j++;
          } else {
            break;
          }
        }

        final hasProxy = children.any(
          (c) => RegExp(r'^\s+proxy\s*:').hasMatch(c),
        );
        final realChildren = children
            .where((c) => c.trim().isNotEmpty)
            .toList(growable: false);

        out.add(line);
        if (!hasProxy && realChildren.isNotEmpty) {
          var lastReal = children.length - 1;
          while (lastReal >= 0 && children[lastReal].trim().isEmpty) {
            lastReal--;
          }
          final childIndent =
              RegExp(r'^[ \t]+').firstMatch(realChildren.first)?.group(0) ??
              ('$entryIndent  ');
          out.addAll(children.sublist(0, lastReal + 1));
          out.add('${childIndent}proxy: DIRECT');
          out.addAll(children.sublist(lastReal + 1));
          changed = true;
        } else {
          out.addAll(children);
        }
        i = j;
        continue;
      }

      out.add(line);
      i++;
    }

    if (!changed) return config;

    return config.substring(0, blockStart) +
        out.join('\n') +
        config.substring(blockEnd);
  }
}
