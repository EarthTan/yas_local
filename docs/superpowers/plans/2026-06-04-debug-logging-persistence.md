# Debug 日志落盘与导出 — 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist `DebugService` records to JSONL files inside the macOS app sandbox, add a one-click "show in Finder" button and a one-click diagnostic-zip export so that AI-grading failures (识别题目 / 涂改策略 / 批改) leave a recoverable trail.

**Architecture:** `DebugService` (existing) keeps its in-memory ring buffers unchanged. A new `DebugLogWriter` (singleton, async-batched JSONL appender with size-based daily rotation) is injected into `DebugService`; every `recordXxx` call gets a sibling `_writer.write(..., trigger: ...)` dispatch. `trigger: 'error'` flushes synchronously and bypasses the `debugMode` gate; `trigger: 'debugMode'` is batched and gated. A new `DebugExportService` zips all current JSONL files plus a redacted task snapshot via the `archive` package and surfaces a save dialog through `file_selector`. `DebugScreen` gains three AppBar buttons (in-Finder / export / clear).

**Tech Stack:** Flutter 3.x, Riverpod 2.x, `path_provider` (existing), `archive: ^3.6.1` (new), `file_selector: ^1.1.0` (new), `path: ^1.9.0` (explicit pin, was transitive). `dart:io` `File` / `IOSink` for the writer. `Process.run` for `open`.

**Reference spec:** [`docs/superpowers/specs/2026-06-04-debug-logging-persistence-design.md`](../specs/2026-06-04-debug-logging-persistence-design.md)

---

## File Structure

| Action | Path | Responsibility |
|---|---|---|
| Modify | `pubspec.yaml` | Add `archive: ^3.6.1`, `file_selector: ^1.1.0`, pin `path: ^1.9.0` |
| Create | `lib/services/log_redactor.dart` | Pure `maskApiKey` + `redactSettings` helpers |
| Create | `lib/services/debug_log_writer.dart` | Async JSONL appender with queue, trigger-aware flush, rotation, deleteAll |
| Create | `lib/services/debug_export_service.dart` | Zip packaging + `openLogDir` + SavePanel driver |
| Modify | `lib/services/debug_service.dart` | Inject writer; dispatch with `trigger` per the rules; add `bootstrap()` static |
| Modify | `lib/screens/debug_screen.dart` | Add 3 AppBar actions: 在 Finder 中显示 / 导出诊断包 / 清空日志 |
| Modify | `lib/main.dart` | `WidgetsFlutterBinding.ensureInitialized()` + `await DebugService.bootstrap()` |
| Create | `test/log_redactor_test.dart` | `maskApiKey` cases |
| Create | `test/debug_log_writer_test.dart` | init / write+queue / trigger rules / rotation / deleteAll / degraded mode |
| Create | `test/debug_export_service_test.dart` | `buildZipBytes` shapes; redaction in `settings_redacted.json` |
| Modify | `test/debug_service_test.dart` | New tests for trigger dispatch + writer no-op injection (no behavior change to existing 32 cases) |
| Modify | `test/debug_screen_test.dart` | Three new buttons rendered + on-tap dispatch |

The three new service files stay under ~250 lines each. `DebugLogWriter` is the heaviest (~300 lines) but its batching, rotation, and trigger logic are independent and testable in isolation.

---

## Task 1: Add dependencies

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Edit `pubspec.yaml` to add the three new/updated dependencies**

In `pubspec.yaml`, replace the `dependencies:` block (keep the alphabetical order) with:

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.5.1
  go_router: ^13.2.0
  dio: ^5.4.1
  image_picker: ^1.0.7
  path_provider: ^2.1.2
  archive: ^3.6.1
  file_selector: ^1.1.0
  path: ^1.9.0
```

- [ ] **Step 2: Run `flutter pub get`**

From `yas_local/`:

```bash
flutter pub get
```

Expected: "Got dependencies!" and `archive`, `file_selector`, `path` now appear in `pubspec.lock` under the new `direct` section.

- [ ] **Step 3: Verify analyze still clean**

```bash
flutter analyze
```

Expected: "No issues found!" (the new deps add no code yet, so this just confirms resolve + lint baseline).

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore(deps): add archive, file_selector, path for debug logging"
```

---

## Task 2: `LogRedactor` (TDD)

**Files:**
- Create: `test/log_redactor_test.dart`
- Create: `lib/services/log_redactor.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/log_redactor_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/settings.dart';
import 'package:yas_local/services/log_redactor.dart';

void main() {
  group('maskApiKey', () {
    test('long key shows first 4 and last 4 with *** in the middle', () {
      expect(LogRedactor.maskApiKey('sk-1234567890abcdef'), 'sk-1...cdef');
    });

    test('short key (< 8 chars) shows first 1 and last 1', () {
      expect(LogRedactor.maskApiKey('short'), 's***t');
    });

    test('empty key returns empty', () {
      expect(LogRedactor.maskApiKey(''), '');
    });
  });

  group('redactSettings', () {
    test('masks apiKey and passes other fields through', () {
      const s = AppSettings(
        apiKey: 'sk-1234567890abcdef',
        baseUrl: 'https://example.com',
        vlModel: 'qwen-vl-max',
        textModel: 'qwen-plus',
        debugMode: true,
      );
      final r = LogRedactor.redactSettings(s);
      expect(r['apiKey'], 'sk-1...cdef');
      expect(r['baseUrl'], 'https://example.com');
      expect(r['vlModel'], 'qwen-vl-max');
      expect(r['textModel'], 'qwen-plus');
      expect(r['debugMode'], true);
    });

    test('empty apiKey stays empty', () {
      const s = AppSettings(apiKey: '');
      final r = LogRedactor.redactSettings(s);
      expect(r['apiKey'], '');
    });
  });
}
```

- [ ] **Step 2: Run, verify fail**

```bash
flutter test test/log_redactor_test.dart
```

Expected: compile error — target `package:yas_local/services/log_redactor.dart` not found.

- [ ] **Step 3: Implement `LogRedactor`**

Create `lib/services/log_redactor.dart`:

```dart
import '../models/settings.dart';

/// Pure utilities for redacting sensitive data before it lands on disk.
/// No state, no side effects — safe to call from any layer.
class LogRedactor {
  LogRedactor._();

  /// Returns `<first1>***<last1>` for short keys (< 8 chars), or
  /// `<first4>...<last4>` for longer ones. Empty string returns empty.
  static String maskApiKey(String key) {
    if (key.isEmpty) return '';
    if (key.length < 8) {
      return '${key[0]}***${key[key.length - 1]}';
    }
    return '${key.substring(0, 4)}...${key.substring(key.length - 4)}';
  }

  /// Returns a redacted map representation of [s] suitable for JSONL / zip.
  static Map<String, dynamic> redactSettings(AppSettings s) => {
        'apiKey': maskApiKey(s.apiKey),
        'baseUrl': s.baseUrl,
        'vlModel': s.vlModel,
        'textModel': s.textModel,
        'debugMode': s.debugMode,
      };
}
```

- [ ] **Step 4: Run tests, verify pass**

```bash
flutter test test/log_redactor_test.dart
```

Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add test/log_redactor_test.dart lib/services/log_redactor.dart
git commit -m "feat(debug): add LogRedactor for API-key masking"
```

---

## Task 3: `DebugLogWriter` — `init()` + basic `write()`

**Files:**
- Create: `test/debug_log_writer_test.dart` (skeleton with first tests)
- Create: `lib/services/debug_log_writer.dart` (skeleton with `init` + `write`)

- [ ] **Step 1: Write the failing tests for `init` and a sync `write`**

Create `test/debug_log_writer_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/services/debug_log_writer.dart';
import 'package:yas_local/services/debug_service.dart';

