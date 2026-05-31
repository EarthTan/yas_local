import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/task_provider.dart';

class PaperDetailScreen extends ConsumerWidget {
  final String submissionId;
  const PaperDetailScreen({super.key, required this.submissionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(taskProvider);
    final sub = state.submissions.firstWhere((s) => s.id == submissionId);
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
                  Text('学生作答：${item.extractedAnswer ?? "（未识别）"}'),
                  if (item.aiComment != null && item.aiComment!.isNotEmpty)
                    Padding(padding: const EdgeInsets.only(top: 4), child: Text('AI 评语：${item.aiComment}')),
                  Row(children: [
                    Text('AI 分：${item.aiScore ?? "-"}'),
                    const Spacer(),
                    Text('终分：${item.finalScore}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ]),
                  Row(children: [
                    const Text('改分：'),
                    Expanded(
                      child: Slider(
                        value: item.finalScore.toDouble().clamp(0, maxPts.toDouble()),
                        min: 0,
                        max: maxPts.toDouble(),
                        divisions: maxPts,
                        label: '${item.finalScore}',
                        onChanged: (v) {
                          final updated = [
                            for (final it in sub.items)
                              if (it.questionNumber == item.questionNumber)
                                it.copyWith(teacherScore: v.round())
                              else it,
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
