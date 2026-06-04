import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/checkpoint.dart';
import '../models/job_state.dart';
import '../models/reference_answer.dart';
import '../models/rubric.dart';
import '../providers/job_queue_provider.dart';
import '../providers/strategy_provider.dart';
import '../providers/task_provider.dart';
import '../services/debug_service.dart';
import 'strategy_review/bottom_action_bar.dart';
import 'strategy_review/chat_sheet.dart';
import 'strategy_review/edit_checkpoint_sheet.dart';
import 'strategy_review/progress_dots.dart';
import 'strategy_review/question_page.dart';

/// The integration point of the strategy review flow (Phase 1 of grading).
///
/// Composes three sibling widgets: [ProgressDots] (header) → [PageView] of
/// [QuestionPage] (body, one rubric item per page) → [BottomActionBar]
/// (footer, refine / confirm / next).
///
/// Owns the [PageController] and the current-page index, and translates user
/// gestures (tap checkpoint, add, retry, confirm) into calls on the
/// [strategyProvider] notifier — sibling widgets stay purely presentational.
///
/// Renders one of three loading states before the page list is ready:
/// a running strategy job (spinner + per-question progress read from the job),
/// `job/state error + empty refs` (red error block with a retry button that
/// calls [JobQueueNotifier.startStrategy]), and `refs.isEmpty` (spinner).
///
/// When every reference is confirmed, an extra "完成" button appears under
/// the action bar; tapping it calls [StrategyNotifier.saveAllConfirmed] and
/// pops back to the task hub (`/tasks/:id`).
class StrategyReviewScreen extends ConsumerStatefulWidget {
  final String taskId;
  const StrategyReviewScreen({super.key, required this.taskId});

  @override
  ConsumerState<StrategyReviewScreen> createState() => _S();
}

