import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:yas_local/models/checkpoint.dart';
import 'package:yas_local/models/reference_answer.dart';
import 'package:yas_local/models/rubric.dart';
import 'package:yas_local/models/settings.dart';
import 'package:yas_local/models/strategy_message.dart';
import 'package:yas_local/models/task.dart';
import 'package:yas_local/providers/settings_provider.dart';
import 'package:yas_local/providers/strategy_provider.dart';
import 'package:yas_local/providers/task_provider.dart';
import 'package:yas_local/services/qwen_service.dart';

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

/// In-memory path provider so `path_provider` calls resolve to a temp dir
/// without needing a real platform channel. Used by the debounce persistence
/// test.
class _MemoryPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _MemoryPathProvider(this.dir);
  final Directory dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir.path;
  @override
  Future<String?> getApplicationSupportPath() async => dir.path;
}

/// Builds a [ReferenceAnswer] for whatever question the caller asked about,
/// and a no-op `refineStrategy` so the notifier can be constructed in tests
/// that don't actually exercise the VLM. Used by the debounce test.
class _StubQwen extends QwenService {
  _StubQwen() : super(const AppSettings(apiKey: 'k'));
  @override
  Future<ReferenceAnswer> generateStrategy({
    required RubricItem rubricItem,
    required List<String> questionPaperPaths,
    required List<String> answerImagePaths,
    int totalQuestions = 0,
    void Function(int attempt)? onAttempt,
  }) async =>
      ReferenceAnswer(questionNumber: rubricItem.questionNumber, checkpoints: const []);
  @override
  Future<ReferenceAnswer> refineStrategy({
    required RubricItem rubric,
    required ReferenceAnswer current,
    required List<StrategyMessage> chatHistory,
    required String userMessage,
  }) async =>
      current;
}

/// Builds a [GradingTask] with the given rubric. Used across all groups.
GradingTask _taskWithRubric(List<RubricItem> rubric) => GradingTask(
      id: 't1',
      name: 't1',
      subject: 'math',
      createdAt: DateTime(2026, 1, 1),
      rubric: rubric,
      questionPaperPaths: const [],
    );

/// [TaskNotifier] stand-in for the mutator / retry tests. Overrides
/// `taskById` to return a fixed task so we don't need to persist one.
class _FakeTaskNotifier extends TaskNotifier {
  _FakeTaskNotifier(super.ref, this._task);
  final GradingTask _task;
  @override
  GradingTask? taskById(String id) => _task;
}

/// Throws on every `generateStrategy` call. Used by the retry-failure test.
class _ThrowingQwenService extends QwenService {
  _ThrowingQwenService() : super(const AppSettings(apiKey: 'k'));
  @override
  Future<ReferenceAnswer> generateStrategy({
    required RubricItem rubricItem,
    required List<String> questionPaperPaths,
    required List<String> answerImagePaths,
    int totalQuestions = 0,
    void Function(int attempt)? onAttempt,
  }) async {
    throw Exception('boom');
  }
}

/// Returns a successful [ReferenceAnswer] for whatever question the caller
/// asked about. Used to verify that `retryGenerate` replaces the existing
/// entry in place rather than appending a new one.
class _FakeSuccessfulQwenService extends QwenService {
  _FakeSuccessfulQwenService() : super(const AppSettings(apiKey: 'k'));
  @override
  Future<ReferenceAnswer> generateStrategy({
    required RubricItem rubricItem,
    required List<String> questionPaperPaths,
    required List<String> answerImagePaths,
    int totalQuestions = 0,
    void Function(int attempt)? onAttempt,
  }) async {
    return ReferenceAnswer(
      questionNumber: rubricItem.questionNumber,
      checkpoints: [
        CheckpointDef(
          id: 'q${rubricItem.questionNumber}-cp0',
          description: '重试生成的 checkpoint',
          points: 5,
        ),
      ],
      hasConsensus: true,
    );
  }
}

class _FakeUnconfiguredSettingsNotifier extends SettingsNotifier {
  _FakeUnconfiguredSettingsNotifier() {
    state = const AppSettings();
  }
}

/// Qwen stub whose `refineStrategy` waits on a static Completer until the
/// test calls [release]. Used by the dispose-mid-flight test to park the
/// notifier on a known await point.
class _HangingQwenService extends QwenService {
  _HangingQwenService() : super(const AppSettings(apiKey: 'k'));

