import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/services/debug/debug_service.dart';
import 'package:yas_local/services/debug/debug_sink.dart';
import 'package:yas_local/services/debug/debug_stats.dart';
import 'package:yas_local/services/debug/in_memory_ring_sink.dart';

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

    test('recordQwenCall is a no-op when disabled', () async {
      await DebugService.instance.recordQwenCall(QwenCallRecord(
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

    test('recordEvent is a no-op when disabled', () async {
      await DebugService.instance.recordEvent(scope: 'task:1', message: 'x');
      expect(DebugService.instance.events, isEmpty);
    });

    test('recordJsonAttempt is a no-op when disabled', () async {
      await DebugService.instance.recordJsonAttempt(JsonAttemptRecord(
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

    test('recordQwenCall stores a record', () async {
      await DebugService.instance.recordQwenCall(QwenCallRecord(
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

    test('recordEvent stores a record with default info level', () async {
      await DebugService.instance.recordEvent(scope: 'task:1', message: 'start');
      expect(DebugService.instance.events.single.message, 'start');
      expect(DebugService.instance.events.single.level, EventLevel.info);
    });

    test('recordJsonAttempt stores a record', () async {
      await DebugService.instance.recordJsonAttempt(JsonAttemptRecord(
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

    test('qwenCalls caps at qwenCapacity (200), evicting oldest', () async {
      for (var i = 0; i < DebugService.qwenCapacity + 5; i++) {
        await DebugService.instance.recordQwenCall(QwenCallRecord(
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

    test('events cap at eventCapacity (1000), evicting oldest', () async {
      for (var i = 0; i < DebugService.eventCapacity + 3; i++) {
        await DebugService.instance.recordEvent(scope: 's', message: 'm-$i');
      }
      expect(DebugService.instance.events, hasLength(DebugService.eventCapacity));
      expect(DebugService.instance.events.first.message, 'm-3');
    });

    test('jsonAttempts cap at jsonAttemptCapacity (200), evicting oldest', () async {
      for (var i = 0; i < DebugService.jsonAttemptCapacity + 2; i++) {
        await DebugService.instance.recordJsonAttempt(JsonAttemptRecord(
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

    test('clears all buffers and snapshot', () async {
      await DebugService.instance.recordEvent(scope: 's', message: 'm');
      DebugService.instance.refreshStateSnapshot(
        tasks: ['t'], references: ['r'], settings: 's',
      );
      DebugService.instance.clear();
      expect(DebugService.instance.events, isEmpty);
      expect(DebugService.instance.stateSnapshot, isNull);
      expect(DebugService.instance.enabled, isTrue); // clear() must not touch _enabled
    });

    test('clear() resets _stats', () async {
      await DebugService.instance.recordQwenCall(QwenCallRecord(
        timestamp: DateTime.now(),
        scope: 'grade',
        model: 'm',
        endpoint: 'https://e',
        statusCode: 200,
        elapsedMs: 100,
        status: QwenCallStatus.ok,
        messages: const [],
        responseContent: 'r',
      ));
      expect(DebugService.instance.stats.snapshot().totalCalls, greaterThan(0));
      DebugService.instance.clear();
      expect(DebugService.instance.stats.snapshot().totalCalls, 0);
    });
  });

  group('changes Listenable', () {
    setUp(() {
      DebugService.instance.setEnabled(true);
    });

    test('changes is a Listenable', () {
      expect(DebugService.instance.changes, isA<Listenable>());
    });

    test('notifies listeners on recordQwenCall', () async {
      var notified = 0;
      DebugService.instance.changes.addListener(() => notified++);
      await DebugService.instance.recordQwenCall(QwenCallRecord(
        timestamp: DateTime.now(),
        scope: 'identify',
        model: 'm',
        endpoint: '/chat/completions',
        statusCode: 200,
        elapsedMs: 1,
        status: QwenCallStatus.ok,
        messages: const [],
      ));
      // The listener fires inside _dispatch (synchronously after each
      // sink.write completes) — by the time record* returns, the listener
      // has already been notified.
      expect(notified, 1);
    });

    test('notifies listeners on recordEvent', () async {
      var notified = 0;
      DebugService.instance.changes.addListener(() => notified++);
      await DebugService.instance.recordEvent(scope: 's', message: 'm');
      expect(notified, 1);
    });

    test('notifies listeners on recordJsonAttempt', () async {
      var notified = 0;
      DebugService.instance.changes.addListener(() => notified++);
      await DebugService.instance.recordJsonAttempt(JsonAttemptRecord(
        timestamp: DateTime.now(),
        scope: 'identify',
        inputSnippet: 'x',
        attempts: const [],
      ));
      expect(notified, 1);
    });

    test('does not notify when disabled (recordX is no-op)', () async {
      DebugService.instance.setEnabled(false);
      var notified = 0;
      DebugService.instance.changes.addListener(() => notified++);
      await DebugService.instance.recordEvent(scope: 's', message: 'm');
      expect(notified, 0);
    });
  });

  group('JsonAttemptBuilder', () {
    setUp(() {
      DebugService.instance.setEnabled(true);
    });

    test('commit records attempts and finalException', () async {
      final b = JsonAttemptBuilder(scope: 'identify', input: 'a' * 500);
      b.record('strip_thinking', ok: true);
      b.record('fence_object', ok: false, error: 'parse failed');
      b.markFailed('JsonParseException: no object');
      b.commit();
      // commit() fires recordJsonAttempt fire-and-forget; let the dispatch
      // microtask settle before asserting on the buffer.
      await Future<void>.delayed(Duration.zero);

      final r = DebugService.instance.jsonAttempts.single;
      expect(r.scope, 'identify');
      expect(r.attempts, hasLength(2));
      expect(r.attempts[1].ok, isFalse);
      expect(r.attempts[1].error, 'parse failed');
      expect(r.finalException, 'JsonParseException: no object');
      expect(r.inputSnippet, hasLength(200)); // truncated
    });

    test('commit is no-op when service disabled', () async {
      DebugService.instance.setEnabled(false);
      final b = JsonAttemptBuilder(scope: 'identify', input: 'x');
      b.record('strip_thinking', ok: true);
      b.commit();
      expect(DebugService.instance.jsonAttempts, isEmpty);
    });
  });

  group('withSinks factory', () {
    test('forwards writes to all sinks', () async {
      final a = InMemoryRingSink();
      final b = InMemoryRingSink();
      final svc = DebugService.withSinks([a, b]);
      svc.setEnabled(true);
      await svc.recordEvent(scope: 's', message: 'x');
      expect(a.events, hasLength(1));
      expect(b.events, hasLength(1));
    });

    test('sinks that throw do not break other sinks or the service', () async {
      final a = InMemoryRingSink();
      final b = _ThrowingSink();
      final svc = DebugService.withSinks([b, a]);
      svc.setEnabled(true);
      await svc.recordEvent(scope: 's', message: 'x');
      expect(a.events, hasLength(1));
    });
  });

  group('addSink', () {
    test('appends a sink to the dispatch list', () async {
      DebugService.instance.setEnabled(true);
      final sink = InMemoryRingSink();
      DebugService.instance.addSink(sink);
      await DebugService.instance.recordEvent(scope: 's', message: 'x');
      expect(sink.events, hasLength(1));
    });
  });

  group('stats integration', () {
    test('recordQwenCall updates DebugStats', () async {
      final svc = DebugService.withSinks([InMemoryRingSink()]);
      svc.setEnabled(true);
      await svc.recordQwenCall(QwenCallRecord(
        timestamp: DateTime.now(),
        scope: 'grade',
        model: 'm',
        endpoint: '/e',
        statusCode: 200,
        elapsedMs: 100,
        status: QwenCallStatus.ok,
        messages: const [],
      ));
      final snap = svc.stats.snapshot();
      expect(snap.byScope[DebugScope.grade]!.calls, 1);
    });
  });

  group('record display metadata', () {
    test('QwenCallRecord.displayName maps known scopes', () {
      expect(
        QwenCallRecord(
          timestamp: DateTime.now(),
          scope: 'identify',
          model: 'm',
          endpoint: '/e',
          statusCode: 200,
          elapsedMs: 1,
          status: QwenCallStatus.ok,
          messages: const [],
        ).displayName,
        '题目识别',
      );
      expect(
        QwenCallRecord(
          timestamp: DateTime.now(),
          scope: 'grade',
          model: 'm',
          endpoint: '/e',
          statusCode: 200,
          elapsedMs: 1,
          status: QwenCallStatus.ok,
          messages: const [],
        ).displayName,
        '批改',
      );
    });

    test('QwenCallRecord.displayName falls back to scope string', () {
      final r = QwenCallRecord(
        timestamp: DateTime.now(),
        scope: 'custom',
        model: 'm',
        endpoint: '/e',
        statusCode: 200,
        elapsedMs: 1,
        status: QwenCallStatus.ok,
        messages: const [],
      );
      expect(r.displayName, 'custom');
    });
  });
}

class _ThrowingSink implements DebugSink {
  @override
  Future<void> write(DebugRecord record) async {
    throw Exception('disk full');
  }

  @override
  Future<void> flush() async {}
  @override
  Future<void> close() async {}
}
