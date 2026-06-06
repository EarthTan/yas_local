// Regression guard for U-12: the regrade AlertDialog must not contain a
// "保留旧结果" action. It used to render three actions — "取消",
// "保留旧结果", "立即重批" — but the "保留旧结果" TextButton was
// functionally identical to "取消" (both close the dialog without
// re-grading). The styling made it look like a distinct third path
// and confused teachers about whether it was an action or a hint.

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

class _NoopJobQueue extends JobQueueNotifier {
  _NoopJobQueue(super.ref) {
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
  @override
  Future<void> startGrading(String taskId) async {}
}

class _StaticTaskNotifier extends TaskNotifier {
  _StaticTaskNotifier(super.ref, this._task, this._subs);
  final GradingTask _task;
  final List<Submission> _subs;
  @override
  GradingTask? taskById(String id) => _task.id == id ? _task : null;
  @override
  List<Submission> submissionsFor(String id) =>
      id == _task.id ? _subs : const [];
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
  // confirmed reference (required for the "重新批改" entry button to
  // appear on the detail screen).
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
    'regrade dialog has exactly 2 action buttons: "取消" and "立即重批" '
    '(no "保留旧结果")',
    (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              taskProvider.overrideWith(
                (ref) => _StaticTaskNotifier(
                  ref,
                  makeTask(),
                  makeSubs(),
                ),
              ),
              jobQueueProvider.overrideWith(
                (ref) => _NoopJobQueue(ref),
              ),
            ],
            child: MaterialApp.router(routerConfig: buildRouter()),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      // Open the regrade dialog from the entry-point button.
      expect(find.text('重新批改'), findsOneWidget);
      await tester.tap(find.text('重新批改'));
      await tester.pumpAndSettle();

      // The dialog must still contain the two intended actions.
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('立即重批'), findsOneWidget);

      // The misleading third action must be gone.
      expect(find.text('保留旧结果'), findsNothing,
          reason: 'regrade dialog must not show the misleading '
              '"保留旧结果" button (U-12)');
    },
  );
}
