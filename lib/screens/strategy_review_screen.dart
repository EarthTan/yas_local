import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/checkpoint.dart';
import '../models/reference_answer.dart';
import '../models/rubric.dart';
import '../providers/strategy_provider.dart';
import '../providers/task_provider.dart';
import 'strategy_review/bottom_action_bar.dart';
import 'strategy_review/edit_checkpoint_sheet.dart';
import 'strategy_review/progress_dots.dart';
import 'strategy_review/question_page.dart';

class StrategyReviewScreen extends ConsumerStatefulWidget {
  final String taskId;
  const StrategyReviewScreen({super.key, required this.taskId});

  @override
  ConsumerState<StrategyReviewScreen> createState() => _S();
}

class _S extends ConsumerState<StrategyReviewScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(strategyProvider.notifier).loadOrGenerate(widget.taskId);
    });
  }

  @override
  void dispose() {
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
    final notifier = ref.read(strategyProvider.notifier);
    final task = ref.read(taskProvider.notifier).taskById(widget.taskId);
    final refs = state.references;
    final isLast = _currentIndex >= refs.length - 1;
    final currentRef = refs.isEmpty ? null : refs[_currentIndex.clamp(0, refs.length - 1)];

    if (state.generating && refs.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('批改策略')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('正在生成第 ${state.genDone + 1}/${state.genTotal} 题的批改策略...'),
              const SizedBox(height: 12),
              if (state.genTotal > 0)
                LinearProgressIndicator(value: state.genDone / state.genTotal),
            ],
          ),
        ),
      );
    }
    if (state.error != null && refs.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('批改策略')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              SelectableText(state.error!,
                  style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => notifier.regenerate(widget.taskId),
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
                  onRetry: () => notifier.retryGenerate(widget.taskId, r.questionNumber),
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
                if (state.error != null)
                  Container(
                    width: double.infinity,
                    color: Colors.orange.shade50,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Text(
                      '部分题目生成失败，可重新确认后继续',
                      style: TextStyle(color: Colors.orange[800], fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
                BottomActionBar(
                  confirmed: currentRef.confirmed,
                  isLast: isLast,
                  isRefining: state.refining && state.refiningQuestion == currentRef.questionNumber,
                  onRefine: () {
                    // Chat foldable lives in body — for v1, do nothing here.
                    // Future task: open chat sheet or scroll-to-chat.
                  },
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
                        if (context.mounted) {
                          context.pushReplacement('/tasks/${widget.taskId}');
                        }
                      },
                      icon: const Icon(Icons.check),
                      label: const Text('完成'),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    ),
                  ),
              ],
            ),
    );
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
            refAnswer.checkpoints.fold<int>(0, (s, c) => s + c.points) - cp.points,
        maxPoints: refAnswer.checkpoints.fold<int>(0, (s, c) => s + c.points),
        onSave: (desc, points) {
          ref.read(strategyProvider.notifier)
              .editCheckpoint(refAnswer.questionNumber, id, description: desc, points: points);
        },
        onDelete: () {
          ref.read(strategyProvider.notifier).removeCheckpoint(refAnswer.questionNumber, id);
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
        currentTotal: refAnswer.checkpoints.fold<int>(0, (s, c) => s + c.points),
        maxPoints: refAnswer.checkpoints.fold<int>(0, (s, c) => s + c.points),
        onSave: (desc, points) {
          ref.read(strategyProvider.notifier)
              .addCheckpoint(refAnswer.questionNumber, description: desc, points: points);
        },
      ),
    );
  }
}
