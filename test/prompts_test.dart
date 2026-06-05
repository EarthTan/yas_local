import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/services/prompts.dart';

void main() {
  group('AppPrompts output protocol', () {
    test('identifyQuestions 包含输出协议', () {
      final text = AppPrompts.identifyQuestions();
      expect(text, contains('## 输出协议'));
      expect(text, isNot(contains('Closure')));
    });

    test('generateStrategy 包含输出协议 + 思考要点', () {
      final text = AppPrompts.generateStrategy(
        questionNumber: 1,
        maxPoints: 5,
        questionText: '示例题',
        hasAnswerImages: false,
      );
      expect(text, contains('## 输出协议'));
      expect(text, contains('思考要点'));
      expect(text, isNot(contains('Closure')));
    });

    test('refineStrategySystem 包含输出协议', () {
      final text = AppPrompts.refineStrategySystem(
        questionLabel: '第 1 题',
        maxPoints: 5,
        checkpointLines: '- 步骤 1（3 分）',
      );
      expect(text, contains('## 输出协议'));
      expect(text, isNot(contains('思考要点')));
      expect(text, isNot(contains('Closure')));
    });

    test('gradePaper 包含输出协议', () {
      final text = AppPrompts.gradePaper(strategyText: '第1题：…');
      expect(text, contains('## 输出协议'));
      expect(text, isNot(contains('思考要点')));
      expect(text, isNot(contains('Closure')));
    });
  });

  group('AppPrompts 硬约束', () {
    test('generateStrategy 包含非空 checkpoint 硬约束与兜底', () {
      final text = AppPrompts.generateStrategy(
        questionNumber: 3,
        maxPoints: 8,
        questionText: '示例题',
        hasAnswerImages: false,
      );
      expect(text, contains('## 硬约束'));
      expect(text, contains('checkpoints 至少要有 1 项'));
      expect(text, contains('不能返回空数组'));
      expect(text, contains('"答案合理且有依据"'));
      expect(text, contains('points 填 8'));
    });

    test('refineStrategySystem 包含非空 checkpoint 硬约束与兜底', () {
      final text = AppPrompts.refineStrategySystem(
        questionLabel: '第 3 题',
        maxPoints: 8,
        checkpointLines: '- 步骤 1（4 分）\n- 步骤 2（4 分）',
      );
      expect(text, contains('## 硬约束'));
      expect(text, contains('checkpoints 至少要有 1 项'));
      expect(text, contains('不能返回空数组'));
      expect(text, contains('"答案合理且有依据"'));
      expect(text, contains('points 填 8'));
    });

    test('generateStrategy 硬约束中 maxPoints 已插值', () {
      final text = AppPrompts.generateStrategy(
        questionNumber: 1,
        maxPoints: 12,
        questionText: '示例',
        hasAnswerImages: false,
      );
      expect(text, contains('points 之和必须恰好等于满分 12'));
      expect(text, contains('points 填 12'));
      expect(text, isNot(contains('points 填 5')));
    });
  });
}
