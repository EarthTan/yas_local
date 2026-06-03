import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:yas_local/models/checkpoint.dart';
import 'package:yas_local/models/reference_answer.dart';
import 'package:yas_local/providers/strategy_provider.dart';
import 'package:yas_local/screens/strategy_review_screen.dart';

// Fake notifier: all strategies pre-confirmed, no API calls or file I/O.
class _AllConfirmedNotifier extends StrategyNotifier {
  _AllConfirmedNotifier(super.ref) {
    state = const StrategyState(
      references: [
        ReferenceAnswer(
          questionNumber: 1,
          checkpoints: [CheckpointDef(id: 'q1-cp0', description: '答对', points: 5)],
          confirmed: true,
        ),
      ],
    );
  }

  @override
  Future<void> loadOrGenerate(String taskId) async {}

  @override
  Future<void> saveAllConfirmed(String taskId) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Mock path_provider so the real TaskNotifier (created when the new
  // StrategyReviewScreen reads taskProvider) doesn't blow up in widget tests.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => '/tmp',
  );

  testWidgets('confirming all strategies navigates to task hub, not grading screen',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/tasks/t1/strategy',
      routes: [
        GoRoute(
          path: '/tasks/:id',
          builder: (_, _) => const Scaffold(body: Text('task-hub')),
        ),
        GoRoute(
          path: '/tasks/:id/strategy',
          builder: (_, s) =>
              StrategyReviewScreen(taskId: s.pathParameters['id']!),
        ),
        GoRoute(
          path: '/tasks/:id/grading',
          builder: (_, _) => const Scaffold(body: Text('grading-screen')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          strategyProvider.overrideWith((ref) => _AllConfirmedNotifier(ref)),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();

    // Find the single FilledButton in the bottom bar (enabled when allConfirmed=true)
    final button = find.byType(FilledButton);
    expect(button, findsOneWidget);

    await tester.tap(button);
    await tester.pumpAndSettle();

    // Must land on task hub, NOT on grading screen
    expect(find.text('task-hub'), findsOneWidget);
    expect(find.text('grading-screen'), findsNothing);
  });
}
