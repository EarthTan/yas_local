import 'package:flutter/material.dart';

class ProgressDots extends StatelessWidget {
  final int count;
  final int currentIndex;
  final List<bool> confirmed;
  final List<bool> failed;
  final void Function(int index) onTap;

  const ProgressDots({
    super.key,
    required this.count,
    required this.currentIndex,
    required this.confirmed,
    required this.failed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: count,
        itemBuilder: (_, i) {
          final isCurrent = i == currentIndex;
          Color color;
          if (failed.length > i && failed[i]) {
            color = Colors.red;
          } else if (confirmed.length > i && confirmed[i]) {
            color = Colors.green;
          } else {
            color = Colors.grey.shade400;
          }
          return GestureDetector(
            onTap: () => onTap(i),
            child: Container(
              width: isCurrent ? 14 : 10,
              height: isCurrent ? 14 : 10,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: isCurrent
                    ? Border.all(color: Colors.black54, width: 1.5)
                    : null,
              ),
              child: failed.length > i && failed[i]
                  ? const Icon(Icons.close, size: 8, color: Colors.white)
                  : null,
            ),
          );
        },
      ),
    );
  }
}
