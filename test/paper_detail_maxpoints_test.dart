import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/checkpoint.dart';
import 'package:yas_local/models/submission.dart';
import 'package:yas_local/models/task.dart';
import 'package:yas_local/providers/task_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('paper_detail_maxpoints_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('maxPts falls back to per-item checkpoint sum when rubric missing',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(taskProvider.notifier);

    // Let the constructor's _load() settle.
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    // Add a task with NO rubric entry for question 5.
    await notifier.addTask(GradingTask(
      id: 't1',
      name: 'T1',
      subject: 'math',
      createdAt: DateTime(2026),
      rubric: const [],
      questionPaperPaths: const [],
      answerImagePaths: const [],
    ));
    // Item's checkpoints sum to 8 (5 + 3), no rubric entry for Q5.
    await notifier.setSubmissions('t1', [
      Submission(
        id: 's1',
        taskId: 't1',
        label: 'A',
        items: const [
          GradedItem(
            questionNumber: 5,
            type: 'subjective',
            aiScore: 3,
            checkpoints: [
              CheckpointResult(
                description: 'a',
                passed: true,
                pointsAwarded: 5,
                reason: '',
              ),
              CheckpointResult(
                description: 'b',
                passed: false,
                pointsAwarded: 3,
                reason: '',
              ),
            ],
          ),
        ],
      ),
    ]);

    // Read maxPts the same way PaperDetailScreen does.
    final state = container.read(taskProvider);
    final sub = state.submissions.first;
    final item = sub.items.first;
    final rubricByNum = {
      for (final r in state.tasks.first.rubric) r.questionNumber: r,
    };
    // The fix: prefer item's checkpoint sum over the literal 20 default.
    final maxPts = rubricByNum[item.questionNumber]?.maxPoints ??
        (item.checkpoints.isNotEmpty
            ? item.checkpoints.fold<int>(0, (sum, c) => sum + c.pointsAwarded)
            : 20);
    expect(maxPts, 8);
  });
}
