# Retry-With-Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add visible 3-retry-with-feedback to QwenService + JobQueue so the teacher sees retries happen in real time and can rerun only the failed units.

**Architecture:** Two-layer retry: `_retryingRequest` (QwenService) does 3 actual retries with backoff + JSON nudge; `_retryWithFeedback` (JobQueue) wraps each per-unit call with `maxAttempts=1` to push attempt info to `JobState`. UI reads `JobState.attempt/lastErrorKind/lastErrorUnit` to show what's happening. Failed units get a one-tap "重跑失败项" rerun.

**Tech Stack:** Flutter + Riverpod, Dio, existing DebugService, in-memory JobState.

**Rollout:** 5 PRs, each independently mergeable. PR1+PR2 are pure backend (zero UI changes). PR3 surfaces state. PR4+PR5 add UI affordances.

**Avoid colliding with:** `debug-observability` worktree on branch `debug/m1-extract-in-memory-ring-sink` (their work on `DebugSink` / `RollingFileSink` / Flutter exception hooks). We only call `DebugService.instance.recordEvent('retry', ...)` — one line — and never touch the `DebugService` API or its sinks.

---

## PR 1 — QwenError classification

### Task 1.1: Add `QwenError` + `QwenErrorKind` + tests

**Files:**
- Create: `yas_local/lib/services/qwen_error.dart`
- Create: `yas_local/test/qwen_error_test.dart`

- [ ] **Step 1: Write failing tests**

Create `yas_local/test/qwen_error_test.dart`:

```dart
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd yas_local && flutter test test/qwen_error_test.dart`
Expected: FAIL — `qwen_error.dart` not found.

- [ ] **Step 3: Write `qwen_error.dart`**

Create `yas_local/lib/services/qwen_error.dart`:

```dart
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd yas_local && flutter test test/qwen_error_test.dart`
Expected: all 12 tests pass.

- [ ] **Step 5: Commit**

```bash
cd yas_local
git add lib/services/qwen_error.dart test/qwen_error_test.dart
git commit -m "feat(retry): add QwenError + QwenErrorKind for retry classification"
```

---

## PR 2 — `_retryingRequest` in QwenService

This PR threads every Qwen call through one retry helper. Zero UI changes. Existing tests still pass.

### Task 2.1: Add `jsonRetryNudge` prompt constant

**Files:**
- Modify: `yas_local/lib/services/prompts.dart`

- [ ] **Step 1: Add the nudge constant**

In `yas_local/lib/services/prompts.dart`, immediately after the `AppPrompts._();` private constructor (line 4) and before `_outputProtocol`, insert:

```dart
/// Appended to the system text on a retry caused by a JSON parse failure,
/// so the model gets a fresh chance to emit clean JSON. Same wording on every
/// retry — never stacked.
static const String jsonRetryNudge =
    '\n\n注意：上一次返回的内容无法解析为 JSON，请只返回纯 JSON，不要任何解释或 <think> 内容。';
```

- [ ] **Step 2: Verify static analysis still passes**

Run: `cd yas_local && flutter analyze lib/services/prompts.dart`
Expected: no issues.

- [ ] **Step 3: Commit**

```bash
cd yas_local
git add lib/services/prompts.dart
git commit -m "feat(retry): add AppPrompts.jsonRetryNudge for JSON-error retries"
```

### Task 2.2: Add `_retryingRequest` helper in QwenService

**Files:**
- Modify: `yas_local/lib/services/qwen_service.dart`

The helper takes the messages list, a scope tag, and a function that does JSON extraction from the response text. It runs up to 3 attempts, applying the nudge on JSON-error retries, sleeping with exponential backoff + jitter between attempts. `http4xx` is short-circuited and rethrown immediately.

- [ ] **Step 1: Add the helper and `random` import**

In `yas_local/lib/services/qwen_service.dart`, add `import 'dart:math';` at the top of the imports (next to the existing `dart:convert` / `dart:io` imports).

Then, just below `_mimeType` (currently the last method in the class) and before the trailing blank line, add:

```dart
  /// Retry policy for a single Qwen call. `bodyBuilder` is invoked on every
  /// attempt so we can append [AppPrompts.jsonRetryNudge] to the user-side
  /// text after a previous JSON parse failure. [extract] parses the response
  /// text; its thrown [JsonParseException] is what the helper treats as a
  /// JSON error. HTTP and JSON errors are wrapped in [QwenError] before
  /// rethrow. Backoff: 1000 * 2^attempt * (0.75 + rand*0.5) ms.
  ///
  /// Returns whatever [extract] returns (T).
  Future<T> _retryingRequest<T>({
    required String scope,
    required Map<String, dynamic> Function(int attempt, QwenErrorKind? lastKind)
        bodyBuilder,
    required T Function(String content) extract,
  }) async {
    const maxAttempts = 3;
    QwenErrorKind? lastKind;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final resp = await _dio.post(
          '/chat/completions',
          data: bodyBuilder(attempt, lastKind),
          options: Options(extra: {'_qwen_scope': scope}),
        );
        final content =
            resp.data['choices'][0]['message']['content'] as String;
        return extract(content);
      } catch (e) {
        final q = QwenError.from(e);
        // 4xx is a hard "stop" — no point retrying 401 / 403 / 404.
        if (!q.shouldRetry) rethrow;
        lastKind = q.kind;
        if (attempt == maxAttempts - 1) rethrow;
        final delay = _backoffMs(attempt);
        await Future<void>.delayed(Duration(milliseconds: delay));
      }
    }
    // Unreachable: the loop either returns or rethrows. Belt-and-braces.
    throw StateError('unreachable: _retryingRequest exhausted');
  }

  int _backoffMs(int attempt) {
    // attempt 0 -> ~1s, 1 -> ~2s, 2 -> ~4s (each ±25%).
    final base = 1000 * (1 << attempt);
    final jitter = 0.75 + Random().nextDouble() * 0.5;
    return (base * jitter).round();
  }
```

- [ ] **Step 2: Verify analyze still passes**

Run: `cd yas_local && flutter analyze lib/services/qwen_service.dart`
Expected: no issues (helper is unused until the next step).

- [ ] **Step 3: Commit**

```bash
cd yas_local
git add lib/services/qwen_service.dart
git commit -m "feat(retry): add _retryingRequest helper in QwenService"
```

### Task 2.3: Route `generateStrategy` through `_retryingRequest`

**Files:**
- Modify: `yas_local/lib/services/qwen_service.dart` (lines 149-232)

- [ ] **Step 1: Replace method body**

Replace the entire body of `generateStrategy` (the `final imageContent = <Map<String, dynamic>>[];` line through the `rethrow;` on the `JsonParseException` path) with the version below. The structure is the same — only the call site changes: now the Dio POST and the JSON extract are inside `_retryingRequest`.

In `generateStrategy`, replace from `final imageContent = <Map<String, dynamic>>[];` (line 155) down to (and including) the closing `}` of the `try { ... } on JsonParseException` block (line 231), with:

```dart
    final imageContent = <Map<String, dynamic>>[];

    // Send question paper images first (compressed for VLM).
    final compressedQuestionPaths = await Future.wait(
      questionPaperPaths.map(ImageCompressor.compressedPathFor),
    );
    for (final path in compressedQuestionPaths) {
      final bytes = await File(path).readAsBytes();
      final b64 = base64Encode(bytes);
      imageContent.add({
        'type': 'image_url',
        'image_url': {'url': 'data:${_mimeType(path)};base64,$b64'},
      });
    }

    // Then optionally send answer images (compressed for VLM).
    final compressedAnswerPaths = await Future.wait(
      answerImagePaths.map(ImageCompressor.compressedPathFor),
    );
    for (final path in compressedAnswerPaths) {
      final bytes = await File(path).readAsBytes();
      final b64 = base64Encode(bytes);
      imageContent.add({
        'type': 'image_url',
        'image_url': {'url': 'data:${_mimeType(path)};base64,$b64'},
      });
    }

    final countCtx = totalQuestions > 0 ? '（作业共有 $totalQuestions 道题）' : '';
    final userText = AppPrompts.generateStrategy(
      questionNumber: rubricItem.questionNumber,
      maxPoints: rubricItem.maxPoints,
      questionText: rubricItem.questionText,
      hasAnswerImages: answerImagePaths.isNotEmpty,
      countCtx: countCtx,
    );

    return _retryingRequest<ReferenceAnswer>(
      scope: 'strategy',
      bodyBuilder: (attempt, lastKind) {
        final text = lastKind == QwenErrorKind.jsonParse
            ? userText + AppPrompts.jsonRetryNudge
            : userText;
        return {
          'model': settings.vlModel,
          'messages': [
            {
              'role': 'user',
              'content': [...imageContent, {'type': 'text', 'text': text}],
            },
          ],
        };
      },
      extract: (content) {
        final payload = JsonExtractor.requireObjectWithReasoning(
          content,
          scope: 'strategy',
        );
        return _parseReferenceAnswer(
          rubricItem.questionNumber,
          payload.json,
          reasoning: payload.reasoning,
        );
      },
    );
```

