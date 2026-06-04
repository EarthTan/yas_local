import '../debug_service.dart';
import 'debug_sink.dart';

class InMemoryRingSink implements DebugSink {
  InMemoryRingSink({
    this.qwenCapacity = 200,
    this.eventCapacity = 1000,
    this.jsonAttemptCapacity = 200,
  });

  final int qwenCapacity;
  final int eventCapacity;
  final int jsonAttemptCapacity;

  final List<QwenCallRecord> qwenCalls = [];
  final List<EventRecord> events = [];
  final List<JsonAttemptRecord> jsonAttempts = [];

  @override
  void write(DebugRecord record) {
    if (record is QwenCallRecord) {
      qwenCalls.add(record);
      if (qwenCalls.length > qwenCapacity) {
        qwenCalls.removeAt(0);
      }
    } else if (record is EventRecord) {
      events.add(record);
      if (events.length > eventCapacity) {
        events.removeAt(0);
      }
    } else if (record is JsonAttemptRecord) {
      jsonAttempts.add(record);
      if (jsonAttempts.length > jsonAttemptCapacity) {
        jsonAttempts.removeAt(0);
      }
    }
    // Unknown record type: silently ignore (forward compat).
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}
