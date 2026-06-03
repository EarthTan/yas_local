import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/services/debug_service.dart';

void main() {
  setUp(() {
    DebugService.instance.resetForTest();
  });

  group('enabled flag', () {
    test('defaults to false', () {
      expect(DebugService.instance.enabled, isFalse);
    });

    test('setEnabled(true) flips the flag', () {
      DebugService.instance.setEnabled(true);
      expect(DebugService.instance.enabled, isTrue);
    });

    test('recordQwenCall is a no-op when disabled', () {
      DebugService.instance.recordQwenCall(QwenCallRecord(
        timestamp: DateTime.now(),
        scope: 'identify',
        model: 'm',
        endpoint: '/chat/completions',
        statusCode: 200,
        elapsedMs: 100,
        status: QwenCallStatus.ok,
        messages: const [],
      ));
      expect(DebugService.instance.qwenCalls, isEmpty);
    });

    test('recordEvent is a no-op when disabled', () {
      DebugService.instance.recordEvent(scope: 'task:1', message: 'x');
      expect(DebugService.instance.events, isEmpty);
    });

    test('recordJsonAttempt is a no-op when disabled', () {
      DebugService.instance.recordJsonAttempt(JsonAttemptRecord(
        timestamp: DateTime.now(),
        scope: 'identify',
        inputSnippet: '',
        attempts: const [],
      ));
      expect(DebugService.instance.jsonAttempts, isEmpty);
    });
  });

  group('recording when enabled', () {
    setUp(() {
      DebugService.instance.setEnabled(true);
    });

    test('recordQwenCall stores a record', () {
      DebugService.instance.recordQwenCall(QwenCallRecord(
        timestamp: DateTime.now(),
        scope: 'identify',
        model: 'm',
        endpoint: '/chat/completions',
        statusCode: 200,
        elapsedMs: 100,
        status: QwenCallStatus.ok,
        messages: const [],
      ));
      expect(DebugService.instance.qwenCalls, hasLength(1));
    });

    test('recordEvent stores a record with default info level', () {
      DebugService.instance.recordEvent(scope: 'task:1', message: 'start');
      expect(DebugService.instance.events.single.message, 'start');
      expect(DebugService.instance.events.single.level, EventLevel.info);
    });

    test('recordJsonAttempt stores a record', () {
      DebugService.instance.recordJsonAttempt(JsonAttemptRecord(
        timestamp: DateTime.now(),
        scope: 'identify',
        inputSnippet: 'raw',
        attempts: const [JsonAttempt(method: 'strip_thinking', ok: true)],
      ));
      expect(DebugService.instance.jsonAttempts.single.attempts, hasLength(1));
    });
  });

  group('ring buffers evict oldest', () {
    setUp(() {
      DebugService.instance.setEnabled(true);
    });

    test('qwenCalls caps at qwenCapacity (200), evicting oldest', () {
      for (var i = 0; i < DebugService.qwenCapacity + 5; i++) {
        DebugService.instance.recordQwenCall(QwenCallRecord(
          timestamp: DateTime.now(),
          scope: 'grade',
          model: 'm',
          endpoint: '/chat/completions',
          statusCode: 200,
          elapsedMs: 1,
          status: QwenCallStatus.ok,
          messages: const [],
          responseContent: 'call-$i',
        ));
      }
      expect(DebugService.instance.qwenCalls, hasLength(DebugService.qwenCapacity));
      // Oldest 5 (call-0 through call-4) should be gone
      expect(DebugService.instance.qwenCalls.first.responseContent, 'call-5');
    });

    test('events cap at eventCapacity (1000), evicting oldest', () {
      for (var i = 0; i < DebugService.eventCapacity + 3; i++) {
        DebugService.instance.recordEvent(scope: 's', message: 'm-$i');
      }
      expect(DebugService.instance.events, hasLength(DebugService.eventCapacity));
      expect(DebugService.instance.events.first.message, 'm-3');
    });

    test('jsonAttempts cap at jsonAttemptCapacity (200), evicting oldest', () {
      for (var i = 0; i < DebugService.jsonAttemptCapacity + 2; i++) {
        DebugService.instance.recordJsonAttempt(JsonAttemptRecord(
          timestamp: DateTime.now(),
          scope: 'grade',
          inputSnippet: 'i-$i',
          attempts: const [],
        ));
      }
      expect(DebugService.instance.jsonAttempts, hasLength(DebugService.jsonAttemptCapacity));
      expect(DebugService.instance.jsonAttempts.first.inputSnippet, 'i-2');
    });
  });

  group('state snapshot', () {
    test('starts null', () {
      expect(DebugService.instance.stateSnapshot, isNull);
    });

    test('refreshStateSnapshot stores and overwrites', () {
      DebugService.instance.refreshStateSnapshot(
        tasks: ['t1'],
        references: ['r1'],
        settings: 's1',
      );
      expect(DebugService.instance.stateSnapshot, isNotNull);
      expect(DebugService.instance.stateSnapshot!.tasks, ['t1']);

      DebugService.instance.refreshStateSnapshot(
        tasks: ['t2'],
        references: ['r2'],
        settings: 's2',
      );
      expect(DebugService.instance.stateSnapshot!.tasks, ['t2']);
    });

    test('refreshStateSnapshot works even when disabled (always updates)', () {
      // setEnabled(false) by default in setUp
      DebugService.instance.refreshStateSnapshot(
        tasks: ['t'],
        references: ['r'],
        settings: 's',
      );
      expect(DebugService.instance.stateSnapshot, isNotNull);
    });
  });

  group('clear', () {
    setUp(() {
      DebugService.instance.setEnabled(true);
    });

    test('clears all buffers and snapshot', () {
      DebugService.instance.recordEvent(scope: 's', message: 'm');
      DebugService.instance.refreshStateSnapshot(
        tasks: ['t'], references: ['r'], settings: 's',
      );
      DebugService.instance.clear();
      expect(DebugService.instance.events, isEmpty);
      expect(DebugService.instance.stateSnapshot, isNull);
      expect(DebugService.instance.enabled, isTrue); // clear() must not touch _enabled
    });
  });
}
