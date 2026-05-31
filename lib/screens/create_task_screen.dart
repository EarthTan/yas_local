import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/task.dart';
import '../models/rubric.dart';
import '../providers/task_provider.dart';

class CreateTaskScreen extends ConsumerStatefulWidget {
  const CreateTaskScreen({super.key});
  @override
  ConsumerState<CreateTaskScreen> createState() => _S();
}

class _Draft {
  final int number;
  String type = 'objective';
  int maxPoints = 5;
  String correctAnswer = '';
  String questionText = '';
  String criteria = '';
  _Draft(this.number);
}

class _S extends ConsumerState<CreateTaskScreen> {
  final _title = TextEditingController();
  String _subject = 'math';
  final List<_Draft> _items = [];

  @override
  void dispose() { _title.dispose(); super.dispose(); }

  void _add() => setState(() => _items.add(_Draft(_items.length + 1)));

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请填写任务名称')));
      return;
    }
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请至少添加一道题')));
      return;
    }
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final task = GradingTask(
      id: id,
      name: _title.text.trim(),
      subject: _subject,
      createdAt: DateTime.now(),
      rubric: _items
          .map((d) => RubricItem(
                questionNumber: d.number,
                type: d.type,
                maxPoints: d.maxPoints,
                correctAnswer: d.type == 'objective' && d.correctAnswer.trim().isNotEmpty
                    ? d.correctAnswer.trim()
                    : null,
                questionText: d.questionText.trim(),
                criteria: d.criteria.trim(),
              ))
          .toList(),
    );
    await ref.read(taskProvider.notifier).addTask(task);
    if (mounted) context.pushReplacement('/tasks/$id/capture');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('新建批改任务'),
        actions: [TextButton(onPressed: _save, child: const Text('保存并拍照'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _title, decoration: const InputDecoration(labelText: '任务名称（如：第3单元测验）', border: OutlineInputBorder())),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _subject,
            decoration: const InputDecoration(labelText: '科目', border: OutlineInputBorder()),
            items: const ['math','chinese','english','physics','chemistry','biology','history']
                .map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: (v) => setState(() => _subject = v!),
          ),
          const SizedBox(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('评分标准', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            TextButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('添加题目')),
          ]),
          ..._items.map((d) => _ItemEditor(
                draft: d,
                onChanged: () => setState(() {}),
                onDelete: () => setState(() => _items.remove(d)),
              )),
        ],
      ),
    );
  }
}

class _ItemEditor extends StatelessWidget {
  final _Draft draft;
  final VoidCallback onChanged;
  final VoidCallback onDelete;
  const _ItemEditor({required this.draft, required this.onChanged, required this.onDelete});

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('第 ${draft.number} 题', style: const TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(onPressed: onDelete, icon: const Icon(Icons.delete_outline, color: Colors.red)),
            ]),
            DropdownButtonFormField<String>(
              initialValue: draft.type,
              decoration: const InputDecoration(labelText: '题型'),
              items: const [
                DropdownMenuItem(value: 'objective', child: Text('客观题')),
                DropdownMenuItem(value: 'subjective', child: Text('主观题')),
              ],
              onChanged: (v) { draft.type = v!; onChanged(); },
            ),
            TextFormField(
              initialValue: '${draft.maxPoints}',
              decoration: const InputDecoration(labelText: '满分'),
              keyboardType: TextInputType.number,
              onChanged: (v) { draft.maxPoints = int.tryParse(v) ?? draft.maxPoints; },
            ),
            if (draft.type == 'objective')
              TextFormField(
                initialValue: draft.correctAnswer,
                decoration: const InputDecoration(labelText: '正确答案（选填，不填则由 AI 判断）'),
                onChanged: (v) => draft.correctAnswer = v,
              )
            else
              TextFormField(
                initialValue: draft.criteria,
                decoration: const InputDecoration(labelText: '评分标准描述（选填）'),
                maxLines: 2,
                onChanged: (v) => draft.criteria = v,
              ),
          ]),
        ),
      );
}
