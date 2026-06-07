# JSON Retry Nudge with Failure Snippet — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enrich `jsonRetryNudge` in `QwenService._retryingRequest` (and `refineStrategy`'s ad-hoc loop) so that on a JSON parse failure, the next attempt's user text includes a 200-300 character cleaned snippet of the previous bad output — letting the model see what to fix instead of a generic "please return clean JSON" sentence. `gradePaper` is explicitly excluded (student OCR PII risk).

**Architecture:** Two-layer change.
- **Data:** `JsonParseException` gains a `cleanedSnippet` field (computed at the two throw sites via the existing `_stripThinking` helper, truncated to 300 chars, null if empty).
- **Composition:** `AppPrompts.jsonRetryNudgeWithSnippet(snippet)` wraps the snippet in 4-backtick outer / 3-backtick inner fences with a "do not verbatim copy" disclaimer. `QwenService._retryingRequest`'s `bodyBuilder` signature gains a third `Object? lastError` parameter; the loop captures `lastError = e` on each throw. Three caller closures (`generateStrategy`, `identifyQuestions`, `gradePaper`) gate the snippet via `scope != 'grade'`. `refineStrategy` is refactored so its retry messages close over the `JsonParseException` from the previous attempt.

**Tech Stack:** Flutter + Riverpod, Dart SDK ^3.12.0, Dio, `flutter_test`, hand-rolled `HttpClientAdapter` mocks (the project's existing pattern — no mockito).

**Avoid colliding with:** None. No DebugService API change, no model change, no settings change. Pure additive behavior on 3 of 4 LLM call sites.

---

## File Structure

**Modified (3 files):**

- `lib/services/json_extractor.dart` — add `cleanedSnippet` field to `JsonParseException`; compute at both throw sites (lines 83-86 and 158-161). No new functions.
- `lib/services/prompts.dart` — add `jsonRetryNudgeWithSnippet(String snippet)` function. `jsonRetryNudge` constant stays untouched.
- `lib/services/qwen_service.dart` — extend `_retryingRequest` bodyBuilder signature to 3 params; thread `lastError` through the loop; update 3 caller closures; refactor `refineStrategy` for-loop so the retry messages close over the previous `JsonParseException`.

**New tests (extend 3 existing files, no new files):**

- `test/json_extractor_test.dart` — add `JsonParseException.cleanedSnippet` round-trip tests.
- `test/qwen_service_retry_test.dart` — extend the "bad json then ok" test family to cover snippet presence/absence per scope; add "cleanedSnippet null → static nudge fallback" test; add "grade scope never includes snippet" test.
- `test/qwen_service_test.dart` — add `refineStrategy` snippet test.
- `test/verify_prompt_runtime_test.dart` — extend "D. Probe" block to assert bad-JSON snippet presence in attempt 2.

**Spec doc update:**

- `docs/superpowers/specs/2026-06-05-retry-with-feedback-design.md` §3.3 — rewrite the "nudge 永远 ~30 字" contract to the new 2-mode contract (static OR with-snippet). Committed alongside the code that changes it.

---

## PR 1: Field + Function + Unit Tests (Zero Behavior Change)

### Task 1.1: Add `cleanedSnippet` field to `JsonParseException`

**Files:**
- Modify: `lib/services/json_extractor.dart:6-19` (the `JsonParseException` class declaration)

- [ ] **Step 1: Write the failing test for the new field**

In `test/json_extractor_test.dart`, find the existing `group('JsonExtractor.requireObject', ...)` block (starts around line 62). The existing test `'JsonParseException 携带原始内容'` is at lines 121-130. Add the following test **right after** that test, still inside the same `group`:

```dart
test('JsonParseException.cleanedSnippet strips <think> and truncates to 300 chars', () {
  // Build a long bad output: 400 chars of garbage AFTER a think block, to
  // exercise the truncation.
  final long = '<think>internal reasoning</think>' + ('x' * 400);
  try {
    JsonExtractor.requireObject(long);
    fail('应该 throw');
  } on JsonParseException catch (e) {
    expect(e.cleanedSnippet, isNotNull);
    expect(e.cleanedSnippet!.length, lessThanOrEqualTo(301),  // 300 + ellipsis
        reason: 'snippet must be truncated to 300 chars');
    expect(e.cleanedSnippet, isNot(contains('<think>')),
        reason: 'snippet must not include think block content');
    expect(e.cleanedSnippet, startsWith('x'),
        reason: 'snippet is the post-think garbage');
  }
});

test('JsonParseException.cleanedSnippet is null when cleaned text is empty', () {
  // Output is JUST a think block with nothing after — cleaned text is empty.
  try {
    JsonExtractor.requireObject('<think>only thinking, no output</think>');
    fail('应该 throw');
  } on JsonParseException catch (e) {
    expect(e.cleanedSnippet, isNull,
        reason: 'cleanedSnippet null when nothing left after stripping think');
  }
});
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run: `cd yas_local && flutter test test/json_extractor_test.dart --name 'cleanedSnippet'`
Expected: FAIL — `JsonParseException` has no `cleanedSnippet` getter.

- [ ] **Step 3: Add the field to `JsonParseException`**

In `lib/services/json_extractor.dart`, replace the class declaration (lines 6-19) with:

```dart
class JsonParseException implements Exception {
  final String message;
  final String rawContent;

  /// Cleaned, truncated snippet of the LLM's output that failed to parse.
  /// `null` when the cleaned text is empty (e.g. response was just
  /// `<think>...</think>` with nothing after). The caller decides whether
  /// to use a plain nudge in that case.
  final String? cleanedSnippet;

  const JsonParseException(
    this.message, {
    required this.rawContent,
    this.cleanedSnippet,
  });

  @override
  String toString() {
    final snippet = rawContent.length > 300
        ? '${rawContent.substring(0, 300)}…'
        : rawContent;
    return 'JsonParseException: $message\n--- raw content ---\n$snippet';
  }
}
```

- [ ] **Step 4: Run the new tests to verify they pass**

Run: `cd yas_local && flutter test test/json_extractor_test.dart --name 'cleanedSnippet'`
Expected: PASS (2 tests).

- [ ] **Step 5: Run the full `json_extractor_test.dart` to check for regressions**

Run: `cd yas_local && flutter test test/json_extractor_test.dart`
Expected: all existing tests still pass — `cleanedSnippet` defaults to `null` so existing constructors (`throw JsonParseException(...)` with two args) work via the optional named param.

- [ ] **Step 6: Commit**

```bash
cd yas_local
git add lib/services/json_extractor.dart test/json_extractor_test.dart
git commit -m "feat(nudge): add JsonParseException.cleanedSnippet field"
```

---

### Task 1.2: Compute `cleanedSnippet` at both throw sites

**Files:**
- Modify: `lib/services/json_extractor.dart:83-86` and `lib/services/json_extractor.dart:158-161` (the two `throw JsonParseException(...)` sites)

- [ ] **Step 1: Locate both throw sites**

Open `lib/services/json_extractor.dart`. The two throw sites are:
- `requireObject` (around line 83-86): the final `throw` in the function
- `requireList` (around line 158-161): the final `throw` in the function

Both currently look like:
```dart
throw JsonParseException(
  'No valid JSON ...',
  rawContent: text,
);
```

- [ ] **Step 2: Update the `requireObject` throw site**

Replace the `throw` block at the end of `requireObject` (the one with the `'No valid JSON object found in AI response.'` message) with:

```dart
      builder.markFailed('JsonParseException: no object found');
      builder.commit();
      final cleaned = _stripThinking(text);
      final snippet = cleaned.length > 300
          ? '${cleaned.substring(0, 300)}…'
          : (cleaned.isEmpty ? null : cleaned);
      throw JsonParseException(
        'No valid JSON object found in AI response.',
        rawContent: text,
        cleanedSnippet: snippet,
      );
```

- [ ] **Step 3: Update the `requireList` throw site**

Replace the `throw` block at the end of `requireList` (the one with the `'No valid JSON list found in AI response.'` message) with:

```dart
      builder.markFailed('JsonParseException: no list found');
      builder.commit();
      final cleaned = _stripThinking(text);
      final snippet = cleaned.length > 300
          ? '${cleaned.substring(0, 300)}…'
          : (cleaned.isEmpty ? null : cleaned);
      throw JsonParseException(
        'No valid JSON list found in AI response.',
        rawContent: text,
        cleanedSnippet: snippet,
      );
```

- [ ] **Step 4: Run the unit tests**

Run: `cd yas_local && flutter test test/json_extractor_test.dart`
Expected: all tests pass, including the 2 new `cleanedSnippet` ones from Task 1.1.

- [ ] **Step 5: Commit**

```bash
cd yas_local
git add lib/services/json_extractor.dart
git commit -m "feat(nudge): compute cleanedSnippet at both throw sites"
```

---

### Task 1.3: Add `jsonRetryNudgeWithSnippet` function

**Files:**
- Modify: `lib/services/prompts.dart:6-10` (right after the existing `jsonRetryNudge` constant)

- [ ] **Step 1: Write the failing test for the new function**

Create a new test file `test/prompts_test.dart` (the project may not have one yet — check with `ls test/prompts_test.dart 2>/dev/null`; if absent, create it). The test file needs just this one test for now (extend later as needed):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/services/prompts.dart';

void main() {
  group('AppPrompts.jsonRetryNudgeWithSnippet', () {
    test('wraps snippet in 4-backtick outer / 3-backtick inner fence', () {
      final out = AppPrompts.jsonRetryNudgeWithSnippet('bad output here');
      expect(out, contains('bad output here'),
          reason: 'snippet text must appear in output');
      expect(out, contains('````json'),
          reason: 'must use 4-backtick outer fence so embedded 3-backticks '
              'do not break the fence');
      expect(out, contains('````'),
          reason: 'must close the 4-backtick fence');
      expect(out, contains('请勿逐字复述'),
          reason: 'must include the do-not-copy disclaimer');
      expect(out, contains('请只返回纯 JSON'),
          reason: 'must include the base instruction');
    });

    test('snippet with embedded ``` does not break outer fence', () {
      final out = AppPrompts.jsonRetryNudgeWithSnippet(
          'here is ```json\n{broken\n```` which is bad');
      // The 4-backtick outer fence must NOT be broken by the inner
      // 3-backtick substring inside the snippet.
      expect(out, contains('````json'),
          reason: 'outer fence must remain intact');
      // The closing outer fence must still be findable.
      final outerOpen = out.indexOf('````json');
      final outerClose = out.indexOf('````', outerOpen + 8);
      expect(outerClose, greaterThan(outerOpen),
          reason: 'outer fence closes after the open');
    });
  });
}
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run: `cd yas_local && flutter test test/prompts_test.dart`
Expected: FAIL — `AppPrompts.jsonRetryNudgeWithSnippet` does not exist.

