import 'dart:io';
import 'package:path_provider/path_provider.dart';

class QwenLogger {
  static const int _maxBytesPerFile = 5 * 1024 * 1024;
  static Directory? _dir;

  static Future<Directory> _ensureDir() async {
    final cached = _dir;
    if (cached != null) return cached;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/log');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _dir = dir;
    return dir;
  }

  static Future<File> _pickFile() async {
    final dir = await _ensureDir();
    final date = DateTime.now().toIso8601String().substring(0, 10);
    final primary = File('${dir.path}/qwen_$date.log');
    if (!primary.existsSync()) return primary;
    if (primary.lengthSync() < _maxBytesPerFile) return primary;
    for (var i = 1; i < 100; i++) {
      final candidate = File('${dir.path}/qwen_$date.$i.log');
      if (!candidate.existsSync()) return candidate;
    }
    return primary;
  }

  static Future<void> _writeBlock(String block) async {
    try {
      final f = await _pickFile();
      await f.writeAsString(block, mode: FileMode.append, flush: false);
    } catch (_) {
      // Logging must never crash the app
    }
  }

  static String get _ts => DateTime.now().toIso8601String();

  static void _writeMessages(StringBuffer buf, List<dynamic> messages) {
    for (final m in messages) {
      final role = (m is Map ? m['role'] : null)?.toString() ?? '?';
      final padded = role.padRight(10);
      final content = m is Map ? m['content'] : null;
      if (content is List) {
        final textParts = content
            .whereType<Map>()
            .map((e) => e['text'])
            .whereType<String>()
            .where((t) => !t.startsWith('data:'))
            .join(' | ');
        final imgCount = content
            .whereType<Map>()
            .where((e) => e['type'] == 'image_url')
            .length;
        buf.writeln('[$padded] ($imgCount images) $textParts');
      } else {
        buf.writeln('[$padded] ${content ?? ""}');
      }
    }
  }

  static Future<void> logSuccess({
    required String model,
    required String endpoint,
    required List<Map<String, dynamic>> messages,
    required String responseContent,
    String? reasoningContent,
    int? statusCode,
    int elapsedMs = 0,
  }) async {
    final buf = StringBuffer()
      ..writeln('=' * 80)
      ..writeln(
          '[$_ts] MODEL: $model | ENDPOINT: $endpoint | STATUS: ${statusCode ?? "?"} | ELAPSED: ${elapsedMs}ms')
      ..writeln('-' * 80);
    _writeMessages(buf, messages);
    buf
      ..writeln('${'-' * 40} RESPONSE ${'-' * 40}')
      ..writeln('[reasoning] ${reasoningContent ?? ""}')
      ..writeln('[content] $responseContent')
      ..writeln('=' * 80);
    await _writeBlock(buf.toString());
  }

  static Future<void> logError({
    required String endpoint,
    required int? statusCode,
    required String errorType,
    required String message,
    String? requestSummary,
    String? responseSnippet,
    int elapsedMs = 0,
  }) async {
    final buf = StringBuffer()
      ..writeln('=' * 80)
      ..writeln(
          '[$_ts] ERROR | ENDPOINT: $endpoint | STATUS: ${statusCode ?? "?"} | ELAPSED: ${elapsedMs}ms')
      ..writeln('TYPE: $errorType')
      ..writeln('MESSAGE: $message');
    if (requestSummary != null && requestSummary.isNotEmpty) {
      buf.writeln('REQUEST: $requestSummary');
    }
    if (responseSnippet != null && responseSnippet.isNotEmpty) {
      buf.writeln('RESPONSE: $responseSnippet');
    }
    buf.writeln('=' * 80);
    await _writeBlock(buf.toString());
  }
}
