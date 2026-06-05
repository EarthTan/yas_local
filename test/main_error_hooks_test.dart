import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/services/debug/debug_service.dart';
import 'package:yas_local/services/debug/debug_stats.dart';
import 'package:yas_local/services/debug/error_hooks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    DebugService.instance.resetForTest();
    DebugService.instance.setEnabled(true);
    installErrorHooks();
  });

  test('FlutterError.onError records EventRecord with scope flutter_error',
      () async {
    FlutterError.onError!(FlutterErrorDetails(
      exception: StateError('boom'),
      stack: StackTrace.current,
      library: 'test',
    ));
    // FlutterError.onError fires recordEvent fire-and-forget; let the
    // dispatch microtask settle before asserting on the buffer.
    await Future<void>.delayed(Duration.zero);
    final events = DebugService.instance.events;
    expect(events, hasLength(1));
    expect(events.first.scope, 'flutter_error');
    expect(events.first.level, EventLevel.error);
    expect(events.first.message, contains('boom'));
  });

  test('PlatformDispatcher.onError records EventRecord with scope async_error',
      () async {
    PlatformDispatcher.instance.onError!(
      StateError('async-boom'),
      StackTrace.current,
    );
    await Future<void>.delayed(Duration.zero);
    final events = DebugService.instance.events;
    expect(events, hasLength(1));
    expect(events.first.scope, 'async_error');
    expect(events.first.message, contains('async-boom'));
  });

  test('zoneErrorHandler records EventRecord with scope zone_error', () async {
    zoneErrorHandler(StateError('zone-boom'), StackTrace.current);
    await Future<void>.delayed(Duration.zero);
    final events = DebugService.instance.events;
    expect(events, hasLength(1));
    expect(events.first.scope, 'zone_error');
    expect(events.first.message, contains('zone-boom'));
  });

  test('flutter_error events update DebugStats.flutterError counter', () async {
    FlutterError.onError!(FlutterErrorDetails(
      exception: StateError('x'),
      stack: StackTrace.current,
    ));
    await Future<void>.delayed(Duration.zero);
    final s = DebugService.instance.stats.snapshot();
    expect(s.byScope[DebugScope.flutterError]!.otherError, 1);
  });
}
