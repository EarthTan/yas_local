import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/debug_provider.dart';
import '../providers/task_provider.dart';
import '../services/debug_service.dart';

class DebugScreen extends ConsumerWidget {
  const DebugScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Debug'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Qwen', icon: Icon(Icons.cloud)),
              Tab(text: '事件', icon: Icon(Icons.timeline)),
              Tab(text: '状态', icon: Icon(Icons.storage)),
              Tab(text: 'JSON', icon: Icon(Icons.data_object)),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _QwenTab(),
            _EventsTab(),
            _StateTab(),
            _JsonTab(),
          ],
        ),
      ),
    );
  }
}

class _QwenTab extends ConsumerWidget {
  const _QwenTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final calls = ref.watch(debugProvider).qwenCalls.reversed.toList();
    if (calls.isEmpty) {
      return const Center(
        child: Text('暂无 Qwen 调用记录', style: TextStyle(color: Colors.black)),
      );
    }
    return ListView.builder(
      itemCount: calls.length,
      itemBuilder: (context, i) => _QwenCallRow(record: calls[i]),
    );
  }
}

class _QwenCallRow extends StatelessWidget {
  const _QwenCallRow({required this.record});
  final QwenCallRecord record;

  @override
  Widget build(BuildContext context) {
    final isError = record.status != QwenCallStatus.ok;
    final headerColor = isError ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4);
    final headerTextColor = isError ? const Color(0xFF7F1D1D) : const Color(0xFF14532D);
    final ts = record.timestamp.toIso8601String().substring(11, 19);
    final images = record.messages
        .expand((m) => (m['content'] is List) ? (m['content'] as List) : const [])
        .whereType<Map>()
        .where((e) => e['type'] == 'image_url')
        .length;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: headerColor,
      child: ExpansionTile(
        initiallyExpanded: false,
        title: Text(
          '${record.status == QwenCallStatus.ok ? "✅" : "❌"} $ts · ${record.model} · POST ${record.endpoint} · ${record.statusCode ?? "?"} · ${record.elapsedMs}ms',
          style: TextStyle(color: headerTextColor, fontSize: 13),
        ),
        subtitle: Text(
          '→ ${record.scope} · $images images${record.errorMessage != null ? " · ${record.errorMessage}" : ""}',
          style: const TextStyle(color: Color(0xFF374151), fontSize: 12),
        ),
        children: [
          _Section(
            title: '📤 发送内容（${record.messages.length} message${record.messages.length == 1 ? "" : "s"} · $images images）',
            background: const Color(0xFFF9FAFB),
            content: _formatMessages(record.messages),
          ),
          _Section(
            title: '🧠 AI 思考（${record.reasoningContent?.length ?? 0} 字符）',
            background: const Color(0xFFFEF3C7),
            content: record.reasoningContent ?? '',
          ),
          _Section(
            title: '💬 AI 回复（${record.responseContent?.length ?? 0} 字符）',
            background: const Color(0xFFF0FDF4),
            content: record.responseContent ?? '',
          ),
        ],
      ),
    );
  }

  String _formatMessages(List<Map<String, dynamic>> messages) {
    final buf = StringBuffer();
    for (final m in messages) {
      final role = (m['role'] ?? '?').toString();
      final content = m['content'];
      if (content is List) {
        final texts = content
            .whereType<Map>()
            .map((e) => e['text'])
            .whereType<String>()
            .where((t) => !t.startsWith('data:'))
            .join(' | ');
        final imgs = content
            .whereType<Map>()
            .where((e) => e['type'] == 'image_url')
            .length;
        buf.writeln('[$role] ($imgs images) $texts');
      } else {
        buf.writeln('[$role] ${content ?? ""}');
      }
    }
    return buf.toString();
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.background, required this.content});
  final String title;
  final Color background;
  final String content;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w600, fontSize: 12)),
          const SizedBox(height: 4),
          SelectableText(
            content,
            style: const TextStyle(color: Colors.black, fontSize: 11, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}

class _EventsTab extends ConsumerWidget {
  const _EventsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(debugProvider).events.reversed.toList();
    if (events.isEmpty) {
      return const Center(
        child: Text('暂无事件', style: TextStyle(color: Colors.black)),
      );
    }
    return ListView.builder(
      itemCount: events.length,
      itemBuilder: (context, i) {
        final e = events[i];
        final ts = e.timestamp.toIso8601String().substring(11, 19);
        Color? bg;
        Color fg = const Color(0xFF111827);
        if (e.level == EventLevel.error) {
          bg = const Color(0xFFFEF2F2);
          fg = const Color(0xFF7F1D1D);
        } else if (e.level == EventLevel.warn) {
          bg = const Color(0xFFFFFBEB);
          fg = const Color(0xFF78350F);
        }
        return Container(
          color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            '$ts  [${e.scope}]  ${e.message}',
            style: TextStyle(color: fg, fontFamily: 'monospace', fontSize: 12),
          ),
        );
      },
    );
  }
}

class _StateTab extends ConsumerWidget {
  const _StateTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap = ref.watch(debugProvider).stateSnapshot;
    if (snap == null) {
      return const Center(
        child: Text('暂无状态快照', style: TextStyle(color: Colors.black)),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        _settingsTile(snap),
        const Divider(color: Colors.black26),
        ..._taskTiles(snap),
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

class _JsonTab extends ConsumerWidget {
  const _JsonTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Center(child: Text('JSON 解析路径 tab placeholder'));
  }
}
