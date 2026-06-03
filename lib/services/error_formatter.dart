import 'package:dio/dio.dart';
import 'json_extractor.dart';

class ErrorFormatter {
  static String format(Object e) {
    if (e is DioException) {
      return _formatDio(e);
    }
    if (e is JsonParseException) {
      return '❌ AI 返回内容无法解析为 JSON，请重试。\n（${e.message}）';
    }
    final msg = e.toString();
    return msg.length > 300 ? '${msg.substring(0, 300)}…' : msg;
  }

  static String _formatDio(DioException e) {
    final status = e.response?.statusCode;
    final actualUrl = e.requestOptions.uri.toString();
    final body = e.response?.data?.toString() ?? '';
    final snippet = body.length > 200 ? '${body.substring(0, 200)}…' : body;

    final header = switch (status) {
      401 => '❌ API Key 无效（401）',
      403 => '❌ 权限不足（403）',
      404 => '❌ 接口不存在（404）',
      422 => '❌ 请求格式有误（422 Unprocessable）',
      429 => '❌ 请求过频（429）',
      500 || 502 || 503 => '❌ 服务器错误（$status）',
      null => '❌ 网络错误：${e.message ?? e.type.name}',
      _ => '❌ HTTP $status',
    };

    return [
      header,
      '实际请求 URL：\n$actualUrl',
      if (snippet.isNotEmpty) '服务器返回：\n$snippet',
    ].join('\n\n');
  }
}
