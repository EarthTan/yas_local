import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/rubric.dart';
import 'package:yas_local/models/task.dart';
import 'package:yas_local/models/submission.dart';
import 'package:yas_local/models/checkpoint.dart';
import 'package:yas_local/models/reference_answer.dart';
import 'package:yas_local/models/identified_question.dart';

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
      questionPaperPaths: const [],
    );
    final back = GradingTask.fromJson(task.toJson());
    expect(back.name, '测验');
    expect(back.rubric.length, 1);
    expect(back.rubric.first.type, 'subjective');
  });

  test('GradingTask 图片路径序列化', () {
    final task = GradingTask(
      id: 't2', name: '单元考', subject: 'math',
      createdAt: DateTime(2026, 6, 1),
      rubric: const [RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 4)],
      questionPaperPaths: ['/path/q1.jpg', '/path/q2.jpg'],
      answerImagePaths: ['/path/a1.jpg'],
    );
    final back = GradingTask.fromJson(task.toJson());
    expect(back.questionPaperPaths, ['/path/q1.jpg', '/path/q2.jpg']);
    expect(back.answerImagePaths, ['/path/a1.jpg']);
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

  test('CheckpointDef JSON 往返', () {
    const def = CheckpointDef(id: 'q1-cp0', description: '正确建立方程', points: 2);
    final back = CheckpointDef.fromJson(def.toJson());
    expect(back.description, '正确建立方程');
    expect(back.points, 2);
  });

  test('CheckpointResult JSON 往返', () {
    const result = CheckpointResult(
      description: '建立方程',
      passed: true,
      pointsAwarded: 2,
      reason: '学生写出了 x+2=5',
    );
    final back = CheckpointResult.fromJson(result.toJson());
    expect(back.passed, true);
    expect(back.pointsAwarded, 2);
    expect(back.reason, '学生写出了 x+2=5');
  });

  test('ReferenceAnswer JSON 往返', () {
    final ref = ReferenceAnswer(
      questionNumber: 2,
      checkpoints: const [CheckpointDef(id: 'q2-cp0', description: '求解 x', points: 3)],
      equivalentForms: const ['x=3', '3'],
      hasConsensus: true,
    );
    final back = ReferenceAnswer.fromJson(ref.toJson());
    expect(back.questionNumber, 2);
    expect(back.checkpoints.length, 1);
    expect(back.checkpoints.first.points, 3);
    expect(back.equivalentForms, ['x=3', '3']);
    expect(back.hasConsensus, true);
  });

  test('ReferenceAnswer hasConsensus=false 序列化', () {
    const ref = ReferenceAnswer(
      questionNumber: 3,
      checkpoints: [],
      hasConsensus: false,
    );
    expect(ReferenceAnswer.fromJson(ref.toJson()).hasConsensus, false);
  });

  test('ReferenceAnswer reasoning 字段 round-trip', () {
    const ref = ReferenceAnswer(
      questionNumber: 4,
      checkpoints: [],
      reasoning: '考查牛顿第二定律的应用，关键步骤是受力分析。',
    );
    final back = ReferenceAnswer.fromJson(ref.toJson());
    expect(back.reasoning, '考查牛顿第二定律的应用，关键步骤是受力分析。');
  });

  test('ReferenceAnswer 旧数据无 reasoning 字段时为 null（向后兼容）', () {
    final json = {
      'questionNumber': 5,
      'checkpoints': [],
      'equivalentForms': <String>[],
      'hasConsensus': true,
      'confirmed': false,
      'chatHistory': <Map<String, dynamic>>[],
    };
    final back = ReferenceAnswer.fromJson(json);
    expect(back.reasoning, isNull);
  });

  test('ReferenceAnswer copyWith 保留 reasoning', () {
    const ref = ReferenceAnswer(
      questionNumber: 6,
      checkpoints: [],
      reasoning: '原始思考',
    );
    final updated = ref.copyWith(confirmed: true);
    expect(updated.reasoning, '原始思考');
    expect(updated.confirmed, true);
  });

  group('IdentifiedQuestion', () {
    test('fromJson parses correctly', () {
      final q = IdentifiedQuestion.fromJson({
        'number': 2,
        'text': '什么是光合作用？',
        'type': 'subjective',
      });
      expect(q.number, 2);
      expect(q.questionText, '什么是光合作用？');
      expect(q.type, 'subjective');
    });

    test('fromJson handles string number', () {
      final q = IdentifiedQuestion.fromJson({
        'number': '3',
        'text': 'Q',
        'type': 'objective',
      });
      expect(q.number, 3);
    });

    test('fromJson defaults missing fields', () {
      final q = IdentifiedQuestion.fromJson({'number': 1});
      expect(q.questionText, '');
      expect(q.type, 'subjective');
    });
  });
}
