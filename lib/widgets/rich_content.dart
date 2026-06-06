import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

/// Converts the app's non-standard LaTeX delimiters to standard ones:
///   $$$$...$$$$  →  \[\n...\n\]  (block, processed first)
///   $$...$$      →  \(...\)      (inline)
///
/// Block pass runs before inline to prevent $$$$...$$$$ being split
/// by the inline rule (since $$$$ starts with $$).
String normalizeLatexDelimiters(String text) {
  if (text.isEmpty) return text;

  // Step 1 (block first): $$$$...$$$$ → \[\n...\n\]
  var result = text.replaceAllMapped(
    RegExp(r'\$\$\$\$([\s\S]*?)\$\$\$\$'),
    (m) => '\n\\[\n${m[1]!.trim()}\n\\]\n',
  );

  // Step 2 (inline): $$...$$ → \(...\)
  // Note: formula content must not contain literal $ characters
  // (rare in standard mathematical notation; no silent crash — raw $$ is
  // passed through to MarkdownBody as plain text if the regex doesn't match).
  result = result.replaceAllMapped(
    RegExp(r'\$\$([^$\n]+?)\$\$'),
    (m) => '\\(${m[1]}\\)',
  );

  return result;
}

// ---------------------------------------------------------------------------
// Block syntax: recognises a line containing only \[ as the start of display
// math, reads until a line containing only \], emits a 'latex-block' element.
//
// The LaTeX content is stored in element.attributes['latex'] so the builder
// can read it without child text nodes (which would require visitText handling
// to avoid leaving orphaned _InlineElement entries in MarkdownBuilder._inlines).
// ---------------------------------------------------------------------------
class _LatexDisplaySyntax extends md.BlockSyntax {
  static final _openPattern = RegExp(r'^\s*\\\[\s*$');
  static final _closePattern = RegExp(r'^\s*\\\]\s*$');

  @override
  RegExp get pattern => _openPattern;

  @override
  bool canParse(md.BlockParser parser) =>
      _openPattern.hasMatch(parser.current.content);

  @override
  md.Node parse(md.BlockParser parser) {
    parser.advance(); // skip \[
    final lines = <String>[];
    while (!parser.isDone &&
        !_closePattern.hasMatch(parser.current.content)) {
      lines.add(parser.current.content);
      parser.advance();
    }
    if (!parser.isDone) {
      parser.advance(); // skip \]
      // Closing \] found — emit as latex-block.
      // Use an empty element with an attribute so no child text nodes are emitted.
      // Child text nodes force MarkdownBuilder to push an _InlineElement into
      // _inlines that must be cleared by _addAnonymousBlockIfNeeded — which only
      // clears when inline.children.isNotEmpty — causing assertion failures.
      final element = md.Element.empty('latex-block');
      element.attributes['latex'] = lines.join('\n').trim();
      return element;
    }
    // No closing \] — emit consumed lines as a plain paragraph to avoid
    // silently dropping document content (e.g. malformed LLM output).
    return md.Element('p', [md.Text(lines.join('\n'))]);
  }
}

// ---------------------------------------------------------------------------
// HTML underline syntax: converts <u>...</u> to an 'underline' element so
// flutter_markdown renders it with TextDecoration.underline rather than
// emitting the raw tag characters as literal text.
// (flutter_markdown 0.7.x has no enableHtml parameter on MarkdownBody.)
// ---------------------------------------------------------------------------
class _HtmlUnderlineSyntax extends md.InlineSyntax {
  // startCharacter: 0x3C ('<') skips the regex on non-'<' characters (perf).
  // MUST be placed before InlineHtmlSyntax in the syntax list so the full
  // <u>...</u> is consumed before InlineHtmlSyntax can grab '<u>' as raw text.
  _HtmlUnderlineSyntax() : super(r'<u>(.*?)</u>', startCharacter: 0x3C);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('underline', match[1]!));
    return true;
  }
}

