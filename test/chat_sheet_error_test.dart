// Regression guard for U-18: when the chat-sheet's "send" failed, the input
// field cleared and re-enabled — the teacher thought the message was sent.
// The error appeared only at the BOTTOM of the chat history, which was
// off-screen if the history was long.
//
// The fix: ChatSheet._handleSend attaches a catchError to the
// sendMessage() future. On error, it pops a SnackBar ("发送失败：$e")
// at the top of the screen.
//
// This test exercises the fix by:
//   1. Pumping the ChatSheet inside a MaterialApp + Scaffold (so
//      ScaffoldMessenger.of(context) has a valid ancestor).
//   2. Overriding strategyProvider with a fake notifier whose
//      sendMessage rethrows (simulating a VLM error).
//   3. Tapping the send button and asserting a SnackBar appears.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/reference_answer.dart';
import 'package:yas_local/providers/strategy_provider.dart';
import 'package:yas_local/screens/strategy_review/chat_sheet.dart';

/// Notifier that simulates a VLM error on sendMessage. The fix under test
/// (U-18) requires sendMessage to rethrow so the chat sheet's catchError
/// can surface a SnackBar — see StrategyNotifier.sendMessage in
/// lib/providers/strategy_provider.dart.
class _ThrowingChatSheetNotifier extends StrategyNotifier {
  _ThrowingChatSheetNotifier(super.ref, this._refs) {
    state = StrategyState(references: _refs);
  }
  final List<ReferenceAnswer> _refs;
  int sendMessageCallCount = 0;

  @override
  Future<void> load(String taskId) async {}

  @override
  Future<void> saveAllConfirmed(String taskId) async {}

  @override
  Future<void> sendMessage(
    String taskId,
    int questionNum,
    String message,
  ) async {
    sendMessageCallCount++;
    // Simulate the VLM call failing (timeout, 5xx, JSON parse error, …).
    throw Exception('boom');
  }
}

void main() {
  testWidgets(
    'chat send failure shows a SnackBar (not only the in-history error)',
    (tester) async {
      final refs = [
        ReferenceAnswer(
          questionNumber: 1,
          checkpoints: const [],
        ),
      ];
      late _ThrowingChatSheetNotifier notifier;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            strategyProvider.overrideWith((ref) {
              notifier = _ThrowingChatSheetNotifier(ref, refs);
              return notifier;
            }),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ChatSheet(
                taskId: 't1',
                questionNumber: 1,
                questionLabel: '第 1 题',
              ),
            ),
          ),
        ),
      );

      // Type and send.
      await tester.enterText(find.byType(TextField), 'help');
      await tester.pump();
      expect(find.byIcon(Icons.send), findsOneWidget);
      await tester.tap(find.byIcon(Icons.send));
      // Let the sendMessage future throw and the catchError handler run.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // The notifier was called.
      expect(notifier.sendMessageCallCount, 1,
          reason: 'send must be dispatched exactly once');
      // The SnackBar surfaced the error.
      expect(find.textContaining('发送失败'), findsOneWidget,
          reason: 'a SnackBar with the failure message must appear so the '
              'teacher does not think the message is still being sent');
    },
  );
}
