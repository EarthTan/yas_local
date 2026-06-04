import 'package:flutter/foundation.dart';

import 'debug_sink.dart';
import 'in_memory_ring_sink.dart';

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
class QwenCallRecord implements DebugRecord {
  @override
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

  @override
  String get recordType => 'qwen_call';

  @override
  Map<String, Object?> toJson() => {
        'recordType': recordType,
        'timestamp': timestamp.toIso8601String(),
        'scope': scope,
        'model': model,
        'endpoint': endpoint,
        'statusCode': statusCode,
        'elapsedMs': elapsedMs,
        'status': status.name,
        'messages': messages,
        'responseContent': responseContent,
        'reasoningContent': reasoningContent,
        'errorMessage': errorMessage,
      };
}


/// One process event from a provider (identification / strategy / grading).
class EventRecord implements DebugRecord {
  @override
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

  @override
  String get recordType => 'event';

  @override
  Map<String, Object?> toJson() => {
        'recordType': recordType,
        'timestamp': timestamp.toIso8601String(),
        'scope': scope,
        'level': level.name,
        'message': message,
        'data': data,
      };
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
class JsonAttemptRecord implements DebugRecord {
  @override
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

  @override
  String get recordType => 'json_attempt';

  @override
  Map<String, Object?> toJson() => {
        'recordType': recordType,
        'timestamp': timestamp.toIso8601String(),
        'scope': scope,
        'inputSnippet': inputSnippet,
        'attempts': attempts
            .map((a) => {'method': a.method, 'ok': a.ok, 'error': a.error})
            .toList(),
        'finalException': finalException,
      };
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

/// Thin [ChangeNotifier] wrapper that exposes `notify()` publicly, so the
/// owning [DebugService] (which is not a [ChangeNotifier] subclass) can
/// fire updates without tripping the protected-`notifyListeners` lint.
class _DebugNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

class DebugService {
  /// Build a [DebugService] backed by the given [sinks]. Use this from
  /// tests to inject custom sinks; production uses [instance] which is
  /// pre-wired with a single [InMemoryRingSink].
  factory DebugService.withSinks(List<DebugSink> sinks) {
    return DebugService._fromSinks(sinks);
  }

  DebugService._fromSinks(this._sinks);

  static final DebugService instance = DebugService.withSinks([InMemoryRingSink()]);

  static const int qwenCapacity = 200;
  static const int eventCapacity = 1000;
  static const int jsonAttemptCapacity = 200;

  bool _enabled = false;
  bool get enabled => _enabled;

  /// Fires whenever a record is appended to one of the ring buffers.
  /// `refreshStateSnapshot` does NOT fire this — callers can decide themselves
  /// whether they want to subscribe to snapshot changes (they typically read
  /// it in lockstep with the buffers).
  ///
  /// Non-final so [resetForTest] can swap in a fresh instance between tests
  /// without leaking listeners from the previous test.
  _DebugNotifier _changes = _DebugNotifier();
  Listenable get changes => _changes;

  List<DebugSink> _sinks = const [];
  InMemoryRingSink? get _memorySink =>
      _sinks.whereType<InMemoryRingSink>().firstOrNull;
  StateSnapshot? _stateSnapshot;

  List<QwenCallRecord> get qwenCalls => _memorySink?.qwenCalls ?? const [];
  List<EventRecord> get events => _memorySink?.events ?? const [];
  List<JsonAttemptRecord> get jsonAttempts => _memorySink?.jsonAttempts ?? const [];
  StateSnapshot? get stateSnapshot => _stateSnapshot;

  void setEnabled(bool value) {
    _enabled = value;
  }

  void recordQwenCall(QwenCallRecord record) {
    if (!_enabled) return;
    _dispatch(record);
  }

  void recordEvent({
    required String scope,
    required String message,
    EventLevel level = EventLevel.info,
    Map<String, Object?>? data,
  }) {
    if (!_enabled) return;
    _dispatch(EventRecord(
      timestamp: DateTime.now(),
      scope: scope,
      level: level,
      message: message,
      data: data,
    ));
  }

  void recordJsonAttempt(JsonAttemptRecord record) {
    if (!_enabled) return;
    _dispatch(record);
  }

  void _dispatch(DebugRecord record) {
    for (final sink in _sinks) {
      try {
        sink.write(record);
      } catch (_) {
        // Sinks must not throw, but be defensive.
      }
    }
    _changes.notify();
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
    _memorySink?.clear();
    _stateSnapshot = null;
  }

  /// Test-only helper. Resets the enabled flag, clears all ring buffers +
  /// the state snapshot, and swaps in a fresh [ChangeNotifier] so listeners
  /// from the previous test don't leak into the next one. Production code
  /// must use [setEnabled] / [clear].
  void resetForTest() {
    _enabled = false;
    _changes.dispose();
    _changes = _DebugNotifier();
    clear();
    if (identical(this, instance)) {
      _sinks = [InMemoryRingSink()];
    }
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