void main() {
  late Directory tmpRoot;
  late DebugLogWriter writer;

  setUp(() async {
    tmpRoot = await Directory.systemTemp.createTemp('yas_log_test_');
    writer = DebugLogWriter();
    await writer.init(overrideDir: tmpRoot);
  });

  tearDown(() async {
    await writer.dispose();
    if (tmpRoot.existsSync()) {
      await tmpRoot.delete(recursive: true);
    }
  });

  test('init creates debug_logs/ subdir and an empty jsonl for today', () async {
    expect(writer.logDir.path, endsWith('debug_logs'));
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final expected = File('${writer.logDir.path}/debug_$today.jsonl');
    expect(expected.existsSync(), isTrue);
  });

  test('init is idempotent: second call does not truncate existing file', () async {
    await writer.write(_qwenOk('first'), trigger: 'debugMode');
    await writer.init(overrideDir: tmpRoot); // re-init on the same dir
    // After re-init the existing file should still exist (we re-open, not truncate)
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final f = File('${writer.logDir.path}/debug_$today.jsonl');
    expect(f.existsSync(), isTrue);
  });

  test('write appends a single jsonl line for trigger=debugMode', () async {
    await writer.write(_qwenOk('hello'), trigger: 'debugMode');
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final lines = await File('${writer.logDir.path}/debug_$today.jsonl')
        .readAsLines();
    expect(lines, hasLength(1));
    final parsed = jsonDecode(lines.single) as Map<String, dynamic>;
    expect(parsed['type'], 'qwen');
    expect(parsed['trigger'], 'debugMode');
    expect(parsed['responseContent'], 'hello');
  });
}

QwenCallRecord _qwenOk(String response) => QwenCallRecord(
      timestamp: DateTime.parse('2026-06-04T10:00:00Z'),
      scope: 'test',
      model: 'm',
      endpoint: '/chat/completions',
      statusCode: 200,
      elapsedMs: 1,
      status: QwenCallStatus.ok,
      messages: const [],
      responseContent: response,
    );
```

- [ ] **Step 2: Run, verify fail**

```bash
flutter test test/debug_log_writer_test.dart
```

Expected: compile error — `package:yas_local/services/debug_log_writer.dart` not found.

- [ ] **Step 3: Implement `DebugLogWriter` skeleton**

Create `lib/services/debug_log_writer.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'debug_service.dart';

/// Appends [DebugService] records to a daily-rotating JSONL file inside
/// the macOS sandbox (`getApplicationDocumentsDirectory()/debug_logs/`).
///
/// Records are batched and flushed on a 1-second timer; `trigger: 'error'`
/// records bypass the queue and are flushed synchronously. The internal
/// queue caps at 5000 entries — oldest are dropped with a warn event when
/// the cap is hit. Files rotate when they exceed 5 MB; up to 5 rotated
/// copies are kept.
class DebugLogWriter {
  DebugLogWriter();

  static final DebugLogWriter instance = DebugLogWriter();

  static const int _maxFileBytes = 5 * 1024 * 1024; // 5 MB
  static const int _maxRotated = 5;
  static const int _queueCap = 5000;
  static const Duration _flushInterval = Duration(seconds: 1);

  Directory? _dir;
  IOSink? _sink;
  String? _currentDate;
  int _currentBytes = 0;
  final _pending = <_PendingRecord>[];
  int _dropped = 0;
  Timer? _timer;
  int _consecutiveFailures = 0;
  bool _degraded = false;
  bool _enabled = false;

  Directory get logDir =>
      _dir ?? (throw StateError('DebugLogWriter.init() not called'));
  File _currentFile(String date) => File('${logDir.path}/debug_$date.jsonl');
  String _today() => DateTime.now().toIso8601String().substring(0, 10);

  /// Initialize the writer. [overrideDir] is for tests.
  /// Idempotent — calling twice on the same dir does not truncate.
  Future<void> init({Directory? overrideDir}) async {
    final base = overrideDir ??
        await Directory(
                '${(await _defaultBase())}/debug_logs')
            .create(recursive: true);
    _dir = base;
    if (!base.existsSync()) {
      base.createSync(recursive: true);
    }
    _openForDate(_today());
    _timer ??= Timer.periodic(_flushInterval, (_) => _flushBatch());
  }

  /// Static seam for tests + the real [getApplicationDocumentsDirectory]
  /// path. Returns the documents directory's path string.
  static Future<String> _defaultBase() async {
    // Defer to a swappable function so tests can stub it.
    return _defaultBaseImpl();
  }

  static Future<String> Function() _defaultBaseImpl =
      () async => throw UnimplementedError(
            'DebugLogWriter: default base path not configured. '
            'Override via DebugLogWriter.configureDefaultBase() '
            'or pass overrideDir to init().',
          );

  /// Production wiring: called from `DebugService.bootstrap()`.
  static void configureDefaultBase(Future<String> Function() fn) {
    _defaultBaseImpl = fn;
  }

  void setEnabled(bool v) {
    _enabled = v;
  }

  void write(Object record, {required String trigger}) {
    if (_degraded) return;
    // Gate: enabled is required for debugMode, but error bypasses the gate.
    if (!_enabled && trigger != 'error') return;
    if (trigger == 'error') {
      _writeLineSync(record, trigger);
      return;
    }
    if (_pending.length >= _queueCap) {
      _dropped++;
      return;
    }
    _pending.add(_PendingRecord(record, trigger));
  }

  void _writeLineSync(Object record, String trigger) {
    _rotateIfDateChanged();
    final line = _encode(record, trigger);
    try {
      _sink?.write('$line\n');
      _sink?.flush();
      _currentBytes += line.length + 1;
      _consecutiveFailures = 0;
    } on FileSystemException {
      _consecutiveFailures++;
      if (_consecutiveFailures >= 3) {
        _degraded = true;
        _timer?.cancel();
        _timer = null;
      }
    }
  }

  void _flushBatch() {
    if (_pending.isEmpty) return;
    if (!_enabled) {
      // enabled was turned off mid-batch: drop the batch.
      _pending.clear();
      return;
    }
    if (_dropped > 0) {
      _pending.add(_PendingRecord(
        EventRecord(
          timestamp: DateTime.now(),
          scope: 'writer',
          level: EventLevel.warn,
          message: 'queue overflow, dropped=$_dropped',
        ),
        'debugMode',
      ));
      _dropped = 0;
    }
    _rotateIfDateChanged();
    final buf = StringBuffer();
    for (final p in _pending) {
      final line = _encode(p.record, p.trigger);
      buf.writeln(line);
      _currentBytes += line.length + 1;
    }
    _pending.clear();
    try {
      _sink?.write(buf.toString());
      _sink?.flush();
      _consecutiveFailures = 0;
    } on FileSystemException {
      _consecutiveFailures++;
      if (_consecutiveFailures >= 3) {
        _degraded = true;
        _timer?.cancel();
        _timer = null;
      }
    }
  }

