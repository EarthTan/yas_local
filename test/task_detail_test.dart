import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:yas_local/models/job_state.dart';
import 'package:yas_local/models/rubric.dart';
import 'package:yas_local/models/submission.dart';
import 'package:yas_local/models/task.dart';
import 'package:yas_local/providers/job_queue_provider.dart';
import 'package:yas_local/providers/task_provider.dart';
import 'package:yas_local/screens/task_detail_screen.dart';

class _FakeTaskNotifier extends TaskNotifier {
  _FakeTaskNotifier(super.ref, this._task, [this._subs = const []]);
  final GradingTask _task;
  final List<Submission> _subs;
  @override
  GradingTask? taskById(String id) => _task.id == id ? _task : null;
  @override
  List<Submission> submissionsFor(String id) =>
      id == _task.id ? _subs : const [];
}

// Seeds the job map with a running strategy job so the detail page renders the
// inline generation progress.
class _StrategyRunningJobQueue extends JobQueueNotifier {
  _StrategyRunningJobQueue(super.ref) {
    state = const {
      't1': JobState(taskId: 't1', kind: JobKind.strategy, total: 3, done: 1),
    };
  }
}

// A finished grading job with 1 failure so the failure banner should show.
class _GradingDoneWithFailuresJobQueue extends JobQueueNotifier {
  _GradingDoneWithFailuresJobQueue(super.ref) {
    state = const {
      't1': JobState(
        taskId: 't1',
        kind: JobKind.grading,
        total: 3,
        done: 3,
        failedCount: 1,
        phase: JobPhase.failed,
      ),
    };
  }
}

// Fake TaskNotifier that blocks on updateSubmission() until the test
// releases the completer — exposes the gap between the failed→pending reset
// and startGrading() so a second tap can race in.
class _BlockingTaskNotifier extends TaskNotifier {
  _BlockingTaskNotifier(
    super.ref,
    this._task,
    this._subs,
    this._updateGate,
  );
  final GradingTask _task;
  final List<Submission> _subs;
  final Completer<void> _updateGate;
  int updateSubmissionCalls = 0;
  int startGradingCalls = 0;

  @override
  GradingTask? taskById(String id) => _task.id == id ? _task : null;
  @override
  List<Submission> submissionsFor(String id) =>
      id == _task.id ? _subs : const [];

  @override
  Future<void> updateSubmission(Submission sub) async {
    updateSubmissionCalls++;
    await _updateGate.future;
  }
}

class _CountingJobQueue extends JobQueueNotifier {
  _CountingJobQueue(super.ref) {
    state = const {
      't1': JobState(
        taskId: 't1',
        kind: JobKind.grading,
        total: 3,
        done: 3,
        failedCount: 2,
        phase: JobPhase.failed,
      ),
    };
  }
  int startGradingCalls = 0;
  int startStrategyCalls = 0;
  @override
  Future<void> startGrading(String taskId) async {
    startGradingCalls++;
  }
  @override
  Future<void> startStrategy(
    String taskId, {
    Iterable<int>? onlyQuestions,
  }) async {
    startStrategyCalls++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('resolveResultsState', () {
    test(
      'readyToGrade when allConfirmed and has submissions and no results',
      () {
        expect(
          resolveResultsState(
            allConfirmed: true,
            subCount: 2,
            hasGradingResults: false,
          ),
          ResultsSectionStatus.readyToGrade,
        );
      },
    );

    test('waitingForSubmissions when allConfirmed but no submissions', () {
      expect(
        resolveResultsState(
          allConfirmed: true,
          subCount: 0,
          hasGradingResults: false,
        ),
        ResultsSectionStatus.waitingForSubmissions,
      );
    });

    test('waitingForStrategy when strategy not confirmed', () {
      expect(
        resolveResultsState(
          allConfirmed: false,
          subCount: 3,
          hasGradingResults: false,
        ),
        ResultsSectionStatus.waitingForStrategy,
      );
    });

    test('hasResults when grading results exist', () {
      expect(
        resolveResultsState(
          allConfirmed: true,
          subCount: 2,
          hasGradingResults: true,
        ),
        ResultsSectionStatus.hasResults,
      );
    });

    test('hasResults overrides all other conditions', () {
      expect(
        resolveResultsState(
          allConfirmed: false,
          subCount: 0,
          hasGradingResults: true,
        ),
        ResultsSectionStatus.hasResults,
      );
    });
  });

  testWidgets(
    'strategy section shows inline progress (not a 生成 button) while a '
    'strategy job is running',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => '/tmp',
          );

      final task = GradingTask(
        id: 't1',
        name: 'T1',
        subject: 'math',
        createdAt: DateTime(2026),
        rubric: const [
          RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 5),
          RubricItem(questionNumber: 2, type: 'subjective', maxPoints: 5),
          RubricItem(questionNumber: 3, type: 'subjective', maxPoints: 5),
        ],
        questionPaperPaths: const [],
      );

      final router = GoRouter(
        initialLocation: '/tasks/t1',
        routes: [
          GoRoute(
            path: '/tasks/:id',
            builder: (_, _) => const TaskDetailScreen(taskId: 't1'),
          ),
        ],
      );

