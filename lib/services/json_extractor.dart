import 'dart:convert';

import 'debug_service.dart';

/// Thrown when AI response text cannot be parsed into the expected JSON shape.
class JsonParseException implements Exception {
  final String message;
  final String rawContent;

  const JsonParseException(this.message, {required this.rawContent});

  @override
  String toString() {
    final snippet = rawContent.length > 300
        ? '${rawContent.substring(0, 300)}…'
        : rawContent;
    return 'JsonParseException: $message\n--- raw content ---\n$snippet';
  }
}

/// Result of [JsonExtractor.requireObjectWithReasoning]: the extracted JSON
/// object plus any reasoning text the model emitted inside a `<think>…</think>`
/// or `<thinking>…</thinking>` block.
class ExtractionResult {
  final String? reasoning;
  final Map<String, dynamic> json;

  const ExtractionResult({this.reasoning, required this.json});
}

/// List counterpart of [ExtractionResult] returned by
/// [JsonExtractor.requireListWithReasoning].
class ExtractionListResult {
  final String? reasoning;
  final List<dynamic> list;

  const ExtractionListResult({this.reasoning, required this.list});
}

/// Robust JSON extraction from raw LLM response text.
///
/// Strategy (applied in order for each method):
/// 1. Strip `<think>…</think>` reasoning blocks.
/// 2. Try every ```json``` / ``` code-fence block in document order —
///    first one that parses successfully wins.
/// 3. Fall back to bracket-matching the entire cleaned text.
/// 4. Throw [JsonParseException] with the full raw content for debugging.
class JsonExtractor {
  JsonExtractor._();

  /// Returns the first valid JSON object found in [text].
  ///
  /// Throws [JsonParseException] if no object can be extracted.
  static Map<String, dynamic> requireObject(String text) {
    final builder = JsonAttemptBuilder(scope: 'caller', input: text);
    try {
      final cleaned = _stripThinking(text);
      builder.record('strip_thinking', ok: true);

      for (final block in _codeFenceContents(cleaned)) {
        final result = _tryObject(block);
        if (result != null) {
          builder.record('fence_object', ok: true);
          builder.commit();
          return result;
        }
        builder.record('fence_object', ok: false, error: 'parse failed');
      }

      final result = _tryObject(cleaned);
      if (result != null) {
        builder.record('braces_object', ok: true);
        builder.commit();
        return result;
      }

      builder.record('braces_object', ok: false, error: 'no { found');
      builder.markFailed('JsonParseException: no object found');
      builder.commit();
      throw JsonParseException(
        'No valid JSON object found in AI response.',
        rawContent: text,
      );
    } catch (e) {
      if (e is! JsonParseException) {
        builder.markFailed(e.toString());
        builder.commit();
      } else {
        // Already marked above
      }
      rethrow;
    }
  }

  /// Returns the first valid JSON list found in [text].
  ///
  /// For each candidate (code-fence blocks then full text), the search order is:
  /// 1. Parse as object and return `candidate[fromKey]` if it is a [List].
  /// 2. Parse as a bare list.
  ///
  /// Throws [JsonParseException] if no list can be extracted.
  static List<dynamic> requireList(String text, {String? fromKey}) {
    final builder = JsonAttemptBuilder(scope: 'caller', input: text);
    try {
      final cleaned = _stripThinking(text);
      builder.record('strip_thinking', ok: true);

      for (final block in _codeFenceContents(cleaned)) {
        if (fromKey != null) {
          final obj = _tryObject(block);
          if (obj != null && obj[fromKey] is List) {
            builder.record('fence_object_with_fromKey', ok: true);
            builder.commit();
            return obj[fromKey] as List<dynamic>;
          }
          if (obj != null) {
            builder.record('fence_object_with_fromKey',
                ok: false, error: 'key missing or not a list');
          }
        }
        final list = _tryList(block);
        if (list != null) {
          builder.record('fence_list', ok: true);
          builder.commit();
          return list;
        }
        builder.record('fence_list', ok: false, error: 'parse failed');
      }

      if (fromKey != null) {
        final obj = _tryObject(cleaned);
        if (obj != null && obj[fromKey] is List) {
          builder.record('braces_object_with_fromKey', ok: true);
          builder.commit();
          return obj[fromKey] as List<dynamic>;
        }
        if (obj != null) {
          builder.record('braces_object_with_fromKey',
              ok: false, error: 'key missing or not a list');
        }
      }
      final result = _tryList(cleaned);
      if (result != null) {
        builder.record('braces_list', ok: true);
        builder.commit();
        return result;
      }

      builder.record('braces_list', ok: false, error: 'no [ found');
      builder.markFailed('JsonParseException: no list found');
      builder.commit();
      throw JsonParseException(
        'No valid JSON list found in AI response.',
        rawContent: text,
      );
    } catch (e) {
      if (e is! JsonParseException) {
        builder.markFailed(e.toString());
        builder.commit();
      }
      rethrow;
    }
  }