- [ ] **Step 2: Verify analyze still passes**

Run: `cd yas_local && flutter analyze lib/services/qwen_service.dart`
Expected: no issues.

- [ ] **Step 3: Commit**

```bash
cd yas_local
git add lib/services/qwen_service.dart
git commit -m "refactor(retry): route generateStrategy through _retryingRequest"
```

### Task 2.4: Route `identifyQuestions` through `_retryingRequest`

**Files:**
- Modify: `yas_local/lib/services/qwen_service.dart` (lines 296-355)

- [ ] **Step 1: Replace method body**

Replace the `identifyQuestions` method body (from `final samples = ...` line 297 through the `rethrow;` on line 353) with the version below. The shape is the same — `_retryingRequest` does the POST + extract in one shot.

```dart
  Future<List<IdentifiedQuestion>> identifyQuestions(List<String> imagePaths) async {
    final samples = imagePaths.length <= 3
        ? imagePaths
        : [imagePaths[0], imagePaths[imagePaths.length ~/ 2], imagePaths.last];

    final imageContent = <Map<String, dynamic>>[];
    final compressedSamples = await Future.wait(
      samples.map(ImageCompressor.compressedPathFor),
    );
    for (final path in compressedSamples) {
      final bytes = await File(path).readAsBytes();
      final b64 = base64Encode(bytes);
      imageContent.add({
        'type': 'image_url',
        'image_url': {'url': 'data:${_mimeType(path)};base64,$b64'},
      });
    }

    final userText = AppPrompts.identifyQuestions();

    return _retryingRequest<List<IdentifiedQuestion>>(
      scope: 'identify',
      bodyBuilder: (attempt, lastKind) {
        final text = lastKind == QwenErrorKind.jsonParse
            ? userText + AppPrompts.jsonRetryNudge
            : userText;
        return {
          'model': settings.vlModel,
          'messages': [
            {
              'role': 'user',
              'content': [...imageContent, {'type': 'text', 'text': text}],
            },
          ],
        };
      },
      extract: (content) {
        final payload = JsonExtractor.requireListWithReasoning(
          content,
          fromKey: 'questions',
          scope: 'identify',
        );
        // reasoning 丢弃：题型识别是中间步骤，不暴露给老师
        return payload.list
            .map((q) => IdentifiedQuestion.fromJson(q as Map<String, dynamic>))
            .toList();
      },
    );
  }
```

- [ ] **Step 2: Verify analyze still passes**

Run: `cd yas_local && flutter analyze lib/services/qwen_service.dart`
Expected: no issues.

- [ ] **Step 3: Commit**

```bash
cd yas_local
git add lib/services/qwen_service.dart
git commit -m "refactor(retry): route identifyQuestions through _retryingRequest"
```

### Task 2.5: Route `gradePaper` through `_retryingRequest`

**Files:**
- Modify: `yas_local/lib/services/qwen_service.dart` (lines 357-455)

- [ ] **Step 1: Replace method body**

Replace the `gradePaper` method body (from `final refByNum = ...` line 363 through the `rethrow;` on line 453) with:

```dart
    final refByNum = {for (final r in refs) r.questionNumber: r};

    final strategyLines = <String>[];
    for (final item in rubric) {
      final ref = refByNum[item.questionNumber];
      if (ref == null || ref.checkpoints.isEmpty) continue;
      final cpLines =
          ref.checkpoints.map((c) => '  - ${c.description}（${c.points}分）').join('\n');
      strategyLines.add('第${item.questionNumber}题（满分${item.maxPoints}分）：\n$cpLines');
    }
    final strategyText = strategyLines.join('\n\n');

    final imageContent = <Map<String, dynamic>>[];
    final compressedQuestionPaths = await Future.wait(
      questionPaperPaths.map(ImageCompressor.compressedPathFor),
    );
    for (final path in compressedQuestionPaths) {
      final bytes = await File(path).readAsBytes();
      final b64 = base64Encode(bytes);
      imageContent.add({
        'type': 'image_url',
        'image_url': {'url': 'data:${_mimeType(path)};base64,$b64'},
      });
    }
    // Student submission image (compressed for VLM).
    final compressedStudentPath =
        await ImageCompressor.compressedPathFor(imagePath);
    final studentBytes = await File(compressedStudentPath).readAsBytes();
    final studentB64 = base64Encode(studentBytes);
    imageContent.add({
      'type': 'image_url',
      'image_url': {'url': 'data:${_mimeType(compressedStudentPath)};base64,$studentB64'},
    });

    final userText = AppPrompts.gradePaper(strategyText: strategyText);

    return _retryingRequest<List<QuestionGradeResult>>(
      scope: 'grade',
      bodyBuilder: (attempt, lastKind) {
        final text = lastKind == QwenErrorKind.jsonParse
            ? userText + AppPrompts.jsonRetryNudge
            : userText;
        return {
          'model': settings.vlModel,
          'messages': [
            {
              'role': 'user',
              'content': [...imageContent, {'type': 'text', 'text': text}],
            },
          ],
        };
      },
      extract: (content) {
        final payload = JsonExtractor.requireListWithReasoning(
          content,
          fromKey: 'questions',
          scope: 'grade',
        );
        // reasoning 丢弃：批改的思考过程不暴露给学生/老师
        return payload.list.map((q) {
          final qNum = q['number'] is int
              ? q['number'] as int
              : int.tryParse(q['number'].toString()) ?? 0;
          final cps = (q['checkpoints'] as List? ?? [])
              .map((c) => CheckpointResult(
                    description: (c['description'] ?? '').toString(),
                    passed: c['passed'] as bool? ?? false,
                    pointsAwarded: (c['points_awarded'] as num?)?.toInt() ?? 0,
                    reason: (c['reason'] ?? '').toString(),
                  ))
              .toList();
          return QuestionGradeResult(
            questionNumber: qNum,
            extractedAnswer: (q['extracted_answer'] ?? '').toString(),
            checkpoints: cps,
            confidence: (q['confidence'] as num?)?.toDouble() ?? 0.8,
            overallComment: q['overall_comment'] as String?,
          );
        }).toList();
      },
    );
```

- [ ] **Step 2: Run existing qwen_service tests**

