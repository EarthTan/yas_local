import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/settings.dart';
import 'package:yas_local/services/debug/debug_service.dart';
import 'package:yas_local/services/qwen_error.dart';
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
    // The Dio interceptor's recordQwenCall is fire-and-forget; drain the
    // microtask queue so the buffer reflects the captured call.
    await Future<void>.delayed(Duration.zero);

    final calls = DebugService.instance.qwenCalls;
    expect(calls, hasLength(1));
    expect(calls.single.status, QwenCallStatus.ok);
    expect(calls.single.scope, 'identify');
    expect(calls.single.statusCode, 200);
  });

  test('http error records one QwenCallRecord per attempt (3 on a 5xx, all httpError)', () async {
    DebugService.instance.setEnabled(true);
    final s = const AppSettings(apiKey: 'k', baseUrl: 'https://example.test/v1');
    final svc = QwenService(s);
    svc.dio.httpClientAdapter = _MockAdapter(_errJson);

    await expectLater(
        () => svc.identifyQuestions(const []),
        throwsA(predicate<QwenError>((e) => e.kind == QwenErrorKind.http5xx)));

    final calls = DebugService.instance.qwenCalls;
    expect(calls, hasLength(3), reason: 'one interceptor record per attempt');
    expect(calls.every((c) => c.status == QwenCallStatus.httpError), isTrue);
    expect(calls.every((c) => c.statusCode == 500), isTrue);
  });

  test('disabled service does not record', () async {
    // enabled stays false
    final s = const AppSettings(apiKey: 'k', baseUrl: 'https://example.test/v1');
    final svc = QwenService(s);
    svc.dio.httpClientAdapter = _MockAdapter(_okJson);

    await svc.identifyQuestions(const []);

    expect(DebugService.instance.qwenCalls, isEmpty);
  });

  test('AI returns invalid JSON 3x → throws QwenError(jsonParse); records 3 ok + 1 parseError (C2)', () async {
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
        () => svc.identifyQuestions(const []),
        throwsA(predicate<QwenError>((e) => e.kind == QwenErrorKind.jsonParse)));

    // The Dio interceptor records one ok per attempt (fire-and-forget).
    // _retryingRequest records ONE parseError summary when the loop
    // is exhausted. Assert multiset counts (not order) to avoid the
    // fire-and-forget race: ordering in qwenCalls is not deterministic
    // under the test scheduler.
    final calls = DebugService.instance.qwenCalls;
    final okCount = calls.where((c) => c.status == QwenCallStatus.ok).length;
    final parseErrCount =
        calls.where((c) => c.status == QwenCallStatus.parseError).length;
    expect(okCount, 3, reason: 'one ok record per attempt');
    expect(parseErrCount, 1, reason: 'one parseError summary on exhaustion');

    // The parseError record carries the raw unparseable text so a
    // teacher can see what the model said in the /debug screen.
    final parseError = calls.firstWhere(
      (c) => c.status == QwenCallStatus.parseError,
    );
    expect(parseError.responseContent, contains('this is not json at all'));
    expect(parseError.scope, 'identify');
    expect(parseError.statusCode, 200);
  });

  test('1 bad-JSON attempt then valid JSON → 2 ok, 0 parseError (regression)', () async {
    DebugService.instance.setEnabled(true);
    final s = const AppSettings(apiKey: 'k', baseUrl: 'https://example.test/v1');
    final svc = QwenService(s);
    var attempt = 0;
    svc.dio.httpClientAdapter = _MockAdapter((options) {
      attempt++;
      if (attempt == 1) {
        return ResponseBody.fromString(
          '{"choices":[{"message":{"content":"not json"}}]}',
          200,
          headers: {'content-type': ['application/json']},
        );
      }
      return _okJson(options);
    });

    await svc.identifyQuestions(const []);

    final calls = DebugService.instance.qwenCalls;
    // Both attempts are recorded as ok by the interceptor. No
    // parseError should be recorded on the success path.
    final parseErrCount =
        calls.where((c) => c.status == QwenCallStatus.parseError).length;
    expect(parseErrCount, 0,
        reason: 'no parseError on the success-after-retry path');
  });

  test('empty body (200 + content: null) → TypeError → parseError record (C2)', () async {
    // Distinguishing "empty body" from "bad JSON" matters for diagnosis
    // but doesn't need a new QwenErrorKind: errorMessage preserves the
    // distinction in the Debug screen. The thrown kind is `unknown`
    // (TypeError on the `as String` cast) but it's functionally a parse
    // failure and gets recorded as parseError.
    DebugService.instance.setEnabled(true);
    final s = const AppSettings(apiKey: 'k', baseUrl: 'https://example.test/v1');
    final svc = QwenService(s);
    svc.dio.httpClientAdapter = _MockAdapter((options) {
      return ResponseBody.fromString(
        '{"choices":[{"message":{}}]}', // no content key
        200,
        headers: {'content-type': ['application/json']},
      );
    });

    await expectLater(
        () => svc.identifyQuestions(const []),
        throwsA(isA<QwenError>()));

    final calls = DebugService.instance.qwenCalls;
    final parseErrCount =
        calls.where((c) => c.status == QwenCallStatus.parseError).length;
    expect(parseErrCount, 1,
        reason: 'empty body should still record one parseError');
    final parseError = calls.firstWhere(
      (c) => c.status == QwenCallStatus.parseError,
    );
    expect(parseError.statusCode, 200);
    // errorMessage contains the original TypeError text — lets the
    // Debug screen distinguish "empty body" from "bad JSON" without
    // a new QwenErrorKind.
    expect(parseError.errorMessage, isNotNull);
  });

  group('redactBase64Messages', () {
    test('replaces data: URLs with [redacted] placeholder, preserving mime type', () {
      final out = QwenService.redactBase64Messages([
        {
          'role': 'user',
          'content': [
            {
              'type': 'image_url',
              'image_url': {'url': 'data:image/jpeg;base64,/9j/4AAQSkZJRgABAQAA'},
            },
            {
              'type': 'text',
              'text': 'hello',
            },
          ],
        },
      ]);
      final content = out.single['content'] as List;
      final imageUrl = (content[0]['image_url'] as Map)['url'] as String;
      expect(imageUrl, 'data:image/jpeg;base64,[redacted]');
      // Text content should pass through untouched.
      expect(content[1]['text'], 'hello');
    });

    test('passes through plain text messages unchanged', () {
      final out = QwenService.redactBase64Messages([
        {'role': 'user', 'content': 'just a string'},
      ]);
      expect(out.single['content'], 'just a string');
    });

    test('does not mutate the input list', () {
      final original = [
        {
          'role': 'user',
          'content': [
            {
              'type': 'image_url',
              'image_url': {'url': 'data:image/png;base64,AAAA'},
            },
          ],
        },
      ];
      QwenService.redactBase64Messages(original);
      // The original list's nested url must still be the long base64 string.
      final url = ((original[0]['content'] as List)[0]['image_url'] as Map)['url'] as String;
      expect(url, 'data:image/png;base64,AAAA');
    });

    test('preserves non-image_url content (audio, file, etc.)', () {
      // If we add audio_url later, it should also be redacted. For now only
      // image_url is supported, and other types should be passed through.
      final input = [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'q'},
          ],
        },
      ];
      final out = QwenService.redactBase64Messages(input);
      expect((out[0]['content'] as List).single['type'], 'text');
    });
  });
}
