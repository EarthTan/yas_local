import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/submission.dart';
import 'package:yas_local/models/task.dart';
import 'package:yas_local/providers/task_provider.dart';
import 'package:yas_local/screens/capture_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('capture_screen_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test(
    'TaskNotifier.replaceSubmissions exists and replaces, not appends',
    () async {
      // Verifies the rename (setSubmissions → replaceSubmissions) succeeded
      // and the method still behaves as "replace for this taskId" — the bug
      // C-1 fix renames the API to match this behavior, and the capture
      // screen gates the call on a confirm dialog.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(taskProvider.notifier);

      // Let the constructor's _load() settle.
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      await notifier.addTask(GradingTask(
        id: 't1',
        name: 'T1',
        subject: 'math',
        createdAt: DateTime(2026),
        rubric: const [],
        questionPaperPaths: const [],
        answerImagePaths: const [],
      ));

      // First batch: 2 submissions.
      await notifier.replaceSubmissions('t1', const [
        Submission(id: 'a1', taskId: 't1', label: 'A1'),
        Submission(id: 'a2', taskId: 't1', label: 'A2'),
      ]);
      expect(notifier.submissionsFor('t1').length, 2);

      // Second batch: 1 submission. Must REPLACE (not append) — this is
      // what makes the rename honest and what the capture screen now warns
      // about before invoking.
      await notifier.replaceSubmissions('t1', const [
        Submission(id: 'b1', taskId: 't1', label: 'B1'),
      ]);
      final after = notifier.submissionsFor('t1');
      expect(after.length, 1,
          reason:
              'replaceSubmissions must REPLACE the prior batch for this taskId');
      expect(after.first.id, 'b1');
    },
  );

  test('CaptureScreen widget type is exported', () {
    // Trivial structural assertion — keeps the capture_screen.dart import
    // load-bearing so the post-rename call site (replaceSubmissions) is
    // type-checked at test compile time.
    expect(const CaptureScreen(taskId: 't1'), isA<Widget>());
  });
}
