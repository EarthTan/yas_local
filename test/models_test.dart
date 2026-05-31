import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/rubric.dart';
import 'package:yas_local/models/task.dart';
import 'package:yas_local/models/submission.dart';

void main() {
  test('RubricItem JSON 往返', () {
    const item = RubricItem(
        questionNumber: 1, type: 'objective', maxPoints: 5, correctAnswer: 'B');
    final back = RubricItem.fromJson(item.toJson());
    expect(back.questionNumber, 1);
    expect(back.correctAnswer, 'B');
  });

  test('GradingTask JSON 往返（含 rubric）', () {
    final task = GradingTask(
      id: 't1', name: '测验', subject: 'math',
      createdAt: DateTime(2026, 1, 1),
      rubric: const [RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 10)],
    );
    final back = GradingTask.fromJson(task.toJson());
    expect(back.name, '测验');
    expect(back.rubric.length, 1);
    expect(back.rubric.first.type, 'subjective');
  });

  test('GradedItem 终审分优先于 AI 分', () {
    const a = GradedItem(questionNumber: 1, type: 'objective', aiScore: 3);
    expect(a.finalScore, 3);
    const b = GradedItem(questionNumber: 1, type: 'objective', aiScore: 3, teacherScore: 5);
    expect(b.finalScore, 5);
  });

  test('Submission 总分汇总 finalScore', () {
    const sub = Submission(id: 's1', taskId: 't1', label: '第1份', items: [
      GradedItem(questionNumber: 1, type: 'objective', aiScore: 5),
      GradedItem(questionNumber: 2, type: 'subjective', aiScore: 6, teacherScore: 8),
    ]);
    expect(sub.computedTotal, 13);
  });

  test('trafficLight 按 confidence 分级', () {
    expect(const GradedItem(questionNumber: 1, type: 'objective', confidence: 0.9).trafficLight, 'green');
    expect(const GradedItem(questionNumber: 1, type: 'objective', confidence: 0.7).trafficLight, 'yellow');
    expect(const GradedItem(questionNumber: 1, type: 'objective', confidence: 0.3).trafficLight, 'red');
  });
}
