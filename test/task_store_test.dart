import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/task.dart';
import 'package:yas_local/models/rubric.dart';
import 'package:yas_local/models/submission.dart';
import 'package:yas_local/services/task_store.dart';

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
}
