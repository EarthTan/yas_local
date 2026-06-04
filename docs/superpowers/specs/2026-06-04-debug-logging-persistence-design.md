# Debug 日志落盘与导出 — 设计文档

**日期**：2026-06-04
**目标用户**：开发者（macOS dev）、老师（导出诊断包发回开发者）
**状态**：已对齐，待实现

---

## 1. 背景与问题

应用在「识别题目」「生成涂改策略」「AI 批改」三步频繁失败，老师只能看到一个失败标志（SnackBar / 错误文案），开发者复现时也看不到：
- Qwen API 实际请求/响应（已 base64 redact）
- 错误堆栈
- 上下文（taskId、questionNumber、submissionId）

更糟的是 macOS 沙盒让日志查找本身就很痛（`~/Library/Containers/cn.yas.yasLocal/...` 路径深），且 `CLAUDE.md` 描述的旧 `QwenLogger`（带 daily rotation 的文件记录器）**已经被删掉**，替换成了纯内存版 `DebugService`——所以"日志似乎不保存了"是真的：**根本没在保存**。

## 2. 目标

| ID | 目标 |
|---|---|
| G1 | 三个失败步骤的完整记录（Qwen call / Event / JSON parse）落盘到沙盒内 JSONL 文件 |
| G2 | 错误记录**永远**落盘，不受 debugMode 开关控制 |
| G3 | 老师/开发者能从 macOS Finder 直接访问日志（"在 Finder 中显示"按钮） |
| G4 | 老师能一键导出诊断包（zip）发回开发者，zip 内含 jsonl + 去敏感任务上下文 |
| G5 | 现有内存环形缓冲 + DebugScreen 行为完全不变（不破坏现有 32+ 测试） |

## 3. 非目标（YAGNI）

- SQLite 持久化、远程日志、云端上报
- 实时 tail UI（debug 屏已有 4 个 tab，刷新即可）
- 自定义日志级别过滤
- 关闭 macOS 沙盒以写入项目目录

## 4. 架构

### 4.1 文件布局

```
lib/services/
  debug_service.dart           ← 改：构造时注入 writer；recordXxx 内部多调一次 writer.write
  debug_log_writer.dart        ← 新：异步批量写 JSONL + 轮转
  debug_export_service.dart    ← 新：zip 打包 + Finder/SavePanel
  log_redactor.dart            ← 新：API key / base64 脱敏工具（纯函数）

lib/screens/debug_screen.dart  ← 改：AppBar actions 加 3 个按钮

pubspec.yaml                   ← 改：+ archive: ^3.6.1
```

### 4.2 磁盘布局

`getApplicationDocumentsDirectory()/debug_logs/`
- 主文件：`debug_YYYY-MM-DD.jsonl`（每日一个）
- 轮转：单文件超 5 MB → `debug_YYYY-MM-DD.1.jsonl`、`.2.jsonl`…最多保留 5 个
- macOS 实际路径：`~/Library/Containers/cn.yas.yasLocal/Data/Documents/debug_logs/`
- 不向用户展示这个路径，全靠"在 Finder 中显示"按钮

### 4.3 jsonl 行结构

每行一个 JSON object，靠 `type` 字段分桶：

```json
{"type":"qwen","ts":"2026-06-04T14:23:01.123Z","scope":"strategy","trigger":"debugMode","model":"qwen-vl-max",...}
{"type":"event","ts":"...","scope":"task:abc / q:1","level":"error","trigger":"error","message":"...","data":{...}}
{"type":"json","ts":"...","scope":"grade","trigger":"debugMode","input_snippet":"...","attempts":[{...}],"final_exception":null}
```

`trigger` 枚举：
- `debugMode`：仅当 `settings.debugMode = true` 时记录的正常调用
- `error`：error 级 event 或 httpError/parseError qwen 调用，**绕过** debugMode 开关

### 4.4 组件

