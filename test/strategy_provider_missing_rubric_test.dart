import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/reference_answer.dart';
import 'package:yas_local/models/rubric.dart';
import 'package:yas_local/models/task.dart';
import 'package:yas_local/providers/strategy_provider.dart';
import 'package:yas_local/providers/task_provider.dart';
import 'package:yas_local/services/reference_store.dart';

GradingTask _taskWithRubric(List<RubricItem> rubric) => GradingTask(
      id: 't1',
      name: 'T1',
      subject: 'math',
      createdAt: DateTime(2026),
      rubric: rubric,
      questionPaperPaths: const [],
      answerImagePaths: const [],
    );

class _FakeTaskNotifier extends TaskNotifier {
  _FakeTaskNotifier(super.ref, this._task);
  final GradingTask _task;
  @override
  GradingTask? taskById(String id) => _task.id == id ? _task : null;
}

/// Drains in-flight ReferenceStore work, then disposes the container.
Future<void> _drainAndDispose(ProviderContainer container) async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  container.dispose();
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

  setUp(() {
    ReferenceStore.resetForTest();
  });

  test(
    'load() tags a cached reference whose question is missing from rubric',
    () async {
      final task = _taskWithRubric(const [
        RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 10),
      ]);
      final container = ProviderContainer(overrides: [
        taskProvider.overrideWith((ref) => _FakeTaskNotifier(ref, task)),
      ]);
      addTearDown(() => _drainAndDispose(container));

      // Keep the strategyProvider alive across awaits — it's autoDispose, so
      // a long enough await between `read(notifier)` and `load()`'s
      // completion would let the provider tear down before state is set.
      final sub = container.listen(strategyProvider, (_, _) {});
      addTearDown(sub.close);

      // Seed the on-disk cache with an orphan reference (questionNumber 5
      // is not in the rubric, which only has question 1).
      await ReferenceStore.save('t1', const [
        ReferenceAnswer(
          questionNumber: 5,
          checkpoints: [],
        ),
      ]);

      // Call the real load() — it should tag the orphan reference.
      final notifier = container.read(strategyProvider.notifier);
      await notifier.load('t1');
      final refs = container.read(strategyProvider).references;
      expect(refs, isNotEmpty);
      expect(refs.single.questionNumber, 5);
      expect(refs.single.missingFromRubric, isTrue);
    },
  );

  test('load() leaves references whose question is still in rubric untouched',
      () async {
    final task = _taskWithRubric(const [
      RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 10),
    ]);
    final container = ProviderContainer(overrides: [
      taskProvider.overrideWith((ref) => _FakeTaskNotifier(ref, task)),
    ]);
    addTearDown(() => _drainAndDispose(container));

    final sub = container.listen(strategyProvider, (_, _) {});
    addTearDown(sub.close);

    await ReferenceStore.save('t1', const [
      ReferenceAnswer(
        questionNumber: 1,
        checkpoints: [],
      ),
    ]);

    final notifier = container.read(strategyProvider.notifier);
    await notifier.load('t1');
    final refs = container.read(strategyProvider).references;
    expect(refs, isNotEmpty);
    expect(refs.single.questionNumber, 1);
    expect(refs.single.missingFromRubric, isFalse);
  });
}
