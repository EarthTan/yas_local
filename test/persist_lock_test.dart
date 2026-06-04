import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/submission.dart';
import 'package:yas_local/providers/task_provider.dart';
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
}
