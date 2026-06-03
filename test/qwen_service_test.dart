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
