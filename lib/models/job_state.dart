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

  const JobState({
    required this.taskId,
    required this.kind,
    this.phase = JobPhase.running,
    this.total = 0,
    this.done = 0,
    this.failedCount = 0,
    this.error,
    this.cancelRequested = false,
  });

  JobState copyWith({
    JobPhase? phase,
    int? total,
    int? done,
    int? failedCount,
    Object? error = _keep,
    bool? cancelRequested,
  }) =>
      JobState(
        taskId: taskId,
        kind: kind,
        phase: phase ?? this.phase,
        total: total ?? this.total,
        done: done ?? this.done,
        failedCount: failedCount ?? this.failedCount,
        error: identical(error, _keep) ? this.error : error as String?,
        cancelRequested: cancelRequested ?? this.cancelRequested,
      );

  static const _keep = Object();
}
