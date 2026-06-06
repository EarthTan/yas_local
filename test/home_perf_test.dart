import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/submission.dart';
import 'package:yas_local/models/task.dart';
import 'package:yas_local/providers/task_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('home_perf_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('submissionsByTask is built in a single pass', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(taskProvider.notifier);

    // Let the constructor's _load() settle.
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    for (var i = 0; i < 5; i++) {
      await n.addTask(GradingTask(
        id: 't$i',
        name: 'T$i',
        subject: 'math',
        createdAt: DateTime(2026),
        rubric: const [],
        questionPaperPaths: const [],
        answerImagePaths: const [],
      ));
    }
    // Build a state with 6 submissions per task, distributed round-robin.
    // replaceSubmissions REPLACES the list per task, so we accumulate the
    // per-task list locally and write the final list in one shot.
    final perTask = <String, List<Submission>>{
      for (var i = 0; i < 5; i++) 't$i': <Submission>[],
    };
    for (var i = 0; i < 30; i++) {
      perTask['t${i % 5}']!
          .add(Submission(id: 's$i', taskId: 't${i % 5}', label: '$i'));
    }
    for (var i = 0; i < 5; i++) {
      await n.replaceSubmissions('t$i', perTask['t$i']!);
    }

    final state = container.read(taskProvider);
    // Build the map in one pass — the same shape home_screen uses
    // to avoid O(N×M) filtering inside the per-task Builder.
    final byTask = <String, List<Submission>>{};
    for (final s in state.submissions) {
      byTask.putIfAbsent(s.taskId, () => <Submission>[]).add(s);
    }
    // 30 submissions / 5 tasks = 6 each.
    expect(byTask['t0']!.length, 6);
    expect(byTask['t1']!.length, 6);
    expect(byTask['t2']!.length, 6);
    expect(byTask['t3']!.length, 6);
    expect(byTask['t4']!.length, 6);
    // And every entry is in the right task.
    for (final entry in byTask.entries) {
      for (final s in entry.value) {
        expect(s.taskId, entry.key);
      }
    }
    expect(state.submissions.length, 30);
  });
}