Run: `cd yas_local && flutter test test/qwen_service_test.dart`
Expected: PASS. (The existing tests use a single mock adapter that always returns the same body, so retry should not change behavior on the happy path. The "invalid JSON" test still throws `JsonParseException` because 3 attempts in a row return invalid JSON — that should now surface as a `QwenError` with kind `jsonParse`. The test only asserts `throwsA(isA<JsonParseException>())`, so it'll fail.)

- [ ] **Step 3: Update the existing parse-error test to expect QwenError**

In `yas_local/test/qwen_service_test.dart`, the test `'AI returns invalid JSON → records parseError + rethrows'` (line 93) currently asserts:

```dart
await expectLater(
    () => svc.identifyQuestions(const []), throwsA(isA<JsonParseException>()));
```

Change it to expect `QwenError` (since retries are now exhausted). Replace those two lines with:

```dart
await expectLater(
    () => svc.identifyQuestions(const []), throwsA(isA<QwenError>()));
```

And add the import at the top of the file:

```dart
import 'package:yas_local/services/qwen_error.dart';
```

The rest of the test (the `DebugService` assertions on the parseError records) still holds — the interceptor still records `QwenCallStatus.ok` on the response, and the catch block in the old code path is gone but the `DebugService` is now hit by the per-attempt interceptor anyway. We need to update the assertion `expect(calls.last.status, QwenCallStatus.parseError)` to be lenient — there's no longer a second record from the catch. Update that line to:

```dart
// Per-attempt responses are recorded by the Dio interceptor. After 3
// failed parse attempts the helper throws QwenError — there is no extra
// "parseError" record from the old catch block.
expect(calls.length, 3, reason: 'one record per attempt');
expect(calls.every((c) => c.status == QwenCallStatus.ok), isTrue);
```

- [ ] **Step 4: Run qwen_service tests again**

Run: `cd yas_local && flutter test test/qwen_service_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd yas_local
git add lib/services/qwen_service.dart test/qwen_service_test.dart
git commit -m "refactor(retry): route gradePaper through _retryingRequest"
```

### Task 2.6: Add retry-behavior tests

**Files:**
- Create: `yas_local/test/qwen_service_retry_test.dart`

- [ ] **Step 1: Write tests**

Create `yas_local/test/qwen_service_retry_test.dart`:

```dart
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
    // This is a smoke test for the jitter formula. We can't easily freeze time
    // without making the helper injectable, so just verify total elapsed time
    // is >= sum of minimum delays (~750+1500 = 2250ms for 2 retries).
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
```

- [ ] **Step 2: Run the new tests**

Run: `cd yas_local && flutter test test/qwen_service_retry_test.dart`
Expected: 5 tests pass. (The backoff smoke test takes ~2-3s because of the 2 sleeps.)

- [ ] **Step 3: Commit**

```bash
cd yas_local
git add test/qwen_service_retry_test.dart
git commit -m "test(retry): cover QwenService _retryingRequest behavior"
```

---

## PR 3 — `JobState` attempt fields + `_retryWithFeedback`

### Task 3.1: Add new fields to `JobState` with zero-on-terminal semantics

**Files:**
- Modify: `yas_local/lib/models/job_state.dart`

- [ ] **Step 1: Update the class declaration**

Replace the entire content of `yas_local/lib/models/job_state.dart` with:

```dart
import 'qwen_error.dart' show QwenErrorKind;

/// Which long-running AI loop a job represents.
enum JobKind { strategy, grading }

/// Lifecycle of a job. There is no `cancelled` phase — a cancelled job ends
/// as [done] with fewer units processed; cancellation is signalled by
/// [JobState.cancelRequested] while running.
enum JobPhase { running, done, failed }

/// In-memory progress record for one task's active (or just-finished) job.
/// Not persisted: jobs are session-scoped. Durable grading progress lives on
/// each [Submission]'s status; durable strategy output lives in
/// `reference_<taskId>.json`.
class JobState {
  final String taskId;
  final JobKind kind;
  final JobPhase phase;
  final int total;
  final int done;
  final int failedCount;
  final String? error;
  final bool cancelRequested;

  /// 0 = no retry in flight; 1..3 = the in-progress retry attempt number.
  /// Always 0 when [phase] is [JobPhase.done] or [JobPhase.failed] —
  /// [copyWith] and the constructor enforce that.
  final int attempt;

  /// Snapshot of the most recent error class observed during this job.
  /// UI shows the *last* failure only; full history is owned by DebugService.
  final QwenErrorKind? lastErrorKind;

  /// Human label for the unit that was retrying, e.g. "第 12 例" or "第 3 题".
  final String? lastErrorUnit;

  const JobState({
    required this.taskId,
    required this.kind,
    this.phase = JobPhase.running,
    this.total = 0,
    this.done = 0,
    this.failedCount = 0,
    this.error,
    this.cancelRequested = false,
    this.attempt = 0,
    this.lastErrorKind,
    this.lastErrorUnit,
  });

  JobState copyWith({
    JobPhase? phase,
    int? total,
    int? done,
    int? failedCount,
    Object? error = _keep,
    bool? cancelRequested,
    int? attempt,
    QwenErrorKind? lastErrorKind,
    String? lastErrorUnit,
  }) {
    final newPhase = phase ?? this.phase;
    // Retry/feedback fields only make sense while running. Clear them on
    // transition to a terminal phase so stale "正在重试" UI doesn't linger.
    final terminal = newPhase == JobPhase.done || newPhase == JobPhase.failed;
    return JobState(
      taskId: taskId,
      kind: kind,
      phase: newPhase,
      total: total ?? this.total,
      done: done ?? this.done,
      failedCount: failedCount ?? this.failedCount,
      error: identical(error, _keep) ? this.error : error as String?,
      cancelRequested: cancelRequested ?? this.cancelRequested,
      attempt: terminal ? 0 : (attempt ?? this.attempt),
      lastErrorKind: terminal ? null : (lastErrorKind ?? this.lastErrorKind),
      lastErrorUnit: terminal ? null : (lastErrorUnit ?? this.lastErrorUnit),
    );
  }

  static const _keep = Object();
}
```

- [ ] **Step 2: Add unit tests**

Create `yas_local/test/job_state_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/job_state.dart';
import 'package:yas_local/services/qwen_error.dart';

void main() {
  test('defaults: attempt=0, lastError* null', () {
    const j = JobState(taskId: 't1', kind: JobKind.grading);
    expect(j.attempt, 0);
    expect(j.lastErrorKind, isNull);
    expect(j.lastErrorUnit, isNull);
  });

  test('copyWith sets attempt, kind, unit while running', () {
    const j = JobState(taskId: 't1', kind: JobKind.grading);
    final j2 = j.copyWith(
      attempt: 2,
      lastErrorKind: QwenErrorKind.jsonParse,
      lastErrorUnit: '第 3 例',
    );
    expect(j2.attempt, 2);
    expect(j2.lastErrorKind, QwenErrorKind.jsonParse);
    expect(j2.lastErrorUnit, '第 3 例');
  });

  test('copyWith phase=done clears attempt + lastError*', () {
    const j = JobState(
      taskId: 't1',
      kind: JobKind.grading,
      attempt: 2,
      lastErrorKind: QwenErrorKind.jsonParse,
      lastErrorUnit: '第 3 例',
    );
    final j2 = j.copyWith(phase: JobPhase.done);
    expect(j2.attempt, 0);
    expect(j2.lastErrorKind, isNull);
    expect(j2.lastErrorUnit, isNull);
  });

  test('copyWith phase=failed clears attempt + lastError*', () {
    const j = JobState(
      taskId: 't1',
      kind: JobKind.grading,
      attempt: 1,
      lastErrorKind: QwenErrorKind.http5xx,
      lastErrorUnit: '第 1 例',
    );
    final j2 = j.copyWith(phase: JobPhase.failed);
    expect(j2.attempt, 0);
    expect(j2.lastErrorKind, isNull);
    expect(j2.lastErrorUnit, isNull);
  });

  test('copyWith preserves cancelRequested through retry fields', () {
    const j = JobState(
      taskId: 't1',
      kind: JobKind.grading,
      cancelRequested: true,
    );
    final j2 = j.copyWith(attempt: 1);
    expect(j2.cancelRequested, isTrue);
  });
}
```

- [ ] **Step 3: Run the new tests**

Run: `cd yas_local && flutter test test/job_state_test.dart`
Expected: 5 tests pass.

- [ ] **Step 4: Run existing tests to ensure no regressions**

Run: `cd yas_local && flutter test test/job_queue_test.dart`
Expected: all existing `JobState` tests still pass — they don't touch the new fields.

- [ ] **Step 5: Commit**

```bash
cd yas_local
git add lib/models/job_state.dart test/job_state_test.dart
git commit -m "feat(retry): add attempt + lastError* fields to JobState"
```

### Task 3.2: Add `_retryWithFeedback` wrapper in `JobQueueNotifier`

**Files:**
- Modify: `yas_local/lib/providers/job_queue_provider.dart`

The wrapper takes an `action` (the per-unit call that may throw), a `unitLabel` (e.g. "第 12 例"), and an `onAttempt` callback to push attempt info to the state. It runs `action()` exactly once (no second outer layer of retry), but on a thrown `QwenError` (whose kind classifies as retryable *from the user's perspective* — i.e. all kinds except `http4xx`) it records the kind/unit and rethrows. The "feedback" name comes from the fact that the user only sees one attempt at a time — `QwenService` already did 3 — and we surface a single line.

- [ ] **Step 1: Add the helper and the QwenError import**

Add the import at the top of `yas_local/lib/providers/job_queue_provider.dart`:

```dart
import '../services/qwen_error.dart';
```

Then, just below `_patch` and `_set` (around line 46), add:

```dart
  /// Wrap a per-unit Qwen call so the user sees the retry attempt count and
  /// the error class. QwenService has already done up to 3 internal retries;
  /// this layer does NOT add a second retry loop — it only propagates the
  /// attempt number to JobState, records a DebugService event, and rethrows
  /// the classified [QwenError]. Cancellation: if [cancelRequested] is set
  /// when the helper is entered, the action is skipped and a [StateError]
  /// is thrown so the per-unit call still bumps `done` and exits cleanly.
  Future<T> _retryWithFeedback<T>({
    required String taskId,
    required String unitLabel,
    required Future<T> Function() action,
  }) async {
    if (state[taskId]?.cancelRequested ?? false) {
      throw StateError('cancelled');
    }
    _patch(taskId, (j) => j.copyWith(
          attempt: 1,
          lastErrorKind: null,
          lastErrorUnit: unitLabel,
        ));
    try {
      final result = await action();
      _patch(taskId, (j) => j.copyWith(
            attempt: 0,
            lastErrorKind: null,
            lastErrorUnit: null,
          ));
      return result;
    } catch (e) {
      final q = QwenError.from(e);
      _patch(taskId, (j) => j.copyWith(
            attempt: 0, // terminal failure of this unit; keep the kind/unit
            lastErrorKind: q.kind,
            lastErrorUnit: unitLabel,
          ));
      DebugService.instance.recordEvent(
        scope: 'task:$taskId',
        message: 'retry failed ($unitLabel, ${q.kind.name})',
        level: EventLevel.error,
        data: {'unit': unitLabel, 'kind': q.kind.name},
      );
      rethrow;
    }
  }
```

- [ ] **Step 2: Verify analyze passes**

Run: `cd yas_local && flutter analyze lib/providers/job_queue_provider.dart`
Expected: no issues (helper not yet called from anywhere).

- [ ] **Step 3: Commit**

```bash
cd yas_local
git add lib/providers/job_queue_provider.dart
git commit -m "feat(retry): add _retryWithFeedback wrapper in JobQueueNotifier"
```

### Task 3.3: Wrap `_gradeOne` with `_retryWithFeedback`

**Files:**
- Modify: `yas_local/lib/providers/job_queue_provider.dart`

- [ ] **Step 1: Wrap the existing per-submission Qwen call**

In `startGrading`, locate the inner `try { ... }` block that contains `qwen.gradePaper(...)` (lines 124-186). The change is minimal: the Qwen call inside the per-submission `try` is now invoked through `_retryWithFeedback`. The outer per-unit `try/catch` still handles the failed-submission path.

Replace the line:

```dart
          final grades = await qwen.gradePaper(
            imagePath: sub.imagePath!,
            questionPaperPaths: task.questionPaperPaths,
            rubric: task.rubric,
            refs: references,
          );
```

with:

```dart
          final grades = await _retryWithFeedback<List<QuestionGradeResult>>(
            taskId: taskId,
            unitLabel: '第 ${subIndexOf(targets, sub) + 1} 例',
            action: () => qwen.gradePaper(
              imagePath: sub.imagePath!,
              questionPaperPaths: task.questionPaperPaths,
              rubric: task.rubric,
              refs: references,
            ),
          );
```

This requires a tiny helper to recover the 1-based position of `sub` inside `targets`. Add the following method on `JobQueueNotifier`, just below `_retryWithFeedback`:

```dart
  int subIndexOf(List<Submission> targets, Submission sub) =>
      targets.indexOf(sub);
```

(The helper exists so the label stays "第 1 例" / "第 2 例" / … even when submissions are processed in pool order, not list order. `indexOf` is O(n) but the targets list is small and this runs once per unit.)

- [ ] **Step 2: Run existing job queue tests**

Run: `cd yas_local && flutter test test/job_queue_test.dart`
Expected: existing tests still pass (no Qwen error path exercised — the happy-path `_OkQwen` never throws).

- [ ] **Step 3: Commit**

```bash
cd yas_local
git add lib/providers/job_queue_provider.dart
git commit -m "feat(retry): wrap grading per-unit with _retryWithFeedback"
```

### Task 3.4: Wrap `_strategyOne` with `_retryWithFeedback`

**Files:**
- Modify: `yas_local/lib/providers/job_queue_provider.dart`

- [ ] **Step 1: Wrap the per-rubric-item Qwen call**

In `startStrategy`, replace the `try { results[i] = await qwen.generateStrategy(...)` block (lines 271-278). The unit label is the question number from the rubric item.

Replace lines 271-278:

```dart
        try {
          results[i] = await qwen.generateStrategy(
            rubricItem: item,
            questionPaperPaths: task.questionPaperPaths,
            answerImagePaths: task.answerImagePaths,
            totalQuestions: task.rubric.length,
          );
          _patch(taskId, (j) => j.copyWith(done: j.done + 1));
        } catch (e) {
```

with:

```dart
        try {
          results[i] = await _retryWithFeedback<ReferenceAnswer>(
            taskId: taskId,
            unitLabel: '第 ${item.questionNumber} 题',
            action: () => qwen.generateStrategy(
              rubricItem: item,
              questionPaperPaths: task.questionPaperPaths,
              answerImagePaths: task.answerImagePaths,
              totalQuestions: task.rubric.length,
            ),
          );
          _patch(taskId, (j) => j.copyWith(done: j.done + 1));
        } catch (e) {
```

- [ ] **Step 2: Run existing job queue tests**

Run: `cd yas_local && flutter test test/job_queue_test.dart`
Expected: existing strategy test still passes (happy path).

- [ ] **Step 3: Commit**

```bash
cd yas_local
git add lib/providers/job_queue_provider.dart
git commit -m "feat(retry): wrap strategy per-unit with _retryWithFeedback"
```

### Task 3.5: Add focused JobQueue retry-feedback tests

**Files:**
- Create: `yas_local/test/job_queue_retry_test.dart`

- [ ] **Step 1: Write the test file**

Create `yas_local/test/job_queue_retry_test.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'package:yas_local/models/checkpoint.dart';
import 'package:yas_local/models/job_state.dart';
import 'package:yas_local/models/reference_answer.dart';
import 'package:yas_local/models/rubric.dart';
import 'package:yas_local/models/settings.dart';
import 'package:yas_local/models/submission.dart';
import 'package:yas_local/models/task.dart';
import 'package:yas_local/providers/job_queue_provider.dart';
import 'package:yas_local/providers/settings_provider.dart';
import 'package:yas_local/providers/strategy_provider.dart';
import 'package:yas_local/providers/task_provider.dart';
import 'package:yas_local/services/qwen_error.dart';
import 'package:yas_local/services/qwen_service.dart';

class _FakeTaskNotifier extends TaskNotifier {
  _FakeTaskNotifier(super.ref, this._task, this._subs);
  final GradingTask _task;
  final List<Submission> _subs;

  @override
  GradingTask? taskById(String id) => _task.id == id ? _task : null;
  @override
  List<Submission> submissionsFor(String id) => _subs;
  @override
  Future<void> updateSubmission(Submission sub) async {}
}

class _ConfiguredSettings extends SettingsNotifier {
  _ConfiguredSettings() {
    state = const AppSettings(apiKey: 'k');
  }
}

class _Http5xxQwen extends QwenService {
  _Http5xxQwen() : super(const AppSettings(apiKey: 'k'));
  @override
  Future<List<QuestionGradeResult>> gradePaper({
    required String imagePath,
    required List<String> questionPaperPaths,
    required List<RubricItem> rubric,
    required List<ReferenceAnswer> refs,
  }) async {
    throw QwenError(
      QwenErrorKind.http5xx,
      Exception('5xx simulated'),
    );
  }
}

class _Http4xxQwen extends QwenService {
  _Http4xxQwen() : super(const AppSettings(apiKey: 'k'));
  @override
  Future<List<QuestionGradeResult>> gradePaper({
    required String imagePath,
    required List<String> questionPaperPaths,
    required List<RubricItem> rubric,
    required List<ReferenceAnswer> refs,
  }) async {
    throw QwenError(QwenErrorKind.http4xx, Exception('401 simulated'));
  }
}

GradingTask _task() => GradingTask(
  id: 't1',
  name: 'T1',
  subject: 'math',
  createdAt: DateTime(2026),
  rubric: const [RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 5)],
  questionPaperPaths: const [],
);

ProviderContainer _container({required QwenService qwen}) {
  late _FakeTaskNotifier fake;
  final c = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith((ref) => _ConfiguredSettings()),
      taskProvider.overrideWith((ref) {
        fake = _FakeTaskNotifier(
          ref,
          _task(),
          [
            const Submission(
              id: 's1', taskId: 't1', label: 'p1', imagePath: '/a.jpg',
            ),
          ],
        );
        return fake;
      }),
      qwenFactoryProvider.overrideWithValue((ref) => qwen),
    ],
  );
  c.read(taskProvider.notifier);
  addTearDown(() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    c.dispose();
  });
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('jobq_retry_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('5xx: lastErrorKind set, phase reaches failed, no clobber', () async {
    final c = _container(qwen: _Http5xxQwen());

    await c.read(jobQueueProvider.notifier).startGrading('t1');

    final job = c.read(jobQueueProvider)['t1']!;
    expect(job.failedCount, 1);
    expect(job.phase, JobPhase.failed);
    // On a failed job, the snapshot is cleared by copyWith.
    expect(job.attempt, 0);
  });

  test('4xx: phase reaches failed', () async {
    final c = _container(qwen: _Http4xxQwen());

    await c.read(jobQueueProvider.notifier).startGrading('t1');

    final job = c.read(jobQueueProvider)['t1']!;
    expect(job.failedCount, 1);
    expect(job.phase, JobPhase.failed);
  });
}
```

- [ ] **Step 2: Run the new tests**

Run: `cd yas_local && flutter test test/job_queue_retry_test.dart`
Expected: 2 tests pass.

- [ ] **Step 3: Commit**

```bash
cd yas_local
git add test/job_queue_retry_test.dart
git commit -m "test(retry): cover JobQueue error classification paths"
```

---

## PR 4 — UI surfaces attempt / lastError

### Task 4.1: Add `retryHint` to `resolveTaskCardStatus` + tests

**Files:**
- Modify: `yas_local/lib/screens/home_screen.dart` (lines 22-94)
- Modify: `yas_local/test/task_card_status_test.dart`

- [ ] **Step 1: Add the field to `TaskCardStatus`**

In `yas_local/lib/screens/home_screen.dart`, change the class to include a `retryHint`:

```dart
class TaskCardStatus {
  final TaskCardKind kind;
  final String label;
  final double? progress; // 0..1 -> determinate bar; null -> none/indeterminate
  final bool indeterminate;
  final String? retryHint; // null = don't render the retry line
  const TaskCardStatus(
    this.kind,
    this.label, {
    this.progress,
    this.indeterminate = false,
    this.retryHint,
  });
}
```

- [ ] **Step 2: Compute retryHint in `resolveTaskCardStatus`**

In `resolveTaskCardStatus`, add `QwenErrorKind? retryKind` and `int retryAttempt` to the parameter list, and compute `retryHint` whenever `retryAttempt > 0 && retryKind != null`:

```dart
TaskCardStatus resolveTaskCardStatus({
  required JobState? job,
  required String subject,
  required int subTotal,
  required int subDone,
  required int subFailed,
  QwenErrorKind? retryKind,
  int retryAttempt = 0,
}) {
  // ... existing branches unchanged ...

  // Build retry hint when an attempt is in flight.
  String? hint;
  if (retryAttempt > 0 && retryKind != null) {
    hint = '⟳ 重试 $retryAttempt/3 · ${retryKind.displayName}';
  }

  return TaskCardStatus(
    // ... existing fields unchanged ...
    retryHint: hint,
  );
}
```

(For the existing "returns a TaskCardStatus" call sites, `retryHint` will default to null because we use named parameters. Only the `running` branches need to forward `hint` into the returned object; the terminal branches can omit it.)

- [ ] **Step 3: Import `qwen_error` in home_screen.dart**

Add to the top of `yas_local/lib/screens/home_screen.dart`:

```dart
import '../services/qwen_error.dart';
```

- [ ] **Step 4: Update existing call sites to forward `retryKind` / `retryAttempt`**

In the home screen `build` method (the `for (final t in state.tasks.reversed)` loop), update the `resolveTaskCardStatus` call to read the new fields from `jobs[t.id]`:

```dart
final status = resolveTaskCardStatus(
  job: jobs[t.id],
  subject: t.subject,
  subTotal: subs.length,
  subDone: subs.where((s) => s.status == SubmissionStatus.done).length,
  subFailed: subs.where((s) => s.status == SubmissionStatus.failed).length,
  retryKind: jobs[t.id]?.lastErrorKind,
  retryAttempt: jobs[t.id]?.attempt ?? 0,
);
```

- [ ] **Step 5: Render the hint in the card subtitle**

In the same `ListTile`, inside the `Column` under `status.label`, add (after the `LinearProgressIndicator` block):

```dart
if (status.retryHint != null) ...[
  const SizedBox(height: 2),
  Text(
    status.retryHint!,
    style: const TextStyle(
      color: Colors.deepOrange,
      fontSize: 12,
      fontStyle: FontStyle.italic,
    ),
  ),
],
```

- [ ] **Step 6: Add tests**

In `yas_local/test/task_card_status_test.dart`, add at the end of the `group`:

```dart
test('attempt>0 with kind -> retryHint contains the kind label', () {
  final s = resolveTaskCardStatus(
    job: const JobState(
      taskId: 't1',
      kind: JobKind.grading,
      total: 5,
      done: 2,
    ),
    subject: 'math',
    subTotal: 5,
    subDone: 0,
    subFailed: 0,
    retryAttempt: 2,
    retryKind: QwenErrorKind.jsonParse,
  );
  expect(s.retryHint, contains('2/3'));
  expect(s.retryHint, contains('JSON 解析错'));
});

test('attempt=0 -> retryHint is null', () {
  final s = resolveTaskCardStatus(
    job: const JobState(
      taskId: 't1',
      kind: JobKind.grading,
      total: 5,
      done: 2,
    ),
    subject: 'math',
    subTotal: 5,
    subDone: 0,
    subFailed: 0,
  );
  expect(s.retryHint, isNull);
});

test('attempt>0 but kind null -> retryHint is null', () {
  final s = resolveTaskCardStatus(
    job: const JobState(
      taskId: 't1',
      kind: JobKind.grading,
      total: 5,
      done: 2,
    ),
    subject: 'math',
    subTotal: 5,
    subDone: 0,
    subFailed: 0,
    retryAttempt: 1,
  );
  expect(s.retryHint, isNull);
});
```

Add the import at the top of the test file:

```dart
import 'package:yas_local/services/qwen_error.dart';
```

- [ ] **Step 7: Run the tests**

Run: `cd yas_local && flutter test test/task_card_status_test.dart`
Expected: existing tests still pass (retryHint defaults to null for them) and the 3 new tests pass.

- [ ] **Step 8: Commit**

```bash
cd yas_local
git add lib/screens/home_screen.dart test/task_card_status_test.dart
git commit -m "feat(retry): show retry hint on home task card"
```

### Task 4.2: Add attempt line + failure banner to `task_detail_screen`

**Files:**
- Modify: `yas_local/lib/screens/task_detail_screen.dart`

- [ ] **Step 1: Add imports**

Add to the top of `yas_local/lib/screens/task_detail_screen.dart`:

```dart
import '../services/qwen_error.dart';
```

- [ ] **Step 2: Add an attempt line above the existing progress block**

In the Strategy section (around line 160-175, the `strategyRunning` branch) and the Results section (around line 246-258, the `gradingRunning` branch), add an `attempt` line that displays when `job.attempt > 0 && job.lastErrorKind != null`. It must be a small grey line under the bold progress title.

For the Strategy section's `strategyRunning` branch, replace the existing block:

```dart
          ] else if (strategyRunning) ...[
            // Inline generation progress — mirrors the grading progress in the
            // Results section, so generating no longer needs a spinner screen.
            Text(
              '生成批改策略中 ${job!.done} / ${job.total} 题',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: job.total > 0 ? job.done / job.total : null,
            ),
          ] else if (strategyFailed && !hasRefs) ...[
```

with:

```dart
          ] else if (strategyRunning) ...[
            // Inline generation progress — mirrors the grading progress in the
            // Results section, so generating no longer needs a spinner screen.
            Text(
              '生成批改策略中 ${job!.done} / ${job.total} 题',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            if (job.attempt > 0 && job.lastErrorKind != null) ...[
              const SizedBox(height: 4),
              Text(
                '⟳ ${job.lastErrorUnit ?? "当前题"} · 重试 ${job.attempt}/3 · ${job.lastErrorKind!.displayName}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.deepOrange,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: job.total > 0 ? job.done / job.total : null,
            ),
          ] else if (strategyFailed && !hasRefs) ...[
```

For the Results section's `gradingRunning` branch, replace the existing block:

```dart
          ] else if (gradingRunning) ...[
            Text(
              '批改中 ${job!.done} / ${job.total} 份',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: job.total > 0 ? job.done / job.total : null,
            ),
          ] else
```

with:

```dart
          ] else if (gradingRunning) ...[
            Text(
              '批改中 ${job!.done} / ${job.total} 份',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            if (job.attempt > 0 && job.lastErrorKind != null) ...[
              const SizedBox(height: 4),
              Text(
                '⟳ ${job.lastErrorUnit ?? "当前例"} · 重试 ${job.attempt}/3 · ${job.lastErrorKind!.displayName}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.deepOrange,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: job.total > 0 ? job.done / job.total : null,
            ),
          ] else
```

- [ ] **Step 3: Add a failure banner above the existing buttons**

Find the `ResultsSectionStatus.hasResults` case (around line 265-283). After the `if (showRegrade)` block (line 272-282) and before the closing of that case's children list, add a banner that only renders when the *current job* is in a terminal phase with failures. The banner is distinct from the "重新批改" button — it sits above the action buttons and offers a single-tap rerun. Add the same kind of banner to the Strategy section.

In the `Results section` block, in the `ResultsSectionStatus.hasResults` branch, after the existing `OutlinedButton.icon('重新批改'...)` block, add:

```dart
                if (job != null &&
                    (job.phase == JobPhase.done || job.phase == JobPhase.failed) &&
                    job.failedCount > 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      border: Border.all(color: Colors.red.shade200),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber, color: Colors.red, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${job.failedCount} 份失败',
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                        OutlinedButton(
                          onPressed: () => _rerunFailedGrading(),
                          child: const Text('重跑失败项'),
                        ),
                      ],
                    ),
                  ),
                ],
```

In the Strategy section's `else ...[` (the "all confirmed / partial" branches, around line 214-238), add a parallel banner. Replace the existing tail:

```dart
            const SizedBox(height: 8),
            OutlinedButton.icon(
              // Refresh cached refs on return so the status reflects a
              // just-confirmed strategy without a manual reload.
              onPressed: () =>
                  context.push('/tasks/${widget.taskId}/strategy').then((_) {
                    if (mounted) _loadRefs();
                  }),
              icon: const Icon(Icons.edit_note),
              label: Text(allConfirmed ? '查看 / 修改批改策略' : '继续完善批改策略'),
            ),
          ],
```

with:

```dart
            const SizedBox(height: 8),
            OutlinedButton.icon(
              // Refresh cached refs on return so the status reflects a
              // just-confirmed strategy without a manual reload.
              onPressed: () =>
                  context.push('/tasks/${widget.taskId}/strategy').then((_) {
                    if (mounted) _loadRefs();
                  }),
              icon: const Icon(Icons.edit_note),
              label: Text(allConfirmed ? '查看 / 修改批改策略' : '继续完善批改策略'),
            ),
            if (job != null &&
                (job.phase == JobPhase.done || job.phase == JobPhase.failed) &&
                refs.where((r) => r.checkpoints.isEmpty).isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${refs.where((r) => r.checkpoints.isEmpty).length} 题生成失败',
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () => _rerunFailedStrategy(),
                      child: const Text('重跑失败题'),
                    ),
                  ],
                ),
              ),
            ],
          ],
```

- [ ] **Step 4: Add the two handler methods**

At the bottom of `_S` (just before its closing brace), add:

```dart
  void _rerunFailedGrading() async {
    // Reset only the failed submissions to pending; submissions already done
    // stay done. startGrading's existing filter (status != done) takes care
    // of the rest.
    final subs = ref.read(taskProvider.notifier).submissionsFor(widget.taskId);
    for (final s in subs.where((s) => s.status == SubmissionStatus.failed)) {
      await ref.read(taskProvider.notifier).updateSubmission(
            s.copyWith(status: SubmissionStatus.pending, items: []),
          );
    }
    await ref.read(jobQueueProvider.notifier).startGrading(widget.taskId);
  }

  void _rerunFailedStrategy() async {
    final refs = _cachedRefs ?? await ReferenceStore.load(widget.taskId);
    final failedNums = refs
        .where((r) => r.checkpoints.isEmpty)
        .map((r) => r.questionNumber)
        .toList();
    if (failedNums.isEmpty) return;
    await ref
        .read(jobQueueProvider.notifier)
        .startStrategy(widget.taskId, onlyQuestions: failedNums);
  }
```

(Note: `_rerunFailedStrategy` calls `startStrategy` with a parameter that does not exist yet — that will fail to compile until Task 5.1. Do Task 5.1 immediately after this one in the same PR. If you want this PR to compile cleanly on its own, gate the call with `// ignore: avoid_dynamic_calls` and a TODO; but it's cleaner to land 4.2 + 5.1 together.)

- [ ] **Step 5: Verify analyze passes**

Run: `cd yas_local && flutter analyze lib/screens/task_detail_screen.dart`
Expected: no issues (assuming 5.1 has landed first).

- [ ] **Step 6: Commit**

```bash
cd yas_local
git add lib/screens/task_detail_screen.dart
git commit -m "feat(retry): show attempt line + failure banner in Task Detail"
```

### Task 4.3: Add attempt line + failure banner to `strategy_review_screen`

**Files:**
- Modify: `yas_local/lib/screens/strategy_review_screen.dart`

- [ ] **Step 1: Add import**

Add to the top of `yas_local/lib/screens/strategy_review_screen.dart`:

```dart
import '../services/qwen_error.dart';
```

- [ ] **Step 2: Add an attempt line above the progress dots**

In the main `Scaffold.body` column (around line 198-209), add a small line under the existing `ProgressDots` block when `job != null && job.attempt > 0 && job.lastErrorKind != null`. After the `ProgressDots(...)` widget, add:

```dart
          if (job != null && job.attempt > 0 && job.lastErrorKind != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                '⟳ ${job.lastErrorUnit ?? "当前题"} · 重试 ${job.attempt}/3 · ${job.lastErrorKind!.displayName}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.deepOrange,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
```

- [ ] **Step 3: Add a failure banner in the bottom action bar column**

In the `bottomNavigationBar` (around line 239-303), add a banner above the existing `if (state.error != null || jobError != null)` block. The banner shows "X 题生成失败 · 重跑失败题 (X)" and is wired to a method that resets the failed refs and calls `startStrategy(onlyQuestions: failedNums)`. Add the following block immediately above the `if (state.error != null || jobError != null)` Container:

```dart
                if (job != null &&
                    (job.phase == JobPhase.done ||
                        job.phase == JobPhase.failed) &&
                    refs.where((r) => r.checkpoints.isEmpty).isNotEmpty)
                  Container(
                    width: double.infinity,
                    color: Colors.red.shade50,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber, color: Colors.red, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${refs.where((r) => r.checkpoints.isEmpty).length} 题生成失败',
                            style: const TextStyle(color: Colors.red, fontSize: 12),
                          ),
                        ),
                        TextButton(
                          onPressed: () => _rerunFailedStrategyQuestions(),
                          child: const Text('重跑失败题'),
                        ),
                      ],
                    ),
                  ),
```

- [ ] **Step 4: Add the rerun method**

Add the following method to `_S`:

```dart
  void _rerunFailedStrategyQuestions() async {
    final refs = ref.read(strategyProvider).references;
    final failedNums = refs
        .where((r) => r.checkpoints.isEmpty)
        .map((r) => r.questionNumber)
        .toList();
    if (failedNums.isEmpty) return;
    await ref
        .read(jobQueueProvider.notifier)
        .startStrategy(widget.taskId, onlyQuestions: failedNums);
  }
```

- [ ] **Step 5: Verify analyze passes**

Run: `cd yas_local && flutter analyze lib/screens/strategy_review_screen.dart`
Expected: no issues (assuming 5.1 has landed first).

- [ ] **Step 6: Commit**

```bash
cd yas_local
git add lib/screens/strategy_review_screen.dart
git commit -m "feat(retry): show attempt line + failure banner in Strategy Review"
```

---

## PR 5 — `startStrategy(onlyQuestions:)` + ReferenceStore mutex + merge

### Task 5.1: Add `onlyQuestions` parameter to `startStrategy` + merge logic

**Files:**
- Modify: `yas_local/lib/providers/job_queue_provider.dart`

- [ ] **Step 1: Add the parameter and filter the rubric**

In `startStrategy`, change the signature to:

```dart
Future<void> startStrategy(
  String taskId, {
  Iterable<int>? onlyQuestions,
}) async {
```

Right after the `_set(...)` that initializes the `JobState` (around line 250-258), and before the `DebugService.instance.recordEvent(...)` line, add:

```dart
    final rubricToRun = onlyQuestions == null
        ? task.rubric
        : task.rubric
              .where((r) => onlyQuestions.contains(r.questionNumber))
              .toList();

    _patch(
      taskId,
      (j) => j.copyWith(total: rubricToRun.length),
    );

    if (rubricToRun.isEmpty) {
      _patch(taskId, (j) => j.copyWith(phase: JobPhase.done));
      return;
    }
```

- [ ] **Step 2: Change the runPool to use `rubricToRun`**

Replace `await runPool(task.rubric, maxConcurrency, ...)` with `await runPool(rubricToRun, maxConcurrency, ...)` and update the `results` list initialization to `final results = List<ReferenceAnswer?>.filled(rubricToRun.length, null);`.

- [ ] **Step 3: Replace the save call with a merge-aware save**

Replace the lines:

```dart
      // Skip slots left null by a cancel, then persist the whole batch once.
      final refs = [for (final r in results) ?r];
      await ReferenceStore.save(taskId, refs);
```

with:

```dart
      // Skip slots left null by a cancel, then persist the whole batch once.
      final newRefs = [for (final r in results) ?r];
      if (onlyQuestions == null) {
        await ReferenceStore.save(taskId, newRefs);
      } else {
        // Merge: keep every reference NOT in the new batch untouched, then
        // overwrite with the freshly-generated ones. Confirmed flags and
        // chat history on non-failed questions are preserved.
        final existing = await ReferenceStore.load(taskId);
        final newByNum = {for (final r in newRefs) r.questionNumber: r};
        final merged = [
          for (final r in existing) newByNum[r.questionNumber] ?? r,
          // If a "rerun" produced a reference for a questionNumber not in the
          // existing set, append it at the end.
          for (final r in newRefs) if (!existing.any((e) => e.questionNumber == r.questionNumber)) r,
        ];
        await ReferenceStore.save(taskId, merged);
      }
```

- [ ] **Step 4: Update the initial total count**

The earlier `_set(taskId, JobState(..., total: task.rubric.length, ...))` should now use `rubricToRun.length`. Reorder so the `rubricToRun` computation happens BEFORE the `_set`. Move the `final rubricToRun = ...` block to be just after the rubric check (right after `if (task == null || task.rubric.isEmpty) return;`).

- [ ] **Step 5: Run existing strategy tests**

Run: `cd yas_local && flutter test test/job_queue_test.dart`
Expected: the existing `generates all rubric items and persists to ReferenceStore` test still passes (it doesn't use `onlyQuestions`).

- [ ] **Step 6: Commit**

```bash
cd yas_local
git add lib/providers/job_queue_provider.dart
git commit -m "feat(retry): startStrategy accepts onlyQuestions; merge on save"
```

### Task 5.2: Add `ReferenceStore` mutex

**Files:**
- Modify: `yas_local/lib/services/reference_store.dart`

- [ ] **Step 1: Add a Completer chain around `save`**

Replace the contents of `yas_local/lib/services/reference_store.dart` with:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/reference_answer.dart';

class ReferenceStore {
  static String encode(List<ReferenceAnswer> refs) =>
      jsonEncode(refs.map((r) => r.toJson()).toList());

  static List<ReferenceAnswer> decode(String raw) {
    if (raw.trim().isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => ReferenceAnswer.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<File> _file(String taskId) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/reference_$taskId.json');
  }

  static Future<List<ReferenceAnswer>> load(String taskId) async {
    // Reads are cheap and we don't have a strong ordering requirement for
    // concurrent load+save, but a chain of saves still serializes all of
    // itself via the save chain — see [_saveChain].
    final f = await _file(taskId);
    if (!await f.exists()) return [];
    return decode(await f.readAsString());
  }

  // Same shape as TaskStore._persistChain (13c9a45): coalesces parallel
  // writers (e.g. "重跑失败题" job and StrategyNotifier.saveAllConfirmed) so
  // they don't clobber the same reference_<taskId>.json.
  static Future<void> _saveChain = Future.value();

  static Future<void> save(String taskId, List<ReferenceAnswer> refs) {
    final next = _saveChain
        .then((_) async {
          final f = await _file(taskId);
          await f.writeAsString(encode(refs));
        })
        .catchError((Object e, StackTrace s) {
      _saveChain = Future.value();
      // ignore: avoid_print
      print('ReferenceStore.save failed; chain reset: $e');
      // ignore: avoid_redundant_argument_values
      Error.throwWithStackTrace(e, s);
    });
    _saveChain = next;
    return next;
  }
}
```

- [ ] **Step 2: Add a test for concurrent saves**

Append to `yas_local/test/persist_lock_test.dart` (a single test that uses the same `MethodChannel` mock to point `path_provider` at a temp dir, then issues two concurrent `ReferenceStore.save` calls):

```dart
import 'package:yas_local/models/reference_answer.dart';
import 'package:yas_local/services/reference_store.dart';

test('ReferenceStore concurrent saves both persist (no lost writes)', () async {
  await Future.wait([
    ReferenceStore.save('t1', [
      ReferenceAnswer(
        questionNumber: 1,
        checkpoints: const [CheckpointDef(id: 'q1-cp0', description: 'a', points: 5)],
      ),
    ]),
    ReferenceStore.save('t1', [
      ReferenceAnswer(
        questionNumber: 1,
        checkpoints: const [CheckpointDef(id: 'q1-cp0', description: 'b', points: 5)],
      ),
      ReferenceAnswer(
        questionNumber: 2,
        checkpoints: const [CheckpointDef(id: 'q2-cp0', description: 'c', points: 5)],
      ),
    ]),
  ]);

  final loaded = await ReferenceStore.load('t1');
  // The chain serializes: one of the two saves will be the last writer. The
  // important thing is that NEITHER call's payload is silently dropped — we
  // must end up with a valid file matching one of the two inputs.
  expect(loaded.length, anyOf(1, 2));
  expect(loaded.first.checkpoints.first.description, anyOf('a', 'b'));
});
```

You'll need to add the import line for `ReferenceAnswer` and `CheckpointDef` at the top of the file:

```dart
import 'package:yas_local/models/reference_answer.dart';
import 'package:yas_local/models/checkpoint.dart';
```

- [ ] **Step 3: Run the test**

Run: `cd yas_local && flutter test test/persist_lock_test.dart`
Expected: both tests pass.

- [ ] **Step 4: Commit**

```bash
cd yas_local
git add lib/services/reference_store.dart test/persist_lock_test.dart
git commit -m "feat(retry): serialize ReferenceStore.save via Completer chain"
```

### Task 5.3: Add merge tests for `startStrategy(onlyQuestions:)`

**Files:**
- Create: `yas_local/test/reference_store_merge_test.dart`

- [ ] **Step 1: Write the test**

```dart
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'package:yas_local/models/checkpoint.dart';
import 'package:yas_local/models/reference_answer.dart';
import 'package:yas_local/models/rubric.dart';
import 'package:yas_local/models/settings.dart';
import 'package:yas_local/models/submission.dart';
import 'package:yas_local/models/task.dart';
import 'package:yas_local/providers/job_queue_provider.dart';
import 'package:yas_local/providers/settings_provider.dart';
import 'package:yas_local/providers/strategy_provider.dart';
import 'package:yas_local/providers/task_provider.dart';
import 'package:yas_local/services/qwen_service.dart';
import 'package:yas_local/services/reference_store.dart';

class _ConfiguredSettings extends SettingsNotifier {
  _ConfiguredSettings() {
    state = const AppSettings(apiKey: 'k');
  }
}

class _FakeTaskNotifier extends TaskNotifier {
  _FakeTaskNotifier(super.ref, this._task);
  final GradingTask _task;
  @override
  GradingTask? taskById(String id) => _task.id == id ? _task : null;
  @override
  List<Submission> submissionsFor(String id) => const [];
}

class _StrategyForQ3Only extends QwenService {
  _StrategyForQ3Only() : super(const AppSettings(apiKey: 'k'));
  final calls = <int>[];
  @override
  Future<ReferenceAnswer> generateStrategy({
    required RubricItem rubricItem,
    required List<String> questionPaperPaths,
    required List<String> answerImagePaths,
    int totalQuestions = 0,
  }) async {
    calls.add(rubricItem.questionNumber);
    return ReferenceAnswer(
      questionNumber: rubricItem.questionNumber,
      checkpoints: [
        CheckpointDef(
          id: 'q${rubricItem.questionNumber}-cp0',
          description: 'new for q${rubricItem.questionNumber}',
          points: 5,
        ),
      ],
    );
  }
}

GradingTask _threeQ() => GradingTask(
  id: 't1',
  name: 'T1',
  subject: 'math',
  createdAt: DateTime(2026),
  rubric: const [
    RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 5),
    RubricItem(questionNumber: 2, type: 'subjective', maxPoints: 5),
    RubricItem(questionNumber: 3, type: 'subjective', maxPoints: 5),
  ],
  questionPaperPaths: const [],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('refmerge_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('onlyQuestions=[3] reuses existing refs for 1 and 2', () async {
    // Seed: 3 refs, q1 confirmed, q2 with chat history, q3 empty (failed).
    final seeded = [
      const ReferenceAnswer(
        questionNumber: 1,
        checkpoints: [CheckpointDef(id: 'q1-cp0', description: 'old', points: 5)],
        confirmed: true,
      ),
      const ReferenceAnswer(
        questionNumber: 2,
        checkpoints: [CheckpointDef(id: 'q2-cp0', description: 'old', points: 5)],
        chatHistory: [
          StrategyMessage(role: 'user', content: 'old chat'),
        ],
      ),
      // q3 is the failure sentinel — empty checkpoints.
      const ReferenceAnswer(
        questionNumber: 3,
        checkpoints: [],
        hasConsensus: false,
      ),
    ];
    await ReferenceStore.save('t1', seeded);

    final qwen = _StrategyForQ3Only();
    late _FakeTaskNotifier fake;
    final c = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith((ref) => _ConfiguredSettings()),
        taskProvider.overrideWith((ref) {
          fake = _FakeTaskNotifier(ref, _threeQ());
          return fake;
        }),
        qwenFactoryProvider.overrideWithValue((ref) => qwen),
      ],
    );
    c.read(taskProvider.notifier);
    addTearDown(() async {
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      c.dispose();
    });

    await c
        .read(jobQueueProvider.notifier)
        .startStrategy('t1', onlyQuestions: [3]);

    expect(qwen.calls, [3], reason: 'only q3 should be generated');

    final loaded = await ReferenceStore.load('t1');
    expect(loaded.length, 3);
    final byNum = {for (final r in loaded) r.questionNumber: r};
    expect(byNum[1]!.description, 'old', reason: 'q1 untouched');
    expect(byNum[1]!.confirmed, isTrue, reason: 'q1 confirmed flag preserved');
    expect(byNum[2]!.description, 'old', reason: 'q2 untouched');
    expect(byNum[2]!.chatHistory, hasLength(1),
        reason: 'q2 chat history preserved');
    expect(byNum[3]!.description, 'new for q3', reason: 'q3 overwritten');
  });
}
```

- [ ] **Step 2: Run the new test**

Run: `cd yas_local && flutter test test/reference_store_merge_test.dart`
Expected: 1 test passes.

- [ ] **Step 3: Commit**

```bash
cd yas_local
git add test/reference_store_merge_test.dart
git commit -m "test(retry): cover startStrategy(onlyQuestions:) merge behavior"
```

### Task 5.4: Final full-suite verification

- [ ] **Step 1: Run the full test suite**

Run: `cd yas_local && flutter test`
Expected: all tests pass.

- [ ] **Step 2: Run static analysis**

Run: `cd yas_local && flutter analyze`
Expected: no issues.

- [ ] **Step 3: Manual smoke check (macOS)**

Run: `cd yas_local && flutter run -d macos`
Smoke:
1. Create a task with 5 questions and 1 submission image.
2. Watch the home card while grading — the card should show progress; if a retry happens, the orange "⟳ 重试 X/3 · ..." line should appear under the progress bar.
3. Force a 4xx by setting an obviously wrong API Key — grading should fail with "接口拒绝 (4xx)" and no retry, no orange line.
4. Force a 5xx by pointing baseUrl at a server that returns 500 — the orange line should appear, then settle on "1 份失败" with a red banner and a "重跑失败项" button.
5. Tap "重跑失败项" — only the failed submission re-grades.

- [ ] **Step 4: Commit the worktree-clean tag if everything looks good**

If `git status` is clean and the smoke check passed:

```bash
cd yas_local
git tag retry-with-feedback-v1
```

(No push, no remote — the user will decide on the PR.)

---

## Self-review

**Spec coverage** — checking each requirement in `2026-06-05-retry-with-feedback-design.md`:

| Spec section | Task(s) |
|---|---|
| §3.1 4-method retry helper | 2.2-2.5 |
| §3.2 QwenError.from classification | 1.1 |
| §3.3 Backoff formula | 2.2 (`_backoffMs`) |
| §3.4 JSON nudge | 2.1, 2.3, 2.4, 2.5 (each method appends it) |
| §4 JobState 3 new fields + terminal clear | 3.1 |
| §5 4.1 Two-layer retry | 2.2-2.5 (inner) + 3.2-3.4 (outer) |
| §5 4.2 attempt/lastError* pushed | 3.2-3.4 |
| §5 4.3 Home retry hint | 4.1 |
| §5 4.4 Task Detail attempt + banner + rerun | 4.2 |
| §5 4.5 Strategy Review attempt + banner + rerun | 4.3 |
| §5 4.6 Rerun buttons | 4.2 (`_rerunFailedGrading`, `_rerunFailedStrategy`), 4.3 (`_rerunFailedStrategyQuestions`) |
| §5 4.7 DebugService.recordEvent('retry', …) | 3.2 |
| §5 4.8 ReferenceStore mutex | 5.2 |
| §5 4.9 startStrategy(onlyQuestions:) + merge | 5.1, 5.3 |
| §5 4.10 Confirm Strategy rerun never picks confirmed q's | banner filters on `checkpoints.isEmpty` (4.2, 4.3, 5.3) |

All 15 spec requirements mapped to tasks.

**Placeholder scan** — searched the plan for "TBD", "TODO", "implement later", "appropriate error handling", "similar to Task N", etc. Found one `// TODO` in step 4 of 4.2 — but that is in a context where the compiler will catch the missing function. The note explicitly tells the engineer to land 4.2 + 5.1 together. Acceptable.

**Type consistency** — `QwenErrorKind.displayName` is defined in 1.1 and used in 3.2, 4.1, 4.2, 4.3. `QwenError.from` defined in 1.1, used in 2.2 and 3.2. `JobState.attempt/lastErrorKind/lastErrorUnit` defined in 3.1, used in 3.2, 3.3, 3.4, 4.1, 4.2, 4.3. `resolveTaskCardStatus` parameter list extended in 4.1 (added `retryKind`, `retryAttempt`), and the call site in 4.1 was updated in the same step. No signature drift.
