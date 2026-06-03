import 'package:flutter/material.dart';
import '../../models/checkpoint.dart';
import '../../models/reference_answer.dart';

class QuestionPage extends StatefulWidget {
  final ReferenceAnswer reference;
  final int maxPoints;
  final String questionType;
  final void Function(String checkpointId, CheckpointDef cp) onEditCheckpoint;
  final VoidCallback onAddCheckpoint;
  final VoidCallback? onRetry;

  const QuestionPage({
    super.key,
    required this.reference,
    required this.maxPoints,
    required this.questionType,
    required this.onEditCheckpoint,
    required this.onAddCheckpoint,
    this.onRetry,
  });

  @override
  State<QuestionPage> createState() => _QuestionPageState();
}

class _QuestionPageState extends State<QuestionPage> {
  bool _thinkingExpanded = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.reference;
    final cpSum = r.checkpoints.fold<int>(0, (s, c) => s + c.points);
    final failed = r.checkpoints.isEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '第 ${r.questionNumber} 题',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(width: 8),
              Chip(
                label: Text(widget.questionType, style: const TextStyle(fontSize: 11)),
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const Spacer(),
              Text('${widget.maxPoints} 分', style: TextStyle(color: Colors.grey[600])),
            ],
          ),
          if (cpSum != widget.maxPoints)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '总分 = $cpSum（与满分不一致，请确认是否需要调整）',
                style: const TextStyle(color: Colors.orange, fontSize: 12),
              ),
            ),
          const SizedBox(height: 12),
          if (failed) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                border: Border.all(color: Colors.red.shade200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('该题生成失败', style: TextStyle(color: Colors.red))),
                  if (widget.onRetry != null)
                    FilledButton.tonal(
                      onPressed: widget.onRetry,
                      child: const Text('重试此题'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (r.checkpoints.isEmpty && !failed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '暂无批改策略（AI 未能生成，可通过对话描述要求）',
                style: TextStyle(color: Colors.orange[700], fontStyle: FontStyle.italic),
              ),
            )
          else
            ...r.checkpoints.map(
              (c) => InkWell(
                onTap: () => widget.onEditCheckpoint(c.id, c),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
                      Expanded(child: Text(c.description)),
                      const SizedBox(width: 8),
                      Text('${c.points}分',
                          style: TextStyle(color: Colors.blue[700], fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: widget.onAddCheckpoint,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('添加得分点'),
          ),
          const SizedBox(height: 16),
          if (r.reasoning != null && r.reasoning!.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.symmetric(vertical: 8),
              title: const Text('查看 AI 思考过程', style: TextStyle(fontSize: 13)),
              onExpansionChanged: (v) => setState(() => _thinkingExpanded = v),
              initiallyExpanded: _thinkingExpanded,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Text(
                    r.reasoning!,
                    style: TextStyle(fontSize: 12, color: Colors.grey[800], height: 1.5),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
