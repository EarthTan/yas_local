import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/services/debug/debug_service.dart';
import 'package:yas_local/services/debug/debug_stats.dart';

void main() {
  group('DebugStats', () {
    test('record increments scope call count', () {
      final stats = DebugStats();
      stats.record(_qwenCall(scope: 'grade', status: QwenCallStatus.ok, elapsedMs: 100));
      stats.record(_qwenCall(scope: 'grade', status: QwenCallStatus.ok, elapsedMs: 200));
      final snap = stats.snapshot();
      expect(snap.byScope[DebugScope.grade]!.calls, 2);
    });

    test('categorizes QwenCallStatus correctly', () {
      final stats = DebugStats();
      stats.record(_qwenCall(scope: 'grade', status: QwenCallStatus.ok));
      stats.record(_qwenCall(scope: 'grade', status: QwenCallStatus.httpError));
      stats.record(_qwenCall(scope: 'grade', status: QwenCallStatus.parseError));
      final s = stats.snapshot().byScope[DebugScope.grade]!;
      expect(s.ok, 1);
      expect(s.httpError, 1);
      expect(s.parseError, 1);
    });

    test('p50 / p95 use only recent 100 elapsedMs', () {
      final stats = DebugStats();
      for (var i = 0; i < 50; i++) {
        stats.record(_qwenCall(scope: 'grade', status: QwenCallStatus.ok, elapsedMs: 10));
      }
      for (var i = 0; i < 50; i++) {
        stats.record(_qwenCall(scope: 'grade', status: QwenCallStatus.ok, elapsedMs: 1000));
      }
      stats.record(_qwenCall(scope: 'grade', status: QwenCallStatus.ok, elapsedMs: 10));
      final s = stats.snapshot().byScope[DebugScope.grade]!;
      expect(s.p50Ms, lessThan(100));
      expect(s.calls, 101);
    });

    test('EventRecord with level=error counts as otherError', () {
      final stats = DebugStats();
      stats.record(EventRecord(timestamp: DateTime.now(), scope: 'flutter_error', level: EventLevel.error, message: 'x'));
      stats.record(EventRecord(timestamp: DateTime.now(), scope: 'task:1', level: EventLevel.info, message: 'y'));
      final s = stats.snapshot().byScope[DebugScope.flutterError]!;
      expect(s.otherError, 1);
      expect(s.calls, 1);
    });

    test('unknown scope maps to strategy (fallback)', () {
      final stats = DebugStats();
      stats.record(_qwenCall(scope: 'unknown_scope', status: QwenCallStatus.ok));
      final s = stats.snapshot().byScope[DebugScope.strategy]!;
      expect(s.calls, 1);
    });
  });
}

QwenCallRecord _qwenCall({
  required String scope,
  required QwenCallStatus status,
  int elapsedMs = 100,
}) =>
    QwenCallRecord(
      timestamp: DateTime.now(),
      scope: scope,
      model: 'm',
      endpoint: '/chat/completions',
      statusCode: 200,
      elapsedMs: elapsedMs,
      status: status,
      messages: const [],
    );
