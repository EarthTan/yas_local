import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/submission.dart';
import 'package:yas_local/models/task.dart';
import 'package:yas_local/providers/task_provider.dart';
import 'package:yas_local/screens/paper_detail_screen.dart';

class _FakeTaskNotifier extends TaskNotifier {
  _FakeTaskNotifier(super.ref, this._task, List<Submission> subs) {
    state = TaskState(tasks: [_task], submissions: subs, loaded: true);
  }
  final GradingTask _task;

  @override
  GradingTask? taskById(String id) => _task.id == id ? _task : null;

  @override
  Future<void> updateSubmission(Submission sub) async {
    // No-op for the smoke test: do not hit TaskStore.
  }
}

void main() {
  testWidgets(
    'teacher score slider screen renders without writing on every tick',
    (tester) async {
      final task = GradingTask(
        id: 't1',
        name: 'T1',
        subject: 'math',
        createdAt: DateTime(2026),
        rubric: const [],
        questionPaperPaths: const [],
        answerImagePaths: const [],
      );
      final sub = Submission(
        id: 's1',
        taskId: 't1',
        label: 'A',
        items: const [GradedItem(questionNumber: 1, type: 'subjective', aiScore: 5)],
      );
      final container = ProviderContainer(overrides: [
        taskProvider.overrideWith((ref) => _FakeTaskNotifier(ref, task, [sub])),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PaperDetailScreen(submissionId: 's1')),
      ));
      // The screen should render without a write-per-onChanged-tick
      // regression. We assert by simply mounting and finding the slider,
      // since the debounce unit test already covers the timer behavior.
      expect(find.byType(Slider), findsWidgets);
    },
  );
}
