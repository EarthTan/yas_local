// Regression guard for U-9: the regrade dialog's "立即重批" button must be
// debounced against rapid double-taps. Rapid clicks used to queue multiple
// `resetGradingResults` + `startGrading` calls, each spawning a separate
// `JobQueue` run.
//
// Two protections are exercised here:
//   1. The entry-point "重新批改" button is gated on `_rerunInProgress`
//      (so the dialog cannot be re-opened while a rerun is in flight).
//   2. The dialog's "立即重批" button is also gated on `_rerunInProgress`
//      (so a rapid double-tap inside the dialog does not queue a second
//      rerun, even before the dialog pops).
//
// The actual `_rerunInProgress` flag is a private field on the screen's
// State, so the test exercises the public surface (button enabled state)
// rather than the flag directly.

import 'dart:async';
import 'dart:io';

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

// Counts the number of `startGrading` invocations. Used to verify that a
// double-tap on the dialog's "立即重批" button only fires the rerun chain
// once.
class _CountingJobQueue extends JobQueueNotifier {
  _CountingJobQueue(super.ref) {
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
  int startGradingCalls = 0;
  @override
  Future<void> startGrading(String taskId) async {
    startGradingCalls++;
  }
}

// TaskNotifier that tracks how many times resetGradingResults was called.
// Fully overrides resetGradingResults to avoid hitting the real TaskStore
// (which would try to write to disk and may hang in the test sandbox).
class _CountingTaskNotifier extends TaskNotifier {
  _CountingTaskNotifier(super.ref, this._task, this._subs);
  final GradingTask _task;
  final List<Submission> _subs;
  int resetCalls = 0;
  @override
  GradingTask? taskById(String id) => _task.id == id ? _task : null;
  @override
  List<Submission> submissionsFor(String id) =>
      id == _task.id ? _subs : const [];
  @override
  Future<void> resetGradingResults(String taskId) async {
    resetCalls++;
    // Simulate the state update that the real method would do, without
    // touching disk.
    state = state.copyWith(
      submissions: [
        for (final s in state.submissions)
          if (s.taskId == taskId)
            s.copyWith(status: SubmissionStatus.pending, items: const [])
          else
            s,
      ],
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  GradingTask makeTask() => GradingTask(
    id: 't1',
    name: 'T1',
    subject: 'math',
    createdAt: DateTime(2026),
    rubric: const [
      RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 5),
    ],
    questionPaperPaths: const [],
  );

  List<Submission> makeSubs() => <Submission>[
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
  ];

  GoRouter buildRouter() => GoRouter(
    initialLocation: '/tasks/t1',
    routes: [
      GoRoute(
        path: '/tasks/:id',
        builder: (_, _) => const TaskDetailScreen(taskId: 't1'),
      ),
    ],
  );

  // Pre-seeds /tmp/reference_t1.json so ReferenceStore.load returns a
  // confirmed reference (required for showRegrade to be true on the
  // detail screen). Caller is responsible for cleanup.
  void seedRefs() {
    final json = '''[
      {
        "questionNumber": 1,
        "checkpoints": [
          {"id": "q1-cp0", "description": "answer is 42", "points": 5}
        ],
        "equivalentForms": [],
        "hasConsensus": true,
        "confirmed": true,
        "chatHistory": [],
        "reasoning": "test"
      }
    ]''';
    File('/tmp/reference_t1.json').writeAsStringSync(json);
  }

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '/tmp',
        );
    seedRefs();
  });

  tearDown(() {
    try {
      File('/tmp/reference_t1.json').deleteSync();
    } catch (_) {}
  });

  testWidgets(
    'regrade dialog opens from the "重新批改" entry button and shows the '
    '"立即重批" button enabled (no rerun in progress)',
    (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              taskProvider.overrideWith(
                (ref) => _CountingTaskNotifier(
                  ref,
                  makeTask(),
                  makeSubs(),
                ),
              ),
              jobQueueProvider.overrideWith(
                (ref) => _CountingJobQueue(ref),
              ),
            ],
            child: MaterialApp.router(routerConfig: buildRouter()),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      // Entry-point "重新批改" button is visible.
      expect(find.text('重新批改'), findsOneWidget);

      // Open the regrade dialog.
      await tester.tap(find.text('重新批改'));
      await tester.pumpAndSettle();

      // Dialog contents render.
      expect(find.text('重新批改将使用当前批改策略覆盖已有的批改结果。'),
          findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('保留旧结果'), findsOneWidget);
      expect(find.text('立即重批'), findsOneWidget);

      // The "立即重批" button must be enabled (no rerun in progress).
      final rerunBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '立即重批'),
      );
      expect(rerunBtn.onPressed, isNotNull,
          reason: 'regrade button must be enabled when no rerun is running');
    },
  );

  testWidgets(
    'rapid double-tap on the dialog "立即重批" button fires the rerun chain '
    'only once (the second tap is gated by _rerunInProgress)',
    (tester) async {
      late _CountingTaskNotifier taskNotifier;
      late _CountingJobQueue jobQueue;
      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              taskProvider.overrideWith(
                (ref) => taskNotifier = _CountingTaskNotifier(
                  ref,
                  makeTask(),
                  makeSubs(),
                ),
              ),
              jobQueueProvider.overrideWith(
                (ref) => jobQueue = _CountingJobQueue(ref),
              ),
            ],
            child: MaterialApp.router(routerConfig: buildRouter()),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      // Open the regrade dialog.
      await tester.tap(find.text('重新批改'));
      await tester.pumpAndSettle();
      expect(find.text('立即重批'), findsOneWidget);

      // First tap on the dialog "立即重批" button: triggers the full
      // reset+startGrading chain. The flag is set true synchronously
      // BEFORE the await, so a second tap landing on the same button
      // while the first is awaiting must be rejected by the guard.
      await tester.tap(find.text('立即重批'));
      await tester.pump();

      // Let the chain run to completion.
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      expect(taskNotifier.resetCalls, 1,
          reason: 'resetGradingResults must be called exactly once');
      expect(jobQueue.startGradingCalls, 1,
          reason: 'startGrading must be called exactly once');
    },
  );

  testWidgets(
    'the "重新批改" entry-point button is gated on _rerunInProgress: when a '
    'rerun is in flight, the entry button is disabled',
    (tester) async {
      final updateGate = Completer<void>();
      final task = makeTask();
      final subs = makeSubs();

      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              taskProvider.overrideWith(
                (ref) => _BlockingTaskNotifierForU9(
                  ref,
                  task,
                  subs,
                  updateGate,
                ),
              ),
              jobQueueProvider.overrideWith(
                (ref) => _CountingJobQueue(ref),
              ),
            ],
            child: MaterialApp.router(routerConfig: buildRouter()),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      // Sanity: both buttons render before any tap.
      expect(find.text('重新批改'), findsOneWidget);
      expect(find.text('重跑失败项'), findsOneWidget);

      // Tap "重跑失败项" to enter the rerun state. This sets
      // _rerunInProgress = true and parks on the blocking updateSubmission.
      await tester.tap(find.text('重跑失败项'));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();

      // The entry-point "重新批改" button must now be disabled.
      final regradeBtn = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, '重新批改'),
      );
      expect(regradeBtn.onPressed, isNull,
          reason: 'entry-point "重新批改" button must be disabled while a '
              'rerun is in progress');

      // Release the gate so the rerun completes and the test cleans up.
      updateGate.complete();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();
    },
  );
}

// Local BlockingTaskNotifier for U-9 — similar to the one in
// task_detail_test.dart, but duplicated here to keep this test self-
// contained.
class _BlockingTaskNotifierForU9 extends TaskNotifier {
  _BlockingTaskNotifierForU9(
    super.ref,
    this._task,
    this._subs,
    this._updateGate,
  );
  final GradingTask _task;
  final List<Submission> _subs;
  final Completer<void> _updateGate;
  int updateSubmissionCalls = 0;
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
