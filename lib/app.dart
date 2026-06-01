import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/create_task_screen.dart';
import 'screens/capture_screen.dart';
import 'screens/identify_screen.dart';
import 'screens/grading_screen.dart';
import 'screens/results_screen.dart';
import 'screens/paper_detail_screen.dart';
import 'screens/task_detail_screen.dart';
import 'screens/strategy_review_screen.dart';

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, _) => const HomeScreen()),
    GoRoute(path: '/settings', builder: (context, _) => const SettingsScreen()),
    GoRoute(path: '/tasks/create', builder: (context, _) => const CreateTaskScreen()),
    GoRoute(path: '/tasks/:id', builder: (_, s) => TaskDetailScreen(taskId: s.pathParameters['id']!)),
    GoRoute(path: '/tasks/:id/strategy', builder: (_, s) => StrategyReviewScreen(taskId: s.pathParameters['id']!)),
    GoRoute(path: '/tasks/:id/capture', builder: (_, s) => CaptureScreen(taskId: s.pathParameters['id']!)),
    GoRoute(path: '/tasks/:id/identify', builder: (_, s) => IdentifyScreen(taskId: s.pathParameters['id']!)),
    GoRoute(path: '/tasks/:id/grading', builder: (_, s) => GradingScreen(taskId: s.pathParameters['id']!)),
    GoRoute(path: '/tasks/:id/results', builder: (_, s) => ResultsScreen(taskId: s.pathParameters['id']!)),
    GoRoute(path: '/submissions/:sid', builder: (_, s) => PaperDetailScreen(submissionId: s.pathParameters['sid']!)),
  ],
);

class YasApp extends ConsumerWidget {
  const YasApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
        title: 'YAS 批改助手',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
          useMaterial3: true,
        ),
        routerConfig: _router,
      );
}
