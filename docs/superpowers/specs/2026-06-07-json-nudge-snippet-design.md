# JSON Retry Nudge: 带失败内容片段

**日期**:2026-06-07
**状态**:设计稿
**关联**:`docs/superpowers/specs/2026-06-05-retry-with-feedback-design.md` 的 §3.3 (JSON nudge) 修订
**避让方向**:无（与 debug-observability 独立；不调 DebugService 接口，只在 `_recordParseError` 里多带一字段）

## 1. 概述

retry-with-feedback (PR #7) 把单次 Qwen 调用的失败率从"一次失败"降到"3 次都失败"。但 jsonParse 这类失败 3 次通常仍是**同一种失败**——LLM 的采样器在前一次出 bad JSON 后,下一次大概率出同样形态的 bad JSON(尤其 temperature 较低时)。

现状 `AppPrompts.jsonRetryNudge` 是一句静态文案「请只返回纯 JSON,不要任何解释或 <think> 内容」——模型**完全不知道**自己前一次错在哪。30 token 的预算被浪费在它看不着的方向。

本 spec 的目标:把上一次失败的**清洗后内容片段**(200-300 字符)拼进 nudge,让模型能针对性修复。**同 token 量级(~200 token),信号密度 5x**。

**`gradePaper` 不参与**——其失败 snippet 含学生手写 OCR 文本(姓名、ID、答案),不能进下一条 prompt。其它 3 个 scope(strategy/identify/refine)都安全:失败输出是模型对教师题目的理解,不含学生 PII。

## 2. 范围

**In scope**

- `JsonParseException` 新增 `final String? cleanedSnippet;` 字段(在两个 throw 站点计算,默认 300 字符上限,`null` if empty after cleaning)。
- `lib/services/prompts.dart` 新增 `static String jsonRetryNudgeWithSnippet(String? snippet)` 函数(`jsonRetryNudge` 静态常量保留,只用于**没有** snippet 的场景——`gradePaper` + 无 snippet 的 fallback)。
- `qwen_service.dart::_retryingRequest` 的 `bodyBuilder` 签名扩展为 `Function(int attempt, QwenErrorKind? lastKind, Object? lastError)`。同时在 loop 内保留 `Object? lastError` 状态。
- 3 个 `_retryingRequest` caller(`generateStrategy` / `identifyQuestions` / `gradePaper`)的 bodyBuilder 同步扩展。
- `refineStrategy` 的 ad-hoc retry 循环(line 268-318)同步加 snippet(同 `bodyBuilder` 模式,`e` 本来就在 scope)。
- 测试:`json_extractor_test.dart`(field 构造)+ `qwen_service_retry_test.dart`(3 scope 各自的 snippet 透传 + 缺省/无 snippet fallback)+ `qwen_service_test.dart`(`refineStrategy` 路径)。
- spec 修订:`docs/superpowers/specs/2026-06-05-retry-with-feedback-design.md` §3.3 的"nudge 永远 ~30 字"改写为"nudge 是 `jsonRetryNudge` 静态文案的 30 字 + 可选 200-300 字符 snippet"。

**Out of scope**

- ❌ `gradePaper` 的 snippet(显式排除,理由 §1)。
- ❌ 改 `QwenErrorKind` / `QwenError.from`(factory 不需要知道 snippet 存在)。
- ❌ 改 `_recordParseError` 的 `responseContent`(它已经写 `rawContent`,`cleanedSnippet` 已经在 `JsonParseException` 上,`errorMessage` 不需要再带一份)。
- ❌ Token 预算 guard(调研后判定不需要,见 §5)。
- ❌ "请勿复述"指令之外的 prompt engineering(比如 "请重写时不要保留 X 模式")——保持最小可观察的改动。
- ❌ 改 `JsonExtractor._stripThinking` 的 regex 不对称(只懂 `<think>` 不懂 `<thinking>`)——pre-existing,不在本 spec。
- ❌ 自定义截断策略(默认 300 字符硬上限即可)。

## 3. 架构

### 3.1 调用栈(改后)

```
QwenService.generateStrategy / identifyQuestions / gradePaper
  └── _retryingRequest
        ├── bodyBuilder(attempt, lastKind, lastError)  ← 签名扩
        │     ├── lastKind == jsonParse && lastError is JsonParseException
        │     │     → userText + jsonRetryNudgeWithSnippet(
        │     │           e.cleanedSnippet)            ← 新函数
        │     └── else → userText + jsonRetryNudge    ← 静态常量,行为不变
        ├── extract(content) → T
        └── catch (e)
              ├── QwenError.from(e)
              ├── lastError = e   ← 新增,类型 Object?
              └── lastKind = q.kind

QwenService.refineStrategy (ad-hoc)
  └── try { ... } on JsonParseException catch (e)
        └── e.cleanedSnippet → jsonRetryNudgeWithSnippet(...)  ← 直接拿 e
```

### 3.2 `JsonParseException` 新字段

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
  String toString() { ... unchanged ... }
}
```

**两个 throw 站点**(line 83, 158)的构造改为:

```dart
final cleaned = _stripThinking(text);          // 复用现有函数
final snippet = cleaned.length > 300
    ? '${cleaned.substring(0, 300)}…'
    : (cleaned.isEmpty ? null : cleaned);

