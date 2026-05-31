import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/task_provider.dart';
import '../providers/settings_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(taskProvider);
    final configured = ref.watch(settingsProvider).isConfigured;
    return Scaffold(
      appBar: AppBar(
        title: const Text('YAS 批改助手'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!configured)
            Material(
              color: Colors.orange.shade100,
              child: ListTile(
                leading: const Icon(Icons.warning_amber, color: Colors.orange),
                title: const Text('还没配置 Qwen API Key'),
                subtitle: const Text('点击前往设置填写后才能批改'),
                onTap: () => context.push('/settings'),
              ),
            ),
          Expanded(
            child: !state.loaded
                ? const Center(child: CircularProgressIndicator())
                : state.tasks.isEmpty
                    ? const Center(child: Text('暂无批改任务，点击 + 新建'))
                    : ListView(
                        children: [
                          for (final t in state.tasks.reversed)
                            ListTile(
                              title: Text(t.name),
                              subtitle: Text('${t.subject} · ${ref.read(taskProvider.notifier).submissionsFor(t.id).length} 份'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => context.push('/tasks/${t.id}/results'),
                            ),
                        ],
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/tasks/create'),
        icon: const Icon(Icons.add),
        label: const Text('新建任务'),
      ),
    );
  }
}
