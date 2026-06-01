import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/task.dart';
import '../providers/task_provider.dart';

class CreateTaskScreen extends ConsumerStatefulWidget {
  const CreateTaskScreen({super.key});
  @override
  ConsumerState<CreateTaskScreen> createState() => _S();
}

class _S extends ConsumerState<CreateTaskScreen> {
  final _title = TextEditingController();
  String _subject = 'math';

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请填写任务名称')));
      return;
    }
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final task = GradingTask(
      id: id,
      name: _title.text.trim(),
      subject: _subject,
      createdAt: DateTime.now(),
      rubric: [],
    );
    await ref.read(taskProvider.notifier).addTask(task);
    if (mounted) context.pushReplacement('/tasks/$id/capture');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('新建批改任务'),
        actions: [
          TextButton(onPressed: _save, child: const Text('保存并拍照')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: '任务名称（如：第3单元测验）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _subject,
            decoration: const InputDecoration(
              labelText: '科目',
              border: OutlineInputBorder(),
            ),
            items: const [
              'math', 'chinese', 'english', 'physics',
              'chemistry', 'biology', 'history'
            ]
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (v) => setState(() => _subject = v!),
          ),
          const SizedBox(height: 24),
          Text(
            '提示：保存后上传作业图片，AI 会自动识别题目，\n您确认后再生成评分策略。',
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
        ],
      ),
    );
  }
}