throw JsonParseException(
  'No valid JSON object found in AI response.',
  rawContent: text,
  cleanedSnippet: snippet,
);
```

`_stripThinking` 是已有函数(line 223),产物正好是我们要的(去掉 `<think>` + trim)。不需要引入新清洗。

### 3.3 `jsonRetryNudgeWithSnippet` 函数

`lib/services/prompts.dart` 新增:

```dart
/// Builds a JSON-retry nudge that quotes a previous failure snippet so the
/// model can see what to fix. [snippet] is the cleaned+truncated text from
/// [JsonParseException.cleanedSnippet].
///
/// Caller MUST ensure [snippet] is not student PII — `gradePaper` failures
/// contain student OCR text and are explicitly excluded from this path.
///
/// Snippet is wrapped in 4-backtick outer / 3-backtick inner fences so:
///  1. The model cannot "fix" it by inline-merging the snippet with the
///     response.
///  2. Triple backticks inside the snippet (which can happen when the
///     model emits ```json ... ```) do not break the outer fence.
static String jsonRetryNudgeWithSnippet(String snippet) =>
    '\n\n注意:上一次返回的内容无法解析为 JSON。以下是模型上次原始输出(已截断,'
    '请勿逐字复述,仅用于理解错误位置):\n\n'
    '````json\n$snippet\n````\n\n'
    '请只返回纯 JSON,不要任何解释或 <think> 内容。';
```

- **Token 量级**:静态文案 ~50 字符 + snippet 200-300 字符 + 围栏 ~30 字符 ≈ 280-380 字符 ≈ 200 tokens。
- **现有 `jsonRetryNudge` 静态常量保留**,用作无 snippet 时的 fallback(`gradePaper` + 清洗为空时)。
- **围栏不堆叠**:每次 retry 是同样的 `jsonRetryNudgeWithSnippet(snippet)`,snippet 也是同样字符串;不会出现"nudge 里套 nudge"。

### 3.4 `bodyBuilder` 签名扩展

`_retryingRequest` 现在的签名(line 496-502):

```dart
Future<T> _retryingRequest<T>({
  required String scope,
  required Map<String, dynamic> Function(int attempt, QwenErrorKind? lastKind)
      bodyBuilder,
  required T Function(String content) extract,
  void Function(int attempt)? onAttempt,
}) async { ... }
```

**改后**:

```dart
Future<T> _retryingRequest<T>({
  required String scope,
  required Map<String, dynamic> Function(
    int attempt,
    QwenErrorKind? lastKind,
    Object? lastError,   // ← 新增
  ) bodyBuilder,
  required T Function(String content) extract,
  void Function(int attempt)? onAttempt,
}) async {
  const maxAttempts = 3;
  QwenErrorKind? lastKind;
  Object? lastError;   // ← 新增
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    onAttempt?.call(attempt);
    try {
      final resp = await _dio.post(
        '/chat/completions',
        data: bodyBuilder(attempt, lastKind, lastError),  // ← 透传
        options: Options(extra: {'_qwen_scope': scope}),
      );
      final rawContent = resp.data['choices'][0]['message']['content'];
      final content = rawContent as String;
      return extract(content);
    } catch (e) {
      final q = QwenError.from(e);
      if (!q.shouldRetry) throw q;
      lastKind = q.kind;
      lastError = e;   // ← 新增
      // ... _recordParseError / backoff 不变 ...
    }
  }
  throw StateError('unreachable: _retryingRequest exhausted');
}
```

3 个 caller 的 bodyBuilder 同步改为:

```dart
// generateStrategy (line 197-225), identifyQuestions (line 343-371),
// gradePaper (line 416-477)
bodyBuilder: (attempt, lastKind, lastError) {
  String text;
  if (lastKind == QwenErrorKind.jsonParse &&
      lastError is JsonParseException &&
      lastError.cleanedSnippet != null &&
      scope != 'grade') {                          // ← grade 跳过
    text = userText + AppPrompts.jsonRetryNudgeWithSnippet(
      lastError.cleanedSnippet!);
  } else {
    text = lastKind == QwenErrorKind.jsonParse
        ? userText + AppPrompts.jsonRetryNudge
        : userText;
  }
  return { 'model': ..., 'messages': [...] };
}
```

**关键点**:
- `scope != 'grade'` 的 guard 让 `gradePaper` 的 bodyBuilder 走"无 snippet"分支——这是 PII 安全的关键。
- `cleanedSnippet != null` 防空 snippet(模型输出就是 `<think>` 空 block 的退化情况)。
- `lastError is JsonParseException` 二次确认——`TypeError`(空 body)路径不会传 snippet(那个 e 不是 JsonParseException,也无 rawContent)。

**`refineStrategy` 路径**(line 268-318)独立改:

```dart
} on JsonParseException catch (e) {
  // ... 现有 DebugService.recordQwenCall 块不变 ...
  if (attempt == 1) rethrow;
}
// 第二次 attempt 的 messages 构造(line 269-277)改为:
final messages = attempt == 0
    ? baseMessages
    : <Map<String, dynamic>>[
        ...baseMessages.sublist(0, baseMessages.length - 1),
        {
          'role': 'user',
          'content': e.cleanedSnippet == null
              ? userMessage + AppPrompts.jsonRetryNudge
              : userMessage + AppPrompts.jsonRetryNudgeWithSnippet(
                  e.cleanedSnippet!),
        },
      ];
