import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/checkpoint.dart';
import '../models/job_state.dart';
import '../models/reference_answer.dart';
import '../models/submission.dart';
import '../services/debug_service.dart';
import '../services/error_formatter.dart';
import '../services/qwen_error.dart';
import '../services/qwen_service.dart';
import '../services/reference_store.dart';
import '../services/run_pool.dart';
import 'settings_provider.dart';
import 'strategy_provider.dart' show qwenFactoryProvider;
import 'task_provider.dart';

class JobQueueNotifier extends StateNotifier<Map<String, JobState>> {
  JobQueueNotifier(
    this.ref, {
    this.maxConcurrency = kMaxConcurrency,
    QwenService Function(Ref ref)? qwenFactory,
  })
    // ignore: prefer_initializing_formals
    : _qwenFactory = qwenFactory,
       super(const {});

  final Ref ref;
  final int maxConcurrency;
  final QwenService Function(Ref ref)? _qwenFactory;

  QwenService _newQwen() {
    final factory = _qwenFactory;
    return factory != null
        ? factory(ref)
        : QwenService(ref.read(settingsProvider));
  }

  bool _isRunning(String taskId) => state[taskId]?.phase == JobPhase.running;

  // Always derive the next job from the freshest map entry so we never clobber
  // a concurrently-set field (e.g. cancelRequested) with a stale copy.
  void _patch(String taskId, JobState Function(JobState) update) {
    final cur = state[taskId];
    if (cur == null) return;
    state = {...state, taskId: update(cur)};
  }

  void _set(String taskId, JobState job) => state = {...state, taskId: job};

  /// Wrap a per-unit Qwen call so the user sees the retry attempt count and
  /// the error class. QwenService has already done up to 3 internal retries;
  /// this layer does NOT add a second retry loop — it only propagates the
  /// attempt number to JobState, records a DebugService event, and rethrows
  /// the classified [QwenError]. Cancellation: if [cancelRequested] is set
  /// when the helper is entered, the action is skipped and a [StateError]
  /// is thrown so the per-unit call still bumps `done` and exits cleanly.
  Future<T> _retryWithFeedback<T>({
    required String taskId,
    required String unitLabel,
    required Future<T> Function() action,
  }) async {
    if (state[taskId]?.cancelRequested ?? false) {
      throw StateError('cancelled');
    }
    _patch(taskId, (j) => j.copyWith(
          attempt: 1,
          lastErrorKind: null,
          lastErrorUnit: unitLabel,
        ));
    try {
      final result = await action();
      _patch(taskId, (j) => j.copyWith(
            attempt: 0,
            lastErrorKind: null,
            lastErrorUnit: null,
          ));
      return result;
    } catch (e) {
      final q = QwenError.from(e);
      _patch(taskId, (j) => j.copyWith(
            attempt: 0, // terminal failure of this unit; keep the kind/unit
            lastErrorKind: q.kind,
            lastErrorUnit: unitLabel,
          ));
      DebugService.instance.recordEvent(
        scope: 'task:$taskId',
        message: 'retry failed ($unitLabel, ${q.kind.name})',
        level: EventLevel.error,
        data: {'unit': unitLabel, 'kind': q.kind.name},
      );
      rethrow;
    }
  }

  /// Removes a finished job so its card status reverts to derived/idle.
  void clear(String taskId) {
    if (_isRunning(taskId)) return;
    final next = {...state}..remove(taskId);
    state = next;
  }

  /// Requests cancellation; running units stop picking up new work.
  void cancel(String taskId) =>
      _patch(taskId, (j) => j.copyWith(cancelRequested: true));

