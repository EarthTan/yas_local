# Qwen 调用重试 + 可见反馈

**日期**:2026-06-05
**状态**:设计稿,待用户审阅
**避让方向**:`feature/debug-mode` 衍生的 `debug/m1-extract-in-memory-ring-sink` worktree(`docs/superpowers/specs/2026-06-05-debug-observability-design.md`)正在抽 sink 接口、加 RollingFileSink、Flutter 异常钩子三件套。本 spec **不动 DebugService 现有接口**,只调用 `recordEvent` 写一条 retry 事件。

## 1. 概述

当前 `lib/services/qwen_service.dart` 4 个 VLM 端点(`identifyQuestions` / `generateStrategy` / `refineStrategy` / `gradePaper`)都是 **0 retry**:任何 Dio 错或 `JsonParseException` 直接冒到 `JobQueueNotifier` 的 per-unit `try/catch`,把 submission 或 strategy question 标 failed。最高频的失败是 **JSON 解析错**(Qwen 偶尔吐出带裂的 JSON、混进 think 内容、缺右括号);其次是网络抖动 / 5xx。

用户痛点:批一次 30 张卷子,3-5 张会因为这种 transient 错误进 failed,只能手动重起整批任务 —— 而那批任务里大部分卷子已经成功了,重起代价高。

本 spec 的目标:
1. **底层**:`QwenService` 内部对 5 类 transient 错误自动重试 3 次,指数退避 + jitter,JSON 错重试时 prompt 加 nudge。
2. **可见性**:`JobState` 加 attempt / lastErrorKind / lastErrorUnit 三字段,Home 卡片 / Task Detail / Strategy Review 屏实时显示「第 N 例·重试 X/3·错误类型」。
3. **兜底**:重试 3 次仍失败的 submission / strategy question,在对应屏顶部出现「重跑失败项 (N)」按钮,生成只含 failed 单元的新 job。

**Strategy 与 grading 同等待遇** —— Phase 1 跑 LLM 失败的频率不低于 Phase 2(prompt 复杂、输出结构严格),用户体验上同等重要。

## 2. 范围

**In scope**

- 新增 `lib/services/qwen_error.dart`:`QwenErrorKind` 枚举(`network` / `timeout` / `http4xx` / `http5xx` / `jsonParse` / `unknown`) + `QwenError` 异常类 + `QwenError.from(Object)` 分类工厂 + `displayName` 中文文案。
- `lib/services/qwen_service.dart` 内新增 `_retryingRequest` helper,4 个公开方法统一走这条;底层 Dio POST + `JsonExtractor.requireListWithReasoning` / `requireObjectWithReasoning` 全包在里面;3 次重试,backoff 公式 `1000ms * 2^attempt * (0.75 + random()*0.5)`,jitter ±25%。
- 抛错统一为 `QwenError`;`http4xx` 短路不重试,其它 5 类重试。
- JSON 错重试时,在 system prompt 末尾追加 `AppPrompts.jsonRetryNudge`(固定 ~30 字)。
- `lib/models/job_state.dart` 新增 `int attempt`、`QwenErrorKind? lastErrorKind`、`String? lastErrorUnit`;`copyWith` 覆盖;`phase=done/failed` 时强制清零。
- `lib/providers/job_queue_provider.dart` 新增 `_retryWithFeedback`(maxAttempts=1,内层 QwenService 已 retry 3 次,这层只负责把 attempt 推到 JobState),包裹 `_gradeOne` 和 `_strategyOne`。
- `lib/providers/job_queue_provider.dart` 的 `startStrategy` 加可选参数 `{Iterable<int>? onlyQuestions}`:默认全跑,传了只跑指定 questionNumber 的 rubric items;保存时 merge 回 `reference_<taskId>.json`(已 confirmed 的题保留 chat history / confirmed flag,只覆盖 failed 题)。
- `lib/services/reference_store.dart` 加 Completer chain mutex,模式同 13c9a45 的 TaskStore;`save` / `load` 串行化,避免「重跑失败题」与 `StrategyNotifier.saveAllConfirmed` 并发写抢同一文件。
- `lib/screens/task_detail_screen.dart`:加 attempt 行(`attempt > 0` 时显示);加失败 banner + 「重跑失败项 (N)」按钮(phase=done/failed + failedCount>0 显示)。
- `lib/screens/strategy_review_screen.dart` 或其子文件:加 attempt 行 + 失败 banner + 「重跑失败题 (N)」按钮。「失败题」判定:`checkpoints.isEmpty`(现状 sentinel,不动 ReferenceAnswer 模型)。
- `lib/screens/home_screen.dart` + `resolveTaskCardStatus`:`retryHint: String?` 字段,attempt>0 时显示「⟳ 重试 N/3 · 错误类型」一行。
- `DebugService.recordEvent` 在每次 retry 时调用一次(scope='retry',含 attempt / kind / unit),不动 DebugService 接口。

