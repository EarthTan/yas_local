import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/settings.dart';
import 'package:yas_local/services/debug_service.dart';
import 'package:yas_local/services/json_extractor.dart';
import 'package:yas_local/services/qwen_service.dart';

class _MockAdapter implements HttpClientAdapter {
  _MockAdapter(this._handler);
  final ResponseBody Function(RequestOptions options) _handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return _handler(options);
  }
}

ResponseBody _okJson(RequestOptions options) {
  // identifyQuestions expects a "questions" list — return a valid one.
  return ResponseBody.fromString(
    '{"choices":[{"message":{"content":"{\\"questions\\": []}","role":"assistant"}}]}',
    200,
    headers: {
      'content-type': ['application/json'],
    },
  );
}

ResponseBody _errJson(RequestOptions options) {
  return ResponseBody.fromString(
    '{"error":"server"}',
    500,
    headers: {
      'content-type': ['application/json'],
    },
  );
}

void main() {
  setUp(() {
    DebugService.instance.resetForTest();
  });

  test('successful call records a QwenCallRecord with status=ok and scope from extra', () async {
    DebugService.instance.setEnabled(true);
    final s = const AppSettings(apiKey: 'k', baseUrl: 'https://example.test/v1');
    final svc = QwenService(s);
    svc.dio.httpClientAdapter = _MockAdapter(_okJson);

    await svc.identifyQuestions(const []); // empty list, will still send

    final calls = DebugService.instance.qwenCalls;
    expect(calls, hasLength(1));
    expect(calls.single.status, QwenCallStatus.ok);
    expect(calls.single.scope, 'identify');
    expect(calls.single.statusCode, 200);
  });

  test('http error records a QwenCallRecord with status=httpError', () async {
    DebugService.instance.setEnabled(true);
    final s = const AppSettings(apiKey: 'k', baseUrl: 'https://example.test/v1');
    final svc = QwenService(s);
    svc.dio.httpClientAdapter = _MockAdapter(_errJson);

    try {
      await svc.identifyQuestions(const []);
    } catch (_) {}

    final calls = DebugService.instance.qwenCalls;
    expect(calls, hasLength(1));
    expect(calls.single.status, QwenCallStatus.httpError);
    expect(calls.single.statusCode, 500);
  });

  test('disabled service does not record', () async {
    // enabled stays false
    final s = const AppSettings(apiKey: 'k', baseUrl: 'https://example.test/v1');
    final svc = QwenService(s);
    svc.dio.httpClientAdapter = _MockAdapter(_okJson);

    await svc.identifyQuestions(const []);

    expect(DebugService.instance.qwenCalls, isEmpty);
  });

  test('AI returns invalid JSON → records parseError + rethrows', () async {
    DebugService.instance.setEnabled(true);
    final s = const AppSettings(apiKey: 'k', baseUrl: 'https://example.test/v1');
    final svc = QwenService(s);
    svc.dio.httpClientAdapter = _MockAdapter((options) {
      return ResponseBody.fromString(
        '{"choices":[{"message":{"content":"this is not json at all"}}]}',
        200,
        headers: {'content-type': ['application/json']},
      );
    });

    await expectLater(
        () => svc.identifyQuestions(const []), throwsA(isA<JsonParseException>()));

    final calls = DebugService.instance.qwenCalls;
    // Expect at least one ok (from interceptor) AND one parseError (from the catch)
    expect(calls.length, greaterThanOrEqualTo(2));
    expect(calls.any((c) => c.status == QwenCallStatus.ok), isTrue);
    expect(calls.last.status, QwenCallStatus.parseError);
    expect(calls.last.errorMessage, contains('JsonParseException'));
  });
}
