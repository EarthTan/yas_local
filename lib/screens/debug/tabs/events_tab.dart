import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/debug_provider.dart';
import '../../../services/debug/debug_service.dart';

class EventsTab extends ConsumerWidget {
  const EventsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(debugProvider).events.reversed.toList();
    if (events.isEmpty) {
      return const Center(
        child: Text('暂无事件', style: TextStyle(color: Colors.black)),
      );
    }
    return ListView.builder(
      itemCount: events.length,
      itemBuilder: (context, i) {
        final e = events[i];
        final ts = e.timestamp.toIso8601String().substring(11, 19);
        Color? bg;
        Color fg = const Color(0xFF111827);
        if (e.level == EventLevel.error) {
          bg = const Color(0xFFFEF2F2);
          fg = const Color(0xFF7F1D1D);
        } else if (e.level == EventLevel.warn) {
          bg = const Color(0xFFFFFBEB);
          fg = const Color(0xFF78350F);
        }
        return Container(
          color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            '$ts  [${e.scope}]  ${e.message}',
            style: TextStyle(color: fg, fontFamily: 'monospace', fontSize: 12),
          ),
        );
      },
    );
  }
}