**Out of scope**

- ❌ 改 `runPool` 接口 / 改 `kMaxConcurrency`。
- ❌ 改 `DebugSink` / `RollingFileSink` / `InMemoryRingSink`(debug worktree 在管)。
- ❌ 后台守护任务自动重跑(只手动「重跑失败项」)。
- ❌ Strategy 「重跑失败题」按钮**不允许**选 confirmed 题(避免对话被冲掉)—— 只处理 `checkpoints.isEmpty`。
- ❌ Retry-After header 解析(Qwen 文档无明示,先用固定 backoff)。
- ❌ Dio 主动 cancel(重试中点 cancel,等当前请求自然结束,新 attempt 不再开始)。
- ❌ 给 ReferenceAnswer 加 status 字段(沿用 `checkpoints.isEmpty` sentinel)。
- ❌ 多 unit 并发时为每个 unit 单独保留 attempt 信息(只全局一份,后启动的覆盖前一个,可接受 UI 闪烁)。

## 3. 架构

### 调用栈(改后)

```
JobQueueNotifier.startGrading
  └── runPool(submissions, 3, _gradeOne)
        └── _gradeOne(submission)                              [新增 retry 反馈包装]
              ├── _patch(taskId, attempt=0, lastErrorUnit="第N例")
              └── _retryWithFeedback(maxAttempts=1, onAttempt:_patch)
                    └── QwenService.gradePaper(...)
                          └── _retryingRequest(...)            [新增 QwenService 内层 helper]
                                ├── try Dio POST
                                ├── try JsonExtractor.requireListWithReasoning
                                └── 错 → throw QwenError(kind, cause)
```

**两层 retry 分工**:`_retryingRequest`(内层)负责对**单次** Qwen 调用做 3 次底层重试,处理 Dio 错 + JSON 错;`_retryWithFeedback`(外层)`maxAttempts=1`,**不再叠加重试**,只负责把当前 attempt 信息推到 `JobState`。`QwenService` 抛 `QwenError` = 3 次都失败了,外层不再重试,直接进 failed 路径。

### 错误分类(QwenError.from)

| 来源 | kind | 是否重试 |
|---|---|---|
| `DioException.type == connectionTimeout / sendTimeout / receiveTimeout` | `timeout` | ✅ |
| `DioException.type == connectionError` | `network` | ✅ |
| `DioException.response?.statusCode ∈ [400, 499]` | `http4xx` | ❌ 立即 rethrow |
| `DioException.response?.statusCode ∈ [500, 599]` | `http5xx` | ✅ |
| `JsonParseException` | `jsonParse` | ✅(prompt 加 nudge) |
| 其它 | `unknown` | ✅(保守) |

### Backoff

`delayMs = 1000 * 2^attempt * (0.75 + Random.nextDouble() * 0.5)`

- attempt=0:首次失败后等 ~1s(范围 750-1250ms)
- attempt=1:~2s(1500-2500ms)
- attempt=2:~4s(3000-5000ms)
- 3 次都失败后抛 `QwenError`,不再重试

最坏单 unit 总等待 ~7s + 3 次实际请求时间。

### JSON 错重试 nudge

```dart
// lib/services/prompts.dart
static const String jsonRetryNudge =
    '\n\n注意:上一次返回的内容无法解析为 JSON,请只返回纯 JSON,不要任何解释或 <think> 内容。';
```