```

注意:`refineStrategy` 的 e 在 line 295 的 catch 块内——snippet 只能用于 attempt 1 的 message 构造(line 269-277 在 try 块外,e 在 catch 块内)。**重构需要把"构造 attempt 1 的 messages"挪进 catch 块**。

**改造**:`refineStrategy` 的 catch 块改为:

```dart
} on JsonParseException catch (e) {
  DebugService.instance.recordQwenCall(...);  // 不变

  // Build the retry's user message with the snippet inside the catch so we
  // can close over `e` (line 269-277 was outside the try block, so `e`
  // wasn't in scope there).
  final retryUserText = e.cleanedSnippet == null
      ? userMessage + AppPrompts.jsonRetryNudge
      : userMessage + AppPrompts.jsonRetryNudgeWithSnippet(e.cleanedSnippet!);
  final retryMessages = <Map<String, dynamic>>[
    ...baseMessages.sublist(0, baseMessages.length - 1),
    {'role': 'user', 'content': retryUserText},
  ];

  // We can't continue the for-loop here directly because messages was
  // already constructed at line 269. Refactor: move messages construction
  // into the loop body. See §3.5.
  if (attempt == 1) rethrow;
}
```

实际上 line 268-318 的 for-loop 结构需要**整体重写**——把 messages 构造挪进 loop body,让 retry attempt 能用 catch 块的 e。见 §3.5。

### 3.5 `refineStrategy` for-loop 重构

原结构(line 268-318):

```dart
for (var attempt = 0; attempt < 2; attempt++) {
  final messages = attempt == 0
      ? baseMessages
      : [...baseMessages.sublist(0, length-1), {user: userMessage+nudge}];
  try {
    final resp = await _dio.post(..., data: {messages});
    // ... extract ...
  } on JsonParseException catch (e) {
    if (attempt == 1) rethrow;
  } on DioException catch (e) {
    // ... backoff ...
  }
}
```

**问题**:retry attempt 的 messages 在 try 块**外**构造,catch 块拿不到 e,无法把 snippet 拼进 retry messages。

**新结构**(把 messages 构造挪进 try 块,catch 块只决定是否继续):

```dart
for (var attempt = 0; attempt < 2; attempt++) {
  // Build messages at the top of each attempt. On attempt 0, use the
  // base. On attempt 1, the previous JsonParseException's cleanedSnippet
  // is now available because we close over `e` from the previous loop
  // iteration's catch via a captured variable.
  final String userText;
  if (attempt == 0) {
    userText = userMessage;
  } else {
    // Closed-over from the previous iteration's catch (e is JsonParseException
    // because the only way attempt 1 is reached is via the JsonParseException
    // path — DioException goes through shouldRetry, not retry).
    final prevSnippet = _previousParseSnippet;
    userText = prevSnippet == null
        ? userMessage + AppPrompts.jsonRetryNudge
        : userMessage + AppPrompts.jsonRetryNudgeWithSnippet(prevSnippet);
  }
  final messages = <Map<String, dynamic>>[
    ...baseMessages.sublist(0, baseMessages.length - 1),
    {'role': 'user', 'content': userText},
  ];

  try {
    final resp = await _dio.post(
      '/chat/completions',
      data: {'model': settings.vlModel, 'messages': messages},
      options: Options(extra: {'_qwen_scope': 'refine'}),
    );
    final content = resp.data['choices'][0]['message']['content'] as String;
    final payload = JsonExtractor.requireObjectWithReasoning(
      content, scope: 'refine');
    return _parseReferenceAnswer(
      current.questionNumber, payload.json, reasoning: payload.reasoning);
  } on JsonParseException catch (e) {
    DebugService.instance.recordQwenCall(...);  // 不变
    _previousParseSnippet = e.cleanedSnippet;  // 抛给下一轮用
    if (attempt == 1) rethrow;
  } on DioException catch (e) {
    final q = QwenError.from(e);
    if (!q.shouldRetry) throw q;
    if (attempt == 1) throw q;
    final delay = _backoffMs(attempt);
    await Future<void>.delayed(Duration(milliseconds: delay));
  }
}
```

`_previousParseSnippet` 是 for-loop 外的局部变量(`String?`),第一次 attempt 后被设置。Dio 错误路径不更新它(因为只有 JsonParseException 才有 snippet)——这意味着如果第一次 attempt 抛的是 DioException,第二次 attempt 不会拼 snippet,但这没意义:第二次 attempt 用的还是同一组 baseMessages,nudge 也无 snippet——行为和现状一致(因为现状 nudge 也不区分错误类型)。

**注意**:这种"Dio 错误后 JsonParse 错误"的混合情况在生产中几乎不可能(只有第一次 attempt 的原始 prompt 错才可能产生 DioException,第二次是同一个 prompt 再发,不可能突然 200 但内容变)。所以这个边界是 **可接受的简化**。

## 4. 行为变化 vs 现状

| 调用 | 现状 | 改后 |
|---|---|---|
| `generateStrategy` 第 1 attempt 成功 | text = userText | 不变 |
| `generateStrategy` 第 1 attempt JSON fail, 第 2 attempt 成功 | text = userText + jsonRetryNudge | text = userText + jsonRetryNudgeWithSnippet(snippet) |
| `generateStrategy` 第 1 attempt 5xx, 第 2 attempt 成功 | text = userText (无 nudge) | 不变 |
| `generateStrategy` 3 attempt 全 JSON fail | 抛 QwenError(jsonParse) | 不变(snippet 在 _recordParseError 的 errorMessage 已经有 JsonParseException.toString) |
| `gradePaper` 第 1 attempt JSON fail, 第 2 attempt 成功 | text = userText + jsonRetryNudge | **不变**(PII guard) |
| `gradePaper` 任何错误 | 行为不变 | 行为不变 |
| `identifyQuestions` 第 1 attempt JSON fail, 第 2 attempt 成功 | text = userText + jsonRetryNudge | text = userText + jsonRetryNudgeWithSnippet(snippet) |
| `refineStrategy` 第 1 attempt JSON fail, 第 2 attempt 成功 | text = userMessage + jsonRetryNudge | text = userMessage + jsonRetryNudgeWithSnippet(snippet) |
| `refineStrategy` 第 1 attempt Dio 5xx, 第 2 attempt 成功 | text = userMessage + jsonRetryNudge | **不变**(refine 走旧 nudge,Dio 错误不更新 snippet) |
| TypeError(空 body)在 3 attempt 都失败 | 抛 QwenError(unknown) | 不变 |
| `_recordParseError` 写入 DebugService | errorMessage = e.toString() | 不变(JsonParseException.toString 不带 snippet) |

## 5. Token 预算

无全局 guard。`prompts.dart` 和 `qwen_service.dart` 都没有 `token` / `max_token` / `budget` 引用。

- 当前 jsonRetryNudge:~50 字符 / ~30 tokens。
- 新 `jsonRetryNudgeWithSnippet(snippet)`:~280-380 字符 / ~200 tokens。
- Qwen 默认 context window(以 qwen-vl-plus 为例)32K tokens。retry prompt 总长(图片 base64 + 静态 prompt)通常 1-3K tokens。**+200 tokens 是 6-20% 的相对增加**。
- `identifyQuestions` 静态 prompt 短(~150 字符),+300 字符 snippet 是 2x 文本——但仍远在 context 内。
- **风险**:snippet 太长可能让模型"focus on snippet"忽略原 prompt 的 schema 指令。**应对**:snippet 硬上限 300 字符 + 围栏 + "请勿逐字复述"指令。

## 6. PII 风险(明确决策)

| Scope | 失败 snippet 含什么 | PII 风险 | 处理 |
|---|---|---|---|
| `strategy` | 模型对教师题目内容的总结 | 无 | 透传 snippet |
| `identify` | 模型枚举的题目文本(教师提供) | 无 | 透传 snippet |
| `refine` | 模型对教师修改指令的回复 | 无 | 透传 snippet |
| `grade` | 学生的 `extracted_answer`(OCR 转录)——含姓名、ID、答案 | **有** | **不传 snippet,只传静态 nudge** |

`scope != 'grade'` guard 在 3 个 `_retryingRequest` caller 的 bodyBuilder 内部。**这是 spec 的硬约束——评审时重点看这个 guard 存不存在**。

`gradePaper` 的 `_recordParseError` 仍写完整 raw content 到 DebugService——这是**pre-existing 行为**,本 spec 不动。DebugService 是 session 内的 in-memory ring buffer,伤害有限。修这个属于另一条线(可能和 PII 整体 redaction 策略合并)。

## 7. 文件改动详单

### 新增

| 文件 | 行数 | 说明 |
|---|---|---|
| `lib/services/prompts.dart` | +20 | `jsonRetryNudgeWithSnippet` 函数 |
| `test/qwen_service_retry_test.dart` | +30 | 3 个 scope 各自的 snippet 透传测试 |
| `test/qwen_service_test.dart` | +25 | `refineStrategy` 的 snippet 透传测试 |
| `test/json_extractor_test.dart` | +15 | `cleanedSnippet` 字段构造测试 |
| `docs/superpowers/specs/2026-06-05-retry-with-feedback-design.md` | ~10 行改写 | §3.3 改契约 |

### 改动

| 文件 | 改动 | 说明 |
|---|---|---|
| `lib/services/json_extractor.dart` | `JsonParseException` +1 字段;两个 throw 站点 +2 行 | 字段计算 + 截断 |
| `lib/services/qwen_service.dart` | `_retryingRequest` bodyBuilder 签名 +1 参数,loop 内 +1 状态;3 个 caller bodyBuilder +5 行;`refineStrategy` 重构 for-loop,~30 行 | 主体改动 |

**合计 ~140 LOC,5 文件**。

## 8. 测试矩阵

**单元(pure Dart)**

| 文件 | 用例 |
|---|---|
| `test/json_extractor_test.dart` 扩展 | ① `_stripThinking` 后的 cleaned text ≤ 300 字符;② 空 cleaned text → `cleanedSnippet == null`;③ 完整 LLM 输出 → snippet 是清洗后的前 300 字符 |
| `test/qwen_service_retry_test.dart` 扩展 | ① "strategy: bad json 含 sentinel BADSENTINEL → 第二次请求的 user text 含 BADSENTINEL" ② "identify: 同上" ③ "grade: bad json → 第二次请求的 user text **不**含 sentinel,只含静态 nudge" ④ "cleanedSnippet null → 第二次请求的 user text 走静态 nudge(没 snippet,也没 snippet 围栏)" |
| `test/qwen_service_test.dart` 扩展 | ① `refineStrategy` 的 "bad json first attempt" → 第二次的 user message 含 snippet ② `refineStrategy` 的 "bad json + snippet null" → 走静态 nudge |

**集成(已有 fixture 复用)**

| 文件 | 用例 |
|---|---|
| `test/verify_prompt_runtime_test.dart` "D. Probe" | 已有 first/second attempt 断言,加 "second attempt 含第一次返回的可识别子串" 即可 |

## 9. 落地顺序(2 个 PR,各独立可合并)

### PR 1: 字段 + 静态 nudge 增强

- `JsonParseException` 加 `cleanedSnippet` 字段 + 2 个 throw 站点
- `jsonRetryNudgeWithSnippet` 函数
- `json_extractor_test.dart` 单元测试
- **行为变化**:`JsonParseException` 多 1 字段(纯加,无破坏),`jsonRetryNudgeWithSnippet` 存在但没 caller
- **零 UI 变化**

### PR 2: 调用点改造

- `_retryingRequest` 签名扩展
- 3 个 bodyBuilder caller 改造 + `scope != 'grade'` guard
- `refineStrategy` for-loop 重构
- `qwen_service_retry_test.dart` + `qwen_service_test.dart` 集成测试
- `verify_prompt_runtime_test.dart` 端到端断言
- spec 修订 `2026-06-05-retry-with-feedback-design.md` §3.3
- **行为变化**:`gradePaper` 完全不变,其它 3 scope retry 时 prompt 多了 200 字符 snippet

## 10. 边界情况

1. **第一次 attempt 直接成功**:`bodyBuilder` 收到 `lastKind=null, lastError=null` → `userText`(无 nudge),行为不变。
2. **第一次 attempt 5xx, 第二次 attempt JSON fail**:第二次 attempt 时 `lastKind=5xx, lastError=DioException` → 走"无 snippet"分支(`e is! JsonParseException`)。**这是正确行为**——5xx 错误的"nudge"语义本来就和 JSON 错不同。
3. **第一次 attempt JSON fail 但 `cleanedSnippet == null**(cleaned 后是空)**: 走 `jsonRetryNudge` 静态常量(无 snippet 围栏)。**不**退化成裸文本——保留"请只返回纯 JSON"。
4. **`gradePaper` 任意错误**:不传 snippet,行为完全不变。
5. **`refineStrategy` 第一次 Dio 5xx, 第二次 JSON fail**:`_previousParseSnippet` 仍是 `null`(Dio 错误不更新),第二次 attempt 拼静态 nudge。**简化决策**——这种"Dio + JSON"混合失败模式几乎不可能,不值得为它增加复杂度。
6. **Snippet 触发 prompt injection**:snippet 是模型自己上一轮的输出,不是用户输入。**无 prompt injection 风险**——攻击面是 LLM 输入,不是 LLM 输出回流到 LLM 输入。但 snippet 进 DebugService 仍走 `redactBase64Messages`(只对 image_url 有效,文本不动)——pre-existing,不动。
7. **Token 稀释**:见 §5 风险,靠 300 字符硬上限 + 围栏 + "请勿逐字复述"控制。