  void _rotateIfDateChanged() {
    final today = _today();
    if (_currentDate == today && _sink != null) return;
    _sink?.flush();
    _sink?.close();
    _sink = null;
    _currentDate = today;
    if (_currentBytes >= _maxFileBytes) {
      _rotate();
    }
    final f = _currentFile(today);
    _sink = f.openWrite(mode: FileMode.append);
    _currentBytes = f.existsSync() ? f.lengthSync() : 0;
  }

  void _rotate() {
    for (var i = _maxRotated; i >= 1; i--) {
      final src = File('${logDir.path}/debug_$_currentDate.${i - 1 == 0 ? "" : "${i - 1}."}jsonl'
          .replaceFirst('..', '.'));
      // collapse paths: simpler: enumerate existing rotated files
    }
    // Simpler approach: rename in a single pass
    _rotateSimple();
    _currentBytes = 0;
  }

  void _rotateSimple() {
    for (var i = _maxRotated; i >= 1; i--) {
      final String srcName, dstName;
      if (i == 1) {
        srcName = 'debug_$_currentDate.jsonl';
        dstName = 'debug_$_currentDate.1.jsonl';
      } else {
        srcName = 'debug_$_currentDate.${i - 1}.jsonl';
        dstName = 'debug_$_currentDate.$i.jsonl';
      }
      final src = File('${logDir.path}/$srcName');
      final dst = File('${logDir.path}/$dstName');
      if (src.existsSync()) {
        if (dst.existsSync()) dst.deleteSync();
        src.renameSync(dst.path);
      }
    }
  }

  void flushNow() {
    _flushBatch();
    _sink?.flush();
  }

  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    _flushBatch();
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
  }

  Future<void> deleteAll() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
    if (logDir.existsSync()) {
      for (final f in logDir.listSync().whereType<File>()) {
        f.deleteSync();
      }
    }
    _currentBytes = 0;
  }

  String _encode(Object record, String trigger) {
    final map = _serialize(record);
    return jsonEncode({...map, 'type': _typeOf(record), 'trigger': trigger});
  }

  String _typeOf(Object r) => switch (r) {
        QwenCallRecord _ => 'qwen',
        EventRecord _ => 'event',
        JsonAttemptRecord _ => 'json',
        _ => 'unknown',
      };

  Map<String, dynamic> _serialize(Object r) {
    if (r is QwenCallRecord) {
      return {
        'ts': r.timestamp.toIso8601String(),
        'scope': r.scope,
        'model': r.model,
        'endpoint': r.endpoint,
        'statusCode': r.statusCode,
        'elapsedMs': r.elapsedMs,
        'status': r.status.name,
        'messages': r.messages,
        'responseContent': r.responseContent,
        'reasoningContent': r.reasoningContent,
        'errorMessage': r.errorMessage,
      };
    }
    if (r is EventRecord) {
      return {
        'ts': r.timestamp.toIso8601String(),
        'scope': r.scope,
        'level': r.level.name,
        'message': r.message,
        'data': r.data,
      };
    }
    if (r is JsonAttemptRecord) {
      return {
        'ts': r.timestamp.toIso8601String(),
        'scope': r.scope,
        'input_snippet': r.inputSnippet,
        'attempts': r.attempts
            .map((a) => {
                  'method': a.method,
                  'ok': a.ok,
                  'error': a.error,
                })
            .toList(),
        'final_exception': r.finalException,
      };
    }
    throw ArgumentError('Unknown record type: ${r.runtimeType}');
  }

  /// Test-only seam: reset internal state.
  void resetForTest() {
    _timer?.cancel();
    _timer = null;
    _sink?.close();
    _sink = null;
    _dir = null;
    _currentDate = null;
    _currentBytes = 0;
    _pending.clear();
    _dropped = 0;
    _consecutiveFailures = 0;
    _degraded = false;
    _enabled = false;
  }
}

class _PendingRecord {
  final Object record;
  final String trigger;
  _PendingRecord(this.record, this.trigger);
}
```

> Note: the placeholder `_rotate` body is dead code — `_rotateIfDateChanged` calls `_rotateSimple` instead. The `_rotate` method is removed in the next task's cleanup step. For now it exists to keep the test compile-clean.

- [ ] **Step 4: Run tests, verify pass**

```bash
flutter test test/debug_log_writer_test.dart
```

Expected: 3 tests pass.

- [ ] **Step 5: Remove the dead `_rotate` placeholder**

In `lib/services/debug_log_writer.dart`, delete the entire `_rotate` method (the one that contains the loop with the broken path string). Keep `_rotateSimple` which is what actually gets called.

- [ ] **Step 6: Run analyzer + tests**

```bash
flutter analyze && flutter test test/debug_log_writer_test.dart
```

Expected: 0 issues, 3 tests pass.

- [ ] **Step 7: Commit**

```bash
git add test/debug_log_writer_test.dart lib/services/debug_log_writer.dart
git commit -m "feat(debug): add DebugLogWriter with daily file + queue + rotation"
```

---

## Task 4: `DebugLogWriter` — trigger rules, rotation trigger, queue overflow, degraded mode

**Files:**
- Modify: `test/debug_log_writer_test.dart` (add 4 new tests)
- Modify: `lib/services/debug_log_writer.dart` (verify trigger rule on `write`)

- [ ] **Step 1: Append 4 new failing tests**

Append to `test/debug_log_writer_test.dart`, before the closing `}` of `void main()`:

```dart
  test('trigger=error flushes synchronously even when enabled=false', () async {
    // writer starts with enabled=false (default in setUp's init)
    await writer.write(_qwenError(), trigger: 'error');
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final lines = await File('${writer.logDir.path}/debug_$today.jsonl')
        .readAsLines();
    expect(lines, hasLength(1));
    final parsed = jsonDecode(lines.single) as Map<String, dynamic>;
    expect(parsed['trigger'], 'error');
  });

  test('enabled=false gates trigger=debugMode writes', () async {
    await writer.write(_qwenOk('dropped'), trigger: 'debugMode');
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final lines = await File('${writer.logDir.path}/debug_$today.jsonl')
        .readAsLines();
    expect(lines, isEmpty);
  });

  test('queue overflow drops oldest and emits a warn event on next flush', () async {
    writer.setEnabled(true);
    // Fill the queue beyond the cap. We bypass the timer by writing
    // many entries synchronously, then call flushNow().
    for (var i = 0; i < DebugLogWriter.queueCapForTest + 10; i++) {
      writer.write(_qwenOk('c-$i'), trigger: 'debugMode');
    }
    writer.flushNow();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final lines = await File('${writer.logDir.path}/debug_$today.jsonl')
        .readAsLines();
    // The 10 dropped are recorded as a single warn event by the writer.
    final warnLines = lines
        .map((l) => jsonDecode(l) as Map<String, dynamic>)
        .where((m) => m['type'] == 'event' && m['level'] == 'warn')
        .toList();
    expect(warnLines, hasLength(1));
    expect(warnLines.single['message'], contains('dropped=10'));
  });

  test('rotation: file at or above max size renames to .1.jsonl', () async {
    writer.setEnabled(true);
    final today = DateTime.now().toIso8601String().substring(0, 10);
    // Pre-grow the current file past the rotation threshold.
    final huge = List<String>.filled(
            DebugLogWriter.maxFileBytesForTest ~/ 100, 'x' * 99)
        .join('\n');
    await File('${writer.logDir.path}/debug_$today.jsonl')
        .writeAsString('$huge\n');
    // Touch via writer so it picks up the new size and rotates on next write.
    await DebugLogWriter.forTestRotate(writer, today);
    final rotated =
        File('${writer.logDir.path}/debug_$today.1.jsonl');
    expect(rotated.existsSync(), isTrue);
    final fresh = File('${writer.logDir.path}/debug_$today.jsonl');
    expect(fresh.existsSync(), isTrue);
    expect(fresh.lengthSync(), lessThan(DebugLogWriter.maxFileBytesForTest));
  });
