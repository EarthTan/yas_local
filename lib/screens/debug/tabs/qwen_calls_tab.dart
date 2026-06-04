import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/debug_provider.dart';
import '../../../services/debug/debug_service.dart';
import '../../../services/debug/tab_constants.dart';
import '_export_button.dart';

class QwenCallsTab extends ConsumerWidget {
  const QwenCallsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debugState = ref.watch(debugProvider);
    final calls = debugState.qwenCalls.reversed.toList();
    Map<String, Object?> exportData() => <String, Object?>{
          'tab': 'qwen_calls',
          'capturedAt': DateTime.now().toIso8601String(),
          'count': debugState.qwenCalls.length,
          'items': debugState.qwenCalls.map((r) => r.toJson()).toList(),
        };
    return Column(
      children: [
        Row(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('Qwen 调用', style: Theme.of(context).textTheme.titleMedium),
            ),
            const Spacer(),
            ExportButton(tab: kTabQwenCalls, data: exportData),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: calls.isEmpty
              ? const Center(
                  child: Text('暂无 Qwen 调用记录', style: TextStyle(color: Colors.black)),
                )
              : ListView.builder(
                  itemCount: calls.length,
                  itemBuilder: (context, i) => _QwenCallRow(record: calls[i]),
                ),
        ),
      ],
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
