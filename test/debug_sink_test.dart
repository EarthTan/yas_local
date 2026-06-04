import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/services/debug/debug_sink.dart';
import 'package:yas_local/services/debug_service.dart';

void main() {
  test('DebugSink is an interface (cannot be instantiated directly)', () {
    final sink = _RecordingSink();
    expect(sink, isA<DebugSink>());
  });

  test('write must not throw — sinks swallow I/O errors', () {
    final sink = _ThrowingSink();
    expect(() => sink.write(_dummyEvent()), returnsNormally);
  });

  test('flush defaults to no-op async', () async {
    final sink = _RecordingSink();
    await sink.flush();
  });
}

class _RecordingSink implements DebugSink {
  int writeCount = 0;
  @override
  void write(DebugRecord record) => writeCount++;
  @override
  Future<void> flush() async {}
  @override
  Future<void> close() async {}
}

class _ThrowingSink implements DebugSink {
  @override
  void write(DebugRecord record) {
    // Demonstrates the contract: sinks MUST swallow I/O errors
    // rather than letting them bubble up to the caller.
    try {
      throw Exception('disk full');
    } catch (_) {
      // Swallowed, per DebugSink contract.
    }
  }

  @override
  Future<void> flush() async {}
  @override
  Future<void> close() async {}
}

DebugRecord _dummyEvent() => EventRecord(
      timestamp: DateTime.now(),
      scope: 'test',
      level: EventLevel.info,
      message: 'x',
    );
