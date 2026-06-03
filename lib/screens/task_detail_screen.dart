import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/reference_answer.dart';
import '../models/submission.dart';
import '../providers/task_provider.dart';
import '../services/reference_store.dart';

enum ResultsSectionStatus {
  waitingForStrategy,
  waitingForSubmissions,
  readyToGrade,
  hasResults,
}

ResultsSectionStatus resolveResultsState({
  required bool allConfirmed,
  required int subCount,
  required bool hasGradingResults,
}) {
  if (hasGradingResults) return ResultsSectionStatus.hasResults;
  if (!allConfirmed) return ResultsSectionStatus.waitingForStrategy;
  if (subCount == 0) return ResultsSectionStatus.waitingForSubmissions;
  return ResultsSectionStatus.readyToGrade;
}

class TaskDetailScreen extends ConsumerStatefulWidget {
  final String taskId;
  const TaskDetailScreen({super.key, required this.taskId});

  @override
  ConsumerState<TaskDetailScreen> createState() => _S();
}

class _S extends ConsumerState<TaskDetailScreen> {
  List<ReferenceAnswer>? _cachedRefs; // null = not loaded yet
  bool _loadingRefs = true;

  @override
  void initState() {
    super.initState();
    _loadRefs();
  }

  Future<void> _loadRefs() async {
    final refs = await ReferenceStore.load(widget.taskId);
    if (!mounted) return;
    setState(() {
      _cachedRefs = refs;
      _loadingRefs = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(taskProvider);
    final notifier = ref.read(taskProvider.notifier);
    final task = notifier.taskById(widget.taskId);
    final subs = notifier.submissionsFor(widget.taskId);

    if (task == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('任务详情')),
        body: const Center(child: Text('任务不存在')),
      );
    }

    final totalPoints = task.rubric.fold<int>(0, (sum, r) => sum + r.maxPoints);
    final gradedCount = subs.where((s) => s.status == SubmissionStatus.done).length;
    final hasGradingResults = gradedCount > 0;

    // Strategy status
    final refs = _cachedRefs ?? <ReferenceAnswer>[];
    final hasRefs = refs.isNotEmpty;
    final allConfirmed = hasRefs && refs.every((r) => r.confirmed);
    final hasRubric = task.rubric.isNotEmpty;

    // Show re-grade button if there are grading results and references exist
    final showRegrade = hasGradingResults && hasRefs;

    return Scaffold(
      appBar: AppBar(title: Text(task.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Task info card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(task.subject,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (hasRubric)
                    Text('共 ${task.rubric.length} 道题 · 满分 $totalPoints 分',
                        style: TextStyle(color: Colors.grey[600])),
                  if (task.questionPaperPaths.isNotEmpty)
                    Text('题目照片 ${task.questionPaperPaths.length} 张',
                        style: TextStyle(color: Colors.grey[600])),
                  if (task.answerImagePaths.isNotEmpty)
                    Text('答案照片 ${task.answerImagePaths.length} 张',
                        style: TextStyle(color: Colors.grey[600])),
                  Text('已上传 ${subs.length} 份 · 已批改 $gradedCount 份',
                      style: TextStyle(color: Colors.grey[600])),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Strategy section
          _sectionHeader('批改策略'),
          const SizedBox(height: 8),
          if (_loadingRefs)
            const Center(child: CircularProgressIndicator())
          else if (!hasRubric)
            _infoTile(
              Icons.photo_library,
              '题目照片已上传，待 AI 识别',
              Colors.orange,
            )
          else if (!hasRefs)
            _infoTile(
              Icons.auto_awesome,
              '题目已确认，尚未生成批改策略',
              Colors.orange,
            )
          else if (allConfirmed)
            _infoTile(
              Icons.check_circle,
              '批改策略已就绪（${refs.length} 道题均已确认）',
              Colors.green,
            )
          else
            _infoTile(
              Icons.pending_actions,
              '批改策略待完善（${refs.where((r) => r.confirmed).length}/${refs.length} 道题已确认）',
              Colors.orange,
            ),
          const SizedBox(height: 8),
          if (!_loadingRefs) ...[
            if (!hasRubric)
              OutlinedButton.icon(
                onPressed: () => context.push('/tasks/${widget.taskId}/identify'),
                icon: const Icon(Icons.find_in_page),
                label: const Text('识别题目'),
              )
            else
              OutlinedButton.icon(
                onPressed: () => context.push('/tasks/${widget.taskId}/strategy'),
                icon: Icon(hasRefs ? Icons.edit_note : Icons.auto_awesome),
                label: Text(
                  hasRefs
                      ? (allConfirmed ? '查看 / 修改批改策略' : '继续完善批改策略')
                      : '生成批改策略',
                ),
              ),
          ],
          const SizedBox(height: 24),

          // Results section
          _sectionHeader('批改结果'),
          const SizedBox(height: 8),
          if (_loadingRefs)
            const Center(child: CircularProgressIndicator())
          else
            ...switch (resolveResultsState(
              allConfirmed: allConfirmed,
              subCount: subs.length,
              hasGradingResults: hasGradingResults,
            )) {
              ResultsSectionStatus.hasResults => [
                FilledButton.icon(
                  onPressed: () => context.push('/tasks/${widget.taskId}/results'),
                  icon: const Icon(Icons.bar_chart),
                  label: const Text('查看批改结果'),
                ),
                if (showRegrade) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.deepOrange),
                    onPressed: _showRegradeDialog,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重新批改'),
                  ),
                ],
              ],
              ResultsSectionStatus.readyToGrade => [
                FilledButton.icon(
                  onPressed: () => context.push('/tasks/${widget.taskId}/grading'),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('开始批改'),
                ),
              ],
              ResultsSectionStatus.waitingForSubmissions => [
                _infoTile(Icons.upload_file, '请先上传学生作业', Colors.orange),
              ],
              ResultsSectionStatus.waitingForStrategy => [
                _infoTile(Icons.pending_actions, '请先完善并确认批改策略', Colors.grey),
              ],
            },

          const SizedBox(height: 24),

          // Upload more section
          _sectionHeader('作业管理'),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => context.push('/tasks/${widget.taskId}/capture'),
            icon: const Icon(Icons.add_a_photo),
            label: const Text('上传学生作业'),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) => Text(
        title,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey),
      );

  Widget _infoTile(IconData icon, String text, Color color) => Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color))),
        ],
      );

  void _showRegradeDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重新批改'),
        content: const Text('重新批改将使用当前批改策略覆盖已有的批改结果。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('旧批改结果保留。可随时点击「重新批改」重新批改。')),
              );
            },
            child: const Text('保留旧结果'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.deepOrange),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final router = GoRouter.of(context);
              await ref.read(taskProvider.notifier).resetGradingResults(widget.taskId);
              if (!mounted) return;
              router.push('/tasks/${widget.taskId}/grading');
            },
            child: const Text('立即重批'),
          ),
        ],
      ),
    );
  }
}
