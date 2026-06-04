import 'package:flutter/material.dart';
import '../../models/checkpoint.dart';
import '../../models/reference_answer.dart';

/// Scrollable page showing the per-question strategy review for one rubric item.
///
/// **Purely presentational** — this widget does not touch any notifier or
/// persist state. The parent (`StrategyReviewScreen`) owns the
/// `ReferenceAnswer` and re-passes it on every rebuild.
///
/// **Layout (top → bottom):**
/// - Header row: `第 N 题`, question-type chip, `maxPoints 分`.
/// - Optional orange "总分 = X（与满分不一致）" warning when the sum of
///   checkpoint points does not equal [maxPoints].
/// - Failure banner (red) when [reference] has no checkpoints. If
///   [onRetry] is non-null a "重试此题" button is shown next to the banner;
///   otherwise the banner stands alone.
/// - One InkWell row per [CheckpointDef]. Tapping a row invokes
///   [onEditCheckpoint] with that checkpoint's id and definition so the
///   parent can open the edit sheet.
/// - "添加得分点" button that fires [onAddCheckpoint].
/// - Optional "查看 AI 思考过程" expansion tile rendering [reference]'s
///   `reasoning` text.
///
/// **Failure detection:** `failed` is inferred from
/// `reference.checkpoints.isEmpty`. The retry button only appears when the
/// parent supplies a non-null [onRetry]; a null retry is the signal to show
/// the failure banner without an action.
class QuestionPage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final r = reference;
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
                label: Text(questionType, style: const TextStyle(fontSize: 11)),
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const Spacer(),
              Text('$maxPoints 分', style: TextStyle(color: Colors.grey[600])),
            ],
          ),
          if (cpSum != maxPoints)
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
                  if (onRetry != null)
                    FilledButton.tonal(
                      onPressed: onRetry,
                      child: const Text('重试此题'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          ...r.checkpoints.map(
            (c) => InkWell(
              onTap: () => onEditCheckpoint(c.id, c),
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
            onPressed: onAddCheckpoint,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('添加得分点'),
          ),
          const SizedBox(height: 16),
          if (r.reasoning != null && r.reasoning!.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.symmetric(vertical: 8),
              title: const Text('查看 AI 思考过程', style: TextStyle(fontSize: 13)),
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
