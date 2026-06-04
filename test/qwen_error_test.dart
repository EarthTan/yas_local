import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/services/json_extractor.dart';
import 'package:yas_local/services/qwen_error.dart';

void main() {
  group('QwenError.from', () {
    test('connectionError DioException -> network', () {
      final e = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.connectionError,
      );
      final q = QwenError.from(e);
      expect(q.kind, QwenErrorKind.network);
    });

    test('connectionTimeout -> timeout', () {
      final e = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.connectionTimeout,
      );
      expect(QwenError.from(e).kind, QwenErrorKind.timeout);
    });

    test('receiveTimeout -> timeout', () {
      final e = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.receiveTimeout,
      );
      expect(QwenError.from(e).kind, QwenErrorKind.timeout);
    });

    test('status 401 -> http4xx', () {
      final e = DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 401,
        ),
        type: DioExceptionType.badResponse,
      );
      final q = QwenError.from(e);
      expect(q.kind, QwenErrorKind.http4xx);
      expect(q.shouldRetry, isFalse);
    });

    test('status 429 -> http4xx (do not retry)', () {
      final e = DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 429,
        ),
        type: DioExceptionType.badResponse,
      );
      expect(QwenError.from(e).shouldRetry, isFalse);
    });

    test('status 500 -> http5xx', () {
      final e = DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 500,
        ),
        type: DioExceptionType.badResponse,
      );
      expect(QwenError.from(e).kind, QwenErrorKind.http5xx);
      expect(QwenError.from(e).shouldRetry, isTrue);
    });

    test('status 503 -> http5xx', () {
      final e = DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 503,
        ),
        type: DioExceptionType.badResponse,
      );
      expect(QwenError.from(e).kind, QwenErrorKind.http5xx);
    });

    test('JsonParseException -> jsonParse, retryable', () {
      final e = JsonParseException('bad', rawContent: 'x');
      final q = QwenError.from(e);
      expect(q.kind, QwenErrorKind.jsonParse);
      expect(q.shouldRetry, isTrue);
    });

    test('unknown exception -> unknown, retryable (conservative)', () {
      final q = QwenError.from(StateError('whatever'));
      expect(q.kind, QwenErrorKind.unknown);
      expect(q.shouldRetry, isTrue);
    });
  });

  group('displayName', () {
    test('returns Chinese label per kind', () {
      expect(QwenErrorKind.network.displayName, '网络未连接');
      expect(QwenErrorKind.timeout.displayName, '请求超时');
      expect(QwenErrorKind.http4xx.displayName, '接口拒绝 (4xx)');
      expect(QwenErrorKind.http5xx.displayName, '服务异常 (5xx)');
      expect(QwenErrorKind.jsonParse.displayName, 'JSON 解析错');
      expect(QwenErrorKind.unknown.displayName, '未知错误');
    });
  });
}