class _UnderlineBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final style = (parentStyle ?? preferredStyle ?? const TextStyle()).copyWith(
      decoration: TextDecoration.underline,
    );
    return Text.rich(TextSpan(text: element.textContent, style: style));
  }
}

// ---------------------------------------------------------------------------
// Inline syntax: recognises \(...\) as inline math, emits 'latex-inline'.
// ---------------------------------------------------------------------------
class _LatexInlineSyntax extends md.InlineSyntax {
  _LatexInlineSyntax() : super(r'\\\((.+?)\\\)');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final element = md.Element.text('latex-inline', match[1]!);
    parser.addNode(element);
    return true;
  }
}

// ---------------------------------------------------------------------------
// Block math builder: renders latex-block elements as display Math widgets.
// MUST override isBlockElement() → true so flutter_markdown registers the
// 'latex-block' tag in _kBlockTags, preventing the null-tag crash when
// a block-level LaTeX element appears at document root.
// ---------------------------------------------------------------------------
class _BlockMathBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final latex = element.attributes['latex'] ?? element.textContent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Math.tex(
          latex,
          mathStyle: MathStyle.display,
          textStyle: preferredStyle,
          onErrorFallback: (e) => SelectableText(
            latex,
            style: (preferredStyle ?? const TextStyle()).copyWith(
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Inline math builder: renders latex-inline elements as text Math widgets.
// isBlockElement() stays false (default) — inline math lives inside paragraphs.
// ---------------------------------------------------------------------------
class _InlineMathBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final latex = element.textContent;
    return Math.tex(
      latex,
      mathStyle: MathStyle.text,
      textStyle: parentStyle ?? preferredStyle,
      onErrorFallback: (e) => SelectableText(
        latex,
        style: (parentStyle ?? preferredStyle ?? const TextStyle()).copyWith(
          color: Colors.grey[600],
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

// Module-level constants — created once, shared across all RichContent builds.
final _blockMathBuilder = _BlockMathBuilder();
final _inlineMathBuilder = _InlineMathBuilder();
final _underlineBuilder = _UnderlineBuilder();

final _mathExtensionSet = md.ExtensionSet(
  [
    ...md.ExtensionSet.gitHubFlavored.blockSyntaxes,
    _LatexDisplaySyntax(),
  ],
  [
    // _HtmlUnderlineSyntax must come FIRST — before InlineHtmlSyntax (from
    // gitHubFlavored) so it matches full <u>...</u> before InlineHtmlSyntax
    // can grab the opening '<u>' tag as a raw text node.
    _HtmlUnderlineSyntax(),
    ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
    _LatexInlineSyntax(),
  ],
);

// ---------------------------------------------------------------------------
// RichContent: the single public widget.
// ---------------------------------------------------------------------------

/// Renders AI-generated text containing Markdown and LaTeX.
///
/// Drop-in replacement for [Text] / [SelectableText] wherever the app
/// displays content from the VLM (question stems, checkpoint descriptions,
/// extracted answers, AI comments, reasoning).
///
/// Supported formats:
///   Markdown: **bold**, <u>underline</u> (HTML)
///   Inline LaTeX: $$formula$$
///   Block/display LaTeX: $$$$formula$$$$
///
/// Always selectable — long-press to copy.
class RichContent extends StatelessWidget {
  final String text;

  /// Overrides the paragraph text style (font size, color, etc.).
  /// Markdown-driven bold/italic layered on top.
  final TextStyle? style;

  const RichContent(this.text, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    final normalized = normalizeLatexDelimiters(text);
    final baseStyle =
        style ?? Theme.of(context).textTheme.bodyMedium ?? const TextStyle();

    return MarkdownBody(
      data: normalized,
      selectable: true,
      extensionSet: _mathExtensionSet,
      builders: {
        'latex-block': _blockMathBuilder,
        'latex-inline': _inlineMathBuilder,
        'underline': _underlineBuilder,
      },
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: baseStyle,
      ),
    );
  }
}
