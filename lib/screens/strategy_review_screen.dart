import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/reference_answer.dart';
import '../models/strategy_message.dart';
import '../providers/strategy_provider.dart';
import '../providers/task_provider.dart';

class StrategyReviewScreen extends ConsumerStatefulWidget {
  final String taskId;
  const StrategyReviewScreen({super.key, required this.taskId});

  @override
  ConsumerState<StrategyReviewScreen> createState() => _S();
}

class _S extends ConsumerState<StrategyReviewScreen> {
  @override
  void initState() {
    super.initState();
    // Kick off loading/generation after first frame so the provider is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(strategyProvider.notifier).loadOrGenerate(widget.taskId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(strategyProvider);
    final notifier = ref.read(strategyProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('批改策略'),
        actions: [
          if (!state.generating && state.error == null && state.references.isNotEmpty)
            TextButton(
              onPressed: () {
                notifier.confirmAll();
              },
              child: const Text('全部确认'),
            ),
        ],
      ),
      body: state.generating
          ? _buildGenerating(state)
          : state.error != null && state.references.isEmpty
              ? _buildError(state, notifier)
              : state.references.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _buildReview(state, notifier),
      bottomNavigationBar: (!state.generating && state.references.isNotEmpty)
          ? _buildBottomBar(state, notifier)
          : null,
    );
  }

  Widget _buildGenerating(StrategyState state) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(
            '正在生成第 ${state.genDone + 1}/${state.genTotal} 题的批改策略...',
            style: const TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: state.genTotal > 0 ? state.genDone / state.genTotal : null,
          ),
        ],
      ),
    );
  }

  Widget _buildError(StrategyState state, StrategyNotifier notifier) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 48),
          const SizedBox(height: 16),
          SelectableText(
            state.error!,
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => notifier.regenerate(widget.taskId),
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildReview(StrategyState state, StrategyNotifier notifier) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
      itemCount: state.references.length,
      itemBuilder: (_, i) => _QuestionCard(
        taskId: widget.taskId,
        reference: state.references[i],
        isRefining: state.refining && state.refiningQuestion == state.references[i].questionNumber,
        notifier: notifier,
      ),
    );
  }

  Widget _buildBottomBar(StrategyState state, StrategyNotifier notifier) {
    final confirmed = state.confirmedCount;
    final total = state.references.length;
    final allDone = state.allConfirmed;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '部分题目生成失败，可重新确认后继续',
                  style: TextStyle(color: Colors.orange[700], fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            FilledButton.icon(
              onPressed: allDone
                  ? () async {
                      await notifier.saveAllConfirmed(widget.taskId);
                      if (mounted) {
                        context.pushReplacement('/tasks/${widget.taskId}');
                      }
                    }
                  : null,
              icon: const Icon(Icons.check),
              label: Text(allDone
                  ? '完成'
                  : '完成（$confirmed/$total 道题已确认）'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionCard extends ConsumerStatefulWidget {
  final String taskId;
  final ReferenceAnswer reference;
  final bool isRefining;
  final StrategyNotifier notifier;

  const _QuestionCard({
    required this.taskId,
    required this.reference,
    required this.isRefining,
    required this.notifier,
  });

  @override
  ConsumerState<_QuestionCard> createState() => _QCS();
}

class _QCS extends ConsumerState<_QuestionCard> {
  bool _chatExpanded = false;
  bool _thinkingExpanded = false;
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reference;
    final task = ref.read(taskProvider.notifier).taskById(widget.taskId);
    final rubricItem = task?.rubric.firstWhere(
      (item) => item.questionNumber == r.questionNumber,
      orElse: () => throw StateError('Rubric item not found'),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Text(
                  '第 ${r.questionNumber} 题',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Chip(
                  label: Text(rubricItem?.type == 'objective' ? '客观题' : '主观题',
                      style: const TextStyle(fontSize: 11)),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                const Spacer(),
                Text('${rubricItem?.maxPoints ?? 0} 分',
                    style: TextStyle(color: Colors.grey[600])),
              ],
            ),
            const SizedBox(height: 8),

            // Checkpoints
            if (r.checkpoints.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '暂无批改策略（AI 未能生成，可通过对话描述要求）',
                  style: TextStyle(color: Colors.orange[700], fontStyle: FontStyle.italic),
                ),
              )
            else
              ...r.checkpoints.map((c) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
                        Expanded(child: Text(c.description)),
                        const SizedBox(width: 8),
                        Text('${c.points}分',
                            style: TextStyle(
                                color: Colors.blue[700], fontWeight: FontWeight.w500)),
                      ],
                    ),
                  )),

            const SizedBox(height: 12),

            // AI reasoning section
            if (r.reasoning != null && r.reasoning!.isNotEmpty) ...[
              InkWell(
                onTap: () => setState(() => _thinkingExpanded = !_thinkingExpanded),
                borderRadius: BorderRadius.circular(4),
                child: Row(
                  children: [
                    Icon(
                      _thinkingExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 18,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _thinkingExpanded ? '收起 AI 思考过程' : '查看 AI 思考过程',
                      style: TextStyle(color: Colors.grey[700], fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (_thinkingExpanded)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Text(
                    r.reasoning!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[800],
                      height: 1.5,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
            ],

            // Chat section toggle
            InkWell(
              onTap: () => setState(() => _chatExpanded = !_chatExpanded),
              borderRadius: BorderRadius.circular(4),
              child: Row(
                children: [
                  Icon(
                    _chatExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 18,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _chatExpanded ? '收起对话' : '修改策略',
                    style: TextStyle(color: Colors.grey[700], fontSize: 13),
                  ),
                  if (r.chatHistory.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Badge(
                        label: Text('${r.chatHistory.length ~/ 2}'),
                      ),
                    ),
                ],
              ),
            ),

            if (_chatExpanded) ...[
              const SizedBox(height: 8),
              _buildChat(r),
            ],

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // Confirm / unconfirm row
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!r.confirmed)
                  FilledButton.icon(
                    onPressed: widget.isRefining
                        ? null
                        : () => widget.notifier.confirmQuestion(r.questionNumber),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('确认此题策略'),
                    style: FilledButton.styleFrom(backgroundColor: Colors.green),
                  )
                else
                  ActionChip(
                    avatar: const Icon(Icons.check_circle, color: Colors.green, size: 16),
                    label: const Text('已确认'),
                    onPressed: () => widget.notifier.unconfirmQuestion(r.questionNumber),
                    backgroundColor: Colors.green.shade50,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChat(ReferenceAnswer r) {
    return Column(
      children: [
        // Chat history
        if (r.chatHistory.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.builder(
              controller: _scrollController,
              shrinkWrap: true,
              itemCount: r.chatHistory.length,
              itemBuilder: (_, i) => _ChatBubble(message: r.chatHistory[i]),
            ),
          ),

        if (widget.isRefining)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8),
                Text('AI 回复中...', style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),

        // Input row
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                enabled: !widget.isRefining,
                decoration: const InputDecoration(
                  hintText: '描述修改要求，例如：第2个checkpoint改严格一些',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(r),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: widget.isRefining ? null : () => _send(r),
              icon: const Icon(Icons.send, size: 18),
            ),
          ],
        ),
      ],
    );
  }

  void _send(ReferenceAnswer r) {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    widget.notifier.sendMessage(widget.taskId, r.questionNumber, text);
    // Scroll to bottom after a brief delay
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }
}

class _ChatBubble extends StatelessWidget {
  final StrategyMessage message;
  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    return Padding(
      padding: EdgeInsets.only(
        top: 4,
        bottom: 4,
        left: isUser ? 32 : 0,
        right: isUser ? 0 : 32,
      ),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isUser ? Colors.blue.shade600 : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            message.content,
            style: TextStyle(
              color: isUser ? Colors.white : Colors.black87,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
