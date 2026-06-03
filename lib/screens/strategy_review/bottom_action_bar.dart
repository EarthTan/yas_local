import 'package:flutter/material.dart';

/// Sticky 3-button action bar for the strategy review page.
///
/// **Layout:** [修改策略]  [确认此题 / 已确认]  [下一题 →]
///
/// The parent owns all state. The bar is purely presentational and forwards
/// taps via the [onRefine] / [onConfirm] / [onNext] callbacks.
///
/// **Behavior:**
/// - The middle button renders as a green [FilledButton] labeled "确认此题"
///   when [confirmed] is `false`, and as a green [ActionChip] labeled
///   "已确认" with a check icon when [confirmed] is `true`. Tapping the chip
///   still calls [onConfirm], so the parent can re-open the confirm flow if
///   needed.
/// - The next button shows "下一题 →" when [isLast] is `false`, and
///   "已是最后一题" when [isLast] is `true` (also disabled in that state).
/// - Both [onRefine] and [onConfirm] are disabled while [isRefining] is
///   `true` (e.g. while a chat refinement is in flight), preventing
///   overlapping requests.
class BottomActionBar extends StatelessWidget {
  final bool confirmed;
  final bool isLast;
  final bool isRefining;
  final VoidCallback onRefine;
  final VoidCallback onConfirm;
  final VoidCallback onNext;

  const BottomActionBar({
    super.key,
    required this.confirmed,
    required this.isLast,
    required this.isRefining,
    required this.onRefine,
    required this.onConfirm,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: isRefining ? null : onRefine,
                child: const Text('修改策略'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: confirmed
                  ? ActionChip(
                      avatar: const Icon(Icons.check_circle, color: Colors.green, size: 16),
                      label: const Text('已确认'),
                      onPressed: onConfirm,
                    )
                  : FilledButton(
                      onPressed: isRefining ? null : onConfirm,
                      style: FilledButton.styleFrom(backgroundColor: Colors.green),
                      child: const Text('确认此题'),
                    ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: isLast ? null : onNext,
                icon: const Icon(Icons.arrow_forward, size: 16),
                label: Text(isLast ? '已是最后一题' : '下一题 →'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