  /// Returns the JSON object plus any reasoning text wrapped in
  /// `<think>…</think>` or `<thinking>…</thinking>` (case-insensitive).
  ///
  /// If no reasoning block is found, [ExtractionResult.reasoning] is null.
  /// The reasoning block is stripped before JSON extraction, so the
  /// surrounding text can be in any format (raw JSON, ```json``` fenced, or
  /// mixed with prose).
  ///
  /// Throws [JsonParseException] if no object can be extracted.
  static ExtractionResult requireObjectWithReasoning(String text) {
    final (reasoning, rest) = _splitReasoning(text);
    return ExtractionResult(reasoning: reasoning, json: requireObject(rest));
  }

  /// List counterpart of [requireObjectWithReasoning]. See that method for
  /// the reasoning-block format. When [fromKey] is given and the response
  /// is an object, the value at that key is returned (same convention as
  /// [requireList]).
  static ExtractionListResult requireListWithReasoning(
    String text, {
    String? fromKey,
  }) {
    final (reasoning, rest) = _splitReasoning(text);
    return ExtractionListResult(
      reasoning: reasoning,
      list: requireList(rest, fromKey: fromKey),
    );
  }

  // ── internal helpers ────────────────────────────────────────────────────────

  /// Splits [text] into (reasoning, remaining). The reasoning block must use
  /// matching open/close tags: `<think>…</think>` or `<thinking>…</thinking>`
  /// (case-insensitive). Returns null for reasoning if no block is found.
  static (String?, String) _splitReasoning(String text) {
    final pattern = RegExp(
      r'<(think|thinking)>([\s\S]*?)</\1>',
      caseSensitive: false,
    );
    final match = pattern.firstMatch(text);
    if (match == null) return (null, text);
    return (
      match.group(2)?.trim(),
      text.replaceFirst(match.group(0)!, '').trim(),
    );
  }

  static String _stripThinking(String text) =>
      text.replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '').trim();

  /// Returns the trimmed contents of every ` ```json ``` ` or ` ``` ``` ` block,
  /// in document order.
  static List<String> _codeFenceContents(String text) {
    final results = <String>[];
    final pattern = RegExp(r'```(?:json)?\s*\n([\s\S]*?)```');
    for (final m in pattern.allMatches(text)) {
      final content = m.group(1)?.trim();
      if (content != null && content.isNotEmpty) results.add(content);
    }
    return results;
  }

  static Map<String, dynamic>? _tryObject(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) return null;
    try {
      return jsonDecode(text.substring(start, end + 1)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static List<dynamic>? _tryList(String text) {
    final start = text.indexOf('[');
    final end = text.lastIndexOf(']');
    if (start == -1 || end == -1 || end <= start) return null;
    try {
      return jsonDecode(text.substring(start, end + 1)) as List<dynamic>;
    } catch (_) {
      return null;
    }
  }
}