  Future<void> startGrading(String taskId) async {
    if (_isRunning(taskId)) return;

    final settings = ref.read(settingsProvider);
    final notifier = ref.read(taskProvider.notifier);
    final task = notifier.taskById(taskId);
    if (task == null) return;

    if (!settings.isConfigured) {
      _set(
        taskId,
        JobState(
          taskId: taskId,
          kind: JobKind.grading,
          phase: JobPhase.failed,
          error: '未配置 API Key，请先到设置填写',
        ),
      );
      return;
    }

    final targets = notifier
        .submissionsFor(taskId)
        .where((s) => s.status != SubmissionStatus.done)
        .toList();

    _set(
      taskId,
      JobState(
        taskId: taskId,
        kind: JobKind.grading,
        total: targets.length,
        done: 0,
      ),
    );

    if (targets.isEmpty) {
      _patch(taskId, (j) => j.copyWith(phase: JobPhase.done));
      return;
    }

    DebugService.instance.recordEvent(
      scope: 'task:$taskId',
      message: 'grading 开始（${targets.length} 份）',
    );

    try {
      final references = await ReferenceStore.load(taskId);
      final refByNum = {for (final r in references) r.questionNumber: r};
      final qwen = _newQwen();

      await runPool(targets, maxConcurrency, (sub, _) async {
        if (state[taskId]?.cancelRequested ?? false) return;

        if (sub.imagePath == null) {
          await notifier.updateSubmission(
            sub.copyWith(status: SubmissionStatus.failed),
          );
          _patch(
            taskId,
            (j) => j.copyWith(done: j.done + 1, failedCount: j.failedCount + 1),
          );
          return;
        }

        try {
          await notifier.updateSubmission(
            sub.copyWith(status: SubmissionStatus.processing),
          );

          final grades = await qwen.gradePaper(
            imagePath: sub.imagePath!,
            questionPaperPaths: task.questionPaperPaths,
            rubric: task.rubric,
            refs: references,
          );
          final gradeByNum = {for (final g in grades) g.questionNumber: g};

          final items = task.rubric.map((rubricItem) {
            final grade = gradeByNum[rubricItem.questionNumber];
            final refAns = refByNum[rubricItem.questionNumber];

            if (grade == null || grade.extractedAnswer.isEmpty) {
              final checkpoints =
                  refAns?.checkpoints
                      .map(
                        (c) => CheckpointResult(
                          description: c.description,
                          passed: false,
                          pointsAwarded: 0,
                          reason: '未作答',
                        ),
                      )
                      .toList() ??
                  [];
              return GradedItem(
                questionNumber: rubricItem.questionNumber,
                type: rubricItem.type,
                extractedAnswer: '',
                checkpoints: checkpoints,
                aiScore: 0,
                confidence: 1.0,
              );
            }

            final aiScore = grade.checkpoints.fold<int>(
              0,
              (sum, c) => sum + c.pointsAwarded,
            );
            return GradedItem(
              questionNumber: rubricItem.questionNumber,
              type: rubricItem.type,
              extractedAnswer: grade.extractedAnswer,
              checkpoints: grade.checkpoints,
              aiScore: aiScore,
              aiComment: grade.overallComment,
              confidence: grade.confidence,
            );
          }).toList();

          await notifier.updateSubmission(
            sub.copyWith(status: SubmissionStatus.done, items: items),
          );
          DebugService.instance.recordEvent(
            scope: 'sub:${sub.id}',
            message: 'graded（${items.length} 题）',
          );
          _patch(taskId, (j) => j.copyWith(done: j.done + 1));
        } catch (e) {
          await notifier.updateSubmission(
            sub.copyWith(status: SubmissionStatus.failed),
          );
          DebugService.instance.recordEvent(
            scope: 'sub:${sub.id}',
            message: 'failed',
            level: EventLevel.error,
            data: {'error': e.toString()},
          );
          _patch(taskId, (j) {
            final err = j.error ?? ErrorFormatter.format(e);
            return j.copyWith(
              done: j.done + 1,
              failedCount: j.failedCount + 1,
              error: err,
            );
          });
        }
      });

      _patch(taskId, (j) {
        final phase = j.failedCount > 0 ? JobPhase.failed : JobPhase.done;
        return j.copyWith(phase: phase);
      });
    } catch (e) {
      // Any failure outside the per-unit try (e.g. ReferenceStore.load) must
      // still drive the job to a terminal phase — otherwise _isRunning stays
      // true and the task can never be re-graded.
      _patch(
        taskId,
        (j) => j.copyWith(
          phase: JobPhase.failed,
          error: j.error ?? ErrorFormatter.format(e),
        ),
      );
    }
    DebugService.instance.recordEvent(
      scope: 'task:$taskId',
      message: 'grading 结束',
    );
  }

  Future<void> startStrategy(String taskId) async {
    if (_isRunning(taskId)) return;

    final settings = ref.read(settingsProvider);
    final task = ref.read(taskProvider.notifier).taskById(taskId);
    if (task == null || task.rubric.isEmpty) return;

    if (!settings.isConfigured) {
      _set(
        taskId,
        JobState(
          taskId: taskId,
          kind: JobKind.strategy,
          phase: JobPhase.failed,
          error: '未配置 API Key，请先到设置填写',
        ),
      );
      return;
    }

    _set(
      taskId,
      JobState(
        taskId: taskId,
        kind: JobKind.strategy,
        total: task.rubric.length,
        done: 0,
      ),
    );

    DebugService.instance.recordEvent(
      scope: 'task:$taskId',
      message: 'strategy generate 开始（${task.rubric.length} 题）',
    );

    final qwen = _newQwen();
    final results = List<ReferenceAnswer?>.filled(task.rubric.length, null);

    try {
      await runPool(task.rubric, maxConcurrency, (item, i) async {
        if (state[taskId]?.cancelRequested ?? false) return;
        try {
          results[i] = await qwen.generateStrategy(
            rubricItem: item,
            questionPaperPaths: task.questionPaperPaths,
            answerImagePaths: task.answerImagePaths,
            totalQuestions: task.rubric.length,
          );
          _patch(taskId, (j) => j.copyWith(done: j.done + 1));
        } catch (e) {
          results[i] = ReferenceAnswer(
            questionNumber: item.questionNumber,
            checkpoints: const [],
            hasConsensus: false,
          );
          _patch(taskId, (j) {
            final err = j.error ?? ErrorFormatter.format(e);
            return j.copyWith(
              done: j.done + 1,
              failedCount: j.failedCount + 1,
              error: err,
            );
          });
        }
      });

      // Skip slots left null by a cancel, then persist the whole batch once.
      final refs = [for (final r in results) ?r];
      await ReferenceStore.save(taskId, refs);

      _patch(taskId, (j) {
        final phase = j.failedCount > 0 ? JobPhase.failed : JobPhase.done;
        return j.copyWith(phase: phase);
      });
    } catch (e) {
      // e.g. ReferenceStore.save failure — still reach a terminal phase so
      // _isRunning doesn't stay true and block regeneration.
      _patch(
        taskId,
        (j) => j.copyWith(
          phase: JobPhase.failed,
          error: j.error ?? ErrorFormatter.format(e),
        ),
      );
    }
    DebugService.instance.recordEvent(
      scope: 'task:$taskId',
      message: 'strategy generate 结束',
    );
  }
}

final jobQueueProvider =
    StateNotifierProvider<JobQueueNotifier, Map<String, JobState>>((ref) {
      return JobQueueNotifier(ref, qwenFactory: ref.read(qwenFactoryProvider));
    });
