import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/job_state.dart';

void main() {
  group('JobState', () {
    test('defaults: phase=running, counters 0, no error', () {
      const j = JobState(taskId: 't1', kind: JobKind.grading);
      expect(j.phase, JobPhase.running);
      expect(j.total, 0);
      expect(j.done, 0);
      expect(j.failedCount, 0);
      expect(j.error, isNull);
      expect(j.cancelRequested, isFalse);
    });

    test('copyWith updates done but preserves cancelRequested', () {
      const j = JobState(
        taskId: 't1',
        kind: JobKind.grading,
        cancelRequested: true,
        total: 5,
      );
      final j2 = j.copyWith(done: 3);
      expect(j2.done, 3);
      expect(j2.total, 5);
      expect(j2.cancelRequested, isTrue, reason: 'unspecified fields preserved');
    });

    test('copyWith can clear error back to null via sentinel', () {
      const j = JobState(taskId: 't1', kind: JobKind.strategy, error: 'boom');
      final j2 = j.copyWith(error: null);
      expect(j2.error, isNull);
    });

    test('copyWith without error arg preserves existing error', () {
      const j = JobState(taskId: 't1', kind: JobKind.strategy, error: 'boom');
      final j2 = j.copyWith(done: 1);
      expect(j2.error, 'boom');
    });
  });
}
