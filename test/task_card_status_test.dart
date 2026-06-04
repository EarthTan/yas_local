import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/job_state.dart';
import 'package:yas_local/screens/home_screen.dart';

void main() {
  group('resolveTaskCardStatus', () {
    test('strategy job running -> strategyRunning with progress', () {
      final s = resolveTaskCardStatus(
        job: const JobState(
          taskId: 't1',
          kind: JobKind.strategy,
          total: 5,
          done: 2,
        ),
        subject: 'math',
        subTotal: 0,
        subDone: 0,
        subFailed: 0,
      );
      expect(s.kind, TaskCardKind.strategyRunning);
      expect(s.label, '生成批改策略中 2 / 5');
      expect(s.progress, closeTo(2 / 5, 1e-9));
    });

    test('grading job running -> gradingRunning with progress', () {
      final s = resolveTaskCardStatus(
        job: const JobState(
          taskId: 't1',
          kind: JobKind.grading,
          total: 10,
          done: 3,
        ),
        subject: 'math',
        subTotal: 10,
        subDone: 3,
        subFailed: 0,
      );
      expect(s.kind, TaskCardKind.gradingRunning);
      expect(s.label, '批改中 3 / 10');
      expect(s.progress, closeTo(0.3, 1e-9));
    });

    test('finished job with failures -> gradingFailed', () {
      final s = resolveTaskCardStatus(
        job: const JobState(
          taskId: 't1',
          kind: JobKind.grading,
          phase: JobPhase.failed,
          total: 5,
          done: 5,
          failedCount: 2,
        ),
        subject: 'math',
        subTotal: 5,
        subDone: 3,
        subFailed: 2,
      );
      expect(s.kind, TaskCardKind.gradingFailed);
      expect(s.label, contains('2 份失败'));
    });

    test('finished strategy job -> strategyDone', () {
      final s = resolveTaskCardStatus(
        job: const JobState(
          taskId: 't1',
          kind: JobKind.strategy,
          phase: JobPhase.done,
          total: 3,
          done: 3,
        ),
        subject: 'math',
        subTotal: 0,
        subDone: 0,
        subFailed: 0,
      );
      expect(s.kind, TaskCardKind.strategyDone);
      expect(s.label, contains('待审核'));
    });

    test(
      'no job, all submissions done -> gradingComplete (survives restart)',
      () {
        final s = resolveTaskCardStatus(
          job: null,
          subject: 'math',
          subTotal: 4,
          subDone: 4,
          subFailed: 0,
        );
        expect(s.kind, TaskCardKind.gradingComplete);
        expect(s.label, '批改完成 4 / 4');
      },
    );

    test('no job, partial done -> gradingIncomplete', () {
      final s = resolveTaskCardStatus(
        job: null,
        subject: 'math',
        subTotal: 10,
        subDone: 7,
        subFailed: 0,
      );
      expect(s.kind, TaskCardKind.gradingIncomplete);
      expect(s.label, '已批改 7 / 10 · 继续');
    });

    test('no job, nothing graded -> idle', () {
      final s = resolveTaskCardStatus(
        job: null,
        subject: 'math',
        subTotal: 3,
        subDone: 0,
        subFailed: 0,
      );
      expect(s.kind, TaskCardKind.idle);
      expect(s.label, 'math · 3 份');
    });
  });
}
