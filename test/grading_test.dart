import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/services/grading.dart';

void main() {
  test('完全匹配得满分，高置信', () {
    final r = gradeObjectiveByKey(student: 'B', correct: 'B', maxPoints: 5);
    expect(r.score, 5);
    expect(r.confidence, greaterThanOrEqualTo(0.95));
  });
  test('不匹配得 0', () {
    final r = gradeObjectiveByKey(student: 'A', correct: 'B', maxPoints: 5);
    expect(r.score, 0);
  });
  test('大小写/空格不敏感', () {
    expect(gradeObjectiveByKey(student: ' b ', correct: 'B', maxPoints: 5).score, 5);
  });
  test('数字匹配', () {
    expect(gradeObjectiveByKey(student: '42', correct: ' 42 ', maxPoints: 3).score, 3);
  });
}
