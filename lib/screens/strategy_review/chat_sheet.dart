import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/reference_answer.dart';
import '../../models/strategy_message.dart';
import '../../providers/strategy_provider.dart';
import '../../widgets/rich_content.dart';

/// Modal bottom sheet for refining the AI's strategy for one question via
/// multi-turn chat.
///
/// **Data flow:** the sheet is a [ConsumerStatefulWidget] that watches
/// [strategyProvider] directly, so it always sees the current
/// `ref.chatHistory` and `refining` flag for the question it was opened on
/// without the parent having to re-pass them. The parent only owns the
/// `taskId` and the `questionNumber`; the sheet looks up the rest.
///
/// **Send path:** tapping send (or pressing Enter) calls
/// [StrategyNotifier.sendMessage]. The notifier appends the user message to
/// the ref's `chatHistory`, calls the VLM, and on completion appends the
/// assistant's reply. The sheet rebuilds on each step, so the new messages
/// appear in place — there is no need to dismiss and re-open the sheet.
///
/// **Why a sheet (not the body foldable in the original spec):** the spec
/// had the chat as a foldable in the question page, but in practice a
/// foldable cramps the input. A modal sheet gives the conversation room to
/// breathe and matches what the user picked. The foldable would still be
/// reachable later if we want the in-place feel.
class ChatSheet extends ConsumerStatefulWidget {
  final String taskId;
  final int questionNumber;
  final String questionLabel;

  const ChatSheet({
    super.key,
    required this.taskId,
    required this.questionNumber,
    required this.questionLabel,
  });

  static Future<void> show(
    BuildContext context, {
    required String taskId,
    required int questionNumber,
    required String questionLabel,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChatSheet(
        taskId: taskId,
        questionNumber: questionNumber,
        questionLabel: questionLabel,
      ),
    );
  }

  @override
  ConsumerState<ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends ConsumerState<ChatSheet> {
  late final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _lastMessageCount = _currentMessages.length;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void didUpdateWidget(ChatSheet old) {
    super.didUpdateWidget(old);
    _scrollIfMessagesChanged();
  }

  List<StrategyMessage> get _currentMessages {
    final ref = _currentRef;
    return ref?.chatHistory ?? const [];
  }

  ReferenceAnswer? get _currentRef {
    final state = ref.read(strategyProvider);
    for (final r in state.references) {
      if (r.questionNumber == widget.questionNumber) return r;
    }
    return null;
  }

  void _scrollIfMessagesChanged() {
    final n = _currentMessages.length;
    if (n != _lastMessageCount) {
      _lastMessageCount = n;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    ref
        .read(strategyProvider.notifier)
        .sendMessage(widget.taskId, widget.questionNumber, text);
    _input.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(strategyProvider);
    final isRefining =
        state.refining && state.refiningQuestion == widget.questionNumber;
    final messages = _currentMessages;
    // ref.watch above rebuilds this widget on provider changes, but
    // didUpdateWidget isn't fired in that case. Schedule a scroll on every
    // build so that new messages from sendMessage / AI replies scroll the
    // list to the bottom. _scrollIfMessagesChanged is a no-op when the
    // message count hasn't changed.
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollIfMessagesChanged());

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(top: 8, bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '修改策略 · ${widget.questionLabel}',
                        style: Theme.of(context).textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: messages.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          '还没有对话。告诉 AI 你想怎么调整批改策略。',
                          style: TextStyle(color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        itemCount: messages.length,
                        itemBuilder: (_, i) =>
                            _MessageBubble(message: messages[i]),
                      ),
              ),
              if (isRefining)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('AI 回复中…',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _handleSend(),
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          hintText: '输入修改要求…',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      icon: const Icon(Icons.send),
                      onPressed: _canSend(isRefining) ? _handleSend : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _canSend(bool isRefining) =>
      !isRefining && _input.text.trim().isNotEmpty;
}

class _MessageBubble extends StatelessWidget {
  final StrategyMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isUser ? Colors.blue.shade100 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: isUser
            ? Text(message.content, style: const TextStyle(fontSize: 14))
            : RichContent(message.content, style: const TextStyle(fontSize: 14)),
      ),
    );
  }
}
