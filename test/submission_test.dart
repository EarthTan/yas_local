import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/submission.dart';

void main() {
  group('GradedItem.copyWith tri-state (S-7)', () {
    const item = GradedItem(
      questionNumber: 1,
      type: 'subjective',
      teacherScore: 8,
    );

    test('teacherScore: null means "no change" (preserves 8)', () {
      final unchanged = item.copyWith(teacherScore: null);
      expect(unchanged.teacherScore, 8);
    });

    test('clearTeacherScore: true clears to null', () {
      final cleared = item.copyWith(clearTeacherScore: true);
      expect(cleared.teacherScore, isNull);
    });

    test('teacherScore: 5 sets to 5 (no clear)', () {
      final updated = item.copyWith(teacherScore: 5);
      expect(updated.teacherScore, 5);
    });

    test('clearTeacherScore: true wins over teacherScore: <value>', () {
      // If both flags are passed, the explicit clear should win — the
      // "set to 99 then clear" sequence should result in null, not 99.
      final cleared = item.copyWith(teacherScore: 99, clearTeacherScore: true);
      expect(cleared.teacherScore, isNull);
    });
  });
}
