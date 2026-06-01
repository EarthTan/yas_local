import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/identified_question.dart';
import '../models/rubric.dart';
import '../providers/identification_provider.dart';
import '../providers/task_provider.dart';

class IdentifyScreen extends ConsumerStatefulWidget {
  final String taskId;
  const IdentifyScreen({super.key, required this.taskId});

  @override
  ConsumerState<IdentifyScreen> createState() => _S();
}

class _EditableQuestion {
  final int questionNumber;
  final TextEditingController textCtrl;
  String type;
  final TextEditingController pointsCtrl;
  final TextEditingController answerCtrl;

  _EditableQuestion({
    required this.questionNumber,
    required String questionText,
    required this.type,
  })  : textCtrl = TextEditingController(text: questionText),
        pointsCtrl = TextEditingController(),
        answerCtrl = TextEditingController();

  void dispose() {
    textCtrl.dispose();
    pointsCtrl.dispose();
    answerCtrl.dispose();
  }
}

class _S extends ConsumerState<IdentifyScreen> {
  final List<_EditableQuestion> _editables = [];
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(identificationProvider.notifier).identify(widget.taskId);
    });
  }

  @override
  void dispose() {
    for (final e in _editables) {
      e.dispose();
    }
    super.dispose();
  }

  void _initEditables(List<IdentifiedQuestion> questions) {
    _initialized = true;
    _editables.clear();
    _editables.addAll(questions.map((q) => _EditableQuestion(
          questionNumber: q.number,
          questionText: q.questionText,
          type: q.type,
        )));
  }

  Future<void> _confirm() async {
    for (final e in _editables) {
      final pts = int.tryParse(e.pointsCtrl.text.trim());
      if (pts == null || pts <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('请为第 ${e.questionNumber} 题填写有效分值')));
        return;
      }
    }

    final rubric = _editables.map((e) {
      final pts = int.parse(e.pointsCtrl.text.trim());
      final answer = e.answerCtrl.text.trim();
      return RubricItem(
        questionNumber: e.questionNumber,
        type: e.type,
        maxPoints: pts,
        correctAnswer:
            e.type == 'objective' && answer.isNotEmpty ? answer : null,
        questionText: e.textCtrl.text.trim(),
      );
    }).toList();

    await ref.read(taskProvider.notifier).updateTaskRubric(widget.taskId, rubric);
    if (mounted) context.pushReplacement('/tasks/${widget.taskId}/strategy');
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<IdentificationState>(identificationProvider, (_, next) {
      if (!next.identifying && next.error == null && next.hasQuestions && !_initialized) {
        setState(() => _initEditables(next.questions));
      }
    });

    final state = ref.watch(identificationProvider);

    if (state.identifying) {
      return Scaffold(
        appBar: AppBar(title: const Text('识别题目')),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('AI 正在识别作业题目…'),
            ],
          ),
        ),
      );
    }

    if (state.error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('识别题目')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(state.error!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    setState(() => _initialized = false);
                    ref.read(identificationProvider.notifier).identify(widget.taskId);
                  },
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('确认题目'),
        actions: [
          TextButton(
            onPressed: _editables.isNotEmpty ? _confirm : null,
            child: const Text('确认并生成策略'),
          ),
        ],
      ),
      body: _editables.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _editables.length,
              itemBuilder: (_, i) => _QuestionCard(
                editable: _editables[i],
                onChanged: () => setState(() {}),
              ),
            ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  final _EditableQuestion editable;
  final VoidCallback onChanged;

  const _QuestionCard({required this.editable, required this.onChanged});

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('第 ${editable.questionNumber} 题',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 10),
              TextFormField(
                controller: editable.textCtrl,
                decoration: const InputDecoration(
                    labelText: '题目内容', border: OutlineInputBorder()),
                maxLines: 3,
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: editable.type,
                    decoration: const InputDecoration(
                        labelText: '题型', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'objective', child: Text('客观题')),
                      DropdownMenuItem(
                          value: 'subjective', child: Text('主观题')),
                    ],
                    onChanged: (v) {
                      editable.type = v!;
                      onChanged();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: editable.pointsCtrl,
                    decoration: const InputDecoration(
                        labelText: '满分', border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ]),
              if (editable.type == 'objective') ...[
                const SizedBox(height: 10),
                TextFormField(
                  controller: editable.answerCtrl,
                  decoration: const InputDecoration(
                      labelText: '正确答案（选填）',
                      border: OutlineInputBorder()),
                ),
              ],
            ],
          ),
        ),
      );
}
