import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/debug_provider.dart';

class DebugScreen extends ConsumerWidget {
  const DebugScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Debug'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Qwen', icon: Icon(Icons.cloud)),
              Tab(text: '事件', icon: Icon(Icons.timeline)),
              Tab(text: '状态', icon: Icon(Icons.storage)),
              Tab(text: 'JSON', icon: Icon(Icons.data_object)),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _QwenTab(),
            _EventsTab(),
            _StateTab(),
            _JsonTab(),
          ],
        ),
      ),
    );
  }
}

class _QwenTab extends ConsumerWidget {
  const _QwenTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final calls = ref.watch(debugProvider).qwenCalls;
    if (calls.isEmpty) {
      return const Center(child: Text('暂无 Qwen 调用记录', style: TextStyle(color: Colors.black)));
    }
    return const Center(child: Text('Qwen tab placeholder'));
  }
}

class _EventsTab extends ConsumerWidget {
  const _EventsTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Center(child: Text('事件流 tab placeholder'));
  }
}

class _StateTab extends ConsumerWidget {
  const _StateTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Center(child: Text('存储状态 tab placeholder'));
  }
}

class _JsonTab extends ConsumerWidget {
  const _JsonTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Center(child: Text('JSON 解析路径 tab placeholder'));
  }
}
