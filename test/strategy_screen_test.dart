import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/screens/strategy_review/edit_checkpoint_sheet.dart';

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
    expect(find.text('保存'), findsOneWidget);
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
}
