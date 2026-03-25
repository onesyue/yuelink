import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../theme.dart';

/// Native in-app content page — fetches HTML from [url] and renders it as
/// styled Flutter widgets.  No WebView dependency.
class InAppWebPage extends StatefulWidget {
  final String title;
  final String url;

  const InAppWebPage({super.key, required this.title, required this.url});

  @override
  State<InAppWebPage> createState() => _InAppWebPageState();
}

class _InAppWebPageState extends State<InAppWebPage> {
  bool _loading = true;
  String? _error;
  List<_Block> _blocks = [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      final request = await client.getUrl(Uri.parse(widget.url));
      final response = await request.close();
      final html = await response.transform(utf8.decoder).join();
      client.close();
      if (!mounted) return;
      setState(() {
        _blocks = _parseHtml(html);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载失败: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? YLColors.bgDark : YLColors.bgLight,
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(widget.title),
        backgroundColor: isDark ? YLColors.bgDark : YLColors.bgLight,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!,
                          style: TextStyle(color: YLColors.zinc500),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton.tonal(
                          onPressed: _fetch, child: const Text('重试')),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                  itemCount: _blocks.length,
                  itemBuilder: (_, i) => _buildBlock(_blocks[i], isDark),
                ),
    );
  }

  Widget _buildBlock(_Block block, bool isDark) {
    final textColor = isDark ? YLColors.zinc200 : YLColors.zinc800;
    final dimColor = isDark ? YLColors.zinc400 : YLColors.zinc500;

    switch (block.type) {
      case _BlockType.h1:
        return Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 12),
          child: Text(block.text,
              style: YLText.titleLarge.copyWith(
                  fontWeight: FontWeight.w700, color: textColor)),
        );
      case _BlockType.h2:
        return Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Text(block.text,
              style: YLText.titleMedium.copyWith(
                  fontWeight: FontWeight.w600, color: textColor)),
        );
      case _BlockType.h3:
        return Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 6),
          child: Text(block.text,
              style: YLText.label.copyWith(
                  fontWeight: FontWeight.w600, color: textColor)),
        );
      case _BlockType.li:
        return Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('•  ', style: TextStyle(color: dimColor, fontSize: 14)),
              Expanded(
                child: _buildRichText(block.text, textColor, dimColor),
              ),
            ],
          ),
        );
      case _BlockType.hr:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Divider(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.08)),
        );
      case _BlockType.p:
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _buildRichText(block.text, textColor, dimColor),
        );
    }
  }

  /// Render inline <strong>/<b>/<em>/<i>/<code> as styled spans.
  Widget _buildRichText(String text, Color color, Color dimColor) {
    final spans = <InlineSpan>[];
    final re = RegExp(
        r'<(strong|b|em|i|code)>(.*?)</\1>',
        dotAll: true);
    var pos = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > pos) {
        spans.add(InlineSpan(text.substring(pos, m.start)));
      }
      final tag = m.group(1)!;
      final inner = m.group(2)!;
      spans.add(InlineSpan(inner, bold: tag == 'strong' || tag == 'b',
          italic: tag == 'em' || tag == 'i', code: tag == 'code'));
      pos = m.end;
    }
    if (pos < text.length) spans.add(InlineSpan(text.substring(pos)));

    return RichText(
      text: TextSpan(
        style: YLText.body.copyWith(color: color, height: 1.6),
        children: spans.map((s) {
          FontWeight? fw;
          FontStyle? fs;
          Color? c;
          if (s.bold) fw = FontWeight.w600;
          if (s.italic) fs = FontStyle.italic;
          if (s.code) c = dimColor;
          return TextSpan(
            text: s.text,
            style: TextStyle(fontWeight: fw, fontStyle: fs, color: c,
                fontFamily: s.code ? 'monospace' : null),
          );
        }).toList(),
      ),
    );
  }
}

// ── Simple HTML parser ─────────────────────────────────────────────────────────

enum _BlockType { h1, h2, h3, p, li, hr }

class _Block {
  final _BlockType type;
  final String text;
  _Block(this.type, this.text);
}

