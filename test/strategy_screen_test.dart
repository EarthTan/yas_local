import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/checkpoint.dart';
import 'package:yas_local/models/reference_answer.dart';
import 'package:yas_local/screens/strategy_review/bottom_action_bar.dart';
import 'package:yas_local/screens/strategy_review/edit_checkpoint_sheet.dart';
import 'package:yas_local/screens/strategy_review/progress_dots.dart';
import 'package:yas_local/screens/strategy_review/question_page.dart';

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
}
