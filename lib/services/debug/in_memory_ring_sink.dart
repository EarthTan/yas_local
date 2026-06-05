import 'debug_service.dart';
import 'debug_sink.dart';

class InMemoryRingSink implements DebugSink {
  InMemoryRingSink({
    this.qwenCapacity = 200,
    this.eventCapacity = 1000,
    this.jsonAttemptCapacity = 200,
  }) {
    assert(qwenCapacity >= 1, 'qwenCapacity must be >= 1');
    assert(eventCapacity >= 1, 'eventCapacity must be >= 1');
    assert(jsonAttemptCapacity >= 1, 'jsonAttemptCapacity must be >= 1');
  }

  final int qwenCapacity;
  final int eventCapacity;
  final int jsonAttemptCapacity;

  final List<QwenCallRecord> _qwenCalls = <QwenCallRecord>[];
  final List<EventRecord> _events = <EventRecord>[];
  final List<JsonAttemptRecord> _jsonAttempts = <JsonAttemptRecord>[];

  List<QwenCallRecord> get qwenCalls => List.unmodifiable(_qwenCalls);
  List<EventRecord> get events => List.unmodifiable(_events);
  List<JsonAttemptRecord> get jsonAttempts => List.unmodifiable(_jsonAttempts);

  @override
  Future<void> write(DebugRecord record) async {
    if (record is QwenCallRecord) {
      _qwenCalls.add(record);
      if (_qwenCalls.length > qwenCapacity) {
        _qwenCalls.removeAt(0);
      }
    } else if (record is EventRecord) {
      _events.add(record);
      if (_events.length > eventCapacity) {
        _events.removeAt(0);
      }
    } else if (record is JsonAttemptRecord) {
      _jsonAttempts.add(record);
      if (_jsonAttempts.length > jsonAttemptCapacity) {
        _jsonAttempts.removeAt(0);
      }
    }
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}

  void clear() {
    _qwenCalls.clear();
    _events.clear();
    _jsonAttempts.clear();
  }
}
