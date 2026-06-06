import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/job_state.dart';
import '../models/submission.dart';
import '../providers/job_queue_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/task_provider.dart';
import '../services/qwen_error.dart';
import '../widgets/debug_entry_button.dart';

enum TaskCardKind {
  idle,
  strategyRunning,
  strategyDone,
  strategyFailed,
  gradingRunning,
  gradingComplete,
  gradingIncomplete,
  gradingFailed,
}

class TaskCardStatus {
  final TaskCardKind kind;
  final String label;
  final double? progress; // 0..1 -> determinate bar; null -> none/indeterminate
  final bool indeterminate;
  final String? retryHint; // null = don't render the retry line
  const TaskCardStatus(
    this.kind,
    this.label, {
    this.progress,
    this.indeterminate = false,
    this.retryHint,
  });
}

/// Pure resolver for what a home card shows. Depends only on the in-memory
/// live [job] plus persisted submission counts — never reads ref files.
/// The last three (job-less) branches derive from persisted submission
/// status, so a task still reads correctly after an app restart clears the
/// job map.
TaskCardStatus resolveTaskCardStatus({
  required JobState? job,
  required String subject,
  required int subTotal,
  required int subDone,
  required int subFailed,
  QwenErrorKind? retryKind,
  int retryAttempt = 0,
}) {
  if (job != null && job.phase == JobPhase.running) {
    if (job.kind == JobKind.strategy) {
      return TaskCardStatus(
        TaskCardKind.strategyRunning,
        '生成批改策略中 ${job.done} / ${job.total}',
        progress: job.total > 0 ? job.done / job.total : null,
        indeterminate: job.total == 0,
        retryHint: _retryHint(retryAttempt, retryKind),
      );
    }
    return TaskCardStatus(
      TaskCardKind.gradingRunning,
      '批改中 ${job.done} / ${job.total}',
      progress: job.total > 0 ? job.done / job.total : null,
      indeterminate: job.total == 0,
      retryHint: _retryHint(retryAttempt, retryKind),
    );
  }
  if (job != null && job.phase == JobPhase.failed && job.failedCount > 0) {
    if (job.kind == JobKind.strategy) {
      return TaskCardStatus(
        TaskCardKind.strategyFailed,
        '策略生成失败 ${job.failedCount} 题 · 点击重试',
        retryHint: _retryHint(retryAttempt, retryKind),
      );
    }
    return TaskCardStatus(
      TaskCardKind.gradingFailed,
      '批改完成，${job.failedCount} 份失败 · 点击重试',
      retryHint: _retryHint(retryAttempt, retryKind),
    );
  }
  if (job != null &&
      job.phase == JobPhase.done &&
      job.kind == JobKind.strategy) {
    return TaskCardStatus(
      TaskCardKind.strategyDone,
      '策略已生成，待审核确认',
      retryHint: _retryHint(retryAttempt, retryKind),
    );
  }
  if (subTotal > 0 && subDone == subTotal) {
    return TaskCardStatus(
      TaskCardKind.gradingComplete,
      '批改完成 $subDone / $subTotal',
      retryHint: _retryHint(retryAttempt, retryKind),
    );
  }
  if (subDone > 0 && subDone < subTotal) {
    final failTag = subFailed > 0 ? '（$subFailed 失败）' : '';
    return TaskCardStatus(
      TaskCardKind.gradingIncomplete,
      '已批改 $subDone / $subTotal$failTag · 继续',
      retryHint: _retryHint(retryAttempt, retryKind),
    );
  }
  return TaskCardStatus(
    TaskCardKind.idle,
    '$subject · $subTotal 份',
    retryHint: _retryHint(retryAttempt, retryKind),
  );
}

/// Build the small orange retry line shown on the home card when an attempt
/// is in flight. Returns null when there is nothing useful to say.
String? _retryHint(int retryAttempt, QwenErrorKind? retryKind) {
  if (retryAttempt <= 0 || retryKind == null) return null;
  return '⟳ 重试 $retryAttempt/3 · ${retryKind.displayName}';
}

