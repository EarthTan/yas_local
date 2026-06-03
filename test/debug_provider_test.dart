import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yas_local/providers/debug_provider.dart';
import 'package:yas_local/services/debug_service.dart';

void main() {
  setUp(() {
    DebugService.instance.resetForTest();
    DebugService.instance.setEnabled(true);
  });

  test('initial state reflects service', () {
    DebugService.instance.recordEvent(scope: 's', message: 'hi');
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final state = container.read(debugProvider);
    expect(state.events, hasLength(1));
    expect(state.events.single.message, 'hi');
  });

  test('refresh() pulls new data from service', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(debugProvider.notifier);
    expect(notifier.state.events, isEmpty);

    DebugService.instance.recordEvent(scope: 's', message: 'after');
    notifier.refresh();
    expect(notifier.state.events.single.message, 'after');
  });
}
