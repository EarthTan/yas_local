import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yas_local/providers/grading_provider.dart';
import 'package:yas_local/screens/grading_screen.dart';
import 'package:yas_local/screens/settings_screen.dart';

class _FakeGradingNotifier extends GradingNotifier {
  _FakeGradingNotifier() : super(_DummyRef());

  @override
  Future<void> runPhase2Only(String taskId) async {
    // no-op: state is set directly by the test, and we don't want
    // the real runPhase2Only to touch the dummy ref.
  }
}

class _DummyRef implements Ref {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used in this test');
}

void main() {
  testWidgets(
    'grading error → "去设置" → settings has back button (regression: was context.go which left no back button)',
    (tester) async {
      final router = GoRouter(
        initialLocation: '/grading',
        routes: [
          GoRoute(
            path: '/grading',
            builder: (_, _) => const GradingScreen(taskId: 't1'),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, _) => const SettingsScreen(),
          ),
        ],
      );

      final fake = _FakeGradingNotifier();
      // Force the error state the screen renders the "去设置" button for.
      fake.state = const GradingProgress(error: '未配置 API Key，请先到设置填写');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            gradingProvider.overrideWith((_) => fake),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      // Sanity: error UI is showing, with the "去设置" button.
      expect(find.text('去设置'), findsOneWidget);

      await tester.tap(find.text('去设置'));
      await tester.pumpAndSettle();

      // We arrived at /settings.
      expect(find.text('API 设置'), findsOneWidget);

      // The regression: a back button must be present, meaning the
      // navigation was a push (preserves history) not a go (replaces stack).
      expect(find.byType(BackButton), findsOneWidget);
    },
  );
}
