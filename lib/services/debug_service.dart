import 'package:flutter/foundation.dart';

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

class DebugService {
  DebugService._();
  static final DebugService instance = DebugService._();

  static const int qwenCapacity = 200;
  static const int eventCapacity = 1000;
  static const int jsonAttemptCapacity = 200;

  bool _enabled = false;
  bool get enabled => _enabled;

  final List<QwenCallRecord> _qwenCalls = <QwenCallRecord>[];
  final List<EventRecord> _events = <EventRecord>[];
  final List<JsonAttemptRecord> _jsonAttempts = <JsonAttemptRecord>[];
  StateSnapshot? _stateSnapshot;

  List<QwenCallRecord> get qwenCalls => List.unmodifiable(_qwenCalls);
  List<EventRecord> get events => List.unmodifiable(_events);
  List<JsonAttemptRecord> get jsonAttempts => List.unmodifiable(_jsonAttempts);
  StateSnapshot? get stateSnapshot => _stateSnapshot;

  void setEnabled(bool value) {
    _enabled = value;
    debugPrint('[DEBUG-SVC] setEnabled($value) at ${_callerFrame()}');
  }

  void recordQwenCall(QwenCallRecord record) {
    if (!_enabled) {
      debugPrint('[DEBUG-SVC] recordQwenCall DROPPED scope=${record.scope} enabled=false');
      return;
    }
    debugPrint('[DEBUG-SVC] recordQwenCall KEPT scope=${record.scope}');
    _qwenCalls.add(record);
    if (_qwenCalls.length > qwenCapacity) {
      _qwenCalls.removeAt(0);
    }
  }

  void recordEvent({
    required String scope,
    required String message,
    EventLevel level = EventLevel.info,
    Map<String, Object?>? data,
  }) {
    if (!_enabled) {
      debugPrint('[DEBUG-SVC] recordEvent DROPPED scope=$scope enabled=false');
      return;
    }
    debugPrint('[DEBUG-SVC] recordEvent KEPT scope=$scope');
    _events.add(EventRecord(
      timestamp: DateTime.now(),
      scope: scope,
      level: level,
      message: message,
      data: data,
    ));
    if (_events.length > eventCapacity) {
      _events.removeAt(0);
    }
  }

  void recordJsonAttempt(JsonAttemptRecord record) {
    if (!_enabled) {
      debugPrint('[DEBUG-SVC] recordJsonAttempt DROPPED scope=${record.scope} enabled=false');
      return;
    }
    debugPrint('[DEBUG-SVC] recordJsonAttempt KEPT scope=${record.scope}');
    _jsonAttempts.add(record);
    if (_jsonAttempts.length > jsonAttemptCapacity) {
      _jsonAttempts.removeAt(0);
    }
  }

  void refreshStateSnapshot({
    required List<dynamic> tasks,
    required List<dynamic> references,
    required dynamic settings,
  }) {
    // Snapshot refresh is intentionally NOT gated on enabled.
    // Cost is one assignment; benefit is "open debug → see current state immediately".
    _stateSnapshot = StateSnapshot(
      tasks: tasks,
      references: references,
      settings: settings,
      capturedAt: DateTime.now(),
    );
  }

  void clear() {
    _qwenCalls.clear();
    _events.clear();
    _jsonAttempts.clear();
    _stateSnapshot = null;
  }

  /// Best-effort: return the first frame of the current call stack that is
  /// neither setEnabled itself nor this helper. Used only for diagnostic
  /// logging — never for control flow.
  static String _callerFrame() {
    try {
      final frames = StackTrace.current.toString().split('\n');
      for (final f in frames) {
        final t = f.trim();
        if (t.isEmpty) continue;
        if (t.contains('DebugService.setEnabled')) continue;
        if (t.contains('DebugService._callerFrame')) continue;
        if (t.contains('DebugService.recordQwenCall')) continue;
        if (t.contains('DebugService.recordEvent')) continue;
        if (t.contains('DebugService.recordJsonAttempt')) continue;
        final m = RegExp(r'#\d+\s+([^<(]+)').firstMatch(t);
        if (m != null) return m.group(1)!.trim();
      }
    } catch (_) {}
    return '?';
  }

  /// Test-only helper. Resets the enabled flag and clears all ring buffers +
  /// the state snapshot. Production code must use [setEnabled] / [clear].
  void resetForTest() {
    _enabled = false;
    clear();
  }
}

/// Builder for [JsonAttemptRecord]. Used inside `JsonExtractor` to record
/// each parsing attempt as it happens, then commit a single record on exit.
class JsonAttemptBuilder {
  JsonAttemptBuilder({required this.scope, required this.input})
      : timestamp = DateTime.now();

  final DateTime timestamp;
  final String scope;
  final String input;
  final List<JsonAttempt> _attempts = <JsonAttempt>[];
  String? _finalException;

  void record(String method, {required bool ok, String? error}) {
    _attempts.add(JsonAttempt(method: method, ok: ok, error: error));
  }

  void markFailed(String exception) {
    _finalException = exception;
  }

  void commit() {
    final snippet = input.length > 200 ? input.substring(0, 200) : input;
    DebugService.instance.recordJsonAttempt(JsonAttemptRecord(
      timestamp: timestamp,
      scope: scope,
      inputSnippet: snippet,
      attempts: List.unmodifiable(_attempts),
      finalException: _finalException,
    ));
  }
}