class InlineSpan {
  final String text;
  final bool bold;
  final bool italic;
  final bool code;
  InlineSpan(this.text, {this.bold = false, this.italic = false, this.code = false});
}

/// Parses basic HTML into a list of blocks.
/// Handles: h1-h3, p, li/ul/ol, hr, br, strong/b/em/i/code (inline kept for rendering).
List<_Block> _parseHtml(String html) {
  // Extract <body> content if present
  final bodyMatch = RegExp(r'<body[^>]*>(.*)</body>', dotAll: true).firstMatch(html);
  var content = bodyMatch?.group(1) ?? html;

  // Remove <style>, <script>, <!-- comments -->
  content = content.replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), '');
  content = content.replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), '');
  content = content.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

  final blocks = <_Block>[];
  final tagRe = RegExp(
      r'<(h[1-3]|p|li|hr|br|div|ul|ol|/ul|/ol|/div)(?:\s[^>]*)?\s*/?>',
      caseSensitive: false);

  var pos = 0;
  _BlockType? currentType;
  final buf = StringBuffer();

  void flush() {
    final text = _cleanText(buf.toString());
    if (text.isNotEmpty && currentType != null) {
      blocks.add(_Block(currentType!, text));
    }
    buf.clear();
    currentType = null;
  }

  for (final m in tagRe.allMatches(content)) {
    // Text before this tag
    if (m.start > pos) {
      buf.write(content.substring(pos, m.start));
    }
    pos = m.end;

    final tag = m.group(1)!.toLowerCase();
    switch (tag) {
      case 'h1':
        flush();
        currentType = _BlockType.h1;
      case 'h2':
        flush();
        currentType = _BlockType.h2;
      case 'h3':
        flush();
        currentType = _BlockType.h3;
      case 'p':
      case 'div':
        flush();
        currentType = _BlockType.p;
      case 'li':
        flush();
        currentType = _BlockType.li;
      case 'hr':
        flush();
        blocks.add(_Block(_BlockType.hr, ''));
      case 'br':
        buf.write('\n');
      case 'ul':
      case 'ol':
      case '/ul':
      case '/ol':
      case '/div':
        flush();
    }
  }

  // Trailing text
  if (pos < content.length) {
    buf.write(content.substring(pos));
  }
  flush();

  // If nothing was parsed (e.g. plain text without tags), treat whole as one paragraph
  if (blocks.isEmpty) {
    final text = _cleanText(content);
    if (text.isNotEmpty) blocks.add(_Block(_BlockType.p, text));
  }

  return blocks;
}

/// Strip closing tags, collapse whitespace, decode basic HTML entities.
String _cleanText(String raw) {
  var s = raw;
  // Remove closing tags (keep inline tags like <strong>/<em>/<code> intact)
  s = s.replaceAll(RegExp(r'</(?:h[1-6]|p|li|div|ul|ol|tr|td|th|table|thead|tbody)>', caseSensitive: false), '');
  // Remove remaining block-level opening tags we didn't catch
  s = s.replaceAll(RegExp(r'<(?:span|a|img|sup|sub|abbr|mark)[^>]*>', caseSensitive: false), '');
  s = s.replaceAll(RegExp(r'</(?:span|a|sup|sub|abbr|mark)>', caseSensitive: false), '');
  // Collapse whitespace
  s = s.replaceAll(RegExp(r'[ \t]+'), ' ');
  s = s.replaceAll(RegExp(r'\n\s*\n'), '\n');
  // Decode common entities
  s = s.replaceAll('&amp;', '&')
       .replaceAll('&lt;', '<')
       .replaceAll('&gt;', '>')
       .replaceAll('&quot;', '"')
       .replaceAll('&#39;', "'")
       .replaceAll('&nbsp;', ' ')
       .replaceAll('&mdash;', '—')
       .replaceAll('&ndash;', '–')
       .replaceAll('&hellip;', '…')
       .replaceAll('&copy;', '©');
  // Numeric entities
  s = s.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
    final code = int.tryParse(m.group(1)!);
    return code != null ? String.fromCharCode(code) : m.group(0)!;
  });
  return s.trim();
}