class _S extends ConsumerState<StrategyReviewScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;
  // Diagnostic listener: ref.listen can only run inside build, so we use
  // ref.listenManual in initState and close the subscription in dispose.
  // It logs refs.length transitions so we can detect a future regression
  // where the list grows (the user reported such a regression, but no
  // current code path can produce it — see the retryGenerate tests).
  ProviderSubscription<StrategyState>? _refsSub;

  @override
  void initState() {
    super.initState();
    // Review-only: generation is triggered from the task detail page and runs
    // in the background. Here we just load whatever has been generated.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(strategyProvider.notifier).load(widget.taskId);
    });
    _refsSub = ref.listenManual<StrategyState>(strategyProvider, (prev, next) {
      final prevLen = prev?.references.length;
      final nextLen = next.references.length;
      if (prevLen != nextLen) {
        DebugService.instance.recordEvent(
          scope: 'strategy / task:${widget.taskId}',
          message: 'refs.length: $prevLen → $nextLen',
          data: {'prev': prevLen, 'next': nextLen},
        );
      }
    });
  }

  @override
  void dispose() {
    _refsSub?.close();
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    if (!_pageController.hasClients) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  void _nextUnconfirmed() {
    final refs = ref.read(strategyProvider).references;
    for (var i = 0; i < refs.length; i++) {
      if (!refs[i].confirmed) {
        _goTo(i);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(strategyProvider);
    final job = ref.watch(jobQueueProvider)[widget.taskId];
    final strategyRunning =
        job?.kind == JobKind.strategy && job?.phase == JobPhase.running;
    ref.listen(jobQueueProvider, (prev, next) {
      // Reload refs only on a strategy job's running -> terminal transition
      // (when startStrategy has just persisted them), not on every tick.
      final j = next[widget.taskId];
      final wasRunning = prev?[widget.taskId]?.phase == JobPhase.running;
      if (j != null &&
          j.kind == JobKind.strategy &&
          j.phase != JobPhase.running &&
          wasRunning) {
        ref.read(strategyProvider.notifier).load(widget.taskId);
      }
    });
    final notifier = ref.read(strategyProvider.notifier);
    final task = ref.read(taskProvider.notifier).taskById(widget.taskId);
    final refs = state.references;

    final isLast = _currentIndex >= refs.length - 1;
    final currentRef = refs.isEmpty
        ? null
        : refs[_currentIndex.clamp(0, refs.length - 1)];

    if (strategyRunning && refs.isEmpty) {
      final done = job?.done ?? 0;
      final total = job?.total ?? 0;
      return Scaffold(
        appBar: AppBar(title: const Text('批改策略')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                '正在生成第 ${done + 1}/$total 题的批改策略...',
                style: const TextStyle(color: Colors.black87),
              ),
              const SizedBox(height: 12),
              if (total > 0) LinearProgressIndicator(value: done / total),
            ],
          ),
        ),
      );
    }
    final jobError = job?.phase == JobPhase.failed ? job?.error : null;
    if ((jobError ?? state.error) != null && refs.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('批改策略')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              SelectableText(
                (jobError ?? state.error)!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => ref
                    .read(jobQueueProvider.notifier)
                    .startStrategy(widget.taskId),
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (refs.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('批改策略')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('批改策略  ·  ${_currentIndex + 1}/${refs.length}'),
        actions: [
          if (refs.any((r) => !r.confirmed))
            TextButton(
              onPressed: notifier.confirmAll,
              child: const Text('全部确认'),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: ProgressDots(
              count: refs.length,
              currentIndex: _currentIndex,
              confirmed: refs.map((r) => r.confirmed).toList(),
              failed: refs.map((r) => r.checkpoints.isEmpty).toList(),
              onTap: _goTo,
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: refs.length,
              onPageChanged: (i) => setState(() => _currentIndex = i),
              itemBuilder: (_, i) {
                final r = refs[i];
                final rubricItem = task?.rubric.firstWhere(
                  (it) => it.questionNumber == r.questionNumber,
                  orElse: () => RubricItem(
                    questionNumber: r.questionNumber,
                    type: 'subjective',
                    maxPoints: 0,
                  ),
                );
                return QuestionPage(
                  reference: r,
                  maxPoints: rubricItem?.maxPoints ?? 0,
                  questionType: rubricItem?.type == 'objective' ? '客观题' : '主观题',
                  onEditCheckpoint: (id, cp) => _openEditSheet(r, id, cp),
                  onAddCheckpoint: () => _openAddSheet(r),
                  onRetry: () =>
                      notifier.retryGenerate(widget.taskId, r.questionNumber),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: currentRef == null
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Bulk generation failures surface on the job (jobError); chat
                // refine failures surface on state.error. Either drives the banner.
                if (state.error != null || jobError != null)
                  Container(
                    width: double.infinity,
                    color: Colors.orange.shade50,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    child: Text(
                      '部分题目生成失败，可重新确认后继续',
                      style: TextStyle(color: Colors.orange[800], fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
                BottomActionBar(
                  confirmed: currentRef.confirmed,
                  isLast: isLast,
                  isRefining:
                      state.refining &&
                      state.refiningQuestion == currentRef.questionNumber,
                  onRefine: () => _openChatSheet(currentRef),
                  onConfirm: () {
                    if (currentRef.confirmed) {
                      notifier.unconfirmQuestion(currentRef.questionNumber);
                    } else {
                      notifier.confirmQuestion(currentRef.questionNumber);
                      HapticFeedback.lightImpact();
                      _nextUnconfirmed();
                    }
                  },
                  onNext: () {
                    if (!isLast) _goTo(_currentIndex + 1);
                  },
                ),
                if (state.allConfirmed)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: FilledButton.icon(
                      onPressed: () async {
                        await notifier.saveAllConfirmed(widget.taskId);
                        // Drop the finished strategy job so the home card stops
                        // showing "策略已生成，待审核确认" now that it's confirmed.
                        ref
                            .read(jobQueueProvider.notifier)
                            .clear(widget.taskId);
                        if (context.mounted) {
                          context.pushReplacement('/tasks/${widget.taskId}');
                        }
                      },
                      icon: const Icon(Icons.check),
                      label: const Text('完成'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  void _openChatSheet(ReferenceAnswer refAnswer) {
    final task = ref.read(taskProvider.notifier).taskById(widget.taskId);
    final rubricItem = task?.rubric.firstWhere(
      (it) => it.questionNumber == refAnswer.questionNumber,
      orElse: () => RubricItem(
        questionNumber: refAnswer.questionNumber,
        type: 'subjective',
        maxPoints: 0,
      ),
    );
    final questionLabel =
        (rubricItem != null && rubricItem.questionText.isNotEmpty)
        ? rubricItem.questionText
        : '第 ${refAnswer.questionNumber} 题';
    ChatSheet.show(
      context,
      taskId: widget.taskId,
      questionNumber: refAnswer.questionNumber,
      questionLabel: questionLabel,
    );
  }

  int _rubricMaxPoints(int questionNumber) {
    final task = ref.read(taskProvider.notifier).taskById(widget.taskId);
    if (task == null) return 0;
    final rubricItem = task.rubric.firstWhere(
      (it) => it.questionNumber == questionNumber,
      orElse: () => RubricItem(
        questionNumber: questionNumber,
        type: 'subjective',
        maxPoints: 0,
      ),
    );
    return rubricItem.maxPoints;
  }

  void _openEditSheet(ReferenceAnswer refAnswer, String id, CheckpointDef cp) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => EditCheckpointSheet(
        mode: EditCheckpointMode.edit,
        initialDescription: cp.description,
        initialPoints: cp.points,
        currentTotal:
            refAnswer.checkpoints.fold<int>(0, (s, c) => s + c.points) -
            cp.points,
        maxPoints: _rubricMaxPoints(refAnswer.questionNumber),
        onSave: (desc, points) {
          ref
              .read(strategyProvider.notifier)
              .editCheckpoint(
                refAnswer.questionNumber,
                id,
                description: desc,
                points: points,
              );
        },
        onDelete: () {
          ref
              .read(strategyProvider.notifier)
              .removeCheckpoint(refAnswer.questionNumber, id);
        },
      ),
    );
  }

  void _openAddSheet(ReferenceAnswer refAnswer) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => EditCheckpointSheet(
        mode: EditCheckpointMode.add,
        initialDescription: '',
        initialPoints: 1,
        currentTotal: refAnswer.checkpoints.fold<int>(
          0,
          (s, c) => s + c.points,
        ),
        maxPoints: _rubricMaxPoints(refAnswer.questionNumber),
        onSave: (desc, points) {
          ref
              .read(strategyProvider.notifier)
              .addCheckpoint(
                refAnswer.questionNumber,
                description: desc,
                points: points,
              );
        },
      ),
    );
  }
}
