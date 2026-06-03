import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yas_local/models/settings.dart';
import 'package:yas_local/providers/settings_provider.dart';
import 'package:yas_local/services/debug_service.dart';

void main() {
  setUp(() {
    DebugService.instance.resetForTest();
  });

  test('update() preserves existing snapshot tasks and references', () async {
    // Pre-populate the snapshot with tasks + references, as TaskNotifier
    // would after loading.
    DebugService.instance.refreshStateSnapshot(
      tasks: ['task-A', 'task-B'],
      references: ['ref-1'],
      settings: const AppSettings(apiKey: '***', vlModel: 'm'),
    );

    final container = ProviderContainer();
    addTearDown(container.dispose);
    // Drive update() to a known-good state (load is async; we just call update).
    await container.read(settingsProvider.notifier).update(
          const AppSettings(apiKey: 'new-key', vlModel: 'qwen-vl-max'),
        );

    final snap = DebugService.instance.stateSnapshot!;
    expect(snap.tasks, ['task-A', 'task-B'],
        reason: 'update() must not clobber tasks that TaskNotifier already pushed');
    expect(snap.references, ['ref-1']);
    expect(snap.settings.apiKey, '***', reason: 'apiKey must remain masked in snapshot');
    expect(snap.settings.vlModel, 'qwen-vl-max');
  });

  test('update() with no prior snapshot stores empty lists, not null', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).update(
          const AppSettings(apiKey: 'k'),
        );

    final snap = DebugService.instance.stateSnapshot!;
    expect(snap.tasks, isEmpty);
    expect(snap.references, isEmpty);
  });
}
