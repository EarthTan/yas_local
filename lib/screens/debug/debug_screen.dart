import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'tabs/qwen_calls_tab.dart';
import 'tabs/events_tab.dart';
import 'tabs/json_attempts_tab.dart';
import 'tabs/state_tab.dart';

class DebugScreen extends ConsumerWidget {
  const DebugScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('调试'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Qwen 调用', icon: Icon(Icons.cloud)),
              Tab(text: '事件', icon: Icon(Icons.event)),
              Tab(text: 'JSON 解析', icon: Icon(Icons.code)),
              Tab(text: '状态', icon: Icon(Icons.dashboard)),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            QwenCallsTab(),
            EventsTab(),
            JsonAttemptsTab(),
            StateTab(),
          ],
        ),
      ),
    );
  }
}