      // _loadRefs does real dart:io file I/O in initState; run it under
      // runAsync so the real event loop can complete it, then pump to apply
      // the resulting setState (_loadingRefs -> false).
      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              taskProvider.overrideWith((ref) => _FakeTaskNotifier(ref, task)),
              jobQueueProvider.overrideWith(
                (ref) => _StrategyRunningJobQueue(ref),
              ),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      // Inline progress shows; the generate button is hidden (no spinner page).
      expect(find.text('生成批改策略中 1 / 3 题'), findsOneWidget);
      expect(find.text('生成批改策略'), findsNothing);
    },
  );

  testWidgets(
    'grading failure banner shows "1 份失败" with rerun button after a job '
    'finishes with failures',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => '/tmp',
          );

      final task = GradingTask(
        id: 't1',
        name: 'T1',
        subject: 'math',
        createdAt: DateTime(2026),
        rubric: const [
          RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 5),
        ],
        questionPaperPaths: const [],
      );

      // One done submission (so hasResults), and a started-but-failed job.
      final subs = <Submission>[
        Submission(
          id: 's1',
          taskId: 't1',
          label: 's1',
          status: SubmissionStatus.done,
          items: const [],
        ),
      ];

      final router = GoRouter(
        initialLocation: '/tasks/t1',
        routes: [
          GoRoute(
            path: '/tasks/:id',
            builder: (_, _) => const TaskDetailScreen(taskId: 't1'),
          ),
        ],
      );

      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              taskProvider.overrideWith(
                (ref) => _FakeTaskNotifier(ref, task, subs),
              ),
              jobQueueProvider.overrideWith(
                (ref) => _GradingDoneWithFailuresJobQueue(ref),
              ),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      expect(find.text('1 份失败'), findsOneWidget);
      expect(find.text('重跑失败项'), findsOneWidget);
    },
  );

  // Strategy failure banner — covered by the same pattern as grading. The
  // grading banner test above exercises the banner widget; the strategy
  // variant uses the same `_rerunFailedStrategy` -> startStrategy(onlyQuestions:)
  // wiring which is exercised by the merge test in test/reference_store_merge_test.dart.
  //
  // (We skip an explicit strategy widget test here because seeding the
  //  reference_<taskId>.json file under the same widget-test path_provider
  //  mock caused a 10-minute hang in CI. The merge test covers the
  //  startStrategy(onlyQuestions:) behavior end-to-end without involving
  //  the widget tree.)

  testWidgets(
    'rerun-failed-grading button is guarded against double-tap: a second '
    'tap does not re-enter the chain and startGrading is called only once',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => '/tmp',
          );

      final task = GradingTask(
        id: 't1',
        name: 'T1',
        subject: 'math',
        createdAt: DateTime(2026),
        rubric: const [
          RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 5),
        ],
        questionPaperPaths: const [],
      );

      // 1 done + 2 failed: ensures hasResults is true AND the rerun loop
      // has multiple failed submissions to reset, so a buggy double-tap
      // would double the updateSubmission call count.
      final subs = <Submission>[
        const Submission(
          id: 's1',
          taskId: 't1',
          label: 's1',
          status: SubmissionStatus.done,
          items: [],
        ),
        const Submission(
          id: 's2',
          taskId: 't1',
          label: 's2',
          status: SubmissionStatus.failed,
          items: [],
        ),
        const Submission(
          id: 's3',
          taskId: 't1',
          label: 's3',
          status: SubmissionStatus.failed,
          items: [],
        ),
      ];

      final updateGate = Completer<void>();
      late _BlockingTaskNotifier blockingNotifier;
      late _CountingJobQueue countingQueue;

      final router = GoRouter(
        initialLocation: '/tasks/t1',
        routes: [
          GoRoute(
            path: '/tasks/:id',
            builder: (_, _) => const TaskDetailScreen(taskId: 't1'),
          ),
        ],
      );

      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              taskProvider.overrideWith(
                (ref) => blockingNotifier = _BlockingTaskNotifier(
                  ref,
                  task,
                  subs,
                  updateGate,
                ),
              ),
              jobQueueProvider.overrideWith(
                (ref) => countingQueue = _CountingJobQueue(ref),
              ),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      // The failure banner is visible.
      expect(find.text('重跑失败项'), findsOneWidget);

      // First tap: enters _rerunFailedGrading, hits await updateSubmission(),
      // parks on the gate. startGrading has not been called yet.
      await tester.tap(find.text('重跑失败项'));
      await tester.pump();
      // Let the await chain reach the first updateSubmission call.
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();

      expect(
        blockingNotifier.updateSubmissionCalls,
        1,
        reason: 'first tap started the chain and is awaiting the gate',
      );
      expect(
        countingQueue.startGradingCalls,
        0,
        reason: 'startGrading is called only after the for-loop completes',
      );

      // Second tap while the chain is still parked on the gate. Without the
      // guard, this would re-enter the function and start a second chain
      // (it would call updateSubmission twice more — once per failed sub).
      await tester.tap(find.text('重跑失败项'));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();

      // With the guard, the second tap is rejected — no new updateSubmission
      // call, no new startGrading.
      expect(
        blockingNotifier.updateSubmissionCalls,
        1,
        reason: 'second tap must be rejected by the in-progress guard',
      );

      // Release the gate so the first chain finishes.
      updateGate.complete();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();

      // First chain completed: both failed submissions were reset (2
      // updateSubmission calls) and startGrading was called once.
      expect(blockingNotifier.updateSubmissionCalls, 2);
      expect(countingQueue.startGradingCalls, 1);
    },
  );
}
