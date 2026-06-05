import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/debug_provider.dart';
import '../../../providers/task_provider.dart';
import '../../../services/debug/debug_service.dart';
import '../../../services/debug/tab_constants.dart';
import '_export_button.dart';

class StateTab extends ConsumerWidget {
  const StateTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap = ref.watch(debugProvider).stateSnapshot;
    Map<String, Object?> exportData() => <String, Object?>{
          'tab': 'state',
          'capturedAt': DateTime.now().toIso8601String(),
          'snapshot': snap == null
              ? null
              : {
                  'capturedAt': snap.capturedAt.toIso8601String(),
                  'taskCount': snap.tasks.length,
                  'referenceCount': snap.references.length,
                  'tasks': snap.tasks.map((t) => (t as dynamic).toJson()).toList(),
                  'references': snap.references.map((r) => (r as dynamic).toJson()).toList(),
                  'settingsNote': 'apiKey redacted',
                },
        };
    if (snap == null) {
      return Column(
        children: [
          Row(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text('状态', style: Theme.of(context).textTheme.titleMedium),
              ),
              const Spacer(),
              ExportButton(tab: kTabState, data: exportData),
            ],
          ),
          const Divider(height: 1),
          const Expanded(
            child: Center(
              child: Text('暂无状态快照', style: TextStyle(color: Colors.black)),
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        Row(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('状态', style: Theme.of(context).textTheme.titleMedium),
            ),
            const Spacer(),
            ExportButton(tab: kTabState, data: exportData),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              _settingsTile(snap),
              const Divider(color: Colors.black26),
              ..._taskTiles(snap),
            ],
          ),
        ),
      ],
    );
  }

  Widget _settingsTile(StateSnapshot snap) {
    final s = snap.settings;
    final apiKey = s.apiKey as String;
    return ExpansionTile(
      title: const Text('📁 Settings', style: TextStyle(color: Colors.black)),
      subtitle: Text('apiKey: ${apiKey.substring(0, apiKey.length < 4 ? apiKey.length : 4)}... · baseUrl: ${s.baseUrl}',
          style: const TextStyle(color: Colors.black, fontSize: 12)),
      children: [
        ListTile(
          title: const Text('vlModel', style: TextStyle(color: Colors.black)),
          subtitle: Text(s.vlModel, style: const TextStyle(color: Colors.black)),
        ),
        ListTile(
          title: const Text('textModel', style: TextStyle(color: Colors.black)),
          subtitle: Text(s.textModel, style: const TextStyle(color: Colors.black)),
        ),
      ],
    );
  }

  List<Widget> _taskTiles(StateSnapshot snap) {
    final tasks = snap.tasks;
    if (tasks.isEmpty) {
      return [
        const ListTile(
          title: Text('📁 Tasks (0)', style: TextStyle(color: Colors.black)),
        ),
      ];
    }
    return [
      ListTile(
        title: Text('📁 Tasks (${tasks.length})', style: const TextStyle(color: Colors.black)),
      ),
      for (final t in tasks) _TaskTile(task: t),
    ];
  }
}

class _TaskTile extends ConsumerWidget {
  const _TaskTile({required this.task});
  final dynamic task; // GradingTask at runtime; dynamic to avoid import

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = task.name as String;
    final subs = ref.read(taskProvider.notifier).submissionsFor(task.id as String);
    final rubric = (task.rubric as List?) ?? const [];
    final questionPaperPaths = (task.questionPaperPaths as List?) ?? const [];
    final answerImagePaths = (task.answerImagePaths as List?) ?? const [];
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: ExpansionTile(
        title: Text('📂 $name · ${subs.length} 份', style: const TextStyle(color: Colors.black)),
        children: [
          ListTile(title: Text('Rubric (${rubric.length} 题)', style: const TextStyle(color: Colors.black))),
          ListTile(title: Text('QuestionPaper (${questionPaperPaths.length} 张)', style: const TextStyle(color: Colors.black))),
          ListTile(title: Text('AnswerKey (${answerImagePaths.length} 张)', style: const TextStyle(color: Colors.black))),
          ListTile(title: Text('Submissions: ${subs.length}', style: const TextStyle(color: Colors.black))),
        ],
      ),
    );
  }
}
