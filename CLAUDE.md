# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository layout

The Flutter project lives in `yas_local/`. The repo root (`gradenow-fast/`) is the parent workspace — run all `flutter` commands from `yas_local/`. The product is branded as "GradeNow · AI 快批" (`pubspec.yaml` description) and "YAS 批改助手" in the UI; both refer to the same app.

## Commands

All commands run from the `yas_local/` directory:

```bash
flutter pub get              # Install dependencies
flutter analyze              # Static analysis / linting (flutter_lints ^6.0.0)
flutter test                 # Run all tests
flutter test test/<file>     # Run a single test file
flutter run -d macos         # Run on macOS desktop (primary dev target)
flutter run -d ios           # Run on iOS simulator
flutter build apk --release  # Build release Android APK
```

## Workflow

```
Create Task (rubric) → [Identify Questions] → Capture Submissions → [Review Strategy] → Grade → Results
```

Bracketed steps are optional: identification auto-discovers question text from images; strategy review lets the teacher confirm/refine reference answers via chat before grading.

## Architecture

Serverless Flutter app (YAS 批改助手 / GradeNow) that calls a vision-language LLM (default: Alibaba Cloud Qwen) directly from device to grade scanned exam papers. All data is local JSON files — no backend, no database, no cloud sync.

### Layer structure

```
Screens (lib/screens/)  →  Providers (lib/providers/)  →  Services (lib/services/)
                              ↕
                           Models (lib/models/)
```

- **Screens** consume providers via Riverpod's `ref.watch` and route between screens.
- **Providers** (`StateNotifierProvider`) hold mutable app state and persist it via the `*_store` services. They call into services for side effects (HTTP, file I/O).
- **Services** are stateless wrappers: HTTP (Dio), file I/O, prompt templates, JSON extraction, logging.
- **Models** are immutable data classes with `fromJson` / `toJson` for persistence.

### Routing

`lib/app.dart` defines a `GoRouter` with 10 routes — root `/`, `/settings`, `/tasks/create`, `/tasks/:id`, `/tasks/:id/{strategy,capture,identify,results}`, `/submissions/:sid`, and `/debug`. Task and submission IDs are path parameters. (The former full-screen `/tasks/:id/grading` route was removed when grading moved to a background job — see "Async background jobs" below.)

## Grading pipeline

Two phases, with Phase 1 now a separate interactive workflow backed by a per-task cache file. **Both phases run as background jobs via `JobQueueNotifier` (see "Async background jobs" below) — there is no full-screen grading screen anymore.**

**Phase 1 — Reference answer generation** (driven by `JobQueueNotifier.startStrategy` for the VLM call, reviewed via `StrategyNotifier`):
1. `JobQueueNotifier.startStrategy(taskId)` runs `QwenService.generateStrategy()` per rubric item in parallel (see JobQueue section) and writes the batch to `reference_<taskId>.json` in one shot.
2. The Strategy Review screen loads the cached references and lets the user review each question's checkpoints, refine via chat (`refineStrategy()`), and confirm individually or all at once. `saveAllConfirmed()` persists the (potentially edited) references back to disk for Phase 2 to consume.

**Phase 2 — Batch grading** (driven by `JobQueueNotifier.startGrading`, rubric-first, one submission at a time, kicked off from the task-detail screen):
1. Load cached `ReferenceAnswer` objects (unconfirmed references are still used for grading).
2. For each submission: `QwenService.gradePaper()` sends question paper + student image to the VLM, which returns per-question `QuestionGradeResult` (extracted answer + `CheckpointResult` list + confidence).
3. `GradedItem.aiScore` = sum of `CheckpointResult.pointsAwarded`; save items + mark submission done/failed.

`StrategyNotifier` still owns the *review* side of Phase 1 (chat history, confirmation, checkpoint editing) but no longer drives the VLM call itself — that lives on the JobQueue so it can run in parallel and survive screen navigation.

**Identification** is an independent pre-rubric step (`IdentificationNotifier` + `QwenService.identifyQuestions()`) that samples 3 submission images and asks the VLM to enumerate question numbers, text, and types before the teacher builds the rubric.

## Async background jobs (JobQueue)

Long-running VLM loops (Phase 1 strategy generation, Phase 2 grading) run as in-memory background jobs keyed by `taskId`, NOT as a screen you navigate to. This lets the teacher trigger grading from the task-detail screen and walk away — progress and errors show up on the task card and the task detail, then the job is dismissed.

