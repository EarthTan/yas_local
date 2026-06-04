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
  _FakeTaskNotifier(super.ref, this._task);
  final GradingTask _task;
  @override
  GradingTask? taskById(String id) => _task.id == id ? _task : null;
  @override
  List<Submission> submissionsFor(String id) => const [];
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
}