**`DebugLogWriter`**（单例）
- 公开 API
  - `Future<void> init()` — 应用启动时调一次，建目录、打开当日文件
  - `void write(record, {required String trigger})` — fire-and-forget 入队；`trigger: 'error'` 走立即 flush，其余入批量队列
  - `void setEnabled(bool)` — 跟随 debugMode；为 `false` 时 `trigger: 'debugMode'` 的 write 在入队前直接 no-op；`trigger: 'error'` 不受影响
  - `void flushNow()` — 调试面板手动触发
  - `Future<void> dispose()` — 应用退出排空队列
  - `Future<void> deleteAll()` — 调试面板"清空日志"用，删 `debug_logs/` 下所有 jsonl
  - getters：`logDir`、`currentFilePath`、`totalSizeBytes`
- 内部
  - FIFO 队列 + 1 秒定时器
  - 立即 flush 通道：error 记录走这里（同步 fsync）
  - 连续 IO 失败 3 次 → 进入 degraded 模式（后续 write no-op）
  - 队列上限 5000 条；满了丢最老的，并在下次 flush 时打一条 `type=event, level=warn` 记录

**`LogRedactor`**（纯函数）
- `String maskApiKey(String key)` — 留前 4 + 末尾 4，中间 `***`；空串返回空串
- `Map<String, dynamic> redactSettings(AppSettings s)` — apiKey 走 maskApiKey
- base64 图片 redact 复用 `QwenService.redactBase64Messages`（已 public static）

**`DebugExportService`**
- 公开 API
  - `Future<void> openLogDir()` — `Process.run('open', [writer.logDir])`
  - `Future<String?> buildAndShowSaveDialog()` — 主流程：buildZipBytes → NSSavePanel → 写盘 → 返回最终路径
  - `Future<List<int>> buildZipBytes({bool includeTaskContext = true})` — 纯函数，可独立测试
- 内部 zip 内容
  - `debug_YYYY-MM-DD.jsonl`（当日所有 jsonl，不只今天）
  - `tasks_snapshot.json`（rubric 完整 + submissions 元数据，无 base64 / 无 imagePath 之外的文件内容）
  - `settings_redacted.json`
  - `manifest.json`（导出时间、jsonl 行数、应用版本）

**`DebugService` 改动**（最小化）
- 新增 `final DebugLogWriter _writer` 字段
- 构造可注入：`DebugService({DebugLogWriter? writer})` → 测试可注入 no-op
- `recordQwenCall` / `recordEvent` / `recordJsonAttempt` 在现有内存追加后多调一次 `_writer.write(record, trigger: ...)`，触发规则：
  - Qwen call `status == ok` → `trigger: 'debugMode'`
  - Qwen call `status` 为 `httpError` / `parseError` → `trigger: 'error'`（**绕过** enabled 开关）
  - Event `level == EventLevel.error` → `trigger: 'error'`（**绕过** enabled 开关）
  - Event `level` 为 `info` / `warn` → `trigger: 'debugMode'`（受 enabled 开关约束）
- `setEnabled(v)` 多调一次 `_writer.setEnabled(v)`
- `resetForTest()` 同时 `_writer.resetForTest()`
- 公开行为（返回值、listener 通知顺序）零变化

**`DebugScreen` 改动**
- AppBar `actions` 区加 3 个按钮（独立于 🐞 入口按钮的可见性——error 记录可能即使 debugMode=false 也会写）
- "📂 在 Finder 中显示" → `ExportService.openLogDir()`
- "📦 导出诊断包" → `ExportService.buildAndShowSaveDialog()`，完成后 SnackBar 显示路径
- "🗑️ 清空日志" → 二次确认 → `writer.deleteAll()`（仅清磁盘，**不**清内存环形缓冲）

