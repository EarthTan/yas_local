import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/job_state.dart';
import 'package:yas_local/services/qwen_error.dart';

void main() {
  test('defaults: attempt=0, lastError* null', () {
    const j = JobState(taskId: 't1', kind: JobKind.grading);
    expect(j.attempt, 0);
    expect(j.lastErrorKind, isNull);
    expect(j.lastErrorUnit, isNull);
  });

  test('copyWith sets attempt, kind, unit while running', () {
    const j = JobState(taskId: 't1', kind: JobKind.grading);
    final j2 = j.copyWith(
      attempt: 2,
      lastErrorKind: QwenErrorKind.jsonParse,
      lastErrorUnit: '第 3 例',
    );
    expect(j2.attempt, 2);
    expect(j2.lastErrorKind, QwenErrorKind.jsonParse);
    expect(j2.lastErrorUnit, '第 3 例');
  });

  test('copyWith phase=done clears attempt + lastError*', () {
    const j = JobState(
      taskId: 't1',
      kind: JobKind.grading,
      attempt: 2,
      lastErrorKind: QwenErrorKind.jsonParse,
      lastErrorUnit: '第 3 例',
    );
    final j2 = j.copyWith(phase: JobPhase.done);
    expect(j2.attempt, 0);
    expect(j2.lastErrorKind, isNull);
    expect(j2.lastErrorUnit, isNull);
  });

  test('copyWith phase=failed clears attempt + lastError*', () {
    const j = JobState(
      taskId: 't1',
      kind: JobKind.grading,
      attempt: 1,
      lastErrorKind: QwenErrorKind.http5xx,
      lastErrorUnit: '第 1 例',
    );
    final j2 = j.copyWith(phase: JobPhase.failed);
    expect(j2.attempt, 0);
    expect(j2.lastErrorKind, isNull);
    expect(j2.lastErrorUnit, isNull);
  });

  test('copyWith preserves cancelRequested through retry fields', () {
    const j = JobState(
      taskId: 't1',
      kind: JobKind.grading,
      cancelRequested: true,
    );
    final j2 = j.copyWith(attempt: 1);
    expect(j2.cancelRequested, isTrue);
  });

  test('copyWith lastErrorKind: null explicitly clears (regression for ?? sentinel bug)', () {
    const j = JobState(
      taskId: 't1',
      kind: JobKind.grading,
      lastErrorKind: QwenErrorKind.jsonParse,
      lastErrorUnit: '第 3 例',
    );
    // Same as what _retryWithFeedback does on success.
    final j2 = j.copyWith(lastErrorKind: null, lastErrorUnit: null);
    expect(j2.lastErrorKind, isNull);
    expect(j2.lastErrorUnit, isNull);
  });
}
