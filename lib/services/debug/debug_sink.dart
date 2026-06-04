/// Common record types: QwenCallRecord, EventRecord, JsonAttemptRecord.
/// All three live in debug_service.dart today and remain there to avoid
/// touching every import site in M1.
abstract class DebugRecord {
  String get recordType; // 'qwen_call' | 'event' | 'json_attempt'
  DateTime get timestamp;
  Map<String, Object?> toJson();
}

/// Pluggable destination for debug records. Implementations MUST NOT throw
/// from [write] — match the contract of the historical QwenLogger
/// (`_writeBlock` swallowed I/O errors).
abstract interface class DebugSink {
  Future<void> write(DebugRecord record);
  Future<void> flush() async {}
  Future<void> close() async {}
}
