import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:yas_local/models/submission.dart';
import 'package:yas_local/models/task.dart';
import 'package:yas_local/providers/task_provider.dart';
import 'package:yas_local/screens/capture_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // path_provider is required by the real TaskNotifier (TaskStore.save runs
  // inside addTask/replaceSubmissions) and by ImageStore.persist in the
  // widget-test flow. Direct both to a tmp dir so the test never touches
  // the real application support directory.
  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('capture_screen_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test(
    'TaskNotifier.replaceSubmissions exists and replaces, not appends',
    () async {
      // Verifies the rename (setSubmissions → replaceSubmissions) succeeded
      // and the method still behaves as "replace for this taskId" — the bug
      // C-1 fix renames the API to match this behavior, and the capture
      // screen gates the call on a confirm dialog.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(taskProvider.notifier);

      // Let the constructor's _load() settle.
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      await notifier.addTask(GradingTask(
        id: 't1',
        name: 'T1',
        subject: 'math',
        createdAt: DateTime(2026),
        rubric: const [],
        questionPaperPaths: const [],
        answerImagePaths: const [],
      ));

      // First batch: 2 submissions.
      await notifier.replaceSubmissions('t1', const [
        Submission(id: 'a1', taskId: 't1', label: 'A1'),
        Submission(id: 'a2', taskId: 't1', label: 'A2'),
      ]);
      expect(notifier.submissionsFor('t1').length, 2);

      // Second batch: 1 submission. Must REPLACE (not append) — this is
      // what makes the rename honest and what the capture screen now warns
      // about before invoking.
      await notifier.replaceSubmissions('t1', const [
        Submission(id: 'b1', taskId: 't1', label: 'B1'),
      ]);
      final after = notifier.submissionsFor('t1');
      expect(after.length, 1,
          reason:
              'replaceSubmissions must REPLACE the prior batch for this taskId');
      expect(after.first.id, 'b1');
    },
  );

  test('CaptureScreen widget type is exported', () {
    // Trivial structural assertion — keeps the capture_screen.dart import
    // load-bearing so the post-rename call site (replaceSubmissions) is
    // type-checked at test compile time.
    expect(const CaptureScreen(taskId: 't1'), isA<Widget>());
  });

  group('confirm-overwrite dialog (C-1 regression test)', () {
    // Pretends the task already has one submission for t1. Same pattern
    // as `test/results_partial_test.dart::_FakeTaskNotifier`: do not seed
    // `state` (the parent _load() overwrites it). Instead override the
    // read methods to return pre-seeded data, and override
    // replaceSubmissions to count calls + mutate the real state.
    late _PretendExistingTaskNotifier notifier;
    late GoRouter router;
    late File photoFile;

    setUp(() {
      router = GoRouter(
        initialLocation: '/tasks/t1/capture',
        routes: [
          GoRoute(
            path: '/tasks/:id/capture',
            builder: (_, _) => const CaptureScreen(taskId: 't1'),
          ),
          GoRoute(
            path: '/tasks/:id',
            builder: (_, _) => const Scaffold(body: Text('task detail')),
          ),
        ],
      );
      // The widget test stages one real on-disk file so ImageStore.persist
      // can copy it into the mocked application-documents directory.
      photoFile = File('${tmp.path}/staged.jpg');
      photoFile.writeAsBytesSync([0, 1, 2, 3]);
    });

    /// Builds a ProviderScope that wires the recording notifier under
    /// `taskProvider`. The override factory is a thunk that closes over
    /// the notifier instance so the test code can read back its counters
    /// and state after widget actions.
    Widget harness() => ProviderScope(
          overrides: [
            taskProvider.overrideWith((ref) {
              notifier = _PretendExistingTaskNotifier(
                ref: ref,
                existing: const [
                  Submission(id: 'preexisting', taskId: 't1', label: 'old'),
                ],
              );
              return notifier;
            }),
          ],
          child: MaterialApp.router(routerConfig: router),
        );

    testWidgets(
        'shows 确认覆盖 dialog when existing submissions exist; '
        '取消 keeps prior submission', (tester) async {
      await tester.pumpWidget(harness());
      // Touch a context-bound ProviderContainer element so the override
      // factory runs and `notifier` is initialized.
      final element = tester.element(find.byType(CaptureScreen));
      // ignore: invalid_use_of_protected_member
      ProviderScope.containerOf(element).read(taskProvider.notifier);
      // Let the parent _load() Future settle so it stops overwriting
      // state after the test stages photos.
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }

      // No dialog before the user opts in.
      expect(find.byType(AlertDialog), findsNothing);

      // Stage a photo via the test seam, then trigger the "下一步" action.
      final state =
          tester.state<CaptureScreenState>(find.byType(CaptureScreen));
      state.debugStagePhotos([photoFile]);
      await tester.pump();

      // Tap the action and let the real file I/O + dialog microtask
      // settle. The ImageStore.persist loop touches the real filesystem
      // (File.copy), so it must run inside runAsync. We then pump a few
      // frames to render the dialog.
      await tester.runAsync(() async {
        await tester.tap(find.text('下一步 (1)'));
        // Let the persist + dialog scheduling finish on the host loop.
        for (var i = 0; i < 5; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.byType(AlertDialog), findsOneWidget,
          reason:
              'Confirm dialog must appear before replaceSubmissions is called');
      expect(find.text('确认覆盖'), findsOneWidget);
      expect(find.text('已有 1 份作业。再次上传将覆盖之前的全部。是否继续？'),
          findsOneWidget);

      // Tap 取消. Dialog dismisses, replaceSubmissions is NEVER invoked, and
      // the prior submission is still in the recorded state.
      await tester.runAsync(() async {
        await tester.tap(find.text('取消'));
        for (var i = 0; i < 10; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.byType(AlertDialog), findsNothing);
      expect(notifier.replaceCallCount, 0,
          reason: '取消 must not call replaceSubmissions');
      // Pre-existing submission must still be visible to the screen via
      // submissionsFor (state may be empty after _load, but the override
      // still returns the seeded list).
      expect(notifier.submissionsFor('t1'), hasLength(1));
      expect(notifier.submissionsFor('t1').single.id, 'preexisting');
    });

    testWidgets(
        'tapping 覆盖 calls replaceSubmissions and navigates', (tester) async {
      await tester.pumpWidget(harness());
      final element = tester.element(find.byType(CaptureScreen));
      // ignore: invalid_use_of_protected_member
      ProviderScope.containerOf(element).read(taskProvider.notifier);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }

      final state =
          tester.state<CaptureScreenState>(find.byType(CaptureScreen));
      state.debugStagePhotos([photoFile]);
      await tester.pump();

      await tester.runAsync(() async {
        await tester.tap(find.text('下一步 (1)'));
        for (var i = 0; i < 5; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byType(AlertDialog), findsOneWidget);

      // Confirm the overwrite. After this, replaceSubmissions runs and the
      // screen navigates away via pushReplacement.
      await tester.runAsync(() async {
        await tester.tap(find.text('覆盖'));
        for (var i = 0; i < 5; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(notifier.replaceCallCount, 1,
          reason: '覆盖 must call replaceSubmissions exactly once');
      // The state should now contain exactly the new submission (replaced
      // the empty real-state list with the new ones).
      expect(notifier.state.submissions, hasLength(1));

      // And the post-replace navigation lands on the task detail page.
      expect(find.text('task detail'), findsOneWidget);
    });
  });
}

/// TaskNotifier fake that pretends the task already has one submission
/// for t1 (so the capture screen's "确认覆盖" branch fires).
///
/// We follow the same pattern as
/// `test/results_partial_test.dart::_FakeTaskNotifier`: do not seed
/// `state` in the constructor (the parent `_load()` overwrites it with
/// the empty disk contents anyway), and instead override the *read*
/// methods (`submissionsFor`) to return the pre-seeded list. Then
/// `replaceSubmissions` is the real implementation, but the in-memory
/// state mutation it produces is observable after the user confirms.
class _PretendExistingTaskNotifier extends TaskNotifier {
  _PretendExistingTaskNotifier({
    required Ref ref,
    required List<Submission> existing,
  }) : super(ref);

  final List<Submission> _existing = const [
    Submission(id: 'preexisting', taskId: 't1', label: 'old'),
  ];

  int _replaceCallCount = 0;
  int get replaceCallCount => _replaceCallCount;

  // The capture screen's "existing > 0" check uses submissionsFor. Return
  // the pre-seeded list regardless of what the parent _load() did to
  // `state`.
  @override
  List<Submission> submissionsFor(String taskId) =>
      _existing.where((s) => s.taskId == taskId).toList();

  @override
  Future<void> replaceSubmissions(String taskId, List<Submission> subs) async {
    _replaceCallCount++;
    final others = state.submissions.where((s) => s.taskId != taskId).toList();
    state = state.copyWith(submissions: [...others, ...subs]);
    // Intentionally skip _persist: this is a test fake and would just hit
    // the mocked path_provider. The state mutation is the observable
    // effect the test asserts on.
  }
}