**iOS 适配**（仅做"不崩"，完整 UX 是后续工作）
- "在 Finder 中显示"按钮在 iOS 上隐藏（用 `Platform.isMacOS` 包一层，Widget 在 `Platform.isMacOS == false` 时返回 `SizedBox.shrink()`）
- "导出诊断包"按钮在 iOS 上仍显示，点击后：
  - 先尝试 `share_plus` 风格的 native share sheet；若未来引入 `share_plus: ^10.x` 再实现，本次只走 fallback
  - Fallback：先调 `buildZipBytes` 写到 `getTemporaryDirectory()/diag_YYYYMMDD-HHMMSS.zip`，SnackBar 提示"诊断包已生成：<绝对路径>"，并提供"复制路径"按钮
- 文件落盘到 `getApplicationDocumentsDirectory()` 在 iOS 同样持久化，没问题

## 5. 数据流

### 5.1 启动

```
app.dart main()
  └─> DebugService.bootstrap()       ← 新增静态
        ├─> DebugLogWriter.init()
        │     ├─> getApplicationDocumentsDirectory()
        │     ├─> mkdir debug_logs/
        │     └─> open debug_YYYY-MM-DD.jsonl for append
        └─> SettingsNotifier 构造时
              └─> DebugService.setEnabled(state.debugMode)
                    └─> writer.setEnabled(debugMode)
```

### 5.2 一次失败 case

```
老师点 "开始批改"
  └─> GradingNotifier.runPhase2Only()
        └─> loop: qwen.gradePaper(submission)
              ├─> Dio onResponse (ok)
              │     └─> DebugService.recordQwenCall(..., status: ok)
              │           ├─> 内存 ring buffer add
              │           └─> writer.write(record, trigger: 'debugMode')  ← 异步入队
              │                 └─> 1 秒后 flush 到 jsonl
              │
              └─> Dio onError (httpError 500)
                    └─> DebugService.recordQwenCall(..., status: httpError)
                          ├─> 内存 ring buffer add
                          └─> writer.write(record, trigger: 'error')  ← 同步 fsync
                                ↓
                                抛 DioException
                                  ↓
    GradingNotifier catch (e)
      ├─> updateSubmission(status: failed)
      ├─> state.error = ErrorFormatter.format(e)   ← 老师看到的失败标志
      └─> DebugService.recordEvent(level: error, data: {'error': e.toString()})
            └─> writer.write(event, trigger: 'error')   ← 同步 fsync
```

### 5.3 老师事后查看——"在 Finder 中显示"

```
老师打开 /debug
  └─> 点 "📂 在 Finder 中显示"
        └─> DebugExportService.openLogDir()
              └─> Process.run('open', [writer.logDir])
                    └─> macOS Finder 打开 debug_logs/ 目录
```

### 5.4 老师事后查看——"导出 zip"

```
老师点 "📦 导出诊断包"
  └─> DebugExportService.buildAndShowSaveDialog()
        ├─> buildZipBytes(includeTaskContext: true)
        │     ├─> 扫 debug_logs/*.jsonl（所有历史，不只今天）
        │     ├─> 收集当日 jsonl 里出现过的 taskId 集合
        │     ├─> 从 TaskStore 加载这些 task 的 rubric + submissions 元数据
        │     ├─> LogRedactor.redactSettings(snapshot)
        │     └─> archive 包打包
        ├─> NSSavePanel（默认文件名 diag_YYYYMMDD-HHMMSS.zip，默认目录 ~/Desktop）
        └─> 写盘 → SnackBar 显示最终路径
```

## 6. 错误处理

| 失败点 | 行为 | 理由 |
|---|---|---|
| `getApplicationDocumentsDirectory()` 抛异常 | `init()` 吞掉 → degraded 模式（write 全 no-op）+ SnackBar 一次提示 | 启动期一次失败不该崩 app |
| `mkdir` 失败 | 同上 | 同上 |
| 单次 jsonl append 失败 | 内部 try/catch + `_consecutiveFailures++`；连续 3 次 → 整体关闭 writer | 防止反复重试浪费 CPU |
| 队列满 5000 | 丢最老的，下次 flush 打 `level=warn, message=queue overflow, dropped=N` 记录 | 防止内存爆炸 |
| `Process.run('open', ...)` 非 0 | SnackBar 提示 "无法打开 Finder，请改用'导出诊断包'" | |
| NSSavePanel 用户取消 | return null，无 SnackBar | 不要噪音 |
| `buildZipBytes` IO 失败 | 抛 `DebugExportException` → SnackBar "打包失败：<原因>" | 让老师重试 |
| 磁盘满 | `FileSystemException` → 走 `consecutiveFailures` 路径 | 已有覆盖 |

