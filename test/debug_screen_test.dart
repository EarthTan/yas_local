import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yas_local/services/debug/debug_service.dart';
import 'package:yas_local/screens/debug/debug_screen.dart';

void main() {
  setUp(() {
    DebugService.instance.resetForTest();
    DebugService.instance.setEnabled(true);
  });

  testWidgets('renders DebugScreen with 4 tabs', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: DebugScreen()),
      ),
    );
    expect(find.text('Qwen 调用'), findsOneWidget);
    expect(find.text('事件'), findsOneWidget);
    expect(find.text('状态'), findsOneWidget);
    expect(find.text('JSON 解析'), findsOneWidget);
  });

  testWidgets('Qwen tab shows empty state when no calls', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: DebugScreen()),
      ),
    );
    expect(find.text('暂无 Qwen 调用记录'), findsOneWidget);
  });

  testWidgets('Events tab shows empty state when no events', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: DebugScreen()),
      ),
    );
    // Switch to events tab (tab index 1)
    await tester.tap(find.text('事件'));
    await tester.pumpAndSettle();
    expect(find.text('暂无事件'), findsOneWidget);
  });

  testWidgets('State tab shows empty state when no snapshot', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: DebugScreen()),
      ),
    );
    await tester.tap(find.text('状态'));
    await tester.pumpAndSettle();
    expect(find.text('暂无状态快照'), findsOneWidget);
  });

  testWidgets('Json tab shows empty state when no attempts', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: DebugScreen()),
      ),
    );
    await tester.tap(find.text('JSON 解析'));
    await tester.pumpAndSettle();
    expect(find.text('暂无 JSON 解析记录'), findsOneWidget);
  });

  testWidgets('Qwen tab renders a recorded call', (tester) async {
    DebugService.instance.recordQwenCall(QwenCallRecord(
      timestamp: DateTime.now(),
      scope: 'identify',
      model: 'qwen-vl-max',
      endpoint: '/chat/completions',
      statusCode: 200,
      elapsedMs: 1234,
      status: QwenCallStatus.ok,
      messages: const [],
    ));
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: DebugScreen()),
      ),
    );
    // The card title contains the elapsed time
    expect(find.textContaining('1234ms'), findsOneWidget);
  });

  testWidgets('Qwen tab auto-rerenders when a new call is recorded after mount',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: DebugScreen()),
      ),
    );
    expect(find.text('暂无 Qwen 调用记录'), findsOneWidget);

    // Record a call after the screen is mounted — no manual refresh allowed.
    DebugService.instance.recordQwenCall(QwenCallRecord(
      timestamp: DateTime.now(),
      scope: 'grade',
      model: 'qwen-vl-max',
      endpoint: '/chat/completions',
      statusCode: 200,
      elapsedMs: 5678,
      status: QwenCallStatus.ok,
      messages: const [],
    ));
    await tester.pump();
    expect(find.text('暂无 Qwen 调用记录'), findsNothing);
    expect(find.textContaining('5678ms'), findsOneWidget);
  });
}