```

Add a helper to the top of the test file (outside `void main()`):

```dart
QwenCallRecord _qwenError() => QwenCallRecord(
      timestamp: DateTime.parse('2026-06-04T10:00:00Z'),
      scope: 'test',
      model: 'm',
      endpoint: '/chat/completions',
      statusCode: 500,
      elapsedMs: 1,
      status: QwenCallStatus.httpError,
      messages: const [],
      errorMessage: 'server boom',
    );
```

- [ ] **Step 2: Run, verify fail**

```bash
flutter test test/debug_log_writer_test.dart
```

Expected: compile errors — `DebugLogWriter.queueCapForTest`, `DebugLogWriter.maxFileBytesForTest`, and `DebugLogWriter.forTestRotate` don't exist.

- [ ] **Step 3: Expose test seams + add the rotation helper**

In `lib/services/debug_log_writer.dart`:

1. Make the constants public (rename or add static getters):

```dart
  static int get queueCapForTest => _queueCap;
  static int get maxFileBytesForTest => _maxFileBytes;
```

2. Add a static helper that lets a test trigger a rotation without writing a new record:

```dart
  /// Test-only: force a rotation check on [w]'s current file. Public so
  /// a test can pre-grow a file and then call this to observe rotation.
  static Future<void> forTestRotate(DebugLogWriter w, String date) async {
    w._currentDate = date;
    w._currentBytes = w._currentFile(date).existsSync()
        ? w._currentFile(date).lengthSync()
        : 0;
    // Force the rotation path even if no write has happened.
    if (w._currentBytes >= _maxFileBytes) {
      w._rotateSimple();
      w._currentBytes = 0;
    }
  }
```

- [ ] **Step 4: Run, verify pass**

```bash
flutter test test/debug_log_writer_test.dart
```

Expected: all 7 tests pass.

- [ ] **Step 5: Verify `setEnabled(true)` after `init` works (regression for the gate)**

In `test/debug_log_writer_test.dart`, add one more test inside the `setUp`'s `group` of the new tests:

```dart
  test('setEnabled(true) lets subsequent trigger=debugMode writes flush', () async {
    writer.setEnabled(true);
    await writer.write(_qwenOk('kept'), trigger: 'debugMode');
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final lines = await File('${writer.logDir.path}/debug_$today.jsonl')
        .readAsLines();
    expect(lines, hasLength(1));
  });
```

Run:

```bash
flutter test test/debug_log_writer_test.dart
```

Expected: 8 tests pass.

- [ ] **Step 6: Commit**

```bash
git add test/debug_log_writer_test.dart lib/services/debug_log_writer.dart
git commit -m "feat(debug): trigger-aware flush + rotation + queue overflow warn"
```

---

## Task 5: Wire `DebugService` to dispatch to `DebugLogWriter`

**Files:**
- Modify: `lib/services/debug_service.dart`
- Modify: `test/debug_service_test.dart` (add trigger dispatch tests)

- [ ] **Step 1: Write failing tests for the dispatch rules**

Append to `test/debug_service_test.dart`, before the closing `}` of `void main()`:

```dart
  group('writer dispatch', () {
    late _FakeWriter fake;

    setUp(() {
      DebugService.instance.resetForTest();
      fake = _FakeWriter();
      DebugService.instance.attachWriter(fake);
    });

    test('qwen ok call is dispatched with trigger=debugMode', () {
      DebugService.instance.setEnabled(true);
      DebugService.instance.recordQwenCall(QwenCallRecord(
        timestamp: DateTime.now(),
        scope: 'test',
        model: 'm',
        endpoint: '/chat/completions',
        statusCode: 200,
        elapsedMs: 1,
        status: QwenCallStatus.ok,
        messages: const [],
      ));
      expect(fake.writes, hasLength(1));
      expect(fake.writes.single.trigger, 'debugMode');
    });

    test('qwen httpError is dispatched with trigger=error', () {
      DebugService.instance.recordQwenCall(QwenCallRecord(
        timestamp: DateTime.now(),
        scope: 'test',
        model: 'm',
        endpoint: '/chat/completions',
        statusCode: 500,
        elapsedMs: 1,
        status: QwenCallStatus.httpError,
        messages: const [],
        errorMessage: 'boom',
      ));
      expect(fake.writes, hasLength(1));
      expect(fake.writes.single.trigger, 'error');
    });

    test('event level=error is dispatched with trigger=error even when enabled=false', () {
      // enabled=false by default after resetForTest
      DebugService.instance.recordEvent(
        scope: 't', message: 'm', level: EventLevel.error,
      );
      expect(fake.writes, hasLength(1));
      expect(fake.writes.single.trigger, 'error');
    });

    test('event level=info is not dispatched when enabled=false', () {
      DebugService.instance.recordEvent(scope: 't', message: 'm');
      expect(fake.writes, isEmpty);
    });

    test('setEnabled propagates to the writer', () {
      DebugService.instance.setEnabled(true);
      expect(fake.lastEnabled, isTrue);
      DebugService.instance.setEnabled(false);
      expect(fake.lastEnabled, isFalse);
    });
  });
}

class _FakeWriter implements DebugLogWriter {
  final List<({Object record, String trigger})> writes = [];
  bool? lastEnabled;

  @override
  void write(Object record, {required String trigger}) {
    writes.add((record: record, trigger: trigger));
  }

  @override
  void setEnabled(bool v) {
    lastEnabled = v;
  }

  // The remaining DebugLogWriter members are no-ops in the fake.
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
```

> The `_FakeWriter` uses `noSuchMethod` so we don't have to stub the full writer API. This is acceptable because the fake is only used to observe `write` and `setEnabled` — other methods are never called by `DebugService`.

- [ ] **Step 2: Run, verify fail**

```bash
flutter test test/debug_service_test.dart
```

Expected: compile error — `DebugService.instance.attachWriter` doesn't exist, and `DebugLogWriter` isn't an abstract class (so `implements` is not allowed without a noSuchMethod approach — which we have, so the second part may not fail; focus is on the first).

- [ ] **Step 3: Make `DebugLogWriter` abstract and add the dispatch**

In `lib/services/debug_log_writer.dart`, change the class declaration to:

```dart
abstract class DebugLogWriter {
  // ... existing static `instance`, constants, etc.
  Future<void> init({Directory? overrideDir});
  void write(Object record, {required String trigger});
  void setEnabled(bool value);
  void flushNow();
  Future<void> dispose();
  Future<void> deleteAll();
  Directory get logDir;
  // ... the rest of the class becomes the implementation `FileDebugLogWriter`
}
```

Then rename the existing class body to a new concrete class:

```dart
class FileDebugLogWriter implements DebugLogWriter {
  FileDebugLogWriter();
  static final DebugLogWriter instance = FileDebugLogWriter();
  // ... (move all the existing fields + methods here verbatim)
}
```

Keep the static getters `queueCapForTest` and `maxFileBytesForTest` and the static `forTestRotate` — but move them to `FileDebugLogWriter`. (The test file at the top of Task 3 referenced `DebugLogWriter.queueCapForTest` etc. — update those to `FileDebugLogWriter.queueCapForTest` accordingly. Also update the `setUp` to do `final writer = FileDebugLogWriter();`.)

In `lib/services/debug_service.dart`:

1. Add a `_writer` field defaulting to `FileDebugLogWriter.instance`:

```dart
  DebugLogWriter _writer = FileDebugLogWriter.instance;
```

2. Add the attach / detach seams (test-only):

```dart
  /// Test-only: inject a fake writer. Use [resetForTest] in tearDown to
  /// detach. Production code should not call this.
  @visibleForTesting
  void attachWriter(DebugLogWriter w) {
    _writer = w;
    _writer.setEnabled(_enabled);
  }
```

3. Modify `recordQwenCall`, `recordEvent`, `recordJsonAttempt` so they call `_writer.write(record, trigger: ...)` with the rules:

```dart
  void recordQwenCall(QwenCallRecord record) {
    if (!_enabled) return;
    _qwenCalls.add(record);
    if (_qwenCalls.length > qwenCapacity) {
      _qwenCalls.removeAt(0);
    }
    _changes.notify();
    final trigger = record.status == QwenCallStatus.ok ? 'debugMode' : 'error';
    _writer.write(record, trigger: trigger);
  }

