import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/grading_provider.dart';
import '../widgets/debug_entry_button.dart';

class GradingScreen extends ConsumerStatefulWidget {
  final String taskId;
  const GradingScreen({super.key, required this.taskId});
  @override
  ConsumerState<GradingScreen> createState() => _S();
}

class _S extends ConsumerState<GradingScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(gradingProvider.notifier).runPhase2Only(widget.taskId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(gradingProvider);
    ref.listen(gradingProvider, (prev, next) {
      if (!next.running &&
          next.error == null &&
          next.total > 0 &&
          next.done == next.total) {
        context.pushReplacement('/tasks/${widget.taskId}/results');
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('批改中…'),
        actions: const [DebugEntryButton()],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (p.error != null) ...[
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: SelectableText(
                  p.error!,
                  textAlign: TextAlign.left,
                  style:
                      const TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
              ),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                FilledButton(
                    onPressed: () => context.push('/settings'),
                    child: const Text('去设置')),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () => context.pushReplacement(
                      '/tasks/${widget.taskId}/results'),
                  child: const Text('查看结果'),
                ),
              ]),
            ] else ...[
              Text(
                '批改中 ${p.done} / ${p.total} 份',
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                  value: p.total > 0 ? p.done / p.total : null),
              const SizedBox(height: 16),
              const Text('正在识别与评分，请稍候…',
                  style: TextStyle(color: Colors.grey)),
            ],
          ]),
        ),
      ),
    );
  }
}