`_retryingRequest` 在 `attempt > 0 && lastKind == jsonParse` 时,system prompt 末尾追加这一行。每次 retry 都是同样 nudge,不 stack。

## 4. JobState 字段

```dart
class JobState {
  // 原有
  final String taskId;
  final JobKind kind;          // strategy | grading
  final JobPhase phase;        // running | done | failed
  final int total;
  final int done;
  final int failedCount;
  final String? error;
  final bool cancelRequested;

  // 新增
  final int attempt;                  // 0=非重试中,1=第1次重试,2=第2次,3=第3次
  final QwenErrorKind? lastErrorKind; // 最近一次失败分类
  final String? lastErrorUnit;        // "第 12 例" / "第 3 题"
}
```

**语义**:
- `attempt > 0` ⟺ 某个 unit 正在重试中;成功或最终失败后立即清零。
- `lastErrorKind` / `lastErrorUnit` 是「最近一次」快照,**不累计**;UI 只能显示「刚刚哪里出了什么」。历史属于 debug worktree 的 sink。
- 多 unit 并发时,这 3 个字段全局只有一份,后启动的 retry 覆盖前一个 → UI 闪烁可接受。
- `phase=done` 或 `phase=failed` 时强制清零(`copyWith` 内逻辑)。

## 5. UI

### Task Detail(grading 进行中,某例重试)

```
┌─────────────────────────────────────────────┐
│ ← 期中数学                                  │
├─────────────────────────────────────────────┤
│ 学生提交  18/30                             │
│ ▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░  60%                  │
│                                              │
│ ⟳ 第 12 例 · 重试 2/3 · JSON 解析错        │   ← attempt > 0 时显示
│                                              │     灰色小字,不抢眼
│ 失败 1                                      │
│ [取消批改]                                   │
└─────────────────────────────────────────────┘
```

### Task Detail(grading 全部跑完,有失败)

```
┌─────────────────────────────────────────────┐
│ ✓ 批改完成  28/30 成功 · 2 失败             │
│                                              │
│ ┌─────────────────────────────────────────┐ │
│ │ ⚠ 2 个 submission 失败                  │ │
│ │                  [重跑失败项 (2)]        │ │   ← phase=done/failed + failedCount>0
│ └─────────────────────────────────────────┘ │
│                                              │
│ 学生列表                                    │
│  • 张三  87  ✓                              │
│  • 李四  ⚠ 失败 — JSON 解析错               │
│  • 王五  92  ✓                              │
└─────────────────────────────────────────────┘
```

### Strategy Review(strategy 重试中 + 失败 banner)

```
┌─────────────────────────────────────────────┐
│ 批改策略 · 第 3/5 题                        │
│ ● ● ○ ○ ○                                  │
│                                              │
│ ⟳ 第 4 题 · 重试 1/3 · 请求超时            │   ← attempt > 0
│                                              │
│ ┌─────────────────────────────────────────┐ │
│ │ ⚠ 2 题生成失败                          │ │
│ │                  [重跑失败题 (2)]        │ │   ← phase=done/failed + 有 empty
│ └─────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

### Home 卡片

```
┌─────────────────────────────────────────────┐
│ 期中数学            18/30 批改中            │
│ ⟳ 重试 2/3 · JSON 解析错                   │   ← attempt > 0 时多一行
└─────────────────────────────────────────────┘
```

`resolveTaskCardStatus` 返回结构加 `retryHint: String?`,null 则不渲染。

### 错误类型 → 中文显示名(QwenError.displayName)

| QwenErrorKind | displayName |
|---|---|
| network | 网络未连接 |
| timeout | 请求超时 |
| http4xx | 接口拒绝 (4xx) |
| http5xx | 服务异常 (5xx) |
| jsonParse | JSON 解析错 |
| unknown | 未知错误 |

### 「重跑失败项 / 失败题」按钮行为

**Grading**:
```dart
void rerunFailedGrading(String taskId) async {
  final failed = taskNotifier.submissionsFor(taskId)
      .where((s) => s.status == SubmissionStatus.failed);
  for (final s in failed) {
    await taskNotifier.updateSubmission(
      s.copyWith(status: SubmissionStatus.pending, items: []),
    );
  }
  await startGrading(taskId);  // 已有逻辑:只挑 status != done 的 submission
}
```

**Strategy**:
```dart
void rerunFailedStrategy(String taskId) async {
  final refs = await ReferenceStore.load(taskId);
  final failed = refs.where((r) => r.checkpoints.isEmpty)
      .map((r) => r.questionNumber)
      .toList();
  if (failed.isEmpty) return;
  await startStrategy(taskId, onlyQuestions: failed);
}
```

`startStrategy` 内部:
```dart
final rubric = onlyQuestions == null
    ? task.rubric
    : task.rubric.where((r) => onlyQuestions.contains(r.questionNumber)).toList();
