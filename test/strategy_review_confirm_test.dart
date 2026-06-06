import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:yas_local/models/checkpoint.dart';
import 'package:yas_local/models/reference_answer.dart';
import 'package:yas_local/models/rubric.dart';
import 'package:yas_local/models/settings.dart';
import 'package:yas_local/models/task.dart';
import 'package:yas_local/providers/settings_provider.dart';
import 'package:yas_local/providers/strategy_provider.dart';
import 'package:yas_local/providers/task_provider.dart';
import 'package:yas_local/screens/strategy_review_screen.dart';
import 'package:yas_local/services/qwen_service.dart';

/// Seeded StrategyNotifier — skips the on-disk load and serves the refs the
/// test provides, mirroring `_SeededNotifier` in `strategy_screen_test.dart`.
class _SeededNotifier extends StrategyNotifier {
  _SeededNotifier(super.ref, this._refs, {super.qwenFactory}) {
    state = StrategyState(references: _refs);
  }
  final List<ReferenceAnswer> _refs;

  @override
  Future<void> load(String taskId) async {} // keep seeded refs

  @override
  Future<void> saveAllConfirmed(String taskId) async {}
}

GradingTask _taskWithRubricForScreen(List<RubricItem> rubric) => GradingTask(
  id: 't1',
  name: 'T1',
  subject: 'math',
  createdAt: DateTime(2026),
  rubric: rubric,
  questionPaperPaths: const [],
  answerImagePaths: const [],
);

class _FakeScreenTaskNotifier extends TaskNotifier {
  _FakeScreenTaskNotifier(super.ref, this._task);
  final GradingTask _task;
  @override
  GradingTask? taskById(String id) => _task.id == id ? _task : null;
}

class _FakeScreenSettingsNotifier extends SettingsNotifier {
  _FakeScreenSettingsNotifier() {
    state = const AppSettings(apiKey: 'k');
  }
}

QwenService Function(Ref) _noQwenFactory() => (_) => throw UnimplementedError();

Future<void> _pumpScreen(
  WidgetTester tester, {
  required List<ReferenceAnswer> refs,
  required GradingTask task,
}) async {
  final router = GoRouter(
    initialLocation: '/tasks/t1/strategy',
    routes: [
      GoRoute(
        path: '/tasks/:id',
        builder: (_, _) => const Scaffold(body: Text('hub')),
      ),
      GoRoute(
        path: '/tasks/:id/strategy',
        builder: (_, s) => StrategyReviewScreen(taskId: s.pathParameters['id']!),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        strategyProvider.overrideWith(
          (ref) => _SeededNotifier(ref, refs, qwenFactory: _noQwenFactory()),
        ),
        taskProvider.overrideWith((ref) => _FakeScreenTaskNotifier(ref, task)),
        settingsProvider.overrideWith((ref) => _FakeScreenSettingsNotifier()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // Bug U-6: tapping "确认此题" on the last unconfirmed question did
  // HapticFeedback.lightImpact() and called _nextUnconfirmed(), which
  // returned silently when there was nowhere to go. Teacher was left
  // staring at the screen wondering if anything happened.
  //
  // Fix: show a SnackBar (and trigger a heavy haptic) when the last
  // unconfirmed question is confirmed.
  testWidgets('confirming the last question shows a "all confirmed" snackbar',
      (tester) async {
    final refs = [
      ReferenceAnswer(
        questionNumber: 1,
        checkpoints: const [
          CheckpointDef(id: 'q1-cp0', description: 'A', points: 1),
        ],
      ),
    ];
    final task = _taskWithRubricForScreen(const [
      RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 1),
    ]);
    await _pumpScreen(tester, refs: refs, task: task);

    // Tap the "确认此题" button. The only question is unconfirmed, so this
    // is the last unconfirmed question and the screen must show feedback.
    await tester.tap(find.text('确认此题'));
    await tester.pump(); // start the snackbar
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('全部题已确认，可开始批改'), findsOneWidget);
  });
}
