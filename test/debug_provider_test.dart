import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yas_local/providers/debug_provider.dart';
import 'package:yas_local/services/debug/debug_service.dart';

void main() {
  setUp(() {
    DebugService.instance.resetForTest();
    DebugService.instance.setEnabled(true);
  });

  test('initial state reflects service', () async {
    DebugService.instance.recordEvent(scope: 's', message: 'hi');
    await Future<void>.delayed(Duration.zero);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final state = container.read(debugProvider);
    expect(state.events, hasLength(1));
    expect(state.events.single.message, 'hi');
  });

  test('refresh() pulls new data from service', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(debugProvider.notifier);
    expect(notifier.state.events, isEmpty);

    DebugService.instance.recordEvent(scope: 's', message: 'after');
    await Future<void>.delayed(Duration.zero);
    notifier.refresh();
    expect(notifier.state.events.single.message, 'after');
  });

  test('auto-refreshes when service changes after construction', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(debugProvider.notifier);
    expect(notifier.state.events, isEmpty);

    // No manual refresh() call — provider should pick up the change via the
    // service's Listenable.
    DebugService.instance.recordEvent(scope: 's', message: 'auto');
    // record* is void async — let the microtask queue drain so the listener
    // (which fires inside _dispatch after the buffer is updated) gets a
    // chance to run.
    await Future<void>.delayed(Duration.zero);
    expect(notifier.state.events.single.message, 'auto');
  });

  test('auto-refreshes on recordQwenCall too', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(debugProvider.notifier);
    expect(notifier.state.qwenCalls, isEmpty);

    DebugService.instance.recordQwenCall(QwenCallRecord(
      timestamp: DateTime.now(),
      scope: 'identify',
      model: 'm',
      endpoint: '/chat/completions',
      statusCode: 200,
      elapsedMs: 1,
      status: QwenCallStatus.ok,
      messages: const [],
      responseContent: 'payload',
    ));
    await Future<void>.delayed(Duration.zero);
    expect(notifier.state.qwenCalls.single.responseContent, 'payload');
  });
}