Color _statusColor(TaskCardKind kind) => switch (kind) {
  TaskCardKind.strategyRunning => Colors.blue,
  TaskCardKind.gradingRunning => Colors.blue,
  TaskCardKind.gradingComplete => Colors.green,
  TaskCardKind.strategyDone => Colors.green,
  TaskCardKind.gradingFailed => Colors.red,
  TaskCardKind.strategyFailed => Colors.red,
  TaskCardKind.gradingIncomplete => Colors.orange,
  TaskCardKind.idle => Colors.black54,
};

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(taskProvider);
    final configured = ref.watch(settingsProvider).isConfigured;
    final jobs = ref.watch(jobQueueProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('YAS 批改助手'),
        actions: [
          const DebugEntryButton(),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!configured)
            Material(
              color: Colors.orange.shade100,
              child: ListTile(
                leading: const Icon(Icons.warning_amber, color: Colors.orange),
                title: const Text('还没配置 Qwen API Key'),
                subtitle: const Text('点击前往设置填写后才能批改'),
                onTap: () => context.push('/settings'),
              ),
            ),
          Expanded(
            child: !state.loaded
                ? const Center(child: CircularProgressIndicator())
                : state.tasks.isEmpty
                ? const Center(child: Text('暂无批改任务，点击 + 新建'))
                : Builder(
                    builder: (context) {
                      // Group submissions by taskId in a single pass (was:
                      // O(N×M) per build, ~900 comparisons for 10 tasks ×
                      // 30 submissions).
                      final subsByTask = <String, List<Submission>>{};
                      for (final s in state.submissions) {
                        subsByTask
                            .putIfAbsent(s.taskId, () => <Submission>[])
                            .add(s);
                      }
                      return ListView(
                        children: [
                          for (final t in state.tasks.reversed)
                            Builder(
                              builder: (context) {
                                final subs =
                                    subsByTask[t.id] ?? const <Submission>[];
                                final status = resolveTaskCardStatus(
                                  job: jobs[t.id],
                                  subject: t.subject,
                                  subTotal: subs.length,
                                  subDone: subs
                                      .where(
                                        (s) =>
                                            s.status == SubmissionStatus.done,
                                      )
                                      .length,
                                  subFailed: subs
                                      .where(
                                        (s) =>
                                            s.status == SubmissionStatus.failed,
                                      )
                                      .length,
                                  retryKind: jobs[t.id]?.lastErrorKind,
                                  retryAttempt: jobs[t.id]?.attempt ?? 0,
                                );
                                return ListTile(
                                  title: Text(
                                    t.name,
                                    style: const TextStyle(color: Colors.black87),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        status.label,
                                        style: TextStyle(
                                          color: _statusColor(status.kind),
                                        ),
                                      ),
                                      if (status.progress != null ||
                                          status.indeterminate) ...[
                                        const SizedBox(height: 6),
                                        LinearProgressIndicator(
                                          value: status.indeterminate
                                              ? null
                                              : status.progress,
                                        ),
                                      ],
                                      if (status.retryHint != null) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          status.retryHint!,
                                          style: const TextStyle(
                                            color: Colors.deepOrange,
                                            fontSize: 12,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  trailing: status.kind ==
                                              TaskCardKind.gradingFailed ||
                                          status.kind ==
                                              TaskCardKind.strategyFailed
                                      ? const Icon(Icons.refresh,
                                          color: Colors.red)
                                      : const Icon(Icons.chevron_right),
                                  // A failed card promises "点击重试": tapping re-runs
                                  // the corresponding job (strategy or grading),
                                  // which targets only the unfinished units. Other
                                  // cards open the task.
                                  onTap: status.kind == TaskCardKind.gradingFailed
                                      ? () => ref
                                            .read(jobQueueProvider.notifier)
                                            .startGrading(t.id)
                                      : status.kind ==
                                              TaskCardKind.strategyFailed
                                          ? () => ref
                                                .read(jobQueueProvider.notifier)
                                                .startStrategy(t.id)
                                          : () => context.push('/tasks/${t.id}'),
                                );
                              },
                            ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/tasks/create'),
        icon: const Icon(Icons.add),
        label: const Text('新建任务'),
      ),
    );
  }
}