- **State**: `lib/models/job_state.dart` — `JobState { taskId, kind (strategy|grading), phase (running|done|failed), total, done, failedCount, error, cancelRequested }`. There is no `cancelled` phase; a cancelled job ends as `done` with fewer units processed.
- **Notifier**: `lib/providers/job_queue_provider.dart` — `jobQueueProvider` holds a `Map<String, JobState>`. Per-task entry points: `startGrading(taskId)`, `startStrategy(taskId)`, `cancel(taskId)`, `clear(taskId)`. Each is idempotent and refuses to re-run while a job is already in `running` phase for that task.
- **Concurrency**: `lib/services/run_pool.dart` — `runPool(items, maxConcurrency, task)` (max = `kMaxConcurrency = 3`, kept small to be friendly to free-tier rate limits). Dart is single-isolate so the worker's `next++` cursor needs no lock. Errors do NOT auto-propagate: the JobQueue wraps each per-unit task in try/catch so one failed submission/question never aborts the batch. The first error wins the job's `error` field.
- **Persistence isolation**: jobs themselves are session-scoped (not written to disk). Durable progress lives on each `Submission`'s status; durable strategy output lives in `reference_<taskId>.json`. `TaskStore` writes are serialized via a mutex (added in 13c9a45) so parallel jobs persisting to `tasks.json` don't clobber each other.
- **UI integration**: home cards and the task-detail screen read `jobQueueProvider` to derive a per-task status (`resolveTaskCardStatus`). The strategy review screen kicks off `startStrategy` and runs the VLM in the background — no spinner screen.

When changing the JobQueue: always derive the next `JobState` via `_patch(taskId, update)` rather than holding a stale copy, so a `cancelRequested` set by another caller is not clobbered. Outer `try/catch` around the per-unit loop is mandatory — if e.g. `ReferenceStore.load` throws, the job must still reach a terminal phase or `_isRunning` will stay true and the task can never be re-graded.

## Qwen service surface

`lib/services/qwen_service.dart` exposes four VLM-backed methods, all using `settings.vlModel`:

| Method | Purpose |
|---|---|
| `generateStrategy` | Phase 1: produce `ReferenceAnswer` (checkpoints + equivalent forms) for one rubric item |
| `refineStrategy` | Phase 1: re-run strategy generation given chat history + new user instruction |
| `identifyQuestions` | Pre-rubric: enumerate questions from sampled submission images |
| `gradePaper` | Phase 2: grade one submission image against all rubric references |

All calls are POSTs to `/chat/completions` with a 30 s connect / 300 s receive timeout. `QwenService._normalizeBaseUrl()` strips common endpoint suffixes (`/chat/completions`, etc.) so users can paste full URLs in settings. The two loop methods (`generateStrategy`, `gradePaper`) are invoked through `runPool(..., kMaxConcurrency)` from `JobQueueNotifier`, so multiple rubric items / submissions are in flight concurrently per task.

## JSON extraction & reasoning stripping

`lib/services/json_extractor.dart` is the only place that parses LLM response bodies. It exposes:

- `requireObjectWithReasoning(text)` → `ExtractionResult { reasoning, json }` — used by Phase 1 (strategy + refinement).
- `requireListWithReasoning(text, fromKey: ...)` → `ExtractionListResult { reasoning, list }` — used by identification and grading.

It strips `<think>…</think>` and `<thinking>…</thinking>` blocks (case-insensitive) and tries, in order: code-fence blocks, then bracket-matching the cleaned text. On failure it throws `JsonParseException` with the raw content (truncated to 300 chars). Reasoning text is kept separate from JSON so it can be surfaced to the teacher in the strategy review but discarded for grading/identification. When the Debug subsystem is enabled, `JsonExtractor` records every parsing attempt (method, ok/err) to `DebugService` via a `JsonAttemptBuilder`, so a failed extraction is debuggable from the in-app debug screen.

## Data persistence

- All data stored as JSON files in the app's documents / app-support directory.
- `tasks.json`: array of `GradingTask` + array of `Submission`, loaded eagerly at app start. Writes are serialized (see "Async background jobs" — parallel jobs sharing the same store must go through a mutex).
- `reference_<taskId>.json`: cached Phase 1 output per task; re-running Phase 1 skips questions already present.
- `settings.json`: single `AppSettings` object.
- Images copied to app documents directory for persistence across sessions.

