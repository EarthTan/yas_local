import 'package:yas_local/services/qwen_error.dart' show QwenErrorKind;

/// Which long-running AI loop a job represents.
enum JobKind { strategy, grading }

/// Lifecycle of a job. There is no `cancelled` phase — a cancelled job ends
/// as [done] with fewer units processed; cancellation is signalled by
/// [JobState.cancelRequested] while running.
enum JobPhase { running, done, failed }

/// In-memory progress record for one task's active (or just-finished) job.
/// Not persisted: jobs are session-scoped. Durable grading progress lives on
/// each [Submission]'s status; durable strategy output lives in
/// `reference_<taskId>.json`.
class JobState {
  final String taskId;
  final JobKind kind;
  final JobPhase phase;
  final int total; // unit count: rubric questions (strategy) or submissions (grading)
  final int done; // completed units, including failed ones
  final int failedCount;
  final String? error; // first error encountered, already Chinese-formatted
  final bool cancelRequested;

  /// 0 = no retry in flight; 1..3 = the in-progress retry attempt number.
  /// Always 0 when [phase] is [JobPhase.done] or [JobPhase.failed] —
  /// [copyWith] and the constructor enforce that.
  final int attempt;

  /// Snapshot of the most recent error class observed during this job.
  /// UI shows the *last* failure only; full history is owned by DebugService.
  final QwenErrorKind? lastErrorKind;

  /// Human label for the unit that was retrying, e.g. "第 12 例" or "第 3 题".
  final String? lastErrorUnit;

  const JobState({
    required this.taskId,
    required this.kind,
    this.phase = JobPhase.running,
    this.total = 0,
    this.done = 0,
    this.failedCount = 0,
    this.error,
    this.cancelRequested = false,
    this.attempt = 0,
    this.lastErrorKind,
    this.lastErrorUnit,
  });

  JobState copyWith({
    JobPhase? phase,
    int? total,
    int? done,
    int? failedCount,
    Object? error = _keep,
    bool? cancelRequested,
    int? attempt,
    QwenErrorKind? lastErrorKind,
    String? lastErrorUnit,
  }) {
    final newPhase = phase ?? this.phase;
    // Retry/feedback fields only make sense while running. Clear them on
    // transition to a terminal phase so stale "正在重试" UI doesn't linger.
    final terminal = newPhase == JobPhase.done || newPhase == JobPhase.failed;
    return JobState(
      taskId: taskId,
      kind: kind,
      phase: newPhase,
      total: total ?? this.total,
      done: done ?? this.done,
      failedCount: failedCount ?? this.failedCount,
      error: identical(error, _keep) ? this.error : error as String?,
      cancelRequested: cancelRequested ?? this.cancelRequested,
      attempt: terminal ? 0 : (attempt ?? this.attempt),
      lastErrorKind: terminal ? null : (lastErrorKind ?? this.lastErrorKind),
      lastErrorUnit: terminal ? null : (lastErrorUnit ?? this.lastErrorUnit),
    );
  }

  static const _keep = Object();
}