// ...生成 results...

// merge 保存:onlyQuestions=null 直接覆盖;非 null 时与已存 refs 合并
final existing = onlyQuestions == null ? <ReferenceAnswer>[] : await ReferenceStore.load(taskId);
final merged = _mergeReferences(existing, [for (final r in results) ?r]);
await ReferenceStore.save(taskId, merged);
```

`_mergeReferences` 规则:新生成的 ReferenceAnswer 按 questionNumber 覆盖旧的,旧的其它 question 保留(含 confirmed / chatHistory)。

## 6. 文件改动详单

### 新增

```
lib/services/qwen_error.dart                  ~50 行
test/qwen_error_test.dart                     ~80 行
test/qwen_service_retry_test.dart             ~120 行
test/job_queue_retry_test.dart                ~100 行
test/reference_store_merge_test.dart          ~60 行
```

### 改动

| 文件 | 新增 | 删除 | 说明 |
|---|---|---|---|
| `lib/services/qwen_service.dart` | +60 | -30 | `_retryingRequest` helper,4 处复用 |
| `lib/services/prompts.dart` | +5 | 0 | `jsonRetryNudge` 常量 |
| `lib/services/reference_store.dart` | +20 | -5 | Completer chain mutex |
| `lib/models/job_state.dart` | +20 | 0 | 3 个新字段 + copyWith |
| `lib/providers/job_queue_provider.dart` | +50 | -10 | `_retryWithFeedback`;`startStrategy` 加 `onlyQuestions` 参数 + merge |
| `lib/screens/task_detail_screen.dart` | +40 | 0 | attempt 行 + 失败 banner + 重跑按钮 |
| `lib/screens/strategy_review_screen.dart` | +25 | 0 | 同上(strategy 侧) |
| `lib/screens/home_screen.dart` | +15 | 0 | retryHint 行 |
| `lib/screens/home_screen.dart`(`resolveTaskCardStatus`) | +10 | 0 | retryHint 字段 |
| `test/task_card_status_test.dart` | +30 | 0 | attempt>0 输出 retryHint |
| `test/task_detail_screen_test.dart` | +50 | 0 | banner + 按钮 |
| `test/strategy_screen_test.dart` | +50 | 0 | strategy 侧同上 |
| `test/job_state_test.dart` | +30 | 0 | 新字段 copyWith + 清零 |

**合计 ~470 LOC,13 文件**(含测试约一半)。

## 7. 边界情况

1. **重试中用户点 cancel**:当前 attempt 的 Dio 请求不被打断(等其自然结束),`_retryWithFeedback` 每个 attempt 开始前检查 `cancelRequested`,直接跳出。最多多等 1 个请求时长。
2. **多 unit 并发重试,attempt 字段被覆盖**:接受 UI 闪烁;有意为之以保持 UI 简单。如真成问题,后续可改 `Map<unitId, attemptInfo>`。
3. **「重跑失败项」时新 job 启动前老 job 没 clear**:`_isRunning` 拦住;按钮在 phase=running 时禁用。UI 层处理。
4. **重跑后再失败**:同流程跑一遍,banner 数字更新。
5. **JSON nudge 累计爆 token**:nudge 只 ~30 字;每次 retry 是同样 nudge,不 stack。可忽略。
6. **`startStrategy(onlyQuestions: [99])` 但 question 99 不在 rubric**:过滤后空,立即 phase=done,total=0,无害。
7. **ReferenceStore 并发写**:补 Completer chain mutex 解决。
8. **重试期间 settings 改了**:`_newQwen()` 在 job 开始时已固定,下次 job 才生效(符合现有行为)。
9. **`http4xx` 不重试的代价**:401/403/404 重试无意义;接受。用户看到「接口拒绝 (4xx)」会自查 settings。
10. **Strategy 「重跑失败题」按钮 N=0 时按钮不出现**:UI 条件 `failed.length > 0`。

## 8. 测试矩阵

**单元(纯 Dart)**

| 文件 | 用例 |
|---|---|
| `test/qwen_error_test.dart` | `from(DioException)` 各 type 映射;`from(JsonParseException)` → jsonParse;`from(其它)` → unknown;`displayName` 中文 |
| `test/qwen_service_retry_test.dart` | Dio MockAdapter:① 第1次500→第2次200 成功;② 3次500 → 抛 QwenError(http5xx);③ 第1次坏 JSON→第2次好,nudge 出现在第2次 body;④ 第1次401 → 立即抛;⑤ backoff 在合理区间(fake clock) |
| `test/job_queue_retry_test.dart` | ① attempt/lastErrorKind/lastErrorUnit 推送;② 并发覆盖不卡 phase;③ retry 中 cancel 达终态;④ `startGrading` 调前 failed reset 为 pending,只跑这批;⑤ `startStrategy(onlyQuestions:[3,5])` 只跑这两题;⑥ 外层 try 失败仍达终态 |
| `test/job_state_test.dart` | copyWith 新字段;phase=done/failed 时清零 |
| `test/reference_store_merge_test.dart` | onlyQuestions=[3] 时 question 1/2 在 reference_*.json 中保留 confirmed/chatHistory |

**widget**

| 文件 | 用例 |
|---|---|
| `test/task_card_status_test.dart` 扩展 | attempt>0 输出 retryHint;phase=done 时 null |
| `test/task_detail_screen_test.dart` 扩展 | attempt 行渲染;banner 渲染;按钮 tap → startGrading 被调 + failed reset 为 pending |
| `test/strategy_screen_test.dart` 扩展 | strategy 侧同上;`onlyQuestions` 参数传对 |

## 9. 落地顺序(增量可合并)

每个 PR 独立可工作、可测、可回滚。

1. **PR 1**:`qwen_error.dart` + 单测。零行为变更。
2. **PR 2**:`_retryingRequest` 集成。**行为变化**:错误分类 + 自动重试 3 次。UI 不动 —— 老 UI 用 `ErrorFormatter.format(QwenError)` 仍能显示中文,失败次数下降 ~3x 是免费收益。
3. **PR 3**:JobState 新字段 + `_retryWithFeedback` + DebugService 事件。**行为变化**:retry 信息推到 state,UI 仍不渲染。
4. **PR 4**:UI 三处加 attempt 行。从此用户看见重试。
5. **PR 5**:`startStrategy(onlyQuestions:)` + ReferenceStore mutex + merge;Task Detail 「重跑失败项」按钮 + Strategy Review 「重跑失败题」按钮。

debug worktree 期间合 main 时,接触面只有 PR 3 的 `recordEvent('retry', ...)` 一行 —— 无 schema 冲突,他们的 sink 接口跟进一行即可。

## 10. 与 debug-observability 的协同

| 关注点 | 本 spec | debug-observability spec |
|---|---|---|
| QwenService 错误分类 | 引入 QwenError | 不动 |
| Retry 事件 | `recordEvent('retry', ...)` | 接收 + 通过 sink 落盘 |
| 长期统计(p50/p95) | 不做 | 做(Stats tab) |
| 历史失败列表 | 不做(只 lastError 快照) | 做(InMemoryRingSink + RollingFileSink) |
| UI 反馈 | 主屏即时 | /debug 屏离线分析 |

两条线**不冲突**:本 spec 把错误**分类、显示、可恢复**;debug-observability 把错误**全量留痕、长期分析**。
