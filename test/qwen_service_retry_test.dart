import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/settings.dart';
import 'package:yas_local/services/qwen_error.dart';
import 'package:yas_local/services/qwen_service.dart';

class _CountingAdapter implements HttpClientAdapter {
  _CountingAdapter(this._handler);
  final ResponseBody Function(int call, RequestOptions options) _handler;
  int calls = 0;
  final List<String> sentUserTexts = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final i = calls++;
    final data = options.data as Map<String, dynamic>;
    final msgs = data['messages'] as List;
    final last = msgs.last as Map;
    final content = last['content'] as List;
    sentUserTexts.add((content.last as Map)['text'] as String);
    return _handler(i, options);
  }
}

ResponseBody _okQuestions() => ResponseBody.fromString(
  '{"choices":[{"message":{"content":"{\\"questions\\": []}","role":"assistant"}}]}',
  200,
  headers: {'content-type': ['application/json']},
);

ResponseBody _ok200() => _okQuestions();

ResponseBody _status500() => ResponseBody.fromString(
  '{"error":"boom"}',
  500,
  headers: {'content-type': ['application/json']},
);

ResponseBody _status401() => ResponseBody.fromString(
  '{"error":"no auth"}',
  401,
  headers: {'content-type': ['application/json']},
);

ResponseBody _badJson() => ResponseBody.fromString(
  '{"choices":[{"message":{"content":"not json at all"}}]}',
  200,
  headers: {'content-type': ['application/json']},
);

void main() {
  test('500 then 200: retries once, succeeds', () async {
    final s = const AppSettings(apiKey: 'k', baseUrl: 'https://example.test/v1');
    final svc = QwenService(s);
    final a = _CountingAdapter((i, _) => i == 0 ? _status500() : _ok200());
    svc.dio.httpClientAdapter = a;

    await svc.identifyQuestions(const []);
    expect(a.calls, 2);
  });

  test('500 x 3: throws QwenError(http5xx)', () async {
    final s = const AppSettings(apiKey: 'k', baseUrl: 'https://example.test/v1');
    final svc = QwenService(s);
    final a = _CountingAdapter((_, __) => _status500());
    svc.dio.httpClientAdapter = a;

    await expectLater(
      () => svc.identifyQuestions(const []),
      throwsA(predicate<QwenError>((e) => e.kind == QwenErrorKind.http5xx)),
    );
    expect(a.calls, 3);
  });

  test('401: throws immediately, no retry', () async {
    final s = const AppSettings(apiKey: 'k', baseUrl: 'https://example.test/v1');
    final svc = QwenService(s);
    final a = _CountingAdapter((_, __) => _status401());
    svc.dio.httpClientAdapter = a;

    await expectLater(
      () => svc.identifyQuestions(const []),
      throwsA(predicate<QwenError>((e) => e.kind == QwenErrorKind.http4xx)),
    );
    expect(a.calls, 1, reason: '4xx short-circuits');
  });

  test('bad json then ok: second attempt has nudge in user text', () async {
    final s = const AppSettings(apiKey: 'k', baseUrl: 'https://example.test/v1');
    final svc = QwenService(s);
    final a = _CountingAdapter((i, _) => i == 0 ? _badJson() : _ok200());
    svc.dio.httpClientAdapter = a;

    await svc.identifyQuestions(const []);
    expect(a.calls, 2);
    expect(a.sentUserTexts.first, isNot(contains('无法解析为 JSON')));
    expect(
      a.sentUserTexts.last,
      contains('无法解析为 JSON'),
      reason: 'nudge appended on JSON-error retry',
    );
  });

  test('backoff delays fall in expected range (scaled-down via small max attempts)',
      () async {
    // Smoke test for the jitter formula. We can't easily freeze time without
    // making the helper injectable, so just verify total elapsed time is >=
    // sum of minimum delays (~750+1500 = 2250ms for 2 retries).
    final s = const AppSettings(apiKey: 'k', baseUrl: 'https://example.test/v1');
    final svc = QwenService(s);
    final a = _CountingAdapter((i, _) => i < 2 ? _status500() : _ok200());
    svc.dio.httpClientAdapter = a;

    final t0 = DateTime.now();
    await svc.identifyQuestions(const []);
    final elapsed = DateTime.now().difference(t0).inMilliseconds;
    expect(elapsed, greaterThanOrEqualTo(2000),
        reason: 'backoff must actually sleep between attempts');
  });
}