  static final _gate = Completer<ReferenceAnswer>();

  static void release() {
    if (!_gate.isCompleted) {
      _gate.complete(ReferenceAnswer(
        questionNumber: 1,
        checkpoints: const [CheckpointDef(id: 'cp1', description: 'd', points: 2)],
      ));
    }
  }

  @override
  Future<ReferenceAnswer> refineStrategy({
    required RubricItem rubric,
    required ReferenceAnswer current,
    required List<StrategyMessage> chatHistory,
    required String userMessage,
  }) =>
      _gate.future;
}

class _FakeConfiguredSettingsNotifier extends SettingsNotifier {
  _FakeConfiguredSettingsNotifier() {
    state = const AppSettings(apiKey: 'k');
  }
}

/// Container wired up with a real [TaskNotifier] and a stub Qwen factory.
/// Used by the debounce test, which needs the real persistence path.
ProviderContainer _container({required Directory tmp}) {
  final c = ProviderContainer(overrides: [
    settingsProvider.overrideWith((ref) {
      final n = SettingsNotifier();
      n.state = const AppSettings(apiKey: 'k');
      return n;
    }),
    taskProvider.overrideWith((ref) => TaskNotifier(ref)),
    qwenFactoryProvider.overrideWithValue((ref) => _StubQwen()),
  ]);
  c.read(taskProvider.notifier);
  addTearDown(c.dispose);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('strategy_');
    // Used by the debounce test (real ReferenceStore) AND by the
    // mutator/retry tests (real TaskNotifier._load → TaskStore.load).
    PathProviderPlatform.instance = _MemoryPathProvider(tmp);
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  // -------------------------------------------------------------------------
  // Mutator behavior tests (C-4 critical coverage)
  // -------------------------------------------------------------------------
  group('StrategyNotifier mutators', () {
    late ProviderContainer container;
    late StrategyNotifier notifier;
    late GradingTask task;
    late ProviderSubscription<StrategyState> sub;

    setUp(() {
      task = _taskWithRubric(const [
        RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 5),
      ]);
      container = ProviderContainer(overrides: [
        taskProvider.overrideWith((ref) => _FakeTaskNotifier(ref, task)),
      ]);
      // strategyProvider is autoDispose — without an active listener the
      // notifier would be disposed before the 500ms debounce timer fires.
      sub = container.listen(strategyProvider, (prev, next) {});
      notifier = container.read(strategyProvider.notifier);
      // Seed with one reference that has 2 checkpoints
      notifier.state = StrategyState(
        references: [
          ReferenceAnswer(
            questionNumber: 1,
            checkpoints: const [
              CheckpointDef(id: 'q1-cp0', description: 'A', points: 2),
              CheckpointDef(id: 'q1-cp1', description: 'B', points: 3),
            ],
          ),
        ],
      );
    });

    tearDown(() async {
      // Drain pending microtasks so the fake's _load() Future (started in
      // the parent's constructor) and any chained loads complete before we
      // dispose the container.
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      // Mutators schedule a 500ms debounced save via Timer. Wait it out so
      // the timer fires while the notifier is still mounted (otherwise
      // `state` writes after dispose throw under `asserts`).
      await Future<void>.delayed(const Duration(milliseconds: 600));
      sub.close();
      container.dispose();
    });

    test('editCheckpoint 替换指定 id 的 description 与 points', () {
      notifier.editCheckpoint(1, 'q1-cp0',
          description: 'A 改', points: 4);
      final cp0 = notifier.state.references.single.checkpoints[0];
      final cp1 = notifier.state.references.single.checkpoints[1];
      expect(cp0.description, 'A 改');
      expect(cp0.points, 4);
      expect(cp1.description, 'B'); // untouched
      expect(cp1.points, 3);
    });

    test('addCheckpoint 追加一个带 id 的 checkpoint', () {
      final before = notifier.state.references.single.checkpoints.length;
      notifier.addCheckpoint(1, description: 'C', points: 1);
      final after = notifier.state.references.single.checkpoints;
      expect(after.length, before + 1);
      expect(after.last.description, 'C');
      expect(after.last.points, 1);
      expect(after.last.id, isNotEmpty);
    });

    test('removeCheckpoint 按 id 删除', () {
      notifier.removeCheckpoint(1, 'q1-cp0');
      final after = notifier.state.references.single.checkpoints;
      expect(after.length, 1);
      expect(after.single.id, 'q1-cp1');
    });
  });

  // -------------------------------------------------------------------------
  // retryGenerate behavior tests (C-4 critical coverage)
  // -------------------------------------------------------------------------
  group('StrategyNotifier retryGenerate', () {
    Future<void> drainAndDispose(ProviderContainer container) async {
      // Drain pending microtasks so the SettingsNotifier's _load() Future
      // (started in the parent's constructor) completes before we dispose.
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      container.dispose();
    }

    test('未配置 settings 时写入 state.error 且不动 references', () {
      final task = _taskWithRubric(const [
        RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 5),
      ]);
      final container = ProviderContainer(overrides: [
        taskProvider.overrideWith((ref) => _FakeTaskNotifier(ref, task)),
        settingsProvider.overrideWith((ref) => _FakeUnconfiguredSettingsNotifier()),
      ]);
      addTearDown(() => drainAndDispose(container));
      final notifier = container.read(strategyProvider.notifier);
      notifier.state = const StrategyState();

      notifier.retryGenerate('t1', 1);

      expect(notifier.state.error, contains('未配置'));
    });

    test('重试失败时 state.error 被设置、refining 清空', () async {
      final task = _taskWithRubric(const [
        RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 5),
      ]);
      final container = ProviderContainer(overrides: [
        taskProvider.overrideWith((ref) => _FakeTaskNotifier(ref, task)),
        qwenFactoryProvider.overrideWithValue((ref) => _ThrowingQwenService()),
      ]);
      addTearDown(() => drainAndDispose(container));
      final notifier = container.read(strategyProvider.notifier);
      notifier.state = StrategyState(
        references: [
          ReferenceAnswer(questionNumber: 1, checkpoints: const [], hasConsensus: false),
        ],
      );

      await notifier.retryGenerate('t1', 1);

      expect(notifier.state.refining, false);
      expect(notifier.state.refiningQuestion, isNull);
      expect(notifier.state.error, isNotNull);
    });

    test('重试成功且全部题都恢复时 state.error 被清空（PR review #3 修复）', () async {
      // 模拟：3 题中第 2 题原本失败（state.error 非空），用户点重试后
      // 第 2 题恢复成功。期望 state.error 被清空，否则底部橙色
      // "部分题目生成失败…" banner 会一直挂着。
      final task = _taskWithRubric(const [
        RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 5),
        RubricItem(questionNumber: 2, type: 'subjective', maxPoints: 5),
        RubricItem(questionNumber: 3, type: 'subjective', maxPoints: 5),
      ]);
      final container = ProviderContainer(overrides: [
        taskProvider.overrideWith((ref) => _FakeTaskNotifier(ref, task)),
        settingsProvider.overrideWith((ref) => _FakeConfiguredSettingsNotifier()),
        qwenFactoryProvider.overrideWithValue((ref) => _FakeSuccessfulQwenService()),
      ]);
      addTearDown(() => drainAndDispose(container));
      final notifier = container.read(strategyProvider.notifier);
      notifier.state = StrategyState(
        error: '部分题目生成失败',
        references: [
          ReferenceAnswer(
            questionNumber: 1,
            checkpoints: const [CheckpointDef(id: 'q1-cp0', description: 'A', points: 5)],
          ),
          const ReferenceAnswer(
            questionNumber: 2,
            checkpoints: [],
            hasConsensus: false,
          ),
          ReferenceAnswer(
            questionNumber: 3,
            checkpoints: const [CheckpointDef(id: 'q3-cp0', description: 'C', points: 5)],
          ),
        ],
      );
      expect(notifier.state.error, '部分题目生成失败');

      await notifier.retryGenerate('t1', 2);

      // 关键断言：error 被清空。
      expect(notifier.state.error, isNull);
      // 仍然没有失败题（兜底断言）。
      expect(notifier.state.references.any((r) => r.checkpoints.isEmpty), false);
    });

    test('重试成功但仍有其它失败题时 state.error 保留', () async {
      // 3 题中第 1、2 题都失败（state.error 非空），用户点重试第 2 题
      // 并成功。期望 state.error 仍保留，因为第 1 题还在失败。
      final task = _taskWithRubric(const [
        RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 5),
        RubricItem(questionNumber: 2, type: 'subjective', maxPoints: 5),
        RubricItem(questionNumber: 3, type: 'subjective', maxPoints: 5),
      ]);
      final container = ProviderContainer(overrides: [
        taskProvider.overrideWith((ref) => _FakeTaskNotifier(ref, task)),
        settingsProvider.overrideWith((ref) => _FakeConfiguredSettingsNotifier()),
        qwenFactoryProvider.overrideWithValue((ref) => _FakeSuccessfulQwenService()),
      ]);
      addTearDown(() => drainAndDispose(container));
      final notifier = container.read(strategyProvider.notifier);
      notifier.state = StrategyState(
        error: '部分题目生成失败',
        references: [
          const ReferenceAnswer(questionNumber: 1, checkpoints: [], hasConsensus: false),
          const ReferenceAnswer(questionNumber: 2, checkpoints: [], hasConsensus: false),
          ReferenceAnswer(
            questionNumber: 3,
            checkpoints: const [CheckpointDef(id: 'q3-cp0', description: 'C', points: 5)],
          ),
        ],
      );

      await notifier.retryGenerate('t1', 2);

      // error 必须保留：第 1 题还在失败。
      expect(notifier.state.error, '部分题目生成失败');
      expect(notifier.state.references[0].checkpoints, isEmpty);
      expect(notifier.state.references[1].checkpoints, isNotEmpty);
    });

    test('重试成功时 references 长度保持不变，失败项被替换为新结果', () async {
      // 3 题 rubric：第 1 题成功、第 2 题失败、第 3 题成功。
      // 模拟用户对失败的第 2 题点「重试此题」，
      // 期望 references 长度仍为 3，且第 2 题的 checkpoints 被填上。
      final task = _taskWithRubric(const [
        RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 5),
        RubricItem(questionNumber: 2, type: 'subjective', maxPoints: 5),
        RubricItem(questionNumber: 3, type: 'subjective', maxPoints: 5),
      ]);
      final container = ProviderContainer(overrides: [
        taskProvider.overrideWith((ref) => _FakeTaskNotifier(ref, task)),
        settingsProvider.overrideWith((ref) => _FakeConfiguredSettingsNotifier()),
        qwenFactoryProvider.overrideWithValue((ref) => _FakeSuccessfulQwenService()),
      ]);
      addTearDown(() => drainAndDispose(container));
      final notifier = container.read(strategyProvider.notifier);
      notifier.state = StrategyState(
        references: [
          ReferenceAnswer(
            questionNumber: 1,
            checkpoints: const [
              CheckpointDef(id: 'q1-cp0', description: 'A', points: 5),
            ],
          ),
          // 第 2 题 _generate 失败：checkpoints 为空。
          const ReferenceAnswer(
            questionNumber: 2,
            checkpoints: [],
            hasConsensus: false,
          ),
          ReferenceAnswer(
            questionNumber: 3,
            checkpoints: const [
              CheckpointDef(id: 'q3-cp0', description: 'C', points: 5),
            ],
          ),
        ],
      );

      // 重试前：长度 3，第 2 题 checkpoints 为空。
      expect(notifier.state.references.length, 3);
      expect(notifier.state.references[1].checkpoints, isEmpty);

      await notifier.retryGenerate('t1', 2);

      // 关键断言：长度仍为 3，**不是 4**。
      expect(notifier.state.references.length, 3,
          reason: 'retryGenerate 不应向列表追加新条目');
      // 第 2 题被成功的新结果替换。
      expect(notifier.state.references[1].questionNumber, 2);
      expect(notifier.state.references[1].checkpoints, isNotEmpty);
      // 其它两题保持原样。
      expect(notifier.state.references[0].questionNumber, 1);
      expect(notifier.state.references[0].checkpoints.single.description, 'A');
      expect(notifier.state.references[2].questionNumber, 3);
      expect(notifier.state.references[2].checkpoints.single.description, 'C');
    });
  });

  // -------------------------------------------------------------------------
  // Debounced persistence (added in 33db26e / c4a)
  // -------------------------------------------------------------------------
  group('StrategyNotifier debounced save', () {
    test('editCheckpoint schedules a debounced save (500ms)', () async {
      final c = _container(tmp: tmp);
      // Keep the autoDispose strategyProvider alive for the duration of the
      // test. Without an active listener, `c.read(strategyProvider.notifier)`
      // would not pin the notifier and it would be disposed before our
      // awaited `n.load()` completes.
      final sub = c.listen(strategyProvider, (prev, next) {});
      addTearDown(sub.close);
      final n = c.read(strategyProvider.notifier);
      // Seed an in-memory reference so editCheckpoint has something to edit.
      final task = GradingTask(
        id: 't1', name: 'T1', subject: 'math', createdAt: DateTime(2026),
        rubric: const [RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 5)],
        questionPaperPaths: const [],
      );
      await c.read(taskProvider.notifier).addTask(task);
      // Seed by writing reference_t1.json directly so load() picks it up.
      final cacheFile = File('${tmp.path}/reference_t1.json');
      await cacheFile.writeAsString(jsonEncode([
        {
          'questionNumber': 1,
          'checkpoints': [
            {'id': 'cp1', 'description': 'd', 'points': 2}
          ],
          'equivalentForms': <String>[],
          'hasConsensus': true,
          'confirmed': false,
          'chatHistory': <Map<String, dynamic>>[],
        }
      ]));
      await n.load('t1');
      // Delete the seeded file so we can assert that editCheckpoint re-creates
      // it (after the debounce window) rather than just leaving it alone.
      await cacheFile.delete();
      n.editCheckpoint(1, 'cp1', description: 'updated');
      // Within 500ms, the save should NOT have happened.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final cacheFile2 = File('${tmp.path}/reference_t1.json');
      expect(await cacheFile2.exists(), isFalse, reason: 'debounce should delay save');
      // After 500ms+, the save should have happened.
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(await cacheFile2.exists(), isTrue);
    });

    test('sendMessage is no-op if notifier is disposed mid-flight', () async {
      // Build a container similar to the one above, but this time we'll
      // dispose it while sendMessage is awaiting the VLM. With the token
      // guard (c4c) the in-flight call must not throw
      // "StateNotifier used after dispose" — it should silently bail.
      final task = _taskWithRubric(const [
        RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 5),
      ]);
      final c = ProviderContainer(overrides: [
        settingsProvider.overrideWith((ref) => _FakeConfiguredSettingsNotifier()),
        taskProvider.overrideWith((ref) => _FakeTaskNotifier(ref, task)),
        // _StubQwen.refineStrategy returns immediately (no await chain),
        // so we use a Completer-based stub that only completes when we
        // tell it to — this lets us deterministically dispose *while* the
        // notifier is mid-flight.
        qwenFactoryProvider.overrideWithValue((ref) => _HangingQwenService()),
      ]);
      // Pin strategyProvider so autoDispose doesn't kick in while we
      // arrange the mid-flight dispose.
      final sub = c.listen(strategyProvider, (prev, next) {});
      // Drain TaskNotifier._load() (started in the constructor) BEFORE we
      // kick off sendMessage. Otherwise the load's post-await state write
      // races with our dispose and throws a different StateError that
      // masks the bug under test. 10 drains is generous for the file I/O
      // chain inside TaskStore.load().
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      addTearDown(() {
        _HangingQwenService.release();
        sub.close();
        c.dispose();
      });
      final n = c.read(strategyProvider.notifier);
      // Seed a reference so sendMessage can find it.
      final ref = ReferenceAnswer(
        questionNumber: 1,
        checkpoints: [const CheckpointDef(id: 'cp1', description: 'd', points: 2)],
      );
      n.state = StrategyState(references: [ref]);
      // Kick off sendMessage but dispose the container mid-flight so the
      // token is bumped.
      final fut = n.sendMessage('t1', 1, 'hi');
      // Yield several times so sendMessage has captured its `myToken` and
      // is now parked on the Completer inside _HangingQwenService.
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      c.dispose();
      // Now release the hanging Qwen so the post-await state write runs.
      _HangingQwenService.release();
      // The sendMessage should complete without throwing "used after dispose".
      await fut;
      // No assertion needed beyond "no throw". If the bug were present, the
      // call would throw StateError.
    });

    test('flushPendingSave persists immediately (no debounce wait)', () async {
      final c = _container(tmp: tmp);
      // Keep strategyProvider pinned even after we drop autoDispose, so the
      // test is robust to either provider lifecycle.
      final sub = c.listen(strategyProvider, (prev, next) {});
      addTearDown(sub.close);
      final n = c.read(strategyProvider.notifier);
      await n.load('t1');
      final ref = ReferenceAnswer(
        questionNumber: 1,
        checkpoints: [const CheckpointDef(id: 'cp1', description: 'd', points: 2)],
      );
      c.read(strategyProvider.notifier).state = StrategyState(references: [ref]);
      n.editCheckpoint(1, 'cp1', description: 'updated');
      // Within 500ms, file should NOT yet exist.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final cacheFile = File('${tmp.path}/reference_t1.json');
      expect(await cacheFile.exists(), isFalse);
      // flushPendingSave writes immediately.
      n.flushPendingSave();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await cacheFile.exists(), isTrue);
    });

    test('sendMessage schedules a debounced save (500ms)', () async {
      // Build a container that uses a *fake* configured SettingsNotifier
      // (the real one's `_load()` would overwrite our apiKey with the empty
      // on-disk value) and a fake TaskNotifier (avoids awaiting addTask
      // which would let SettingsNotifier._load() complete and overwrite
      // the apiKey).
      final task = _taskWithRubric(const [
        RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 5),
      ]);
      final c = ProviderContainer(overrides: [
        settingsProvider.overrideWith((ref) => _FakeConfiguredSettingsNotifier()),
        taskProvider.overrideWith((ref) => _FakeTaskNotifier(ref, task)),
        qwenFactoryProvider.overrideWithValue((ref) => _StubQwen()),
      ]);
      // Keep the autoDispose strategyProvider alive for the test.
      final sub = c.listen(strategyProvider, (prev, next) {});
      addTearDown(() async {
        // Drain pending microtasks + wait out the 500ms debounce so the
        // timer fires before dispose.
        for (var i = 0; i < 5; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        await Future<void>.delayed(const Duration(milliseconds: 600));
        sub.close();
        c.dispose();
      });
      final n = c.read(strategyProvider.notifier);
      // Seed the reference directly. We do NOT call n.load('t1') or
      // addTask(...) here because any await would let
      // SettingsNotifier._load() complete and overwrite our configured
      // apiKey with the empty on-disk value.
      final ref = ReferenceAnswer(
        questionNumber: 1,
        checkpoints: [const CheckpointDef(id: 'cp1', description: 'd', points: 2)],
      );
      n.state = StrategyState(references: [ref]);
      await n.sendMessage('t1', 1, '请更严格');
      await Future<void>.delayed(const Duration(milliseconds: 600));
      final cacheFile = File('${tmp.path}/reference_t1.json');
      expect(await cacheFile.exists(), isTrue);
      // The cache file should contain the chat history (assistant response
      // from _StubQwen.refineStrategy returns the same ref, but the notifier
      // appends an assistant message).
      final raw = await cacheFile.readAsString();
      expect(raw.contains('已更新批改策略'), isTrue);
    });

    test('saveAllConfirmed flushes any pending debounced save', () async {
      final c = _container(tmp: tmp);
      final n = c.read(strategyProvider.notifier);
      await n.load('t1');
      final ref = ReferenceAnswer(
        questionNumber: 1,
        checkpoints: [const CheckpointDef(id: 'cp1', description: 'd', points: 2)],
      );
      c.read(strategyProvider.notifier).state = StrategyState(references: [ref]);
      // Trigger a debounced save.
      n.editCheckpoint(1, 'cp1', description: 'updated');
      // Immediately call saveAllConfirmed (within the 500ms debounce window).
      await n.saveAllConfirmed('t1');
      // After 600ms (past the debounce), the file should still exist
      // (proving the immediate write happened) and NOT have been
      // rewritten again (proving the pending timer was cancelled).
      await Future<void>.delayed(const Duration(milliseconds: 600));
      final cacheFile = File('${tmp.path}/reference_t1.json');
      expect(await cacheFile.exists(), isTrue);
      // The post-edit state should be on disk.
      final raw = await cacheFile.readAsString();
      expect(raw.contains('updated'), isTrue);
    });
  });
}

