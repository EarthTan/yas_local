import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/services/debug/debug_service.dart';
import 'package:yas_local/services/debug/error_hooks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    DebugService.instance.resetForTest();
    DebugService.instance.setEnabled(true);
    installErrorHooks();
  });

  test(
      'ErrorWidget.builder records a flutter_error event with widgetError flag',
      () {
    final builder = ErrorWidget.builder;
    final result = builder(FlutterErrorDetails(
      exception: StateError('boom'),
      stack: StackTrace.current,
    ));
    final events = DebugService.instance.events;
    expect(events, hasLength(1));
    expect(events.first.scope, 'flutter_error');
    expect(events.first.level, EventLevel.error);
    expect(events.first.message, contains('boom'));
    expect(events.first.data?['widgetError'], isTrue);
    expect(result, isA<Widget>());
  });

  test('ErrorWidget.builder records stack trace as a non-null string', () {
    final stack = StackTrace.current;
    final builder = ErrorWidget.builder;
    builder(FlutterErrorDetails(
      exception: StateError('boom'),
      stack: stack,
    ));
    final events = DebugService.instance.events;
    final recorded = events.first.data?['stack'];
    expect(recorded, isA<String>());
    expect((recorded as String).isNotEmpty, isTrue);
  });
}