## Debug 与可观测性

所有 Qwen 调用 / 业务事件 / JSON 解析尝试 / Flutter 错误都通过 `DebugService` 记录，由一个 sink 列表分发到多个目的地。

### 架构

```
Flutter 代码
   ↓ recordQwenCall / recordEvent / recordJsonAttempt
DebugService (singleton)
   ├→ DebugStats (O(1) 写入路径上更新计数)
   └→ [InMemoryRingSink, RollingFileSink, ...]   (可插拔)
```

- **Service**: `lib/services/debug/debug_service.dart` —— `DebugService.instance` 是单例，public API 是 `recordQwenCall` / `recordEvent` / `recordJsonAttempt` / `setEnabled` / `clear` / `resetForTest`。内部用 `_dispatch` 路由到所有 sink。
- **Sink 接口**: `lib/services/debug/debug_sink.dart` —— `DebugSink.write(record)` **绝不能抛异常**。
- **InMemoryRingSink**: 进程内 ring buffer，容量（qwen 200 / event 1000 / json 200）通过构造参数注入。
- **RollingFileSink**: 落盘到 `getApplicationSupportDirectory()/log/yas_YYYY-MM-DD.log`，5MB 轮转、NDJSON 格式。
- **DebugStats**: 写入路径上 O(1) 更新 `Map<DebugScope, _ScopeStats>` 计数器；snapshot 给 Stats tab 用。

### 错误捕获三件套（main.dart）

| 钩子 | 捕获 | 典型来源 |
|---|---|---|
| `FlutterError.onError` | framework 内同步异常 | Widget build 抛错、layout overflow、`setState() called after dispose()` |
| `PlatformDispatcher.instance.onError` | 顶层 async 未捕获 | `Future` 里 throw 但没人 await |
| `runZonedGuarded` 兜底 | zone 内所有未捕获 | 启动期 async、Timer callback、Stream subscription |
| `ErrorWidget.builder` | widget render 抛错 | 自定义 widget build 异常 |

`kDebugMode` 时仍 `FlutterError.presentError` 弹红屏；release 模式不暴露。

### /debug 屏

`/debug` 路由 5 个 tab（`lib/screens/debug/tabs/`）：
- **Qwen 调用** — 每次 Qwen HTTP 调用的完整记录
- **事件** — 业务事件（`scope` 形如 `task:<id>` / `sub:<id>` / `flutter_error` 等）
- **JSON 解析** — 每次 `JsonExtractor` 解析尝试链
- **状态** — `DebugService.stateSnapshot`（tasks / references / settings）
- **统计** — `DebugStats` 实时面板，per-scope 计数 + 全局 p50/p95 + 错误率

每 tab 顶部都有 Export 按钮（见下）。

### 调试导出

每个 tab 顶部的 Export IconButton：
- 序列化当前 tab 数据为 pretty JSON
- 写到 `{getApplicationDocumentsDirectory()}/exports/{tab}_{yyyyMMdd_HHmmss}.json`
- macOS 弹 Finder 高亮（`open -R`）；iOS 弹 share sheet（`share_plus`）；其它降级到剪贴板

## Key patterns

