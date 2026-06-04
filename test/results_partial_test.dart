import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:yas_local/models/submission.dart';
import 'package:yas_local/models/task.dart';
import 'package:yas_local/providers/task_provider.dart';
import 'package:yas_local/screens/results_screen.dart';

class _FakeTaskNotifier extends TaskNotifier {
  _FakeTaskNotifier(super.ref, this._task, this._subs);
  final GradingTask _task;
  final List<Submission> _subs;
  @override
  GradingTask? taskById(String id) => _task.id == id ? _task : null;
  @override
  List<Submission> submissionsFor(String id) => _subs;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => '/tmp',
  );

  // Regression guard: background grading means the results screen can be opened
  // while some submissions are still pending/processing. It must render the
  // mixed state (done/processing/pending) without crashing.
  testWidgets('results screen renders while grading is partially done', (
    tester,
  ) async {
    final task = GradingTask(
      id: 't1',
      name: 'T1',
      subject: 'math',
      createdAt: DateTime(2026),
      rubric: const [],
      questionPaperPaths: const [],
    );
    const subs = [
      Submission(
        id: 's1',
        taskId: 't1',
        label: 'p1',
        status: SubmissionStatus.done,
      ),
      Submission(
        id: 's2',
        taskId: 't1',
        label: 'p2',
        status: SubmissionStatus.processing,
      ),
      Submission(id: 's3', taskId: 't1', label: 'p3'), // pending
    ];

    final router = GoRouter(
      initialLocation: '/tasks/t1/results',
      routes: [
        GoRoute(
          path: '/tasks/:id/results',
          builder: (_, _) => const ResultsScreen(taskId: 't1'),
        ),
        GoRoute(
          path: '/tasks/:id/capture',
          builder: (_, _) => const Scaffold(body: Text('capture')),
        ),
        GoRoute(
          path: '/submissions/:sid',
          builder: (_, _) => const Scaffold(body: Text('paper')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          taskProvider.overrideWith((ref) => _FakeTaskNotifier(ref, task, subs)),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();

    // "已批改 1/3" counts only the done submission; the processing row renders a
    // spinner; no crash on the pending row.
    expect(find.text('1/3'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
  });
}
