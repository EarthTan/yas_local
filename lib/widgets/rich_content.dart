import 'package:flutter/material.dart';

/// Converts the app's non-standard LaTeX delimiters to standard ones.
String normalizeLatexDelimiters(String text) {
  if (text.isEmpty) return text;

  // Step 1 (block first): $$$$...$$$$ → \[\n...\n\]
  // [\s\S]*? matches across newlines, non-greedy for multiple blocks.
  var result = text.replaceAllMapped(
    RegExp(r'\$\$\$\$([\s\S]*?)\$\$\$\$'),
    (m) => '\n\\[\n${m[1]!.trim()}\n\\]\n',
  );

  // Step 2 (inline): $$...$$ → \(...\)
  // [^$\n]+ avoids crossing line boundaries or consuming $$$$.
  result = result.replaceAllMapped(
    RegExp(r'\$\$([^$\n]+?)\$\$'),
    (m) => '\\(${m[1]}\\)',
  );

  return result;
}

/// Stub widget — replaced in Task 3.
class RichContent extends StatelessWidget {
  final String text;
  final TextStyle? style;
  const RichContent(this.text, {super.key, this.style});

  @override
  Widget build(BuildContext context) => Text(text, style: style);
}