- **State management**: Riverpod `StateNotifierProvider` for all mutable state.
- **API calls**: Dio with 30 s connect / 300 s receive timeout; all calls use `vlModel` (vision-language model).
- **Checkpoint scoring**: `GradedItem.aiScore` is the sum of `CheckpointResult.pointsAwarded` across all checkpoints for that question — not a single AI score.
- **Reference caching**: `reference_<taskId>.json` written by `JobQueueNotifier.startStrategy` (initial batch) and `StrategyNotifier.saveAllConfirmed` (after edits). Read by `JobQueueNotifier.startGrading` for Phase 2.
- **Interactive strategy refinement**: `ReferenceAnswer.confirmed` + `chatHistory` enable a teacher-in-the-loop workflow where strategy can be iterated per-question before final grading. Refinement (`refineStrategy`) is a *sync* call from the review screen, distinct from the *async* generation done by `JobQueueNotifier.startStrategy`.
- **Background jobs over full-screen flows**: long-running VLM loops run as `JobQueueNotifier` jobs keyed by `taskId`, not as dedicated screens. UI shows live progress and errors on the task card / task detail. Always reach a terminal phase — even an outer `try/catch` failure must set `phase` to `failed`, otherwise `_isRunning` stays true and the task can never be re-graded.
- **Concurrency**: `runPool(items, kMaxConcurrency, task)` runs units in parallel (max 3, friendly to free-tier rate limits). Per-unit errors are caught and reflected on `JobState.failedCount` / `error`; the first error wins. `TaskStore` writes are serialized to make parallel persistence safe.
- **Error handling**: `lib/services/error_formatter.dart` formats Dio errors in Chinese with URL, status code, and response snippet. First error in a batch is surfaced on the job's `error` field; the batch continues.
- **Base URL normalization**: `QwenService._normalizeBaseUrl()` strips common endpoint suffixes so users can paste full URLs in settings.
- **Teacher overrides**: `GradedItem.finalScore` prefers `teacherScore` over `aiScore`; `teacherScore` set via slider in `paper_detail_screen.dart`.
- **Confidence traffic light**: `GradedItem.trafficLight` — green (≥0.85), yellow (≥0.60), red (<0.60).
- **Debug 是开发者工具**：所有 debug 数据只在 `/debug` 屏 + 磁盘日志里，**不**对老师 / 学生可见。
- **ErrorBoundary 不存在**：Flutter 没有真正的局部 ErrorBoundary，依赖 `FlutterError.onError` / `PlatformDispatcher.onError` / `runZonedGuarded` / `ErrorWidget.builder` 四件套兜底；自定义 widget 内的 try/catch 由业务侧负责。
- **Sink 永远不抛**：`DebugSink.write` 必须 try/catch 内部错误（兜底），但 sink 实现不应依赖这个兜底。

## File map

This list is intentionally non-exhaustive — only the files that materially shape the architecture are called out.

**Models** (`lib/models/`) — pure data classes, all with `fromJson`/`toJson`:
`rubric.dart`, `task.dart`, `submission.dart` (incl. `GradedItem`, `SubmissionStatus`), `checkpoint.dart` (incl. `CheckpointDef`, `CheckpointResult`), `reference_answer.dart`, `identified_question.dart`, `strategy_message.dart`, `settings.dart`, `job_state.dart` (in-memory only — not persisted; see "Async background jobs").

**Services** (`lib/services/`):
- `qwen_service.dart` — Dio HTTP, all VLM calls (see table above).
- `prompts.dart` — `AppPrompts` static methods, all LLM prompt templates live here. Edit here to tune prompts.
- `json_extractor.dart` — `JsonExtractor` + `JsonParseException` + `ExtractionResult`/`ExtractionListResult`. The only place that parses response bodies.
- `debug/debug_service.dart` — `DebugService` singleton + record types (QwenCallRecord, EventRecord, JsonAttemptRecord). Routes records through a `List<DebugSink>`. See "Debug sink architecture" above.
- `debug/debug_sink.dart` — `DebugSink` interface (`write` / `flush` / `close`).
- `debug/in_memory_ring_sink.dart` — `InMemoryRingSink`, the default in-memory sink on `DebugService.instance`.
- `debug/rolling_file_sink.dart` — `RollingFileSink`, NDJSON + 5MB rotation sink; added at app startup via `DebugService.instance.addSink(...)` in `main.dart`.
- `debug/debug_stats.dart` — `DebugStats` with O(1) per-scope counters and percentile snapshot.
- `debug/debug_export.dart` — `DebugExport.writeJson` + `reveal` (per-tab JSON export).
- `debug/tab_constants.dart` — 5 tab name constants.
- `run_pool.dart` — `runPool(items, maxConcurrency, task)` concurrency helper (see "Async background jobs").
- `error_formatter.dart` — Chinese-language Dio error formatter.
- `task_store.dart`, `reference_store.dart`, `settings_store.dart` — JSON file I/O.
- `image_store.dart` — copies temp photos to app documents directory.

**Providers** (`lib/providers/`):
- `task_provider.dart` — `TaskNotifier`, CRUD for tasks + submissions, auto-persists to JSON.
- `identification_provider.dart` — `IdentificationNotifier`, AI question discovery from submission images.
- `strategy_provider.dart` — `StrategyNotifier`, Phase 1 *review* side: chat refinement + confirmation + checkpoint editing. The VLM generation call itself lives on `JobQueueNotifier.startStrategy`.
- `job_queue_provider.dart` — `JobQueueNotifier`, the background-job manager for `startGrading` / `startStrategy` / `cancel` / `clear` (see "Async background jobs"). Backed by `runPool` for concurrency.
- `settings_provider.dart` — `SettingsNotifier`, API config state.
- `debug_provider.dart` — `debugProvider` for the in-app Debug screen (see "Debug subsystem").

