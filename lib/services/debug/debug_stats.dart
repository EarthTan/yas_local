import 'debug_service.dart';
import 'debug_sink.dart';

enum DebugScope { identify, strategy, refine, grade, flutterError, asyncError, zoneError }

class _ScopeStats {
  int calls = 0;
  int ok = 0;
  int httpError = 0;
  int parseError = 0;
  int otherError = 0;
  int totalMs = 0;
  int maxMs = 0;
  final List<int> _recent = [];
  static const int kRecentCap = 100;
}

class ScopeSnapshot {
  final int calls;
  final int ok;
  final int httpError;
  final int parseError;
  final int otherError;
  final int totalMs;
  final int maxMs;
  final int p50Ms;
  final int p95Ms;
  const ScopeSnapshot({
    required this.calls,
    required this.ok,
    required this.httpError,
    required this.parseError,
    required this.otherError,
    required this.totalMs,
    required this.maxMs,
    required this.p50Ms,
    required this.p95Ms,
  });
}

class StatsSnapshot {
  final Map<DebugScope, ScopeSnapshot> byScope;
  final DateTime capturedAt;
  StatsSnapshot(this.byScope, this.capturedAt);

  int get totalCalls => byScope.values.fold(0, (sum, s) => sum + s.calls);
  int get totalErrors => byScope.values.fold(0, (sum, s) => sum + s.httpError + s.parseError + s.otherError);
  int get totalVlmMs => byScope.entries
      .where((e) =>
          e.key != DebugScope.flutterError &&
          e.key != DebugScope.asyncError &&
          e.key != DebugScope.zoneError)
      .fold(0, (sum, e) => sum + e.value.totalMs);

  double get errorRate => totalCalls == 0 ? 0.0 : totalErrors / totalCalls;
}

class DebugStats {
  final Map<DebugScope, _ScopeStats> _byScope = {
    for (final s in DebugScope.values) s: _ScopeStats(),
  };

  void record(DebugRecord record) {
    final s = _scopeOf(record);
    final stats = _byScope[s]!;
    stats.calls += 1;

    if (record is QwenCallRecord) {
      switch (record.status) {
        case QwenCallStatus.ok:
          stats.ok += 1;
        case QwenCallStatus.httpError:
          stats.httpError += 1;
        case QwenCallStatus.parseError:
          stats.parseError += 1;
      }
      stats.totalMs += record.elapsedMs;
      if (record.elapsedMs > stats.maxMs) stats.maxMs = record.elapsedMs;
      stats._recent.add(record.elapsedMs);
      if (stats._recent.length > _ScopeStats.kRecentCap) {
        stats._recent.removeAt(0);
      }
    } else if (record is EventRecord && record.level == EventLevel.error) {
      stats.otherError += 1;
    }
  }

  DebugScope _scopeOf(DebugRecord r) {
    if (r is QwenCallRecord) {
      switch (r.scope) {
        case 'identify':
          return DebugScope.identify;
        case 'strategy':
          return DebugScope.strategy;
        case 'refine':
          return DebugScope.refine;
        case 'grade':
          return DebugScope.grade;
        default:
          return DebugScope.strategy;
      }
    }
    if (r is EventRecord) {
      switch (r.scope) {
        case 'flutter_error':
          return DebugScope.flutterError;
        case 'async_error':
          return DebugScope.asyncError;
        case 'zone_error':
          return DebugScope.zoneError;
        default:
          return DebugScope.strategy;
      }
    }
    return DebugScope.strategy;
  }

  StatsSnapshot snapshot() {
    final now = DateTime.now();
    final map = <DebugScope, ScopeSnapshot>{};
    _byScope.forEach((k, v) {
      map[k] = ScopeSnapshot(
        calls: v.calls,
        ok: v.ok,
        httpError: v.httpError,
        parseError: v.parseError,
        otherError: v.otherError,
        totalMs: v.totalMs,
        maxMs: v.maxMs,
        p50Ms: _percentile(v._recent, 0.5),
        p95Ms: _percentile(v._recent, 0.95),
      );
    });
    return StatsSnapshot(map, now);
  }
}

int _percentile(List<int> sorted, double p) {
  if (sorted.isEmpty) return 0;
  final sortedCopy = [...sorted]..sort();
  final idx = ((sortedCopy.length - 1) * p).floor().clamp(0, sortedCopy.length - 1);
  return sortedCopy[idx];
}
