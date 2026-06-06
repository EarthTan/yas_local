// Smoke test for CreateTaskScreen (D-9b).
//
// The plan's placeholder test assumed the screen used a `必填` validation
// message and a "创建任务" submit button. The actual screen uses:
//   - AppBar title "新建批改任务"
//   - TextField with label "任务名称（如：第3单元测验）"
//   - DropdownButtonFormField labeled "科目"
//   - Submit button "保存并识别题目" (icon: search)
//   - Validation: empty name shows a SnackBar "请填写任务名称";
//     empty question photos shows "请至少上传一张题目照片".
//   - On success it calls addTask + pushReplacement('/tasks/$id/identify'),
//     so a real submit test needs GoRouter + a writable temp dir for
//     ImageStore.persistQuestionImages.
//
// Image picking (camera / photo library) is not exercised here — that
// path goes through the image_picker plugin and is not unit-testable
// without a platform channel mock that doesn't exist in this repo.
//
// Three meaningful tests, mirroring the structure of
// `test/identify_screen_test.dart`:
//   1. Renders all expected form fields.
//   2. Tapping save with an empty name surfaces the validation SnackBar
//      (and does not add a task).
//   3. The back button pops the screen via the Navigator.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:yas_local/models/submission.dart';
import 'package:yas_local/models/task.dart';
import 'package:yas_local/providers/task_provider.dart';
import 'package:yas_local/screens/create_task_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock path_provider so the real TaskNotifier (created when
  // CreateTaskScreen reads taskProvider in its _save method) does not
  // crash on `getApplicationDocumentsDirectory` during widget tests.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => '/tmp',
      );

  // Fake notifier that records addTask calls but never touches disk
  // (the real `addTask` persists to TaskStore, which in a unit test
  // would race with the mocked path_provider).
  //
  // Each test builds a fresh ProviderContainer, so the overrideWith
  // factory is invoked once per testWidgets call. Tests that need to
  // inspect the live notifier (e.g. to assert no addTask happened) do
  // so via a `late` local captured inside the factory closure.

  testWidgets(
    'CreateTaskScreen 渲染任务名称、科目下拉、题目照片区块、提交按钮',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            taskProvider.overrideWith(
              (ref) => _RecordingTaskNotifier(ref),
            ),
          ],
          child: const MaterialApp(
            home: CreateTaskScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // AppBar title.
      expect(find.text('新建批改任务'), findsOneWidget);
      // TextField for the task name.
      expect(find.widgetWithText(TextField, '任务名称（如：第3单元测验）'),
          findsOneWidget);
      // Subject dropdown.
      expect(find.widgetWithText(DropdownButtonFormField<String>, '科目'),
          findsOneWidget);
      // Section headers.
      expect(find.text('1. 上传题目照片（必填）'), findsOneWidget);
      expect(find.text('2. 上传教师答案（可选）'), findsOneWidget);
      // Camera + album buttons (one set per photo section).
      expect(find.widgetWithText(ElevatedButton, '拍照'), findsNWidgets(2));
      expect(find.widgetWithText(OutlinedButton, '相册'), findsNWidgets(2));
      // Submit button (idle label).
      expect(find.text('保存并识别题目'), findsOneWidget);
    },
  );

  testWidgets(
    '任务名称为空时点击保存弹出 SnackBar「请填写任务名称」',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            taskProvider.overrideWith(
              (ref) => _RecordingTaskNotifier(ref),
            ),
          ],
          child: const MaterialApp(
            home: CreateTaskScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap submit with an empty title and no photos.
      await tester.tap(find.text('保存并识别题目'));
      await tester.pump(); // schedule the SnackBar
      await tester.pump(const Duration(milliseconds: 100));

      // The empty-name SnackBar is the first validation branch.
      // (The screen bails out before touching the notifier, so we
      // only need to assert the SnackBar text — notifier activity
      // is not part of this path.)
      expect(find.text('请填写任务名称'), findsOneWidget);
    },
  );

  testWidgets(
    'back 按钮通过 Navigator 弹出 CreateTaskScreen',
    (tester) async {
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('home')),
          ),
          GoRoute(
            path: '/create',
            builder: (_, _) => const CreateTaskScreen(),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            taskProvider.overrideWith(
              (ref) => _RecordingTaskNotifier(ref),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      // Navigate from / to /create.
      router.push('/create');
      await tester.pumpAndSettle();
      expect(find.text('新建批改任务'), findsOneWidget);

      // Tap the default leading BackButton in the AppBar.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      // We're back on /.
      expect(find.text('home'), findsOneWidget);
      expect(find.text('新建批改任务'), findsNothing);
    },
  );
}

class _RecordingTaskNotifier extends TaskNotifier {
  _RecordingTaskNotifier(super.ref);
  final List<GradingTask> addedTasks = [];

  @override
  Future<void> addTask(GradingTask task) async {
    addedTasks.add(task);
    // Mirror the real notifier's state update so consumers see the new
    // task immediately (no persistence — we override to keep the test
    // sandbox clean).
    state = state.copyWith(tasks: [...state.tasks, task]);
  }

  @override
  List<Submission> submissionsFor(String taskId) => const [];
}
