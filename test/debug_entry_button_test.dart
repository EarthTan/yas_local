import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yas_local/models/settings.dart';
import 'package:yas_local/providers/settings_provider.dart';
import 'package:yas_local/widgets/debug_entry_button.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier({required this.debugMode}) {
    state = AppSettings(debugMode: debugMode);
  }
  final bool debugMode;
}

Widget _harness({
  required bool debugMode,
  GoRouter? router,
}) {
  return ProviderScope(
    overrides: [
      settingsProvider.overrideWith((_) => _FakeSettingsNotifier(debugMode: debugMode)),
    ],
    child: router == null
        ? MaterialApp(
            home: Scaffold(
              appBar: AppBar(
                title: const Text('Origin'),
                actions: const [DebugEntryButton()],
              ),
            ),
          )
        : MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('shows 🐞 icon when settings.debugMode is true', (tester) async {
    await tester.pumpWidget(_harness(debugMode: true));
    expect(find.byIcon(Icons.bug_report), findsOneWidget);
  });

  testWidgets('hides 🐞 icon when settings.debugMode is false', (tester) async {
    await tester.pumpWidget(_harness(debugMode: false));
    expect(find.byIcon(Icons.bug_report), findsNothing);
  });

  testWidgets('tapping pushes /debug (preserves history, can pop)', (tester) async {
    final router = GoRouter(
      initialLocation: '/some',
      routes: [
        GoRoute(
          path: '/some',
          builder: (_, _) => Scaffold(
            appBar: AppBar(
              title: const Text('Origin'),
              actions: const [DebugEntryButton()],
            ),
          ),
        ),
        GoRoute(
          path: '/debug',
          builder: (_, _) => Scaffold(
            appBar: AppBar(title: const Text('Debug')),
            body: const Center(child: Text('DebugScreen')),
          ),
        ),
      ],
    );
    await tester.pumpWidget(_harness(debugMode: true, router: router));
    await tester.tap(find.byIcon(Icons.bug_report));
    await tester.pumpAndSettle();
    expect(find.text('DebugScreen'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
  });
}
