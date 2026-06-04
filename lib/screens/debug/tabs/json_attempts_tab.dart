import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/debug_provider.dart';
import '../../../services/debug/debug_service.dart';
import '../../../services/debug/tab_constants.dart';
import '_export_button.dart';

class JsonAttemptsTab extends ConsumerWidget {
  const JsonAttemptsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debugState = ref.watch(debugProvider);
    final attempts = debugState.jsonAttempts.reversed.toList();
    final exportData = <String, Object?>{
      'tab': 'json_attempts',
      'capturedAt': DateTime.now().toIso8601String(),
      'count': debugState.jsonAttempts.length,
      'items': debugState.jsonAttempts.map((r) => r.toJson()).toList(),
    };
    return Column(
      children: [
        Row(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('JSON 解析', style: Theme.of(context).textTheme.titleMedium),
            ),
            const Spacer(),
            ExportButton(tab: kTabJsonAttempts, data: exportData),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: attempts.isEmpty
              ? const Center(
                  child: Text('暂无 JSON 解析记录', style: TextStyle(color: Colors.black)),
                )
              : ListView.builder(
                  itemCount: attempts.length,
                  itemBuilder: (context, i) => _JsonAttemptRow(record: attempts[i]),
                ),
        ),
      ],
    );
  }
}

class _JsonAttemptRow extends StatelessWidget {
  const _JsonAttemptRow({required this.record});
  final JsonAttemptRecord record;

  @override
  Widget build(BuildContext context) {
    final ok = record.finalException == null;
    final ts = record.timestamp.toIso8601String().substring(11, 19);
    final headerColor = ok ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2);
    final headerTextColor = ok ? const Color(0xFF14532D) : const Color(0xFF7F1D1D);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: headerColor,
      child: ExpansionTile(
        title: Text(
          '${ok ? "✅" : "❌"} $ts · ${record.scope} · ${record.attempts.length} 次尝试',
          style: TextStyle(color: headerTextColor, fontSize: 13),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < record.attempts.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '${i + 1}️⃣ ${record.attempts[i].method}  ${record.attempts[i].ok ? "✓" : "✗"}  ${record.attempts[i].error ?? ""}',
                      style: const TextStyle(color: Colors.black, fontSize: 12, fontFamily: 'monospace'),
                    ),
                  ),
                if (record.finalException != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '❌ ${record.finalException}',
                      style: const TextStyle(color: Color(0xFF7F1D1D), fontSize: 12, fontFamily: 'monospace'),
                    ),
                  ),
                const SizedBox(height: 8),
                const Text('原始返回（前 200 字符）', style: TextStyle(color: Color(0xFF6B7280), fontSize: 11)),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SelectableText(
                    record.inputSnippet,
                    style: const TextStyle(color: Colors.black, fontSize: 11, fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
