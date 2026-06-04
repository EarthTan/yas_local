import 'package:dio/dio.dart';
import 'json_extractor.dart';

/// Coarse classification of any failure that can escape a Qwen call.
/// Lives at the boundary so callers can render a short Chinese reason and
/// decide whether to retry.
enum QwenErrorKind {
  network,
  timeout,
  http4xx,
  http5xx,
  jsonParse,
  unknown;

  /// User-facing short label, kept Chinese to match the rest of the UI.
  String get displayName => switch (this) {
        QwenErrorKind.network => '网络未连接',
        QwenErrorKind.timeout => '请求超时',
        QwenErrorKind.http4xx => '接口拒绝 (4xx)',
        QwenErrorKind.http5xx => '服务异常 (5xx)',
        QwenErrorKind.jsonParse => 'JSON 解析错',
        QwenErrorKind.unknown => '未知错误',
      };

  /// 4xx is a configuration / auth problem, never worth auto-retrying.
  bool get shouldRetry => this != QwenErrorKind.http4xx;
}

class QwenError implements Exception {
  final QwenErrorKind kind;
  final Object cause;

  const QwenError(this.kind, this.cause);

  bool get shouldRetry => kind.shouldRetry;

  static QwenError from(Object e) {
    if (e is QwenError) return e;
    if (e is JsonParseException) {
      return QwenError(QwenErrorKind.jsonParse, e);
    }
    if (e is DioException) {
      final status = e.response?.statusCode;
      if (status != null) {
        if (status >= 400 && status < 500) {
          return QwenError(QwenErrorKind.http4xx, e);
        }
        if (status >= 500 && status < 600) {
          return QwenError(QwenErrorKind.http5xx, e);
        }
      }
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return QwenError(QwenErrorKind.timeout, e);
        case DioExceptionType.connectionError:
          return QwenError(QwenErrorKind.network, e);
        case DioExceptionType.badCertificate:
        case DioExceptionType.cancel:
        case DioExceptionType.badResponse:
        case DioExceptionType.unknown:
          return QwenError(QwenErrorKind.unknown, e);
      }
    }
    return QwenError(QwenErrorKind.unknown, e);
  }

  @override
  String toString() => 'QwenError(${kind.name}): $cause';
}