**不变量**
- 磁盘写永远 best-effort，绝不让日志写挂掉主流程
- error 触发永远落盘，绕过 debugMode
- 内存环形缓冲容量 200/1000/200 不变
- API key 永远不落盘（`LogRedactor` + 复用 `redactBase64Messages`）
- 不向用户展示沙盒绝对路径

## 7. 测试

### 7.1 新增

**`test/debug_log_writer_test.dart`**
- `init()` 在干净目录建出 `debug_logs/debug_YYYY-MM-DD.jsonl`
- `init()` 第二次调用不会覆盖旧文件
- `write(qwen, trigger: debugMode)` 落盘后再读能 parse
- `write(event level: error, trigger: error)` 即使 `enabled=false` 也会落盘
- 连续 3 次 write 失败后 writer 进入 degraded 模式
- daily rotation：把当日文件 mock 成 6 MB → 下次 `write` 触发轮转
- 队列 5000 上限：mock 超量 → 老记录被丢 + 有 warn event

**`test/debug_export_service_test.dart`**
- `buildZipBytes(includeTaskContext: true)` 生成的 zip 用 `archive` 反向解，拿到 manifest + settings_redacted + 至少一个 jsonl
- `buildZipBytes(includeTaskContext: false)` 不含 tasks_snapshot
- 空 `debug_logs/` 仍生成有效 zip（只有 manifest）

**`test/log_redactor_test.dart`**
- `maskApiKey('sk-1234567890abcdef')` → `'sk-1...cdef'`
- `maskApiKey('short')` → `'s***t'`
- `maskApiKey('')` → `''`
- `redactBase64Messages` 已有覆盖，不重测

### 7.2 回归（要确认不破）

- `test/debug_service_test.dart` — 32 个用例（writer 注入不改变 recordXxx 行为）
- `test/qwen_service_test.dart` — Dio 拦截器
- `test/debug_provider_test.dart` — listener 通知顺序
- `test/json_extractor_test.dart` — JsonAttemptBuilder
- `test/debug_screen_test.dart` — DebugScreen 渲染

## 8. 验收 checklist

实施完成后必跑：

1. `flutter run -d macos` → 启用 debugMode → 触发一次 gradePaper 失败 → `debug_logs/` 出现 jsonl → debug 屏能看到 ✅❌
2. 同上，但**不**开 debugMode → jsonl 里仍有那条 error → debug 屏空（保持原状）
3. "📂 在 Finder 中显示" → Finder 打开目录
4. "📦 导出诊断包" → SavePanel 弹 → 选 Desktop → 桌面生成 zip → 解压看 manifest + jsonl + settings_redacted + tasks_snapshot
5. `flutter test` 全过
6. `flutter analyze` 0 issue

## 9. 依赖

- `archive: ^3.6.1`（zip 打包，跨平台）
- `path: ^1.9.0`（已有传递依赖，显式 pin 一下确保可解析）
- macOS 沙盒仅需现有 `user-selected.read-write` 授权，NSSavePanel 自动获用户授权
- iOS 暂不新增 `share_plus`（fallback 路径已足够）

## 10. 不动的文件

- `qwen_service.dart` — Dio 拦截器继续调 `DebugService.recordQwenCall`，不直接碰 writer
- `json_extractor.dart` — 继续走 `JsonAttemptBuilder`
- 三个 provider 继续调 `recordEvent`
- `app.dart` 仅加一行 `DebugService.bootstrap()`（除非需要 await）
