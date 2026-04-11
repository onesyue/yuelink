import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';

/// Renders server-provided content (HTML / Markdown / plain text) safely.
///
/// XBoard backend typically returns HTML from its rich-text editor. This widget
/// uses flutter_widget_from_html_core which is lightweight (no WebView) and
/// handles common tags: p, h1-h6, br, hr, strong/b, em/i, code, pre, ul/ol/li,
/// a, img, table, blockquote, etc.
///
/// Usage:
/// ```dart
/// RichContent(content: announcement.content)
/// RichContent(content: plan.content, maxLines: 3)
/// ```
class RichContent extends StatelessWidget {
  final String? content;

  /// Optional max lines — truncates with "..." when exceeded.
  /// null = show all content.
  final int? maxLines;

  /// Text style override for body text.
  final TextStyle? textStyle;

  /// Whether to make the widget selectable.
  final bool selectable;

  const RichContent({
    super.key,
    required this.content,
    this.maxLines,
    this.textStyle,
    this.selectable = false,
  });

  @override
  Widget build(BuildContext context) {
    final raw = content?.trim();
    if (raw == null || raw.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bodyColor = isDark ? YLColors.zinc300 : YLColors.zinc700;
    final linkColor = isDark ? YLColors.primary : YLColors.primary;
    final codeColor = isDark ? const Color(0xFF27272A) : const Color(0xFFF4F4F5);

    final baseStyle = textStyle ??
        YLText.body.copyWith(
          color: bodyColor,
          fontSize: 14,
          height: 1.6,
        );

    // If maxLines is set and content looks like plain text (no tags), use Text
    // for proper ellipsis. HtmlWidget doesn't support maxLines natively.
    if (maxLines != null && !_looksLikeHtml(raw)) {
      return Text(
        raw,
        style: baseStyle,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      );
    }

    // Wrap plain text in <p> if it has no HTML tags at all.
    final html = _looksLikeHtml(raw) ? raw : _plainToHtml(raw);

    return HtmlWidget(
      html,
      textStyle: baseStyle,
      onTapUrl: (url) {
        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        return true;
      },
      customStylesBuilder: (element) {
        switch (element.localName) {
          case 'a':
            return {'color': _colorToCss(linkColor), 'text-decoration': 'none'};
          case 'code':
            return {
              'background-color': _colorToCss(codeColor),
              'padding': '2px 6px',
              'border-radius': '4px',
              'font-size': '13px',
            };
          case 'pre':
            return {
              'background-color': _colorToCss(codeColor),
              'padding': '12px',
              'border-radius': '8px',
              'overflow-x': 'auto',
            };
          case 'blockquote':
            return {
              'border-left': '3px solid ${_colorToCss(YLColors.zinc400)}',
              'padding-left': '12px',
              'margin': '8px 0',
              'color': _colorToCss(YLColors.zinc500),
            };
          case 'h1':
            return {'font-size': '20px', 'font-weight': '600'};
          case 'h2':
            return {'font-size': '18px', 'font-weight': '600'};
          case 'h3':
            return {'font-size': '16px', 'font-weight': '600'};
          default:
            return null;
        }
      },
    );
  }

  /// Check if content contains HTML tags.
  static final _htmlTagRegex = RegExp(r'<[a-zA-Z][^>]*>');
  static bool _looksLikeHtml(String s) => _htmlTagRegex.hasMatch(s);

  /// Convert plain text with newlines to basic HTML.
  static String _plainToHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .split('\n')
        .map((line) => line.isEmpty ? '<br>' : '<p>$line</p>')
        .join();
  }

  static String _colorToCss(Color c) =>
      'rgba(${(c.r * 255).round()},${(c.g * 255).round()},${(c.b * 255).round()},${c.a.toStringAsFixed(2)})';
}
