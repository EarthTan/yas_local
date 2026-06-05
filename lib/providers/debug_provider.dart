import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/debug/debug_service.dart';

class DebugState {
  final List<QwenCallRecord> qwenCalls;
  final List<EventRecord> events;
  final List<JsonAttemptRecord> jsonAttempts;
  final StateSnapshot? stateSnapshot;

  const DebugState({
    this.qwenCalls = const [],
    this.events = const [],
    this.jsonAttempts = const [],
    this.stateSnapshot,
  });

  DebugState copyWith({
    List<QwenCallRecord>? qwenCalls,
    List<EventRecord>? events,
    List<JsonAttemptRecord>? jsonAttempts,
    StateSnapshot? stateSnapshot,
  }) =>
      DebugState(
        qwenCalls: qwenCalls ?? this.qwenCalls,
        events: events ?? this.events,
        jsonAttempts: jsonAttempts ?? this.jsonAttempts,
        stateSnapshot: stateSnapshot ?? this.stateSnapshot,
      );
}

class DebugNotifier extends StateNotifier<DebugState> {
  DebugNotifier() : super(const DebugState()) {
    // Initial pull so the screen has data even before the first mutation.
    _pull();
    // Auto-refresh: every record added to the service fires `changes`, which
    // re-pulls the current buffers into state. Riverpod re-renders anything
    // watching `debugProvider` on the new state object.
    _service.changes.addListener(_pull);
  }

  final DebugService _service = DebugService.instance;

  @override
  void dispose() {
    _service.changes.removeListener(_pull);
    super.dispose();
  }

  void _pull() {
    state = DebugState(
      qwenCalls: _service.qwenCalls,
      events: _service.events,
      jsonAttempts: _service.jsonAttempts,
      stateSnapshot: _service.stateSnapshot,
    );
  }

  /// Manual refresh — kept for callers that want to pull right now (e.g. a
  /// pull-to-refresh action). The auto-refresh via [DebugService.changes]
  /// already covers all in-process record additions.
  void refresh() => _pull();
}

final debugProvider =
    StateNotifierProvider<DebugNotifier, DebugState>((ref) => DebugNotifier());
