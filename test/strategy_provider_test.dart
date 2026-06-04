import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/checkpoint.dart';
import 'package:yas_local/models/reference_answer.dart';
import 'package:yas_local/models/rubric.dart';
import 'package:yas_local/models/settings.dart';
import 'package:yas_local/models/task.dart';
import 'package:yas_local/providers/settings_provider.dart';
import 'package:yas_local/providers/strategy_provider.dart';
import 'package:yas_local/providers/task_provider.dart';
import 'package:yas_local/services/qwen_service.dart';

GradingTask _taskWithRubric(List<RubricItem> rubric) => GradingTask(
      id: 't1',
      name: 't1',
      subject: 'math',
      createdAt: DateTime(2026, 1, 1),
      rubric: rubric,
      questionPaperPaths: const [],
    );

class _FakeTaskNotifier extends TaskNotifier {
  _FakeTaskNotifier(super.ref, this._task);
  final GradingTask _task;
  @override
  GradingTask? taskById(String id) => _task;
}

class _ThrowingQwenService extends QwenService {
  _ThrowingQwenService() : super(const AppSettings(apiKey: 'k'));
  @override
  Future<ReferenceAnswer> generateStrategy({
    required RubricItem rubricItem,
    required List<String> questionPaperPaths,
    required List<String> answerImagePaths,
    int totalQuestions = 0,
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

class _FakeConfiguredSettingsNotifier extends SettingsNotifier {
  _FakeConfiguredSettingsNotifier() {
    state = const AppSettings(apiKey: 'k');
  }
}

ProviderContainer _container(GradingTask task) {
  return ProviderContainer(overrides: [
    taskProvider.overrideWith((ref) => _FakeTaskNotifier(ref, task)),
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The real TaskNotifier constructor calls _load() which calls TaskStore.load()
  // which uses path_provider. In a unit test the platform channel is missing,
  // so we mock it with a writable temp dir.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => '/tmp',
  );

  group('StrategyNotifier mutators', () {
    late ProviderContainer container;
    late StrategyNotifier notifier;
    late GradingTask task;

    setUp(() {
      task = _taskWithRubric(const [
        RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 5),
      ]);
      container = _container(task);
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
}
