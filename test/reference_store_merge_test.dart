import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'package:yas_local/models/checkpoint.dart';
import 'package:yas_local/models/reference_answer.dart';
import 'package:yas_local/models/rubric.dart';
import 'package:yas_local/models/settings.dart';
import 'package:yas_local/models/strategy_message.dart';
import 'package:yas_local/models/submission.dart';
import 'package:yas_local/models/task.dart';
import 'package:yas_local/providers/job_queue_provider.dart';
import 'package:yas_local/providers/settings_provider.dart';
import 'package:yas_local/providers/strategy_provider.dart';
import 'package:yas_local/providers/task_provider.dart';
import 'package:yas_local/services/qwen_service.dart';
import 'package:yas_local/services/reference_store.dart';

class _ConfiguredSettings extends SettingsNotifier {
  _ConfiguredSettings() {
    state = const AppSettings(apiKey: 'k');
  }
}

class _FakeTaskNotifier extends TaskNotifier {
  _FakeTaskNotifier(super.ref, this._task);
  final GradingTask _task;
  @override
  GradingTask? taskById(String id) => _task.id == id ? _task : null;
  @override
  List<Submission> submissionsFor(String id) => const [];
}

class _StrategyForQ3Only extends QwenService {
  _StrategyForQ3Only() : super(const AppSettings(apiKey: 'k'));
  final calls = <int>[];
  @override
  Future<ReferenceAnswer> generateStrategy({
    required RubricItem rubricItem,
    required List<String> questionPaperPaths,
    required List<String> answerImagePaths,
    int totalQuestions = 0,
  }) async {
    calls.add(rubricItem.questionNumber);
    return ReferenceAnswer(
      questionNumber: rubricItem.questionNumber,
      checkpoints: [
        CheckpointDef(
          id: 'q${rubricItem.questionNumber}-cp0',
          description: 'new for q${rubricItem.questionNumber}',
          points: 5,
        ),
      ],
    );
  }
}

GradingTask _threeQ() => GradingTask(
  id: 't1',
  name: 'T1',
  subject: 'math',
  createdAt: DateTime(2026),
  rubric: const [
    RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 5),
    RubricItem(questionNumber: 2, type: 'subjective', maxPoints: 5),
    RubricItem(questionNumber: 3, type: 'subjective', maxPoints: 5),
  ],
  questionPaperPaths: const [],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('refmerge_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('onlyQuestions=[3] reuses existing refs for 1 and 2', () async {
    // Seed: 3 refs, q1 confirmed, q2 with chat history, q3 empty (failed).
    final seeded = [
      const ReferenceAnswer(
        questionNumber: 1,
        checkpoints: [CheckpointDef(id: 'q1-cp0', description: 'old', points: 5)],
        confirmed: true,
      ),
      const ReferenceAnswer(
        questionNumber: 2,
        checkpoints: [CheckpointDef(id: 'q2-cp0', description: 'old', points: 5)],
        chatHistory: [
          StrategyMessage(role: 'user', content: 'old chat'),
        ],
      ),
      // q3 is the failure sentinel — empty checkpoints.
      const ReferenceAnswer(
        questionNumber: 3,
        checkpoints: [],
        hasConsensus: false,
      ),
    ];
    await ReferenceStore.save('t1', seeded);

    final qwen = _StrategyForQ3Only();
    late _FakeTaskNotifier fake;
    final c = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith((ref) => _ConfiguredSettings()),
        taskProvider.overrideWith((ref) {
          fake = _FakeTaskNotifier(ref, _threeQ());
          return fake;
        }),
        qwenFactoryProvider.overrideWithValue((ref) => qwen),
      ],
    );
    c.read(taskProvider.notifier);
    addTearDown(() async {
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      c.dispose();
    });

    await c
        .read(jobQueueProvider.notifier)
        .startStrategy('t1', onlyQuestions: [3]);

    expect(qwen.calls, [3], reason: 'only q3 should be generated');

    final loaded = await ReferenceStore.load('t1');
    expect(loaded.length, 3);
    final byNum = {for (final r in loaded) r.questionNumber: r};
    expect(
      byNum[1]!.checkpoints.first.description,
      'old',
      reason: 'q1 untouched',
    );
    expect(byNum[1]!.confirmed, isTrue, reason: 'q1 confirmed flag preserved');
    expect(
      byNum[2]!.checkpoints.first.description,
      'old',
      reason: 'q2 untouched',
    );
    expect(byNum[2]!.chatHistory, hasLength(1),
        reason: 'q2 chat history preserved');
    expect(
      byNum[3]!.checkpoints.first.description,
      'new for q3',
      reason: 'q3 overwritten',
    );
  });
}
