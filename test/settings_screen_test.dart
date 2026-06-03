import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yas_local/models/settings.dart';
import 'package:yas_local/providers/settings_provider.dart';
import 'package:yas_local/screens/settings_screen.dart';

class _RecordingSettingsNotifier extends SettingsNotifier {
  _RecordingSettingsNotifier({required this.initial});

  final AppSettings initial;
  final List<AppSettings> updates = <AppSettings>[];

  @override
  AppSettings get state => initial;

  @override
  Future<void> update(AppSettings settings) async {
    updates.add(settings);
  }
}

Widget _harness(_RecordingSettingsNotifier notifier) {
  return ProviderScope(
    overrides: [
      settingsProvider.overrideWith((_) => notifier),
    ],
    child: const MaterialApp(home: SettingsScreen()),
  );
}

void main() {
  testWidgets('saving the form preserves debugMode=true', (tester) async {
    final notifier = _RecordingSettingsNotifier(
      initial: const AppSettings(apiKey: 'k', debugMode: true),
    );
    await tester.pumpWidget(_harness(notifier));

    // Tap the "保存" button — debugMode is the toggle right below it.
    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(notifier.updates, hasLength(1));
    expect(notifier.updates.single.debugMode, isTrue,
        reason: '保存 must not silently reset debugMode');
  });

  testWidgets('saving the form preserves debugMode=false', (tester) async {
    final notifier = _RecordingSettingsNotifier(
      initial: const AppSettings(apiKey: 'k', debugMode: false),
    );
    await tester.pumpWidget(_harness(notifier));

    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(notifier.updates.single.debugMode, isFalse);
  });

  testWidgets('debug-mode toggle subtitle lists all 4 entry points', (tester) async {
    final notifier = _RecordingSettingsNotifier(
      initial: const AppSettings(apiKey: 'k'),
    );
    await tester.pumpWidget(_harness(notifier));

    // The subtitle is one long string — find it as a unit and assert each
    // entry point is present in it. (We can't just search for "识别" because
    // the visual-model field above also contains it.)
    final subtitleFinder = find.textContaining('🐞');
    expect(subtitleFinder, findsOneWidget);
    final subtitleText = (tester.widget<Text>(subtitleFinder)).data!;
    expect(subtitleText, contains('主页'));
    expect(subtitleText, contains('识别'));
    expect(subtitleText, contains('策略'));
    expect(subtitleText, contains('批改'));
  });
}
