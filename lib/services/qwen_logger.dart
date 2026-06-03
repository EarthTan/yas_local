import 'dart:io';

class QwenLogger {
  static File? _file;

  static File get _logFile {
    if (_file == null) {
      final logDir = Directory('log');
      if (!logDir.existsSync()) {
        logDir.createSync(recursive: true);
      }
      final date = DateTime.now().toIso8601String().substring(0, 10);
      _file = File('log/qwen_$date.log');
    }
    return _file!;
  }

  static void log(String message) {
    try {
      final file = _logFile;
      final ts = DateTime.now().toIso8601String();
      file.writeAsStringSync('[$ts] $message\n', mode: FileMode.append);
    } catch (_) {
      // Logging must never crash the app
    }
  }

  static void logRound({
    required String model,
    required String endpoint,
    required List<Map<String, dynamic>> messages,
    required String responseContent,
    String? reasoningContent,
    int? statusCode,
  }) {
    try {
      final buf = StringBuffer();
      buf.writeln('=' * 80);
      buf.writeln('MODEL: $model | ENDPOINT: $endpoint | STATUS: ${statusCode ?? "?"}');
      buf.writeln('-' * 80);

      for (final m in messages) {
        final role = (m['role'] ?? '?').toString().padRight(10);
        final content = m['content'];
        if (content is List) {
          final textParts = content
              .whereType<Map>()
              .map((e) => e['text'])
              .whereType<String>()
              .join(' | ');
          final imgCount =
              content.whereType<Map>().where((e) => e['type'] == 'image_url').length;
          buf.writeln('[$role] ($imgCount images) $textParts');
        } else {
          buf.writeln('[$role] ${content ?? ""}');
        }
      }

      buf.writeln('${'-' * 40} RESPONSE ${'-' * 40}');
      if (reasoningContent != null) {
        buf.writeln('[reasoning] $reasoningContent');
      }
      buf.writeln('[content] $responseContent');
      buf.writeln('=' * 80);

      log(buf.toString());
    } catch (_) {}
  }
}