- [ ] **Step 3: Add the function in `prompts.dart`**

In `lib/services/prompts.dart`, **immediately after** the existing `jsonRetryNudge` constant (lines 6-10) and **before** the `_outputProtocol` function (line 14-15), insert:

```dart
  /// Builds a JSON-retry nudge that quotes a previous failure snippet so the
  /// model can see what to fix. [snippet] is the cleaned+truncated text from
  /// [JsonParseException.cleanedSnippet].
  ///
  /// Caller MUST ensure [snippet] is not student PII — `gradePaper` failures
  /// contain student OCR text and are explicitly excluded from this path.
  ///
  /// The snippet is wrapped in a 4-backtick outer / 3-backtick inner fence
  /// so:
  ///   1. The model cannot "fix" it by inline-merging the snippet with its
  ///      response.
  ///   2. Triple backticks that the model may have emitted inside the
  ///      snippet (e.g. ```json ... ```) do not break the outer fence.
  static String jsonRetryNudgeWithSnippet(String snippet) =>
      '\n\n注意：上一次返回的内容无法解析为 JSON。以下是模型上次原始输出（已截断，'
      '请勿逐字复述，仅用于理解错误位置）：\n\n'
      '````json\n$snippet\n````\n\n'
      '请只返回纯 JSON，不要任何解释或 <think> 内容。';
```