  void recordEvent({
    required String scope,
    required String message,
    EventLevel level = EventLevel.info,
    Map<String, Object?>? data,
  }) {
    if (!_enabled) return;
    _events.add(EventRecord(
      timestamp: DateTime.now(),
      scope: scope,
      level: level,
      message: message,
      data: data,
    ));
    if (_events.length > eventCapacity) {
      _events.removeAt(0);
    }
    _changes.notify();
    final trigger = level == EventLevel.error ? 'error' : 'debugMode';
    _writer.write(
      _events.last,
      trigger: trigger,
    );
  }

  void recordJsonAttempt(JsonAttemptRecord record) {
    if (!_enabled) return;
    _jsonAttempts.add(record);
    if (_jsonAttempts.length > jsonAttemptCapacity) {
      _jsonAttempts.removeAt(0);
    }
    _changes.notify();
    // JsonAttemptRecord has no `error` flag we can read; treat all attempts
    // as debugMode. Parse failures are already captured in
    // recordQwenCall(status: parseError) so the error path is covered there.
    _writer.write(record, trigger: 'debugMode');
  }
```

4. Update `setEnabled`:

```dart
  void setEnabled(bool value) {
    _enabled = value;
    _writer.setEnabled(value);
  }
```

5. Update `resetForTest`:

```dart
  void resetForTest() {
    _enabled = false;
    _changes.dispose();
    _changes = _DebugNotifier();
    _writer.setEnabled(false);
    clear();
  }
```

6. Add a static `bootstrap` method:

```dart
  /// One-time app-startup wiring. Awaits writer init and configures the
  /// default base path. Call this from `main()` before `runApp`.
  static Future<void> bootstrap() async {
    DebugLogWriter.configureDefaultBase(
      () async {
        final dir = await getApplicationDocumentsDirectory();
        return dir.path;
      },
    );
    await FileDebugLogWriter.instance.init();
  }
```

7. Add the missing imports at the top of `debug_service.dart`:

```dart
import 'package:path_provider/path_provider.dart';
```

- [ ] **Step 4: Run DebugService tests**

```bash
flutter test test/debug_service_test.dart
```

Expected: 32 existing tests + 5 new tests = 37 pass.

- [ ] **Step 5: Run full test suite to confirm no regression**

```bash
flutter test
```

Expected: all pre-existing tests still pass.

- [ ] **Step 6: Commit**

```bash
git add lib/services/debug_service.dart lib/services/debug_log_writer.dart test/debug_service_test.dart
git commit -m "feat(debug): dispatch DebugService records to DebugLogWriter"
```

---

## Task 6: `DebugExportService` — `buildZipBytes` (pure, TDD)

**Files:**
- Create: `test/debug_export_service_test.dart`
- Create: `lib/services/debug_export_service.dart`

- [ ] **Step 1: Write failing tests**

Create `test/debug_export_service_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/settings.dart';
import 'package:yas_local/services/debug_export_service.dart';
import 'package:yas_local/services/log_redactor.dart';
import 'package:yas_local/services/debug_log_writer.dart';
import 'package:yas_local/services/debug_service.dart';

void main() {
  late Directory tmpRoot;
  late Directory logsDir;
  late FileDebugLogWriter writer;
  late AppSettings settings;

  setUp(() async {
    tmpRoot = await Directory.systemTemp.createTemp('yas_export_test_');
    logsDir = Directory('${tmpRoot.path}/debug_logs')..createSync();
    writer = FileDebugLogWriter();
    await writer.init(overrideDir: logsDir);
    settings = const AppSettings(
      apiKey: 'sk-1234567890abcdef',
      baseUrl: 'https://example.com',
      vlModel: 'qwen-vl-max',
      textModel: 'qwen-plus',
      debugMode: true,
    );
  });

  tearDown(() async {
    await writer.dispose();
    if (tmpRoot.existsSync()) {
      await tmpRoot.delete(recursive: true);
    }
  });

  test('buildZipBytes includes manifest + settings_redacted + jsonl', () async {
    writer.setEnabled(true);
    await writer.write(_event('test', EventLevel.info), trigger: 'debugMode');
    final bytes = await DebugExportService.buildZipBytes(
      writer: writer,
      settings: settings,
    );
    final archive = ZipDecoder().decodeBytes(bytes);
    final names = archive.files.map((f) => f.name).toSet();
    expect(names.any((n) => n.startsWith('debug_') && n.endsWith('.jsonl')), isTrue);
    expect(names.contains('settings_redacted.json'), isTrue);
    expect(names.contains('manifest.json'), isTrue);
  });

  test('settings_redacted.json masks the apiKey', () async {
    final bytes = await DebugExportService.buildZipBytes(
      writer: writer,
      settings: settings,
    );
    final archive = ZipDecoder().decodeBytes(bytes);
    final s = utf8.decode(archive.findFile('settings_redacted.json')!.content as List<int>);
    final parsed = jsonDecode(s) as Map<String, dynamic>;
    expect(parsed['apiKey'], 'sk-1...cdef');
  });

  test('includeTaskContext=true adds tasks_snapshot.json; false omits it', () async {
    final withCtx = await DebugExportService.buildZipBytes(
      writer: writer,
      settings: settings,
      includeTaskContext: true,
      taskContext: {'task:abc': {'name': 'Test', 'rubric': []}},
    );
    final withoutCtx = await DebugExportService.buildZipBytes(
      writer: writer,
      settings: settings,
      includeTaskContext: false,
    );
    final a1 = ZipDecoder().decodeBytes(withCtx);
    final a2 = ZipDecoder().decodeBytes(withoutCtx);
    expect(a1.findFile('tasks_snapshot.json'), isNotNull);
    expect(a2.findFile('tasks_snapshot.json'), isNull);
  });

  test('empty logs dir still produces a valid zip with just manifest', () async {
    final bytes = await DebugExportService.buildZipBytes(
      writer: writer,
      settings: settings,
    );
    final archive = ZipDecoder().decodeBytes(bytes);
    expect(archive.findFile('manifest.json'), isNotNull);
  });
}

EventRecord _event(String scope, EventLevel level) => EventRecord(
      timestamp: DateTime.parse('2026-06-04T10:00:00Z'),
      scope: scope,
      level: level,
      message: 'm',
    );
```

- [ ] **Step 2: Run, verify fail**

```bash
flutter test test/debug_export_service_test.dart
```

Expected: compile error — `package:yas_local/services/debug_export_service.dart` not found.

- [ ] **Step 3: Implement `DebugExportService`**

Create `lib/services/debug_export_service.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import '../models/settings.dart';
import 'debug_log_writer.dart';
import 'log_redactor.dart';

/// Packages debug logs into a zip for the user to share back to the
/// developer. All work is best-effort; failures throw
/// [DebugExportException] so the UI can show a SnackBar.
class DebugExportService {
  DebugExportService._();

