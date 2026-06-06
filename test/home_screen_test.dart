// Smoke test for HomeScreen (D-9c).
//
// The plan's placeholder test asserted `find.text('T0')` etc. The actual
// screen renders each task as a ListTile with `t.name` as the title AND
// a status label as the subtitle (e.g. `'math · 0 份'` when the task has
// no submissions and no in-flight job). The empty state is the full
// sentence `'暂无批改任务，点击 + 新建'`, not just `'暂无'`.
//
// Two meaningful tests, mirroring the structure of
// `test/create_task_screen_test.dart`:
//   1. Three seeded tasks render three cards (one ListTile per task, with
//      the task name and idle status label both visible).
//   2. With no tasks, the empty state string is shown.
//
// path_provider is mocked because the real SettingsNotifier (watched by
// HomeScreen for `isConfigured`) calls `getApplicationSupportDirectory`
// on construction; without a mock the widget tests crash on a missing
// platform channel. The tests also override `settingsProvider` with a
// configured value (see _FakeSettingsNotifier) to suppress the "请配置
// Qwen API Key" warning banner so the only ListTiles on screen are
// task cards.
//
// The fake task notifier extends TaskNotifier and pre-seeds `state` with
// the supplied tasks (loaded=true, no submissions) so the screen renders
// cards immediately, mirroring the `_RecordingTaskNotifier` pattern from
// `test/create_task_screen_test.dart`.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/rubric.dart';
import 'package:yas_local/models/settings.dart';
import 'package:yas_local/models/submission.dart';
import 'package:yas_local/models/task.dart';
import 'package:yas_local/providers/settings_provider.dart';
import 'package:yas_local/providers/task_provider.dart';
import 'package:yas_local/screens/home_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock path_provider so the real SettingsNotifier (and TaskNotifier,
  // if it ever runs) does not crash on `getApplicationDocumentsDirectory`
  // / `getApplicationSupportDirectory` during widget tests.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => '/tmp',
      );

  // Helper: build a single GradingTask with sensible defaults for the
  // fields the home screen does not display.
  GradingTask task(String id, String name) => GradingTask(
        id: id,
        name: name,
        subject: 'math',
        createdAt: DateTime(2026),
        rubric: const [
          RubricItem(
            questionNumber: 1,
            type: 'subjective',
            maxPoints: 10,
          ),
        ],
        questionPaperPaths: const [],
        answerImagePaths: const [],
      );

  // The home screen renders a "请配置 Qwen API Key" warning banner as
  // its own ListTile when `settings.isConfigured` is false. Both tests
  // override `settingsProvider` with a configured value (see
  // _FakeSettingsNotifier) so the warning is suppressed and the only
  // ListTiles on screen are the task cards (or none, in the
  // empty-state test).

  testWidgets(
    'HomeScreen 渲染每个任务一张卡片（标题 + 空闲状态副标题）',
    (tester) async {
      final seededTasks = [task('t0', 'T0'), task('t1', 'T1'), task('t2', 'T2')];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith((ref) => _FakeSettingsNotifier()),
            taskProvider.overrideWith(
              (ref) => _SeededTaskNotifier(ref, seededTasks),
            ),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // AppBar title.
      expect(find.text('YAS 批改助手'), findsOneWidget);
      // One ListTile per task (the home body is a ListView of task cards).
      // (The "请配置" warning is suppressed by the configured settings
      // override above.)
      expect(find.byType(ListTile), findsNWidgets(3));
      // Each task name appears as a tile title.
      expect(find.text('T0'), findsOneWidget);
      expect(find.text('T1'), findsOneWidget);
      expect(find.text('T2'), findsOneWidget);
      // Idle status label: `'$subject · $subTotal 份'` (resolveTaskCardStatus
      // returns this when there are no submissions and no in-flight job).
      // All three tasks have subject='math' and 0 submissions.
      expect(find.text('math · 0 份'), findsNWidgets(3));
      // Empty state should NOT show when tasks are present.
      expect(find.text('暂无批改任务，点击 + 新建'), findsNothing);
    },
  );

  testWidgets(
    'HomeScreen 在没有任务时显示「暂无批改任务，点击 + 新建」空态',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith((ref) => _FakeSettingsNotifier()),
            taskProvider.overrideWith(
              (ref) => _SeededTaskNotifier(ref, const []),
            ),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // AppBar title still renders.
      expect(find.text('YAS 批改助手'), findsOneWidget);
      // Empty state string is on screen.
      expect(find.text('暂无批改任务，点击 + 新建'), findsOneWidget);
      // No task cards.
      expect(find.byType(ListTile), findsNothing);
    },
  );
}

class _FakeSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings get state => const AppSettings(apiKey: 'test-key');
}

class _SeededTaskNotifier extends TaskNotifier {
  _SeededTaskNotifier(super.ref, this._seed);

  final List<GradingTask> _seed;

  @override
  TaskState get state => TaskState(
        tasks: _seed,
        submissions: const [],
        loaded: true,
      );

  @override
  set state(TaskState value) {
    // No-op: tests do not exercise mutators.
  }

  @override
  List<Submission> submissionsFor(String taskId) => const [];
}