- [ ] **Step 4: Run the new tests to verify they pass**

Run: `cd yas_local && flutter test test/prompts_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Run static analysis**

Run: `cd yas_local && flutter analyze lib/services/prompts.dart test/prompts_test.dart`
Expected: no issues.

- [ ] **Step 6: Commit**

```bash
cd yas_local
git add lib/services/prompts.dart test/prompts_test.dart
git commit -m "feat(nudge): add jsonRetryNudgeWithSnippet with fenced snippet"
```

---

## PR 2: Wire the snippet through `_retryingRequest` and `refineStrategy`

### Task 2.1: Extend `_retryingRequest` bodyBuilder signature

**Files:**
- Modify: `lib/services/qwen_service.dart:496-502` (the helper signature) and `lib/services/qwen_service.dart:504-525` (the loop body)

- [ ] **Step 1: Extend the `bodyBuilder` typedef and signature**

In `lib/services/qwen_service.dart`, replace lines 496-502 with:

```dart
  Future<T> _retryingRequest<T>({
    required String scope,
    required Map<String, dynamic> Function(
      int attempt,
      QwenErrorKind? lastKind,
      Object? lastError,
    ) bodyBuilder,
    required T Function(String content) extract,
    void Function(int attempt)? onAttempt,
  }) async {
    const maxAttempts = 3;
    QwenErrorKind? lastKind;
    Object? lastError;
```

- [ ] **Step 2: Thread `lastError` through the loop body**

In the same helper, find the `catch (e)` block (around lines 519-555). After the line `lastKind = q.kind;` (which is right after `if (!q.shouldRetry) throw q;`), add:

```dart
        lastKind = q.kind;
        lastError = e;
```

The full catch block should now read (with the existing `_recordParseError` and backoff intact):

```dart
      } catch (e) {
        final q = QwenError.from(e);
        // 4xx is a hard "stop" — no point retrying 401 / 403 / 404.
        if (!q.shouldRetry) throw q;
        lastKind = q.kind;
        lastError = e;
        if (attempt == maxAttempts - 1) {
          // ... existing _recordParseError fire-and-forget block unchanged ...
          throw q;
        }
        final delay = _backoffMs(attempt);
        await Future<void>.delayed(Duration(milliseconds: delay));
      }
```

- [ ] **Step 3: Update the bodyBuilder call site inside the loop**

Find the line in the loop that calls `bodyBuilder(...)` (it's in the `try` block, right before the `_dio.post` call). It currently reads:

```dart
          data: bodyBuilder(attempt, lastKind),
```

Replace with:

```dart
          data: bodyBuilder(attempt, lastKind, lastError),
