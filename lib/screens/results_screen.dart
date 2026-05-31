import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/submission.dart';
import '../providers/task_provider.dart';

class ResultsScreen extends ConsumerWidget {
  final String taskId;
  const ResultsScreen({super.key, required this.taskId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(taskProvider);
    final notifier = ref.read(taskProvider.notifier);
    final task = notifier.taskById(taskId);
    final subs = notifier.submissionsFor(taskId);
    final scored = subs.where((s) => s.status == SubmissionStatus.done).map((s) => s.computedTotal).toList();
    final avg = scored.isEmpty ? 0.0 : scored.reduce((a, b) => a + b) / scored.length;

    return Scaffold(
      appBar: AppBar(title: Text(task?.name ?? '结果')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _stat('已批改', '${scored.length}/${subs.length}'),
            _stat('平均分', avg.toStringAsFixed(1)),
            _stat('最高', scored.isEmpty ? '-' : '${scored.reduce((a, b) => a > b ? a : b)}'),
            _stat('最低', scored.isEmpty ? '-' : '${scored.reduce((a, b) => a < b ? a : b)}'),
          ]),
        ),
        const Divider(),
        Expanded(
          child: ListView(children: [
            for (final s in subs)
              ListTile(
                leading: _statusIcon(s.status),
                title: Text(s.label),
                subtitle: s.pendingReviewCount > 0 ? Text('${s.pendingReviewCount} 道主观题待复核') : null,
                trailing: Text('${s.computedTotal} 分', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                onTap: () => context.push('/submissions/${s.id}'),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton.icon(
            onPressed: () => context.push('/tasks/$taskId/capture'),
            icon: const Icon(Icons.add_a_photo),
            label: const Text('继续添加作业'),
          ),
        ),
      ]),
    );
  }

  Widget _stat(String label, String value) => Column(children: [
        Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.grey)),
      ]);

  Widget _statusIcon(SubmissionStatus s) => switch (s) {
        SubmissionStatus.done => const Icon(Icons.check_circle, color: Colors.green),
        SubmissionStatus.failed => const Icon(Icons.error, color: Colors.red),
        SubmissionStatus.processing => const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        _ => const Icon(Icons.hourglass_empty, color: Colors.grey),
      };
}
