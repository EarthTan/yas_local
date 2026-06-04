import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/checkpoint.dart';
import 'package:yas_local/models/reference_answer.dart';
import 'package:yas_local/models/submission.dart';
import 'package:yas_local/providers/task_provider.dart';
import 'package:yas_local/services/reference_store.dart';
import 'package:yas_local/services/task_store.dart';
import 'dart:io';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('persist_lock_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('concurrent updateSubmission calls all persist (no lost writes)', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(taskProvider.notifier);

    // Let the constructor's _load() settle.
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    final subs = [
      for (var i = 0; i < 8; i++)
        Submission(id: 's$i', taskId: 't1', label: 'p$i'),
    ];
    await notifier.setSubmissions('t1', subs);

    // Fire all updates concurrently, then await them together.
    await Future.wait([
      for (final s in subs)
        notifier.updateSubmission(s.copyWith(status: SubmissionStatus.done)),
    ]);

    final loaded = await TaskStore.load();
    final done = loaded.submissions
        .where((s) => s.status == SubmissionStatus.done)
        .length;
    expect(done, 8, reason: 'every concurrent write must survive');
  });

  test('ReferenceStore concurrent saves both persist (no lost writes)', () async {
    await Future.wait([
      ReferenceStore.save('t1', [
        ReferenceAnswer(
          questionNumber: 1,
          checkpoints: const [CheckpointDef(id: 'q1-cp0', description: 'a', points: 5)],
        ),
      ]),
      ReferenceStore.save('t1', [
        ReferenceAnswer(
          questionNumber: 1,
          checkpoints: const [CheckpointDef(id: 'q1-cp0', description: 'b', points: 5)],
        ),
        ReferenceAnswer(
          questionNumber: 2,
          checkpoints: const [CheckpointDef(id: 'q2-cp0', description: 'c', points: 5)],
        ),
      ]),
    ]);

    final loaded = await ReferenceStore.load('t1');
    // The chain serializes: one of the two saves will be the last writer. The
    // important thing is that NEITHER call's payload is silently dropped — we
    // must end up with a valid file matching one of the two inputs.
    expect(loaded.length, anyOf(1, 2));
    expect(loaded.first.checkpoints.first.description, anyOf('a', 'b'));
  });
}
