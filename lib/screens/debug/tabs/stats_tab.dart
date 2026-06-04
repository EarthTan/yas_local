import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/debug_provider.dart';
import '../../../services/debug/debug_service.dart';
import '../../../services/debug/debug_stats.dart';
import '../../../services/debug/tab_constants.dart';
import '_export_button.dart';

class StatsTab extends ConsumerWidget {
  const StatsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the provider so the tab repaints whenever new records land in
    // the buffers; the actual numbers come from the canonical DebugStats on
    // the singleton service.
    ref.watch(debugProvider);
    final stats = DebugService.instance.stats.snapshot();
    Map<String, Object?> exportData() => <String, Object?>{
          'tab': 'stats',
          'capturedAt': DateTime.now().toIso8601String(),
          'byScope': stats.byScope.map((k, v) => MapEntry(k.name, {
                'calls': v.calls,
                'ok': v.ok,
                'httpError': v.httpError,
                'parseError': v.parseError,
                'otherError': v.otherError,
                'totalMs': v.totalMs,
                'maxMs': v.maxMs,
                'p50Ms': v.p50Ms,
                'p95Ms': v.p95Ms,
              })),
          'global': {
            'totalCalls': stats.totalCalls,
            'totalErrors': stats.totalErrors,
            'totalVlmMs': stats.totalVlmMs,
            'errorRate': stats.errorRate,
          },
        };
    return Column(
      children: [
        Row(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('统计', style: Theme.of(context).textTheme.titleMedium),
            ),
            const Spacer(),
            ExportButton(tab: kTabStats, data: exportData),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ...DebugScope.values
                  .where((s) => stats.byScope[s]!.calls > 0)
                  .map((s) => _ScopeCard(scope: s, snap: stats.byScope[s]!)),
              const Divider(),
              _GlobalCard(snap: stats),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScopeCard extends StatelessWidget {
  const _ScopeCard({required this.scope, required this.snap});
  final DebugScope scope;
  final ScopeSnapshot snap;

  String get _displayName => switch (scope) {
        DebugScope.identify => '题目识别',
        DebugScope.strategy => '策略生成',
        DebugScope.refine => '策略优化',
        DebugScope.grade => '批改',
        DebugScope.flutterError => 'Flutter 错误',
        DebugScope.asyncError => 'Async 错误',
        DebugScope.zoneError => 'Zone 错误',
      };

  @override
  Widget build(BuildContext context) {
    final errCount = snap.httpError + snap.parseError + snap.otherError;
    final errRate = snap.calls == 0 ? 0.0 : errCount / snap.calls;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_displayName, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('调用 ${snap.calls}  成功 ${snap.ok}  HTTP 错误 ${snap.httpError}  解析 ${snap.parseError}'),
            Text('错误率 ${(errRate * 100).toStringAsFixed(1)}%'),
            if (snap.totalMs > 0) ...[
              const SizedBox(height: 4),
              Text('总耗时 ${_formatMs(snap.totalMs)}  最长 ${_formatMs(snap.maxMs)}'),
              Text('p50 ${_formatMs(snap.p50Ms)}  p95 ${_formatMs(snap.p95Ms)}'),
            ],
          ],
        ),
      ),
    );
  }
}

class _GlobalCard extends StatelessWidget {
  const _GlobalCard({required this.snap});
  final StatsSnapshot snap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('全局 (since app start)', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('调用 ${snap.totalCalls}  错误 ${snap.totalErrors}  错误率 ${(snap.errorRate * 100).toStringAsFixed(1)}%'),
            Text('VLM 总耗时 ${_formatMs(snap.totalVlmMs)}'),
          ],
        ),
      ),
    );
  }
}

String _formatMs(int ms) {
  if (ms < 1000) return '${ms}ms';
  if (ms < 60000) return '${(ms / 1000).toStringAsFixed(1)}s';
  return '${ms ~/ 60000}m ${((ms % 60000) / 1000).toStringAsFixed(0)}s';
}
