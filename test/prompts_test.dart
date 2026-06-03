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
}