## 11. 与上游 spec 的同步

`docs/superpowers/specs/2026-06-05-retry-with-feedback-design.md` §3.3(原 spec 89-97 行)写的契约是「nudge 永远 ~30 字」。改后契约是「nudge 是 `jsonRetryNudge` 静态文案的 30 字 + 可选 200-300 字符 snippet(grade 除外)」。**spec 修订与 PR 2 同步 commit**,避免文档与代码脱节。

`docs/superpowers/plans/2026-06-05-retry-with-feedback.md` 是当时的实现 plan,落地后已与代码对齐,不需要再改(本 spec 是一层新增强,plan 文档不需要回填)。

## 12. 验收清单

- [ ] `JsonParseException.cleanedSnippet` 字段存在,3 个测试断言字段值正确(含 null case)
- [ ] `AppPrompts.jsonRetryNudgeWithSnippet(snippet)` 存在,接受非空 snippet 返回带围栏的字符串
- [ ] `_retryingRequest` 的 `bodyBuilder` 签名是 3 参数
- [ ] `gradePaper` bodyBuilder 内 `scope != 'grade'` guard 存在
- [ ] `gradePaper` retry test 断言:bad JSON 时第二次请求 user text **不**含 sentinel
- [ ] `generateStrategy` / `identifyQuestions` retry test 断言:bad JSON 时第二次请求 user text 含 sentinel
- [ ] `refineStrategy` test 断言:bad JSON 时第二次 user message 含 snippet
- [ ] `verify_prompt_runtime_test.dart` 端到端断言:真实 `generateStrategy` 路径下,第二次请求 user text 含第一次返回的可识别子串
- [ ] 现有所有 qwen_service / json_extractor / job_queue 测试仍通过(无行为破坏)
- [ ] `flutter analyze` 无 issue
- [ ] spec §3.3 改写为新契约,与代码一致