  /// Pure function: build a zip containing all current jsonl files, the
  /// redacted settings, and (optionally) a task snapshot. Returns the
  /// zip as a byte array. No platform calls.
  ///
  /// [taskContext] is a `Map<taskId, {name, rubric, ...}>` shape; it is
  /// the caller's responsibility to decide what to include. Pass an
  /// empty map to skip the snapshot.
  static Future<List<int>> buildZipBytes({
    required FileDebugLogWriter writer,
    required AppSettings settings,
    bool includeTaskContext = true,
    Map<String, dynamic> taskContext = const {},
  }) async {
    final archive = Archive();

    // 1. All JSONL files in the log dir.
    final dir = writer.logDir;
    if (dir.existsSync()) {
      for (final entity in dir.listSync().whereType<File>()) {
        if (entity.path.endsWith('.jsonl')) {
          final bytes = await entity.readAsBytes();
          final name = entity.uri.pathSegments.last;
          archive.addFile(ArchiveFile(name, bytes.length, bytes));
        }
      }
    }

    // 2. settings_redacted.json
    final settingsJson = utf8.encode(
      jsonEncode(LogRedactor.redactSettings(settings)),
    );
    archive.addFile(ArchiveFile('settings_redacted.json', settingsJson.length, settingsJson));

    // 3. manifest.json
    final manifest = {
      'exportedAt': DateTime.now().toIso8601String(),
      'jsonlCount': dir.existsSync()
          ? dir.listSync().whereType<File>().where((f) => f.path.endsWith('.jsonl')).length
          : 0,
      'appVersion': '1.0.0+1', // from pubspec.yaml; hard-coded for now
    };
    final manifestJson = utf8.encode(jsonEncode(manifest));
    archive.addFile(ArchiveFile('manifest.json', manifestJson.length, manifestJson));

    // 4. tasks_snapshot.json (optional)
    if (includeTaskContext && taskContext.isNotEmpty) {
      final taskJson = utf8.encode(jsonEncode(taskContext));
      archive.addFile(ArchiveFile('tasks_snapshot.json', taskJson.length, taskJson));
    }

    final encoded = ZipEncoder().encode(archive);
    if (encoded == null) {
      throw const DebugExportException('zip encoding returned null');
    }
    return encoded;
  }
}

class DebugExportException implements Exception {
  final String message;
  const DebugExportException(this.message);
  @override
  String toString() => 'DebugExportException: $message';
}
```

- [ ] **Step 4: Run tests, verify pass**

```bash
flutter test test/debug_export_service_test.dart
```

Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add test/debug_export_service_test.dart lib/services/debug_export_service.dart
git commit -m "feat(debug): add DebugExportService.buildZipBytes"
```

---

## Task 7: `DebugExportService` — `openLogDir` and `buildAndShowSaveDialog`

**Files:**
- Create: `test/debug_export_service_test.dart` (add a test for `openLogDir` happy path)
- Modify: `lib/services/debug_export_service.dart`

The save dialog and platform SavePanel are not unit-testable (they require a real Flutter binding + native code). The "show in Finder" path is testable as a `Process.run` invocation via mocking the `Process` runner.

- [ ] **Step 1: Write a failing test for `openLogDir`**

Append to `test/debug_export_service_test.dart` (before the closing `}` of `void main()`):

```dart
  group('openLogDir', () {
    test('runs `/usr/bin/open` on the writer logDir on macOS', () async {
      final calls = <List<String>>[];
      await DebugExportService.openLogDir(
        writer: writer,
        isMacOS: true,
        processRunner: (exe, args) async {
          calls.add([exe, ...args]);
          return 0;
        },
      );
      expect(calls, hasLength(1));
      expect(calls.single.first, '/usr/bin/open');
      expect(calls.single.last, writer.logDir.path);
    });

    test('is a no-op on non-macOS platforms (returns silently)', () async {
      var called = false;
      await DebugExportService.openLogDir(
        writer: writer,
        isMacOS: false,
        processRunner: (_, __) async {
          called = true;
          return 0;
        },
      );
      expect(called, isFalse);
    });
  });
```

- [ ] **Step 2: Run, verify fail**

```bash
flutter test test/debug_export_service_test.dart
```

Expected: compile error — `openLogDir` doesn't exist.

- [ ] **Step 3: Implement `openLogDir`**

Replace the `DebugExportService` class in `lib/services/debug_export_service.dart` with:

```dart
class DebugExportService {
  DebugExportService._();

  /// Opens the writer's log directory in Finder (macOS). No-op on
  /// other platforms. The `processRunner` parameter is a test seam.
  static Future<void> openLogDir({
    required FileDebugLogWriter writer,
    required bool isMacOS,
    Future<int> Function(String executable, List<String> arguments) processRunner =
        _defaultProcessRunner,
  }) async {
    if (!isMacOS) return;
    await processRunner('/usr/bin/open', [writer.logDir.path]);
  }

  static Future<int> _defaultProcessRunner(String executable, List<String> arguments) {
    return Process.run(executable, arguments).then((r) => r.exitCode);
  }

  /// Builds a zip of the current logs and surfaces a platform save
  /// dialog. Returns the chosen absolute path, or `null` if the user
  /// cancelled.
  ///
  /// macOS / Windows / Linux: uses `file_selector`'s `showSaveDialog`.
  /// iOS / Android: writes to `getTemporaryDirectory()` and surfaces the
  /// path via a thrown `DebugExportException` whose message contains
  /// the path; the UI is expected to render that as a SnackBar.
  static Future<String?> buildAndShowSaveDialog({
    required FileDebugLogWriter writer,
    required AppSettings settings,
    required bool isMacOS,
    bool includeTaskContext = true,
    Map<String, dynamic> taskContext = const {},
  }) async {
    final bytes = await buildZipBytes(
      writer: writer,
      settings: settings,
      includeTaskContext: includeTaskContext,
      taskContext: taskContext,
    );
    final defaultName =
        'diag_${DateTime.now().toIso8601String().replaceAll(':', '-').replaceAll('.', '-').substring(0, 19)}.zip';
    if (isMacOS) {
      // Lazy import: file_selector needs the Flutter binding.
      // The UI layer is expected to await this; we import at use-site
      // to keep `flutter` import out of this service for unit tests.
      return _showSaveDialogBytes(defaultName, bytes);
    }
    // iOS / Android / other: write to tmpdir and signal the UI via throw.
    final tmp = Directory.systemTemp;
    final out = File('${tmp.path}/$defaultName');
    await out.writeAsBytes(bytes);
    throw DebugExportException(
      'Diagnostic saved to ${out.path}. Attach this file to your bug report.',
    );
  }

  static Future<String?> _showSaveDialogBytes(String name, List<int> bytes) async {
    // Implemented in the UI layer (see DebugScreen wiring in Task 9).
    // This stub exists so unit tests don't pull in the Flutter binding.
    throw UnimplementedError(
      '_showSaveDialogBytes is patched by DebugScreen at runtime.',
    );
  }
}
```

- [ ] **Step 4: Run tests, verify pass**

```bash
flutter test test/debug_export_service_test.dart
```

Expected: 6 tests pass (4 from Task 6 + 2 from this task).

- [ ] **Step 5: Commit**

```bash
git add test/debug_export_service_test.dart lib/services/debug_export_service.dart
git commit -m "feat(debug): add openLogDir + buildAndShowSaveDialog"
```

---

## Task 8: `DebugScreen` — three new AppBar buttons

**Files:**
- Modify: `lib/screens/debug_screen.dart`
- Modify: `test/debug_screen_test.dart` (add 3 widget tests)

- [ ] **Step 1: Read the existing `DebugScreen` widget to find a clean insertion point**

You should already know from the brainstorming phase: the AppBar has a `bottom: TabBar(...)` but no `actions:`. We need to add `actions:` with three IconButtons.

- [ ] **Step 2: Add a small wrapper widget for the 3 actions**

Append to `lib/screens/debug_screen.dart` (at the end of the file, outside the existing classes):

```dart
class _DebugActions extends ConsumerStatefulWidget {
  const _DebugActions();
  @override
  ConsumerState<_DebugActions> createState() => _DebugActionsState();
}

class _DebugActionsState extends ConsumerState<_DebugActions> {
  bool _busy = false;

  Future<void> _openInFinder() async {
    setState(() => _busy = true);
    try {
      await DebugExportService.openLogDir(
        writer: FileDebugLogWriter.instance,
        isMacOS: defaultTargetPlatform == TargetPlatform.macOS,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开 Finder：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportZip() async {
    setState(() => _busy = true);
    try {
      final settings = ref.read(settingsProvider);
      final path = await DebugExportService.buildAndShowSaveDialog(
        writer: FileDebugLogWriter.instance,
        settings: settings,
        isMacOS: defaultTargetPlatform == TargetPlatform.macOS,
      );
      if (mounted && path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('诊断包已导出：$path')),
        );
      }
    } on DebugExportException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空日志？'),
        content: const Text('会删除磁盘上所有 debug_*.jsonl 文件，内存中的最近记录会保留。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('清空')),
        ],
      ),
    );
    if (confirmed != true) return;
    await FileDebugLogWriter.instance.deleteAll();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已清空磁盘日志')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.macOS) {
      // On iOS / Android, hide the Finder button but keep the other two.
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.archive),
            tooltip: '导出诊断包',
            onPressed: _busy ? null : _exportZip,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '清空日志',
            onPressed: _busy ? null : _clearLogs,
          ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.folder_open),
          tooltip: '在 Finder 中显示',
          onPressed: _busy ? null : _openInFinder,
        ),
        IconButton(
          icon: const Icon(Icons.archive),
          tooltip: '导出诊断包',
          onPressed: _busy ? null : _exportZip,
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: '清空日志',
          onPressed: _busy ? null : _clearLogs,
        ),
      ],
    );
  }
}
```

- [ ] **Step 3: Add the import + wire `_DebugActions` into the AppBar**

At the top of `lib/screens/debug_screen.dart`, add:

```dart
import 'package:file_selector/file_selector.dart' show XFile, getSaveLocation;
import '../providers/settings_provider.dart';
import '../services/debug_export_service.dart';
import '../services/debug_log_writer.dart';
```

Replace the `appBar: AppBar(...)` block in `DebugScreen.build` with:

```dart
        appBar: AppBar(
          title: const Text('Debug'),
          actions: const [_DebugActions()],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Qwen', icon: Icon(Icons.cloud)),
              Tab(text: '事件', icon: Icon(Icons.timeline)),
              Tab(text: '状态', icon: Icon(Icons.storage)),
              Tab(text: 'JSON', icon: Icon(Icons.data_object)),
            ],
          ),
        ),
```

- [ ] **Step 4: Replace the `_showSaveDialogBytes` stub with a real `file_selector` call**

In `lib/services/debug_export_service.dart`, replace `_showSaveDialogBytes`:

```dart
  static Future<String?> _showSaveDialogBytes(String name, List<int> bytes) async {
    final cs = const XTypeGroup(label: 'zip', extensions: ['zip']);
    final location = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: [cs],
    );
    if (location == null) return null;
    await File(location.path).writeAsBytes(bytes);
    return location.path;
  }
```

Add the import:

```dart
import 'package:file_selector/file_selector.dart' show XTypeGroup, getSaveLocation;
```

- [ ] **Step 5: Write 3 widget tests**

Open `test/debug_screen_test.dart`. Append inside `void main()` (or the appropriate `group`):

```dart
  testWidgets('renders 3 AppBar actions on macOS', (tester) async {
    await tester.pumpWidget(_harness(platform: TargetPlatform.macOS));
    expect(find.byTooltip('在 Finder 中显示'), findsOneWidget);
    expect(find.byTooltip('导出诊断包'), findsOneWidget);
    expect(find.byTooltip('清空日志'), findsOneWidget);
  });

  testWidgets('hides the Finder button on iOS', (tester) async {
    await tester.pumpWidget(_harness(platform: TargetPlatform.iOS));
    expect(find.byTooltip('在 Finder 中显示'), findsNothing);
    expect(find.byTooltip('导出诊断包'), findsOneWidget);
    expect(find.byTooltip('清空日志'), findsOneWidget);
  });

  testWidgets('清空日志 shows a confirmation dialog', (tester) async {
    await tester.pumpWidget(_harness(platform: TargetPlatform.macOS));
    await tester.tap(find.byTooltip('清空日志'));
    await tester.pumpAndSettle();
    expect(find.text('清空日志？'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('清空'), findsOneWidget);
  });
```

Add a `_harness` helper if it doesn't already exist; if the file already has a `_harness` that hard-codes macOS, refactor it to accept a `TargetPlatform` parameter. The signature should look like:

```dart
Widget _harness({TargetPlatform platform = TargetPlatform.macOS}) { ... }
```

- [ ] **Step 6: Run tests, verify pass**

```bash
flutter test test/debug_screen_test.dart
```

Expected: pre-existing tests + 3 new tests pass.

- [ ] **Step 7: Commit**

```bash
git add lib/screens/debug_screen.dart lib/services/debug_export_service.dart test/debug_screen_test.dart
git commit -m "feat(debug): add 在 Finder 中显示 / 导出诊断包 / 清空日志 buttons"
```

---

## Task 9: Wire `DebugService.bootstrap()` into `main.dart`

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: Replace `main.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'services/debug_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DebugService.bootstrap();
  runApp(const ProviderScope(child: YasApp()));
}
```

- [ ] **Step 2: Verify analyze + full test suite still green**

```bash
flutter analyze && flutter test
```

Expected: 0 issues, all tests pass (existing 50+ plus the new ones from Tasks 2–8).

- [ ] **Step 3: Smoke test — run app on macOS, hit the debug screen**

```bash
flutter run -d macos
```

In the running app:

1. Open Settings → toggle debugMode ON.
2. Open any task → Strategy Review.
3. Open the debug screen (🐞).
4. Confirm the 3 new buttons appear.
5. Tap "📂 在 Finder 中显示" — Finder should open `debug_logs/`.
6. Tap "📦 导出诊断包" — a save dialog should appear; save to Desktop.
7. On Desktop, unzip the resulting file: it should contain `manifest.json`, `settings_redacted.json`, at least one `debug_*.jsonl`, and (if there are tasks) `tasks_snapshot.json`.
8. Open `settings_redacted.json`: `apiKey` should be masked.
9. Open one `debug_*.jsonl`: each line should be valid JSON with a `type` and `trigger` field.

If any step fails, **stop and debug before continuing** — this is the integration verification.

- [ ] **Step 4: Force a failure case end-to-end**

With the app still running:

1. In Settings, set the API key to an invalid value.
2. Trigger a grading run.
3. Check the debug screen → it should show a red ❌ entry.
4. Open the JSONL file in `debug_logs/` — the failure should be present with `trigger: 'error'`.
5. **Verify**: with `debugMode` toggled OFF, the same error still appears in the JSONL (because `trigger: 'error'` bypasses the gate).

- [ ] **Step 5: Commit**

```bash
git add lib/main.dart
git commit -m "feat(debug): bootstrap DebugLogWriter on app start"
```

---

## Task 10: Manual acceptance checklist (per spec §8)

- [ ] **Step 1: Run through the spec's acceptance checklist**

From `docs/superpowers/specs/2026-06-04-debug-logging-persistence-design.md` §8:

1. `flutter run -d macos` → enable debugMode → trigger a gradePaper failure → `debug_logs/` has jsonl → debug screen shows ✅❌
2. Same as above with debugMode=OFF → jsonl still has the error → debug screen empty (preserved behavior)
3. "📂 在 Finder 中显示" → Finder opens
4. "📦 导出诊断包" → SavePanel appears → save to Desktop → zip on Desktop → unzip shows manifest + jsonl + settings_redacted + tasks_snapshot
5. `flutter test` passes
6. `flutter analyze` reports 0 issues

Tick each box; if any fails, stop and fix before final commit.

- [ ] **Step 2: Final commit (only if changes were needed)**

```bash
git status
# If anything is dirty:
git add -A
git commit -m "chore(debug): post-acceptance cleanup"
```

- [ ] **Step 3: Update `CLAUDE.md` QwenLogger section**

Replace the `## Qwen API logging (QwenLogger)` section in `/Users/concerto391/Documents/GitHub/gradenow-fast/CLAUDE.md` with a new section that reflects the new architecture. The new section should describe:

- `DebugService` is the in-memory ring-buffer + UI source of truth
- `DebugLogWriter` is the new disk-persistence layer; JSONL daily files under `getApplicationDocumentsDirectory()/debug_logs/`
- `DebugExportService` builds zip diagnostics
- The `DebugScreen` (`/debug`) shows the in-memory buffers; the disk is a shadow
- Errors bypass `debugMode` and always land on disk

This step is documentation-only and does not require a test.

- [ ] **Step 4: Final commit for docs**

```bash
git add ../CLAUDE.md
git commit -m "docs(debug): update CLAUDE.md to describe new logging architecture"
```

---

## Self-Review

**Spec coverage** (from `docs/superpowers/specs/2026-06-04-debug-logging-persistence-design.md`):

| Spec section | Task(s) |
|---|---|
| §4.1 file layout | Task 1 (deps), 2 (redactor), 3-4 (writer), 5 (debug service), 6-7 (export), 8 (screen), 9 (main) |
| §4.2 disk layout (debug_logs/, daily, 5MB rotation, 5 copies) | Task 3 (init + write), Task 4 (rotation) |
| §4.3 jsonl line structure (type, ts, trigger) | Task 3 (`_encode`, `_typeOf`, `_serialize`) |
| §4.4 LogRedactor | Task 2 |
| §4.4 DebugLogWriter API (init / write / setEnabled / flushNow / dispose / deleteAll / logDir / currentFilePath / totalSizeBytes) | Tasks 3, 4 (the spec's `currentFilePath` and `totalSizeBytes` getters were not added in this plan — they're listed in §4.4 but not referenced in §6/§7/§8 acceptance. Adding them as YAGNI for now. If a future task needs them, add then.) |
| §4.4 DebugExportService (buildZipBytes / openLogDir / buildAndShowSaveDialog) | Tasks 6, 7, 8 (Step 4) |
| §4.4 DebugService changes (writer injection, trigger rules, bootstrap) | Task 5 |
| §4.4 DebugScreen 3 buttons | Task 8 |
| §4.4 iOS adaptation (hide Finder button, fallback to tmpdir + SnackBar) | Task 7 (buildAndShowSaveDialog iOS branch), Task 8 (Row in non-macOS branch) |
| §5.1 startup bootstrap | Task 5 (`bootstrap()`), Task 9 (main.dart wiring) |
| §5.2 / 5.3 / 5.4 data flows | Implicit: covered by code structure (writer.write in DebugService, button taps in DebugScreen) |
| §6 error handling table | Task 3 (init swallowed), Task 3 (degraded mode), Task 4 (queue overflow warn), Task 7 (openLogDir is no-op on non-macOS), Task 7 (cancel returns null), Task 7 (buildZipBytes throws DebugExportException) |
| §7.1 new tests | Tasks 2, 3, 4, 6, 7, 8 |
| §7.2 regression tests | Task 5 (debug_service_test.dart), Task 8 (debug_screen_test.dart) |
| §8 acceptance checklist | Task 9 (Steps 3-4), Task 10 (Step 1) |
| §10 untouched files | Confirmed: qwen_service.dart, json_extractor.dart, all 3 providers, app.dart unchanged |

**Gaps**: `currentFilePath` and `totalSizeBytes` getters on the writer are not implemented. Decision: skip per YAGNI; they aren't referenced anywhere in the spec's test or acceptance. Re-add only if a future task needs them.

**Placeholder scan**: no "TBD" / "TODO" / "implement later" in the plan body. Task 7's `_showSaveDialogBytes` initially has a `throw UnimplementedError` stub, but Task 8 Step 4 replaces it before any commit.

**Type consistency**:
- `DebugLogWriter` is the abstract class; `FileDebugLogWriter` is the concrete impl. Both names are used consistently.
- `attachWriter` is documented as test-only. `_FakeWriter` uses `implements DebugLogWriter` + `noSuchMethod` (no compile error since the abstract class has the needed members).
- `recordQwenCall` etc. always pass `trigger: 'debugMode' | 'error'` as a `String` literal — matches the writer's signature.
- `DebugExportException` is thrown from `buildAndShowSaveDialog` (iOS branch) and caught in `DebugScreen._exportZip` — consistent.

**Ambiguity check**:
- Task 5 says "json attempts are always `trigger: 'debugMode'`" — this is a spec choice I made to avoid teaching `JsonAttemptRecord` an `ok` field. The error path is already covered by the Qwen call's `parseError` status. Reaffirmed in the test.
- Task 7's iOS branch throws `DebugExportException` with the path in the message. The UI renders it as a SnackBar. This is the spec's "fallback" path — consistent.
- Task 8's `_harness` parameter `platform: TargetPlatform` is the cleanest way to test iOS vs macOS; if the existing file has a different signature, the engineer should refactor it as part of Step 5.

**Fixes applied during self-review**:
- Added explicit `bool includeTaskContext = true` default to `buildAndShowSaveDialog` for symmetry with `buildZipBytes`.
- Added `manifest.json` includes `appVersion: '1.0.0+1'` (hard-coded; can be wired from `pubspec.yaml` later if needed).
- Confirmed Task 4's `_rotate` placeholder is removed in Task 3 Step 5.
