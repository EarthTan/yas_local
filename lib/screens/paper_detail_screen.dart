import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/task_provider.dart';
import '../utils/debouncer.dart';
import '../widgets/rich_content.dart';

class PaperDetailScreen extends ConsumerStatefulWidget {
  final String submissionId;
  const PaperDetailScreen({super.key, required this.submissionId});

  @override
  ConsumerState<PaperDetailScreen> createState() => _PaperDetailScreenState();
}

class _PaperDetailScreenState extends ConsumerState<PaperDetailScreen> {
  final Map<int, double> _dragValues = {};
  final Debouncer _saveDebouncer = Debouncer(const Duration(milliseconds: 200));

  @override
  void dispose() {
    _saveDebouncer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(taskProvider);
    final sub = state.submissions.firstWhere((s) => s.id == widget.submissionId);
    final notifier = ref.read(taskProvider.notifier);
    final task = notifier.taskById(sub.taskId);
    final rubricByNum = {
      if (task != null)
        for (final r in task.rubric) r.questionNumber: r,
    };

    return Scaffold(
      appBar: AppBar(title: Text('${sub.label} · ${sub.computedTotal} 分')),
      body: ListView(children: [
        if (sub.imagePath != null)
          Image.file(File(sub.imagePath!), height: 220, fit: BoxFit.contain),
        for (final item in sub.items)
          Builder(builder: (context) {
            final maxPts = rubricByNum[item.questionNumber]?.maxPoints ?? 20;
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('第 ${item.questionNumber} 题（${item.type == 'objective' ? '客观' : '主观'}）',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text(_emoji(item.trafficLight)),
                  ]),
                  const SizedBox(height: 4),
                  RichContent('学生作答：${item.extractedAnswer ?? "（未识别）"}'),
                  if (item.checkpoints.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Divider(height: 1),
                    const SizedBox(height: 6),
                    for (final cp in item.checkpoints)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Icon(
                            cp.passed ? Icons.check_circle : Icons.cancel,
                            color: cp.passed ? Colors.green : Colors.red,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: RichContent(
                                      cp.description,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                  Text(
                                    '（${cp.pointsAwarded}分）',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ],
                              ),
                              if (cp.reason.isNotEmpty)
                                RichContent(
                                  cp.reason,
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                            ]),
                          ),
                        ]),
                      ),
                    const SizedBox(height: 4),
                  ],
                  if (item.aiComment != null && item.aiComment!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: RichContent('AI 评语：${item.aiComment!}'),
                    ),
                  Row(children: [
                    Text('AI 分：${item.aiScore ?? "-"}'),
                    const Spacer(),
                    Text('终分：${item.finalScore}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ]),
                  Row(children: [
                    const Text('改分：'),
                    Expanded(
                      child: Slider(
                        value: _dragValues[item.questionNumber] ?? item.finalScore.toDouble().clamp(0, maxPts.toDouble()),
                        min: 0,
                        max: maxPts.toDouble(),
                        divisions: maxPts,
                        label: (_dragValues[item.questionNumber] ?? item.finalScore.toDouble()).round().toString(),
                        onChanged: (v) {
                          setState(() => _dragValues[item.questionNumber] = v);
                          _saveDebouncer(() {
                            final updated = [
                              for (final it in sub.items)
                                if (it.questionNumber == item.questionNumber)
                                  it.copyWith(teacherScore: v.round())
                                else
                                  it,
                            ];
                            notifier.updateSubmission(sub.copyWith(items: updated));
                          });
                        },
                        onChangeEnd: (v) {
                          _saveDebouncer.flush();
                          final updated = [
                            for (final it in sub.items)
                              if (it.questionNumber == item.questionNumber)
                                it.copyWith(teacherScore: v.round())
                              else
                                it,
                          ];
                          notifier.updateSubmission(sub.copyWith(items: updated));
                        },
                      ),
                    ),
                    Text('/ $maxPts'),
                  ]),
                ]),
              ),
            );
          }),
      ]),
    );
  }

  String _emoji(String light) => switch (light) { 'green' => '🟢', 'yellow' => '🟡', _ => '🔴' };
}