**Screens** (`lib/screens/`) — wired to the router. The strategy review screen is split into a folder of sub-screens; the full-screen grading screen has been removed in favor of background jobs (see "Async background jobs"):
`home_screen` (task list + FAB + unconfigured-API banner + per-task progress), `settings_screen`, `create_task_screen` (rubric builder), `task_detail_screen` (task hub + start-grading button + inline job progress), `identify_screen`, `capture_screen` (camera/picker + grid preview), `strategy_review_screen` + `strategy_review/` sub-screens (`question_page`, `chat_sheet`, `edit_checkpoint_sheet`, `progress_dots`, `bottom_action_bar`), `results_screen` (avg/max/min + submission list), `paper_detail_screen` (per-question checkpoint breakdown + teacher score slider), `debug_screen` (in-app Debug viewer at `/debug`).

**Widgets** (`lib/widgets/`): `debug_entry_button` — a small entry point to the Debug screen, shown only in development builds.

## Tests

Run from `yas_local/`. The vast majority of tests are pure-Dart unit tests — no Flutter binding required. Only the `*_screen_test.dart`, `widget_test.dart`, and `debug_entry_button_test.dart` files need the binding.

Notable files (full directory is in `yas_local/test/`):

- `json_extractor_test.dart` — largest suite: reasoning split, code-fence extraction, fallback, error paths (incl. DebugService hook).
- `models_test.dart` — JSON round-trips for all models; `finalScore`, `trafficLight`.
- `task_detail_test.dart`, `strategy_screen_test.dart`, `settings_screen_test.dart`, `debug_screen_test.dart`, `debug_entry_button_test.dart` — widget tests.
- `prompts_test.dart` — `AppPrompts` template content (no API calls).
- `grading_test.dart` — `CheckpointResult` aggregation, `ReferenceAnswer` construction.
- `settings_test.dart`, `settings_provider_snapshot_test.dart` — `AppSettings` defaults, `isConfigured`, JSON round-trip, provider snapshot.
- `task_store_test.dart` — `TaskStore` + `ReferenceStore` encode/decode round-trips.
- `persist_lock_test.dart` — `TaskStore` write serialization under concurrent jobs.
- `run_pool_test.dart` — `runPool` concurrency semantics (no leaking, error isolation).
- `job_queue_test.dart` — `JobQueueNotifier` lifecycle: idempotent start, cancel, terminal-phase-on-outer-error, per-task state isolation.
- `qwen_service_test.dart` — Dio interceptor / `QwenCallRecord` capture.
- `results_partial_test.dart` — locks in partial-grading rendering on the results screen.
- `task_card_status_test.dart` — `resolveTaskCardStatus` derivation from `JobState`.
- `strategy_provider_test.dart`, `strategy_navigation_test.dart` — `StrategyNotifier` review side, navigation.
- `debug_service_test.dart`, `debug_provider_test.dart` — `DebugService` ring buffers + opt-in flag + reset semantics.
- `image_compressor_test.dart` — VLM-input image compression.
- `debug_sink_test.dart` — InMemoryRingSink 裁剪 + RollingFileSink rotation
- `debug_stats_test.dart` — O(1) 计数、p50/p95、最近 100 裁剪
- `debug_export_test.dart` — 写文件 + 平台 reveal 不抛
- `main_error_hooks_test.dart` — 四件套钩子安装
- `error_widget_test.dart` — `ErrorWidget.builder` 触发 record
- `widget_test.dart` — smoke test, renders `YasApp`.

## Project docs

- `docs/2026-05-31-yas-local-mvp.md` — Original MVP plan (superseded by the two-phase redesign).
- `docs/grading-redesign.md` — Two-phase grading design doc (now fully implemented; explains why Phase 1 exists separately and why checkpoint scoring replaced binary grading).
- `docs/superpowers/plans/2026-06-05-debug-observability.md` — M1-M5 implementation plan (sink-based debug architecture).
- `yas_local/README.md` — User-facing Chinese README; covers dev commands, log file locations, and how to export logs from iOS.
