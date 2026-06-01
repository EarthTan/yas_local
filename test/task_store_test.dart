import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/task.dart';
import 'package:yas_local/models/rubric.dart';
import 'package:yas_local/models/submission.dart';
import 'package:yas_local/services/task_store.dart';
import 'package:yas_local/models/checkpoint.dart';
import 'package:yas_local/models/reference_answer.dart';
import 'package:yas_local/services/reference_store.dart';

void main() {
  test('encode/decode 整库往返', () {
    final tasks = [
      GradingTask(
        id: 't1', name: '测验1', subject: 'math', createdAt: DateTime(2026, 1, 1),
        rubric: const [RubricItem(questionNumber: 1, type: 'objective', maxPoints: 5, correctAnswer: 'B')],
      ),
    ];
    const subs = [
      Submission(id: 's1', taskId: 't1', label: '第1份', items: [
        GradedItem(questionNumber: 1, type: 'objective', aiScore: 5, confidence: 0.95),
      ]),
    ];
    final json = TaskStore.encode(tasks, subs);
    final decoded = TaskStore.decode(json);
    expect(decoded.tasks.length, 1);
    expect(decoded.tasks.first.name, '测验1');
    expect(decoded.submissions.length, 1);
    expect(decoded.submissions.first.items.first.aiScore, 5);
  });

  test('decode 空字符串返回空库', () {
    final decoded = TaskStore.decode('');
    expect(decoded.tasks, isEmpty);
    expect(decoded.submissions, isEmpty);
  });

  test('ReferenceStore encode/decode 往返', () {
    final refs = [
      ReferenceAnswer(
        questionNumber: 1,
        checkpoints: const [CheckpointDef(description: '答对', points: 5)],
      ),
    ];
    final decoded = ReferenceStore.decode(ReferenceStore.encode(refs));
    expect(decoded.length, 1);
    expect(decoded.first.questionNumber, 1);
    expect(decoded.first.checkpoints.first.points, 5);
  });
}
