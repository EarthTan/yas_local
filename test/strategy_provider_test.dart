import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/checkpoint.dart';
import 'package:yas_local/models/reference_answer.dart';
import 'package:yas_local/models/rubric.dart';
import 'package:yas_local/models/task.dart';
import 'package:yas_local/providers/strategy_provider.dart';
import 'package:yas_local/providers/task_provider.dart';

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
}