```

- [ ] **Step 4: Verify analyze passes**

Run: `cd yas_local && flutter analyze lib/services/qwen_service.dart`
Expected: **FAIL** with "bodyBuilder declared as 2-parameter function but called with 3" or similar at all 3 caller closures (`generateStrategy`, `identifyQuestions`, `gradePaper`). This is expected — the next 3 tasks fix each caller.

- [ ] **Step 5: Commit the partial change**

```bash
cd yas_local
git add lib/services/qwen_service.dart
git commit -m "refactor(nudge): thread lastError through _retryingRequest"
```

(The commit is intentionally mid-refactor — `flutter analyze` and tests will fail until Tasks 2.2-2.4 land. This is fine for an isolated branch.)

---

### Task 2.2: Update `generateStrategy` bodyBuilder

**Files:**
- Modify: `lib/services/qwen_service.dart:197-225` (the `_retryingRequest<ReferenceAnswer>(...)` call inside `generateStrategy`)

- [ ] **Step 1: Update the bodyBuilder closure**

In `lib/services/qwen_service.dart`, locate the `generateStrategy` method's `_retryingRequest` call (around lines 197-225). The current `bodyBuilder` parameter reads:

```dart
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
```

Replace this entire `bodyBuilder:` argument with:

```dart
      bodyBuilder: (attempt, lastKind, lastError) {
        final text = _composeUserText(
          base: userText,
          scope: 'strategy',
          lastKind: lastKind,
          lastError: lastError,
        );
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
```

- [ ] **Step 2: Add the `_composeUserText` helper**

Add a new private method to the `QwenService` class. Place it **immediately after** the `_backoffMs` method (around line 597) and **before** `_parseReferenceAnswer` (around line 599). Insert:

```dart
  /// Decide what text to send on a retry attempt. Strategy + identify use
  /// the snippet-augmented nudge; grade uses the static nudge only (PII).
  /// [base] is the original user prompt; [lastKind] / [lastError] are the
  /// previous attempt's outcome.
  String _composeUserText({
    required String base,
    required String scope,
    required QwenErrorKind? lastKind,
    required Object? lastError,
  }) {
    if (lastKind != QwenErrorKind.jsonParse) return base;
    if (scope == 'grade') {
      // Student OCR PII: never echo the bad output back to the model.
      return base + AppPrompts.jsonRetryNudge;
    }
    if (lastError is JsonParseException && lastError.cleanedSnippet != null) {
      return base + AppPrompts.jsonRetryNudgeWithSnippet(
        lastError.cleanedSnippet!);
    }
    return base + AppPrompts.jsonRetryNudge;
  }
```

This requires importing `json_extractor.dart` in `qwen_service.dart`. The import already exists at line 15, so no change needed.

- [ ] **Step 3: Run static analysis**

Run: `cd yas_local && flutter analyze lib/services/qwen_service.dart`
Expected: **2 errors remaining**, both in `identifyQuestions` and `gradePaper` bodyBuilders. The 3 caller closures are now consistent in that `generateStrategy` is fixed; the others will be fixed in Tasks 2.3 and 2.4.

- [ ] **Step 4: Commit the partial change**

```bash
cd yas_local
git add lib/services/qwen_service.dart
git commit -m "refactor(nudge): route generateStrategy bodyBuilder through _composeUserText"
```

---

### Task 2.3: Update `identifyQuestions` bodyBuilder

**Files:**
- Modify: `lib/services/qwen_service.dart:343-371` (the `_retryingRequest<List<IdentifiedQuestion>>(...)` call inside `identifyQuestions`)

- [ ] **Step 1: Update the bodyBuilder closure**

In `lib/services/qwen_service.dart`, locate the `identifyQuestions` method's `_retryingRequest` call (around lines 343-371). The current `bodyBuilder` parameter reads:

```dart
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
```

Replace this entire `bodyBuilder:` argument with:

```dart
      bodyBuilder: (attempt, lastKind, lastError) {
        final text = _composeUserText(
          base: userText,
          scope: 'identify',
          lastKind: lastKind,
          lastError: lastError,
        );
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
```

- [ ] **Step 2: Run static analysis**

Run: `cd yas_local && flutter analyze lib/services/qwen_service.dart`
Expected: **1 error remaining**, in `gradePaper` bodyBuilder.

- [ ] **Step 3: Commit**

```bash
cd yas_local
git add lib/services/qwen_service.dart
git commit -m "refactor(nudge): route identifyQuestions bodyBuilder through _composeUserText"
```

---

### Task 2.4: Update `gradePaper` bodyBuilder

**Files:**
- Modify: `lib/services/qwen_service.dart:416-477` (the `_retryingRequest<List<QuestionGradeResult>>(...)` call inside `gradePaper`)

- [ ] **Step 1: Update the bodyBuilder closure**

In `lib/services/qwen_service.dart`, locate the `gradePaper` method's `_retryingRequest` call (around lines 416-477). The current `bodyBuilder` parameter reads:

```dart
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
```

Replace this entire `bodyBuilder:` argument with:

```dart
      bodyBuilder: (attempt, lastKind, lastError) {
        final text = _composeUserText(
          base: userText,
          scope: 'grade',
          lastKind: lastKind,
          lastError: lastError,
        );
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
```

The `_composeUserText` helper's `scope == 'grade'` branch (Task 2.2 step 2) ensures the snippet is never appended for grading.

- [ ] **Step 2: Run static analysis — expect all green**

Run: `cd yas_local && flutter analyze lib/services/qwen_service.dart`
Expected: no issues.

- [ ] **Step 3: Run existing `qwen_service_retry_test.dart` — should still pass**

Run: `cd yas_local && flutter test test/qwen_service_retry_test.dart`
Expected: all existing tests pass (5 tests + the refineStrategy retry test = 6 tests). The "bad json then ok" test asserts the static nudge is in the second attempt — that assertion still holds because `identifyQuestions` (the test's target) goes through the with-snippet path AND the static nudge substring `'无法解析为 JSON'` is still present in the with-snippet output (see §3.3 of the spec for the wording).

- [ ] **Step 4: Commit**

```bash
cd yas_local
git add lib/services/qwen_service.dart
git commit -m "refactor(nudge): route gradePaper bodyBuilder through _composeUserText (PII guard)"
```

---

### Task 2.5: Refactor `refineStrategy` to use snippet in its retry messages

**Files:**
- Modify: `lib/services/qwen_service.dart:228-321` (the entire `refineStrategy` method)

- [ ] **Step 1: Write the failing test for the snippet-in-retry behavior**

In `test/qwen_service_test.dart`, find the top-level `void main()` (starts around line 48). Add a new test (alongside the existing tests) — it uses the same `_MockAdapter` pattern as the existing tests in this file:

```dart
test('refineStrategy: bad JSON on attempt 1 includes snippet in attempt 2 user text', () async {
  // Adapter that returns bad JSON on the first call, good JSON on the
  // second. Captures the user-side text of each call.
  final sentUserTexts = <String>[];
  final adapter = _MockAdapter((options) {
    final data = options.data as Map<String, dynamic>;
    final msgs = data['messages'] as List;
    // The refineStrategy retry replaces only the LAST user message; the
    // previous messages (system + assistant ack) stay the same. So we can
    // pick out the last 'user' role message's content text.
    final userMessages = msgs.whereType<Map<String, dynamic>>()
        .where((m) => m['role'] == 'user');
    final last = userMessages.last as Map;
    final content = last['content'];
    // In refineStrategy the user content is a plain string, not a list.
    sentUserTexts.add(content as String);
    if (sentUserTexts.length == 1) {
      // Bad JSON containing a recognizable sentinel.
      return ResponseBody.fromString(
        '{"choices":[{"message":{"content":"BADSENTINEL not parseable"},"role":"assistant"}}]}',
        200,
        headers: {'content-type': ['application/json']},
      );
    }
    // Good JSON on retry.
    return ResponseBody.fromString(
      '{"choices":[{"message":{"content":"{\\"checkpoints\\":[{\\"description\\":\\"x\\",\\"points\\":5}]}"},"role":"assistant"}}]}',
      200,
      headers: {'content-type': ['application/json']},
    );
  });

  final s = const AppSettings(apiKey: 'k', baseUrl: 'https://example.test/v1');
  final svc = QwenService(s);
  svc.dio.httpClientAdapter = adapter;

  final rubric = const RubricItem(
    questionNumber: 1,
    type: 'subjective',
    maxPoints: 5,
  );
  final current = ReferenceAnswer(
    questionNumber: 1,
    checkpoints: const [],
  );

  await svc.refineStrategy(
    rubric: rubric,
    current: current,
    chatHistory: const [],
    userMessage: '把第 2 步拆细一点',
  );

  expect(sentUserTexts.length, 2, reason: 'should have made 2 attempts');
  expect(sentUserTexts.first, isNot(contains('BADSENTINEL')),
      reason: 'first attempt does not yet see the snippet');
  expect(sentUserTexts.last, contains('BADSENTINEL'),
      reason: 'second attempt user text includes the previous failure snippet');
});
```

This test requires the import `package:yas_local/models/reference_answer.dart` at the top of `qwen_service_test.dart`. Check if it's already imported; if not, add it. (The file currently imports `rubric.dart` and `settings.dart` but probably not `reference_answer.dart`.)

- [ ] **Step 2: Run the new test to verify it fails**

Run: `cd yas_local && flutter test test/qwen_service_test.dart --name 'bad JSON on attempt 1 includes snippet'`
Expected: FAIL — the current `refineStrategy` does not include the previous attempt's bad output in its retry.

- [ ] **Step 3: Refactor `refineStrategy`'s for-loop**

In `lib/services/qwen_service.dart`, replace the entire `refineStrategy` method body (lines 228-321, from `Future<ReferenceAnswer> refineStrategy({` through the closing `}` of the method) with the refactored version. The key change is moving the `messages` list construction **into** the loop body, so the retry attempt can close over the previous `JsonParseException` (`_previousParseSnippet`):

```dart
  Future<ReferenceAnswer> refineStrategy({
    required RubricItem rubric,
    required ReferenceAnswer current,
    required List<StrategyMessage> chatHistory,
    required String userMessage,
  }) async {
    final checkpointLines =
        current.checkpoints.map((c) => '- ${c.description}（${c.points}分）').join('\n');
    final questionLabel = rubric.questionText.isEmpty
        ? '第 ${rubric.questionNumber} 题'
        : rubric.questionText;

    // Build multi-turn messages: system context first, then prior history, then new user message
    final baseMessages = <Map<String, dynamic>>[
      {
        'role': 'user',
        'content': AppPrompts.refineStrategySystem(
          questionLabel: questionLabel,
          maxPoints: rubric.maxPoints,
          checkpointLines: checkpointLines,
        ),
      },
      {
        'role': 'assistant',
        'content': AppPrompts.refineStrategyAssistantAck(),
      },
      for (final m in chatHistory) {'role': m.role, 'content': m.content},
    ];

    // Lightweight one-shot retry: if the first response fails JSON parsing,
    // re-send with the new user turn appended with jsonRetryNudge (with or
    // without a snippet, depending on whether the previous attempt produced
    // a parseable cleanedSnippet). We don't go through _retryingRequest
    // because the multi-turn message structure doesn't match its bodyBuilder
    // contract.
    //
    // We also catch DioException so transport errors (timeout, 5xx, network)
    // retry just like _retryingRequest would. This matches the rest of the
    // service's retry contract — a chat retry must not be strictly less
    // resilient than a grade/strategy call. Non-retryable kinds (4xx) are
    // rethrown immediately; retryable kinds go through _backoffMs(attempt).
    String? previousParseSnippet;
    for (var attempt = 0; attempt < 2; attempt++) {
      final userText = attempt == 0
          ? userMessage
          : (previousParseSnippet == null
              ? userMessage + AppPrompts.jsonRetryNudge
              : userMessage + AppPrompts.jsonRetryNudgeWithSnippet(
                  previousParseSnippet!));
      final messages = <Map<String, dynamic>>[
        ...baseMessages,
        {'role': 'user', 'content': userText},
      ];

      try {
        final resp = await _dio.post(
          '/chat/completions',
          data: {
            'model': settings.vlModel,
            'messages': messages,
          },
          options: Options(extra: {'_qwen_scope': 'refine'}),
        );
        final content = resp.data['choices'][0]['message']['content'] as String;
        try {
          final payload = JsonExtractor.requireObjectWithReasoning(content, scope: 'refine');
          return _parseReferenceAnswer(
            current.questionNumber,
            payload.json,
            reasoning: payload.reasoning,
          );
        } on JsonParseException catch (e) {
          DebugService.instance.recordQwenCall(QwenCallRecord(
            timestamp: DateTime.now(),
            scope: 'refine',
            model: settings.vlModel,
            endpoint: '/chat/completions',
            statusCode: resp.statusCode,
            elapsedMs: 0,
            status: QwenCallStatus.parseError,
            messages: redactBase64Messages(messages), // one-shot chat, useful to see what we sent
            errorMessage: e.toString(),
          ));
          previousParseSnippet = e.cleanedSnippet;
          if (attempt == 1) rethrow;
        }
      } on DioException catch (e) {
        final q = QwenError.from(e);
        // 4xx is a hard stop (config / auth problem). Honor shouldRetry so
        // the behavior matches _retryingRequest for retryable kinds.
        if (!q.shouldRetry) throw q;
        if (attempt == 1) throw q;
        final delay = _backoffMs(attempt);
        await Future<void>.delayed(Duration(milliseconds: delay));
      }
    }
    // Unreachable: the loop either returns or rethrows.
    throw StateError('unreachable: refineStrategy retry loop exhausted');
  }
```

Note the differences from the original:
1. The `messages` list is now constructed **inside** the loop body (so each attempt gets its own variant).
2. The closing `{...baseMessages, {'role': 'user', 'content': userText}}` no longer does `baseMessages.sublist(0, baseMessages.length - 1)` — instead, the loop body uses `baseMessages` (which is the system + assistant + chat history but **not** the latest user message) and appends the freshly-constructed latest user message.
3. The `previousParseSnippet` closure variable carries the snippet forward.
4. The `on JsonParseException catch (e)` block sets `previousParseSnippet = e.cleanedSnippet` so the next iteration's `userText` can use it.

- [ ] **Step 4: Run the new test to verify it passes**

Run: `cd yas_local && flutter test test/qwen_service_test.dart --name 'bad JSON on attempt 1 includes snippet'`
Expected: PASS.

- [ ] **Step 5: Run the full `qwen_service_test.dart` and `qwen_service_retry_test.dart` to check for regressions**

Run: `cd yas_local && flutter test test/qwen_service_test.dart test/qwen_service_retry_test.dart`
Expected: all tests pass. In particular, the existing `refineStrategy: DioException on attempt 1 is retried` test in `qwen_service_retry_test.dart` must still pass — the refactor preserves the Dio retry path.

- [ ] **Step 6: Commit**

```bash
cd yas_local
git add lib/services/qwen_service.dart test/qwen_service_test.dart
git commit -m "feat(nudge): refineStrategy retry includes previous failure snippet"
```

---

### Task 2.6: Add focused retry-test coverage for the snippet behavior

**Files:**
- Modify: `test/qwen_service_retry_test.dart` (extend the existing "bad json then ok" test family with 3 new tests)

- [ ] **Step 1: Add a parameterized bad-JSON helper**

In `test/qwen_service_retry_test.dart`, locate the existing `_badJson()` helper at lines 56-60. Add a sibling helper **right after it** (still at the top level, not inside `main`):

```dart
ResponseBody _badJsonWith(String body) => ResponseBody.fromString(
  '{"choices":[{"message":{"content":${jsonEncode(body)}},"role":"assistant"}}]}',
  200,
  headers: {'content-type': ['application/json']},
);
```

This requires `import 'dart:convert';` at the top of the file. Check if it's already there; if not, add it. (Looking at the file, it only imports `dart:async` and `dart:typed_data` from `dart:` — so `dart:convert` must be added.)

- [ ] **Step 2: Add 3 new tests in the `void main() { ... }` block**

Add these tests inside the `void main()` block, **after** the existing "bad json then ok" test (which ends at line 113):

```dart
  test('identify: bad JSON with sentinel → 2nd attempt user text contains sentinel', () async {
    final s = const AppSettings(apiKey: 'k', baseUrl: 'https://example.test/v1');
    final svc = QwenService(s);
    final a = _CountingAdapter((i, _) =>
        i == 0 ? _badJsonWith('BADSENTINEL_xyz garbage not json') : _ok200());
    svc.dio.httpClientAdapter = a;

    await svc.identifyQuestions(const []);
    expect(a.calls, 2);
    expect(a.sentUserTexts.last, contains('BADSENTINEL_xyz'),
        reason: 'previous failure snippet is in the 2nd request body');
  });

  test('grade: bad JSON → 2nd attempt user text does NOT contain sentinel '
      '(PII guard)', () async {
    // The grade retry must use the STATIC nudge, not the snippet-augmented
    // one, because the snippet would echo the student's OCR back to the
    // model on the next attempt.
    final s = const AppSettings(apiKey: 'k', baseUrl: 'https://example.test/v1');
    final svc = QwenService(s);
    final a = _CountingAdapter((i, _) =>
        i == 0 ? _badJsonWith('STUDENT_OCR_SENTINEL') : _ok200());
    svc.dio.httpClientAdapter = a;

    // Use gradePaper. A valid rubric + a dummy image path is required.
    // We need a real or stub image for ImageCompressor.compressedPathFor;
    // the simplest approach: pass an empty path. ImageCompressor returns
    // its input unchanged for paths that don't exist (caller is expected
    // to feed real files in production). The test only cares about the
    // HTTP prompt, not the image bytes.
    await svc.gradePaper(
      imagePath: '/tmp/__no_such_file.jpg',
      questionPaperPaths: const [],
      rubric: const [RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 5)],
      refs: const [],
    );
    expect(a.calls, 2);
    expect(a.sentUserTexts.last, isNot(contains('STUDENT_OCR_SENTINEL')),
        reason: 'grade scope must never echo student OCR back to the model');
    // The static nudge is still appended — only the snippet is excluded.
    expect(a.sentUserTexts.last, contains('无法解析为 JSON'),
        reason: 'grade scope still gets the static nudge');
  });

  test('identify: JsonParseException with cleanedSnippet=null → 2nd attempt '
      'uses static nudge, not snippet fence', () async {
    // A response that is just a think block (cleaned text is empty after
    // stripping). JsonParseException.cleanedSnippet should be null in that
    // case, and the retry should use the static nudge.
    final s = const AppSettings(apiKey: 'k', baseUrl: 'https://example.test/v1');
    final svc = QwenService(s);
    final a = _CountingAdapter((i, _) =>
        i == 0 ? _badJsonWith('<think>only thinking no output</think>')
            : _ok200());
    svc.dio.httpClientAdapter = a;

    await svc.identifyQuestions(const []);
    expect(a.calls, 2);
    // Static nudge substring is present.
    expect(a.sentUserTexts.last, contains('无法解析为 JSON'));
    // Snippet fence is NOT present (because cleanedSnippet was null).
    expect(a.sentUserTexts.last, isNot(contains('````json')),
        reason: 'no snippet fence when cleanedSnippet is null');
  });
```

- [ ] **Step 3: Run the new tests to verify they pass**

Run: `cd yas_local && flutter test test/qwen_service_retry_test.dart`
Expected: all tests pass (existing 6 + new 3 = 9 tests).

- [ ] **Step 4: Commit**

```bash
cd yas_local
git add test/qwen_service_retry_test.dart
git commit -m "test(nudge): cover snippet presence/absence across scopes"
```

---

### Task 2.7: Extend `verify_prompt_runtime_test.dart` end-to-end probe

**Files:**
- Modify: `test/verify_prompt_runtime_test.dart:198-242` (the "D. Probe" block)

- [ ] **Step 1: Locate the existing "D. Probe" block**

Open `test/verify_prompt_runtime_test.dart`. The probe block starts around line 198 and ends around line 242. The block currently:
1. Sets up a `_MultiCallAdapter` with bad-JSON-then-good-JSON responses.
2. Calls `svc.generateStrategy(...)`.
3. Asserts `multi.calls == 2`, `multi.sentUserTexts.length == 2`.
4. Asserts `硬约束` appears once in each attempt's user text (no duplication).

- [ ] **Step 2: Add a snippet assertion right before the closing `}` of the `main()` function (or the test block)**

Find the end of the probe block — it ends with the `expect(hardCount2, 1, ...)` line. **Immediately after** that line, add:

```dart
    // The 2nd attempt's user text must include the bad JSON's body so
    // the model can see what to fix. The first attempt returns the
    // literal string "not json" (set above at line 205), so the snippet
    // quoted in the retry should contain that exact substring.
    expect(multi.sentUserTexts[1], contains('not json'),
        reason: '2nd attempt user text must quote the previous failure');
```

- [ ] **Step 3: Run the test**

Run: `cd yas_local && flutter test test/verify_prompt_runtime_test.dart`
Expected: PASS — the new assertion is satisfied because the first response body is `'not json'` and `JsonExtractor.requireObject` will throw a `JsonParseException` with `cleanedSnippet` containing `'not json'` (length 8, well under the 300-char cap), and the retry will include that snippet in the user text.

- [ ] **Step 4: Commit**

```bash
cd yas_local
git add test/verify_prompt_runtime_test.dart
git commit -m "test(nudge): assert snippet quoted in 2nd attempt user text (end-to-end)"
```

---

### Task 2.8: Update the upstream spec to reflect the new contract

**Files:**
- Modify: `docs/superpowers/specs/2026-06-05-retry-with-feedback-design.md` (find the §3.3 / "JSON 错重试 nudge" section, which is around line 89-97)

- [ ] **Step 1: Locate the section to update**

Open `docs/superpowers/specs/2026-06-05-retry-with-feedback-design.md` and find the section "### JSON 错重试 nudge" (around lines 89-97). It currently reads:

```
### JSON 错重试 nudge

```dart
// lib/services/prompts.dart
static const String jsonRetryNudge =
    '\n\n注意：上一次返回的内容无法解析为 JSON，请只返回纯 JSON，不要任何解释或 <think> 内容。';
```

`_retryingRequest` 在 `attempt > 0 && lastKind == jsonParse` 时，system prompt 末尾追加这一行。每次 retry 都是同样 nudge，不 stack。
```

- [ ] **Step 2: Replace it with the new two-mode contract**

Replace the entire "### JSON 错重试 nudge" section (from the heading line through the "不 stack" line) with:

```
### JSON 错重试 nudge

静态兜底（`jsonRetryNudge`，无 snippet）：

```dart
// lib/services/prompts.dart
static const String jsonRetryNudge =
    '\n\n注意：上一次返回的内容无法解析为 JSON，请只返回纯 JSON，不要任何解释或 <think> 内容。';
```

带 snippet 的版本（`jsonRetryNudgeWithSnippet(snippet)`），其中 `snippet` 是
`JsonParseException.cleanedSnippet`（清洗 + 截断 300 字符）：

```dart
static String jsonRetryNudgeWithSnippet(String snippet) =>
    '\n\n注意：上一次返回的内容无法解析为 JSON。以下是模型上次原始输出（已截断，'
    '请勿逐字复述，仅用于理解错误位置）：\n\n'
    '````json\n$snippet\n````\n\n'
    '请只返回纯 JSON，不要任何解释或 <think> 内容。';
```

`_retryingRequest` 在 `attempt > 0 && lastKind == jsonParse` 时：
- `scope == 'grade'`：用 `jsonRetryNudge`（静态兜底），**不传 snippet**——grade 失败时
  `cleanedSnippet` 含学生手写 OCR 文本（PII），禁止回流到下一条 prompt。
- 其它 scope（`strategy` / `identify`）：`cleanedSnippet` 非 null 时用
  `jsonRetryNudgeWithSnippet(snippet)`；为 null 时回退到 `jsonRetryNudge`。

`refineStrategy` 的 ad-hoc 重试循环走同一规则。

每次 retry 使用同样的 nudge + 同样的 snippet（snippet 也是同一段清洗文本），不 stack。
```

- [ ] **Step 3: Commit**

```bash
cd yas_local
git add docs/superpowers/specs/2026-06-05-retry-with-feedback-design.md
git commit -m "docs(spec): update retry-with-feedback §3.3 to two-mode nudge contract"
```

---

### Task 2.9: Final full-suite verification

- [ ] **Step 1: Run the full test suite**

Run: `cd yas_local && flutter test`
Expected: all tests pass. Watch for:
- `test/json_extractor_test.dart` — the 2 new `cleanedSnippet` tests + all existing tests
- `test/prompts_test.dart` — the 2 new `jsonRetryNudgeWithSnippet` tests
- `test/qwen_service_test.dart` — the new `refineStrategy` snippet test + all existing tests
- `test/qwen_service_retry_test.dart` — the 3 new scope tests + all existing tests
- `test/verify_prompt_runtime_test.dart` — the extended D. Probe

- [ ] **Step 2: Run static analysis on the whole project**

Run: `cd yas_local && flutter analyze`
Expected: no issues.

- [ ] **Step 3: Commit the worktree-clean tag if everything looks good**

If `git status` is clean and all checks passed:

```bash
cd yas_local
git tag json-nudge-snippet-v1
```

(No push, no remote — the user will decide on the PR.)

---

## Self-Review

**1. Spec coverage:**

| Spec section | Task(s) |
|---|---|
| §3.2 `JsonParseException` 新字段 + 2 throw 站点计算 | 1.1, 1.2 |
| §3.3 `jsonRetryNudgeWithSnippet` 函数（围栏 + 截断 + "请勿逐字复述"） | 1.3 |
| §3.4 `_retryingRequest` 签名扩展 + `bodyBuilder` 3 参数 | 2.1 |
| §3.4 3 个 caller bodyBuilder 同步 + `scope != 'grade'` guard | 2.2, 2.3, 2.4 |
| §3.5 `refineStrategy` for-loop 重构 + snippet 透传 | 2.5 |
| §6 `gradePaper` 不参与（PII guard） | 2.4 (`_composeUserText` 内 `scope == 'grade'` 分支) + 2.6 (测试断言) |
| §8 单元测试：`json_extractor_test.dart` `cleanedSnippet` 字段 | 1.1 |
| §8 集成测试：`qwen_service_retry_test.dart` 3 个 scope 各自的 snippet 透传 + fallback | 2.6 |
| §8 集成测试：`qwen_service_test.dart` `refineStrategy` 路径 | 2.5 |
| §8 集成测试：`verify_prompt_runtime_test.dart` 端到端断言 | 2.7 |
| §11 spec 修订 | 2.8 |

All 11 spec requirements mapped to tasks.

**2. Placeholder scan:** Searched the plan for "TBD", "TODO", "implement later", "fill in details", "appropriate error handling", "similar to Task N". No hits. All code blocks are complete and self-contained.

**3. Type consistency:**
- `JsonParseException.cleanedSnippet` (defined Task 1.1) — referenced by Task 1.2 (throw sites), Task 2.2 (`_composeUserText` reads `lastError.cleanedSnippet`), Task 2.5 (`previousParseSnippet = e.cleanedSnippet`). Consistent throughout.
- `_retryingRequest` bodyBuilder typedef (defined Task 2.1 as `Function(int attempt, QwenErrorKind? lastKind, Object? lastError)`) — used by Tasks 2.2/2.3/2.4 caller closures (all 3 use `(attempt, lastKind, lastError) => {...}`) and by the helper's call site (`bodyBuilder(attempt, lastKind, lastError)`). Consistent.
- `_composeUserText` method (defined Task 2.2 with signature `String _composeUserText({required String base, required String scope, required QwenErrorKind? lastKind, required Object? lastError})`) — used by Tasks 2.2 (`scope: 'strategy'`), 2.3 (`scope: 'identify'`), 2.4 (`scope: 'grade'`). All calls use named args matching the signature. Consistent.
- `AppPrompts.jsonRetryNudgeWithSnippet` (defined Task 1.3 as `String jsonRetryNudgeWithSnippet(String snippet)`) — used by Tasks 2.2 (`_composeUserText`), 2.5 (refineStrategy loop), 2.6 (test assertions). All callers pass a non-null `String`. Consistent.

No type drift detected.
