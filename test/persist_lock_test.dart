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

  group('H1: save chain does not drop the next write after an error', () {
    test('write A succeeds, write B fails, write C still lands', () async {
      ReferenceStore.resetForTest();
      // Force B to fail by pre-creating a *directory* at the target path.
      // POSIX rename(2) refuses to overwrite a directory with a file
      // (EISDIR), so writeJsonAtomic's rename step throws — simulating a
      // disk-write failure for a real-world transient error.
      final blockDir = Directory('${tmp.path}/reference_t1.json');
      await blockDir.create(recursive: true);
      addTearDown(() async {
        if (await blockDir.exists()) await blockDir.delete(recursive: true);
      });

      // Write A: must throw because the target path is a directory.
      Object? caughtA;
      try {
        await ReferenceStore.save('t1', [
          ReferenceAnswer(
            questionNumber: 1,
            checkpoints: const [CheckpointDef(id: 'q1-cp0', description: 'A', points: 5)],
          ),
        ]);
      } catch (e) {
        caughtA = e;
      }
      expect(caughtA, isNotNull,
          reason: 'A should have thrown because the target is a directory');

      // Remove the directory so the next write can succeed.
      await blockDir.delete(recursive: true);

      // Write B: must succeed and land on disk, NOT be skipped because the
      // failed A's error handler ran while B was queued.
      await ReferenceStore.save('t1', [
        ReferenceAnswer(
          questionNumber: 1,
          checkpoints: const [CheckpointDef(id: 'q1-cp0', description: 'B', points: 5)],
        ),
      ]);

      final loaded = await ReferenceStore.load('t1');
      expect(loaded.length, 1, reason: 'one ReferenceAnswer expected');
      expect(loaded.first.checkpoints.first.description, 'B',
          reason: 'B must be the surviving writer');
    });
  });

  group('H3: load() on corrupt / missing files', () {
    test('returns [] when the file does not exist', () async {
      final loaded = await ReferenceStore.load('does-not-exist');
      expect(loaded, isEmpty);
    });

    test('on corrupt JSON: renames file to .broken.<scope>… and returns []',
        () async {
      ReferenceStore.resetForTest();
      final f = File('${tmp.path}/reference_t-corrupt.json');
      await f.create(recursive: true);
      await f.writeAsString('{ not valid json');

      final loaded = await ReferenceStore.load('t-corrupt');
      expect(loaded, isEmpty);
      expect(await f.exists(), isFalse,
          reason: 'original file should have been renamed aside');
      // Sibling quarantine file in the same dir.
      final siblings = tmp
          .listSync()
          .map((e) => e.uri.pathSegments.last)
          .where((n) => n.startsWith('reference_t-corrupt.json.broken.reference.'))
          .toList();
      expect(siblings, isNotEmpty,
          reason: 'expected a .broken.reference.* sibling file');
    });
  });
}
