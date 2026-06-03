/// Status of a Qwen HTTP call as observed by DebugService.
enum QwenCallStatus {
  /// HTTP 2xx, response received and parsed successfully.
  ok,

  /// HTTP non-2xx, or network/timeout error before any response.
  httpError,

  /// HTTP 2xx but response body failed JSON extraction.
  parseError,
}

/// Severity of a process event.
enum EventLevel { info, warn, error }

/// One Qwen HTTP call. Captured by the Dio interceptor in QwenService
/// (status ok/httpError) and by the calling method's try/catch (status parseError).
class QwenCallRecord {
  final DateTime timestamp;
  final String scope; // 'identify' | 'strategy' | 'refine' | 'grade'
  final String model;
  final String endpoint;
  final int? statusCode;
  final int elapsedMs;
  final QwenCallStatus status;
  final List<Map<String, dynamic>> messages;
  final String? responseContent;
  final String? reasoningContent;
  final String? errorMessage;

  const QwenCallRecord({
    required this.timestamp,
    required this.scope,
    required this.model,
    required this.endpoint,
    required this.statusCode,
    required this.elapsedMs,
    required this.status,
    required this.messages,
    this.responseContent,
    this.reasoningContent,
    this.errorMessage,
  });
}

/// One process event from a provider (identification / strategy / grading).
class EventRecord {
  final DateTime timestamp;
  final String scope;
  final EventLevel level;
  final String message;
  final Map<String, Object?>? data;

  const EventRecord({
    required this.timestamp,
    required this.scope,
    required this.level,
    required this.message,
    this.data,
  });
}

/// A single parsing attempt within JsonExtractor.
class JsonAttempt {
  final String method; // 'strip_thinking' | 'fence_object' | 'fence_list' | 'braces_object' | 'braces_list'
  final bool ok;
  final String? error;

  const JsonAttempt({
    required this.method,
    required this.ok,
    this.error,
  });
}

/// One JSON extraction. Contains all attempts and a snippet of the input.
class JsonAttemptRecord {
  final DateTime timestamp;
  final String scope;
  final String inputSnippet; // first 200 chars of the raw AI response
  final List<JsonAttempt> attempts;
  final String? finalException; // non-null when extraction ultimately failed

  const JsonAttemptRecord({
    required this.timestamp,
    required this.scope,
    required this.inputSnippet,
    required this.attempts,
    this.finalException,
  });
}

/// Snapshot of in-memory app state. Refreshed by TaskNotifier / SettingsNotifier.
class StateSnapshot {
  final List<dynamic> tasks; // typed as dynamic to avoid import cycle in tests; runtime type is List<GradingTask>
  final List<dynamic> references; // runtime type: List<ReferenceAnswer>
  final dynamic settings; // runtime type: AppSettings (apiKey masked)
  final DateTime capturedAt;

  const StateSnapshot({
    required this.tasks,
    required this.references,
    required this.settings,
    required this.capturedAt,
  });
}
