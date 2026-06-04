import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:yas_local/screens/strategy_review/bottom_action_bar.dart';
import 'package:yas_local/screens/strategy_review/edit_checkpoint_sheet.dart';
import 'package:yas_local/screens/strategy_review/progress_dots.dart';
import 'package:yas_local/screens/strategy_review/question_page.dart';
import 'package:yas_local/screens/strategy_review_screen.dart';
import 'package:yas_local/services/qwen_service.dart';

class _SeededNotifier extends StrategyNotifier {
  _SeededNotifier(super.ref, this._refs, {super.qwenFactory}) {
    state = StrategyState(references: _refs);
  }
  final List<ReferenceAnswer> _refs;

  @override
  Future<void> loadOrGenerate(String taskId) async {}

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

/// Fake [QwenService] that short-circuits [generateStrategy] to return a
/// pre-seeded [ReferenceAnswer], so retry tests don't hit the network.
class _FakeQwenService extends QwenService {
  _FakeQwenService(this._next) : super(const AppSettings(apiKey: 'k'));
  final ReferenceAnswer _next;

  @override
  Future<ReferenceAnswer> generateStrategy({
    required RubricItem rubricItem,
    required List<String> questionPaperPaths,
    required List<String> answerImagePaths,
    int totalQuestions = 0,
  }) async =>
      _next;
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required List<ReferenceAnswer> refs,
  required GradingTask task,
  QwenService Function(Ref ref)? qwenFactory,
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
          (ref) => _SeededNotifier(ref, refs, qwenFactory: qwenFactory),
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
  testWidgets('EditCheckpointSheet 编辑模式：保存按钮初始 enabled', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditCheckpointSheet(
            mode: EditCheckpointMode.edit,
            initialDescription: 'A',
            initialPoints: 3,
            currentTotal: 5,
            onSave: (_, _) {},
            onDelete: () {},
          ),
        ),
      ),
    );
    expect(find.text('A'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    final FilledButton save = tester.widget(find.widgetWithText(FilledButton, '保存'));
    expect(save.onPressed, isNotNull);
  });

  testWidgets('EditCheckpointSheet 描述清空后保存按钮 disabled', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditCheckpointSheet(
            mode: EditCheckpointMode.edit,
            initialDescription: 'A',
            initialPoints: 3,
            currentTotal: 5,
            onSave: (_, _) {},
            onDelete: () {},
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump();
    final FilledButton save = tester.widget(find.widgetWithText(FilledButton, '保存'));
    expect(save.onPressed, isNull);
  });

  testWidgets('EditCheckpointSheet 单个 4 分 checkpoint：合计显示 4（不是 0）', (tester) async {
    // Bug 1+2：之前公式 currentTotal + _points - initialPoints 在「唯一一个
    // checkpoint = 4 分」时算出 0 + 4 - 4 = 0，错误地提示「总分不足 4」。
    // 修正后期望：合计 = 4，与 maxPoints 一致，不显示警告。
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditCheckpointSheet(
            mode: EditCheckpointMode.edit,
            initialDescription: '答对',
            initialPoints: 4,
            currentTotal: 0, // sum of OTHER checkpoints (this is the only one)
            maxPoints: 4,
            onSave: (_, _) {},
            onDelete: () {},
          ),
        ),
      ),
    );
    // 没有警告。
    expect(find.textContaining('全部 checkpoint 分值合计'), findsNothing);
  });

  testWidgets('EditCheckpointSheet 多 checkpoint：合计随 _points 变化', (tester) async {
    // Bug 1+2：3 个其他 checkpoint 各 1 分（合计 3），当前编辑项初始 1 分。
    // 修正后期望：合计 = 3 + 1 = 4（与 maxPoints 一致），不显示警告。
    // 把当前项调到 2 分后，合计应为 3 + 2 = 5（与 maxPoints 不一致，显示警告）。
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditCheckpointSheet(
            mode: EditCheckpointMode.edit,
            initialDescription: 'X',
            initialPoints: 1,
            currentTotal: 3,
            maxPoints: 4,
            onSave: (_, _) {},
            onDelete: () {},
          ),
        ),
      ),
    );
    expect(find.textContaining('全部 checkpoint 分值合计'), findsNothing);

    // 点 + 把分值调到 2。
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
    expect(find.textContaining('全部 checkpoint 分值合计 = 5'), findsOneWidget);
  });

  testWidgets('EditCheckpointSheet 添加模式没有删除按钮', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditCheckpointSheet(
            mode: EditCheckpointMode.add,
            initialDescription: '',
            initialPoints: 1,
            currentTotal: 0,
            onSave: (_, _) {},
          ),
        ),
      ),
    );
    expect(find.text('删除'), findsNothing);
    expect(find.text('保存'), findsOneWidget);
  });

  testWidgets('ProgressDots 渲染 N 个点、当前页高亮', (tester) async {
    var tapped = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProgressDots(
            count: 4,
            currentIndex: 1,
            confirmed: const [true, false, false, false],
            failed: const [false, false, false, false],
            onTap: (i) => tapped = i,
          ),
        ),
      ),
    );
    // Tap dot 3 (index 2)
    await tester.tap(find.byType(GestureDetector).at(2));
    await tester.pump();
    expect(tapped, 2);
  });

  testWidgets('BottomActionBar 未确认时显示「确认此题」、最后一题时「已是最后一题」disabled', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BottomActionBar(
            confirmed: false,
            isLast: true,
            isRefining: false,
            onRefine: () {},
            onConfirm: () {},
            onNext: () {},
          ),
        ),
      ),
    );
    expect(find.text('确认此题'), findsOneWidget);
    expect(find.text('已是最后一题'), findsOneWidget);
    // 「已是最后一题」应该是 disabled 的 OutlinedButton —— 仅检查文本存在
  });

  testWidgets('BottomActionBar 未确认时显示「确认此题」、非最后一题时「下一题 →」enabled', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BottomActionBar(
            confirmed: false,
            isLast: false,
            isRefining: false,
            onRefine: () {},
            onConfirm: () {},
            onNext: () {},
          ),
        ),
      ),
    );
    expect(find.text('确认此题'), findsOneWidget);
    expect(find.text('下一题 →'), findsOneWidget);
  });

  testWidgets('BottomActionBar 已确认时显示「已确认」', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BottomActionBar(
            confirmed: true,
            isLast: false,
            isRefining: false,
            onRefine: () {},
            onConfirm: () {},
            onNext: () {},
          ),
        ),
      ),
    );
    expect(find.text('已确认'), findsOneWidget);
  });

  testWidgets('BottomActionBar 三个按钮分别触发各自的 callback', (tester) async {
    var refineCount = 0;
    var confirmCount = 0;
    var nextCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BottomActionBar(
            confirmed: false,
            isLast: false,
            isRefining: false,
            onRefine: () => refineCount++,
            onConfirm: () => confirmCount++,
            onNext: () => nextCount++,
          ),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, '修改策略'));
    await tester.pump();
    expect(refineCount, 1);
    expect(confirmCount, 0);
    expect(nextCount, 0);

    await tester.tap(find.widgetWithText(FilledButton, '确认此题'));
    await tester.pump();
    expect(refineCount, 1);
    expect(confirmCount, 1);
    expect(nextCount, 0);

    await tester.tap(find.widgetWithText(OutlinedButton, '下一题 →'));
    await tester.pump();
    expect(refineCount, 1);
    expect(confirmCount, 1);
    expect(nextCount, 1);
  });

  testWidgets('BottomActionBar disabled 状态：isLast 禁用 next、isRefining 禁用 refine + confirm', (tester) async {
    // Scenario A: isLast: true → next 按钮 disabled，其余 enabled
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BottomActionBar(
            confirmed: false,
            isLast: true,
            isRefining: false,
            onRefine: () {},
            onConfirm: () {},
            onNext: () {},
          ),
        ),
      ),
    );
    expect(
      tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '已是最后一题')).onPressed,
      isNull,
    );
    expect(
      tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '修改策略')).onPressed,
      isNotNull,
    );
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '确认此题')).onPressed,
      isNotNull,
    );

    // Scenario B: isRefining: true → refine + confirm disabled，next enabled
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BottomActionBar(
            confirmed: false,
            isLast: false,
            isRefining: true,
            onRefine: () {},
            onConfirm: () {},
            onNext: () {},
          ),
        ),
      ),
    );
    expect(
      tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '修改策略')).onPressed,
      isNull,
    );
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '确认此题')).onPressed,
      isNull,
    );
    expect(
      tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '下一题 →')).onPressed,
      isNotNull,
    );
  });

  testWidgets('QuestionPage 渲染 checkpoint 描述与分值', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuestionPage(
            reference: const ReferenceAnswer(
              questionNumber: 1,
              checkpoints: [
                CheckpointDef(id: 'q1-cp0', description: '答对', points: 3),
                CheckpointDef(id: 'q1-cp1', description: '完整', points: 2),
              ],
            ),
            maxPoints: 5,
            questionType: '主观题',
            onEditCheckpoint: (_, _) {},
            onAddCheckpoint: () {},
            onRetry: () {},
          ),
        ),
      ),
    );
    expect(find.text('答对'), findsOneWidget);
    expect(find.text('完整'), findsOneWidget);
    expect(find.text('3分'), findsOneWidget);
    expect(find.text('2分'), findsOneWidget);
  });

  testWidgets('QuestionPage 点击 checkpoint 行触发 onEditCheckpoint', (tester) async {
    var editId = '';
    var editCpDescription = '';
    var editCpPoints = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuestionPage(
            reference: const ReferenceAnswer(
              questionNumber: 1,
              checkpoints: [
                CheckpointDef(id: 'q1-cp0', description: '答对', points: 3),
                CheckpointDef(id: 'q1-cp1', description: '完整', points: 2),
              ],
            ),
            maxPoints: 5,
            questionType: '主观题',
            onEditCheckpoint: (id, cp) {
              editId = id;
              editCpDescription = cp.description;
              editCpPoints = cp.points;
            },
            onAddCheckpoint: () {},
          ),
        ),
      ),
    );
    // Tap the first checkpoint row via its description text's InkWell ancestor.
    final firstRow = find.ancestor(of: find.text('答对'), matching: find.byType(InkWell));
    await tester.tap(firstRow);
    await tester.pump();
    expect(editId, 'q1-cp0');
    expect(editCpDescription, '答对');
    expect(editCpPoints, 3);
  });

  testWidgets('QuestionPage 失败状态渲染 banner 和重试按钮，点击触发 onRetry', (tester) async {
    var retryCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuestionPage(
            reference: const ReferenceAnswer(
              questionNumber: 2,
              checkpoints: [],
            ),
            maxPoints: 5,
            questionType: '主观题',
            onEditCheckpoint: (_, _) {},
            onAddCheckpoint: () {},
            onRetry: () => retryCount++,
          ),
        ),
      ),
    );
    expect(find.text('该题生成失败'), findsOneWidget);
    expect(find.text('重试此题'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '重试此题'));
    await tester.pump();
    expect(retryCount, 1);
  });

  testWidgets('QuestionPage checkpoint 分值合计与满分不一致时显示警告', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuestionPage(
            reference: const ReferenceAnswer(
              questionNumber: 3,
              checkpoints: [
                CheckpointDef(id: 'q3-cp0', description: '答对', points: 3),
                CheckpointDef(id: 'q3-cp1', description: '完整', points: 2),
              ],
            ),
            maxPoints: 7, // sum is 5, but max is 7
            questionType: '主观题',
            onEditCheckpoint: (_, _) {},
            onAddCheckpoint: () {},
          ),
        ),
      ),
    );
    expect(find.text('总分 = 5（与满分不一致，请确认是否需要调整）'), findsOneWidget);
  });

  testWidgets('QuestionPage 点击「添加得分点」触发 onAddCheckpoint', (tester) async {
    var addCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuestionPage(
            reference: const ReferenceAnswer(
              questionNumber: 1,
              checkpoints: [
                CheckpointDef(id: 'q1-cp0', description: '答对', points: 5),
              ],
            ),
            maxPoints: 5,
            questionType: '主观题',
            onEditCheckpoint: (_, _) {},
            onAddCheckpoint: () => addCount++,
          ),
        ),
      ),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, '添加得分点'));
    await tester.pump();
    expect(addCount, 1);
  });

  group('StrategyReviewScreen PageView 集成', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Mock path_provider so TaskNotifier constructor (called by the real
    // provider when not overridden) doesn't blow up during widget tests.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => '/tmp',
    );

    testWidgets('StrategyReviewScreen PageView 渲染 N 页', (tester) async {
      final refs = [
        for (var i = 1; i <= 3; i++)
          ReferenceAnswer(
            questionNumber: i,
            checkpoints: [CheckpointDef(id: 'q$i-cp0', description: 'A', points: 1)],
          ),
      ];
      final task = _taskWithRubricForScreen(const [
        RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 1),
        RubricItem(questionNumber: 2, type: 'subjective', maxPoints: 1),
        RubricItem(questionNumber: 3, type: 'subjective', maxPoints: 1),
      ]);
      await _pumpScreen(tester, refs: refs, task: task);
      expect(find.byType(PageView), findsOneWidget);
      expect(find.text('第 1 题'), findsOneWidget);
    });

    testWidgets('确认此题 后 state.confirmed = true 并 auto-advance', (tester) async {
      final refs = [
        ReferenceAnswer(
          questionNumber: 1,
          checkpoints: const [CheckpointDef(id: 'q1-cp0', description: 'A', points: 1)],
        ),
        ReferenceAnswer(
          questionNumber: 2,
          checkpoints: const [CheckpointDef(id: 'q2-cp0', description: 'A', points: 1)],
        ),
      ];
      final task = _taskWithRubricForScreen(const [
        RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 1),
        RubricItem(questionNumber: 2, type: 'subjective', maxPoints: 1),
      ]);
      await _pumpScreen(tester, refs: refs, task: task);
      await tester.tap(find.text('确认此题'));
      await tester.pumpAndSettle();
      // After confirm, auto-advance to the next unconfirmed (page 1 = 第 2 题)
      expect(find.text('第 2 题'), findsOneWidget);
    });

    testWidgets('进度点 tap 跳到指定题', (tester) async {
      final refs = [
        for (var i = 1; i <= 3; i++)
          ReferenceAnswer(
            questionNumber: i,
            checkpoints: [CheckpointDef(id: 'q$i-cp0', description: 'A', points: 1)],
          ),
      ];
      final task = _taskWithRubricForScreen(const [
        RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 1),
        RubricItem(questionNumber: 2, type: 'subjective', maxPoints: 1),
        RubricItem(questionNumber: 3, type: 'subjective', maxPoints: 1),
      ]);
      await _pumpScreen(tester, refs: refs, task: task);
      // Tap the 3rd progress dot via ProgressDots descendants
      final allDots = find.descendant(
        of: find.byType(ProgressDots),
        matching: find.byType(GestureDetector),
      );
      await tester.tap(allDots.at(2));
      await tester.pumpAndSettle();
      expect(find.text('第 3 题'), findsOneWidget);
    });

    testWidgets('点击 checkpoint 打开 EditCheckpointSheet', (tester) async {
      final refs = [
        ReferenceAnswer(
          questionNumber: 1,
          checkpoints: const [CheckpointDef(id: 'q1-cp0', description: '答对', points: 3)],
        ),
      ];
      final task = _taskWithRubricForScreen(const [
        RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 3),
      ]);
      await _pumpScreen(tester, refs: refs, task: task);
      // Find the checkpoint row via the InkWell ancestor of the description text.
      final row = find.ancestor(of: find.text('答对'), matching: find.byType(InkWell));
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.byType(EditCheckpointSheet), findsOneWidget);
    });

    testWidgets('Edit sheet 保存 更新 description 并关闭 sheet', (tester) async {
      final refs = [
        ReferenceAnswer(
          questionNumber: 1,
          checkpoints: const [CheckpointDef(id: 'q1-cp0', description: '答对', points: 3)],
        ),
      ];
      final task = _taskWithRubricForScreen(const [
        RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 3),
      ]);
      await _pumpScreen(tester, refs: refs, task: task);
      // Open the edit sheet.
      final row = find.ancestor(of: find.text('答对'), matching: find.byType(InkWell));
      await tester.tap(row);
      await tester.pumpAndSettle();
      // Modify the description in the sheet.
      await tester.enterText(find.byType(TextField).first, '新描述');
      await tester.pump();
      // Tap 保存.
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      // Sheet should be gone; the new description should appear on the page.
      expect(find.byType(EditCheckpointSheet), findsNothing);
      expect(find.text('新描述'), findsOneWidget);
      expect(find.text('答对'), findsNothing);
    });

    testWidgets('点击「添加得分点」并保存，checkpoint 数量 +1 且显示新描述', (tester) async {
      final refs = [
        ReferenceAnswer(
          questionNumber: 1,
          checkpoints: const [CheckpointDef(id: 'q1-cp0', description: '答对', points: 3)],
        ),
      ];
      final task = _taskWithRubricForScreen(const [
        RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 5),
      ]);
      await _pumpScreen(tester, refs: refs, task: task);
      // Tap 「添加得分点」.
      await tester.tap(find.widgetWithText(OutlinedButton, '添加得分点'));
      await tester.pumpAndSettle();
      // The add sheet should be open with an empty description.
      expect(find.byType(EditCheckpointSheet), findsOneWidget);
      // Fill the description and save.
      await tester.enterText(find.byType(TextField).first, '新加的');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      // Sheet gone, new description visible alongside the original.
      expect(find.byType(EditCheckpointSheet), findsNothing);
      expect(find.text('新加的'), findsOneWidget);
      expect(find.text('答对'), findsOneWidget);
    });

    testWidgets('失败题 点重试 后 checkpoints 被新生成结果替换', (tester) async {
      final refs = [
        // Failed: empty checkpoints.
        const ReferenceAnswer(questionNumber: 1, checkpoints: []),
      ];
      final task = _taskWithRubricForScreen(const [
        RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 5),
      ]);

      // Fake QwenService — its generateStrategy returns a successful reference
      // with non-empty checkpoints, simulating a successful retry.
      const replacement = ReferenceAnswer(
        questionNumber: 1,
        checkpoints: [CheckpointDef(id: 'q1-cp0', description: '新策略', points: 5)],
      );
      final fakeQwen = _FakeQwenService(replacement);

      await _pumpScreen(
        tester,
        refs: refs,
        task: task,
        qwenFactory: (_) => fakeQwen,
      );
      // Failure banner + retry button visible.
      expect(find.text('该题生成失败'), findsOneWidget);
      expect(find.text('重试此题'), findsOneWidget);
      // Tap retry.
      await tester.tap(find.widgetWithText(FilledButton, '重试此题'));
      await tester.pumpAndSettle();
      // Replacement checkpoint should now be on the page.
      expect(find.text('该题生成失败'), findsNothing);
      expect(find.text('新策略'), findsOneWidget);
    });

    testWidgets('3 题场景：失败题点重试后列表长度仍为 3', (tester) async {
      // Bug 复现：3 题 rubric，第 2 题失败；用户对第 2 题点「重试此题」
      // 之后，期望 progress dots、pageview、title 仍对应 3 题。
      final refs = [
        ReferenceAnswer(
          questionNumber: 1,
          checkpoints: const [CheckpointDef(id: 'q1-cp0', description: 'A1', points: 5)],
        ),
        const ReferenceAnswer(
          questionNumber: 2,
          checkpoints: [],
          hasConsensus: false,
        ),
        ReferenceAnswer(
          questionNumber: 3,
          checkpoints: const [CheckpointDef(id: 'q3-cp0', description: 'A3', points: 5)],
        ),
      ];
      final task = _taskWithRubricForScreen(const [
        RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 5),
        RubricItem(questionNumber: 2, type: 'subjective', maxPoints: 5),
        RubricItem(questionNumber: 3, type: 'subjective', maxPoints: 5),
      ]);

      // Fake QwenService — simulate successful retry.
      const replacement = ReferenceAnswer(
        questionNumber: 2,
        checkpoints: [CheckpointDef(id: 'q2-cp0', description: '新策略 q2', points: 5)],
      );
      final fakeQwen = _FakeQwenService(replacement);

      await _pumpScreen(
        tester,
        refs: refs,
        task: task,
        qwenFactory: (_) => fakeQwen,
      );

      // 重试前：3 个 progress dots，title 是 1/3。
      final dots = find.descendant(
        of: find.byType(ProgressDots),
        matching: find.byType(GestureDetector),
      );
      expect(dots, findsNWidgets(3), reason: '重试前应有 3 个 progress dots');
      expect(find.text('批改策略  ·  1/3'), findsOneWidget);

      // 跳到第 2 题：用 progress dot 2（index 1）。
      await tester.tap(dots.at(1));
      await tester.pumpAndSettle();
      expect(find.text('第 2 题'), findsOneWidget);
      expect(find.text('重试此题'), findsOneWidget);

      // 点重试。
      await tester.tap(find.widgetWithText(FilledButton, '重试此题'));
      await tester.pumpAndSettle();

      // 关键断言：列表里仍是 3 题，没有变 4 题。
      final dotsAfter = find.descendant(
        of: find.byType(ProgressDots),
        matching: find.byType(GestureDetector),
      );
      expect(dotsAfter, findsNWidgets(3),
          reason: '重试后 progress dots 应仍为 3 个，不应多出一个');
      expect(find.text('第 4 题'), findsNothing,
          reason: '不应出现「第 4 题」');

      // 重试结果应该出现在第 2 题的页面上。
      expect(find.text('该题生成失败'), findsNothing,
          reason: '重试成功后失败 banner 应消失');
      expect(find.text('新策略 q2'), findsOneWidget);
    });
  });
}
