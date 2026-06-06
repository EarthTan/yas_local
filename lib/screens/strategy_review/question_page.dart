import 'package:flutter/material.dart';
import '../../models/checkpoint.dart';
import '../../models/job_state.dart';
import '../../models/reference_answer.dart';
import '../../widgets/rich_content.dart';

/// Scrollable page showing the per-question strategy review for one rubric item.
///
/// **Purely presentational** — this widget does not touch any notifier or
/// persist state. The parent (`StrategyReviewScreen`) owns the
/// `ReferenceAnswer` and re-passes it on every rebuild.
///
/// **Layout (top → bottom):**
/// - Header row: `第 N 题`, question-type chip, `maxPoints 分`.
/// - Question-stem block: when [questionText] is non-null/non-empty, renders
///   it on a light-blue background; when it is null/empty, renders a yellow
///   "未识别题面" hint pointing the teacher to the identify step. A null
///   [questionText] means the rubric has no stem text for this question
///   (e.g. identify step never ran, or VLM missed it) and the hint gives the
///   teacher a way to recover.
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
  // Question stem (题干). Null or empty means the rubric has no text for this
  // question — we surface a "未识别题面" hint in that case.
  final String? questionText;
  // Per-task strategy job (may be null). When set, the in-flight retry banner
  // is rendered for whichever question matches `job.lastErrorUnit`. Scoped to
  // the question's own card so the teacher looking at, say, question 5 does
  // not see "⟳ 第 3 题 · 重试 2/3" floating above it.
  final JobState? job;
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
    this.questionText,
    this.job,
  });

  @override
  Widget build(BuildContext context) {
    final r = reference;
    final cpSum = r.checkpoints.fold<int>(0, (s, c) => s + c.points);
    final failed = r.checkpoints.isEmpty;
    final stem = (questionText ?? '').trim();
    final hasStem = stem.isNotEmpty;
    // Build the same "第 N 题" label the job queue uses for lastErrorUnit, so
    // the in-flight-retry check below matches by string equality.
    final unitLabel = '第 ${r.questionNumber} 题';
    final showRetryBanner = job != null &&
        job!.attempt > 0 &&
        job!.lastErrorKind != null &&
        job!.lastErrorUnit == unitLabel;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showRetryBanner)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '⟳ ${job!.lastErrorUnit ?? unitLabel} · 重试 ${job!.attempt}/3 · ${job!.lastErrorKind!.displayName}',
                style: TextStyle(color: Colors.orange[800], fontSize: 12),
              ),
            ),
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
          const SizedBox(height: 10),
          if (r.missingFromRubric)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                '该题已从 rubric 中移除，原分数不再适用',
                style: TextStyle(color: Colors.orange[800], fontSize: 12),
              ),
            ),
          if (hasStem)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                border: Border.all(color: Colors.blue.shade100),
                borderRadius: BorderRadius.circular(8),
              ),
              child: RichContent(
                stem,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[900],
                  height: 1.5,
                ),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                border: Border.all(color: Colors.amber.shade200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.amber.shade800,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '暂无题面文字',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '建议在「识别题目」步骤补充',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (!failed && cpSum != maxPoints)
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
            (c) => _CheckpointRow(
              checkpoint: c,
              onTap: () => onEditCheckpoint(c.id, c),
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
                  child: RichContent(
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

/// Tappable row for a single checkpoint. Adds a leading chevron and a hover
/// background so the row reads as interactive even before the InkWell ripple
/// fires (fixes U-16: mouse users had no way to know the row was tappable).
class _CheckpointRow extends StatefulWidget {
  final CheckpointDef checkpoint;
  final VoidCallback onTap;

  const _CheckpointRow({required this.checkpoint, required this.onTap});

  @override
  State<_CheckpointRow> createState() => _CheckpointRowState();
}

class _CheckpointRowState extends State<_CheckpointRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.checkpoint;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: _hovered ? Colors.grey.shade100 : Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
                Expanded(child: RichContent(c.description)),
                const SizedBox(width: 8),
                Text('${c.points}分',
                    style: TextStyle(color: Colors.blue[700], fontWeight: FontWeight.w500)),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, size: 18, color: Colors.black54),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
