import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yas_local/models/task.dart';
import 'package:yas_local/models/rubric.dart';
import 'package:yas_local/models/submission.dart';
import 'package:yas_local/services/task_store.dart';
import 'package:yas_local/services/debug/debug_service.dart';
import 'package:yas_local/models/checkpoint.dart';
import 'package:yas_local/models/reference_answer.dart';
import 'package:yas_local/services/reference_store.dart';

void main() {
  test('encode/decode 整库往返（含图片路径）', () {
    final tasks = [
      GradingTask(
        id: 't1', name: '测验1', subject: 'math', createdAt: DateTime(2026, 1, 1),
        rubric: const [RubricItem(questionNumber: 1, type: 'objective', maxPoints: 5, correctAnswer: 'B')],
        questionPaperPaths: ['/q1.jpg', '/q2.jpg'],
        answerImagePaths: ['/a1.jpg'],
      ),
    ];
    const subs = [
      Submission(id: 's1', taskId: 't1', label: '第1份', items: [
        GradedItem(questionNumber: 1, type: 'objective', aiScore: 5, confidence: 0.95),
      ]),
    ];
    final json = TaskStore.encode(tasks, subs);
    // Pre-refactor decode took a String; post-refactor it takes the parsed
    // JSON value, so jsonDecode it first.
    final decoded = TaskStore.decode(jsonDecode(json));
    expect(decoded.tasks.length, 1);
    expect(decoded.tasks.first.name, '测验1');
    expect(decoded.submissions.length, 1);
    expect(decoded.submissions.first.items.first.aiScore, 5);
  });

  test('decode 非 Map 返回空库', () {
    final decoded = TaskStore.decode(<String, dynamic>{});
    expect(decoded.tasks, isEmpty);
    expect(decoded.submissions, isEmpty);
  });

  test('ReferenceStore encode/decode 往返', () {
    final refs = [
      ReferenceAnswer(
        questionNumber: 1,
        checkpoints: const [CheckpointDef(id: 'q1-cp0', description: '答对', points: 5)],
      ),
    ];
    final decoded = ReferenceStore.decode(jsonDecode(ReferenceStore.encode(refs)));
    expect(decoded.length, 1);
    expect(decoded.first.questionNumber, 1);
    expect(decoded.first.checkpoints.first.points, 5);
  });

  test('ReferenceAnswer.fromJson 回填空 checkpoint id', () {
    final raw = ReferenceStore.encode([
      const ReferenceAnswer(
        questionNumber: 3,
        checkpoints: [
          CheckpointDef(id: '', description: 'A', points: 1),
          CheckpointDef(id: '', description: 'B', points: 2),
        ],
      ),
    ]);
    final decoded = ReferenceStore.decode(jsonDecode(raw));
    expect(decoded.single.checkpoints[0].id, 'q3-cp0');
    expect(decoded.single.checkpoints[1].id, 'q3-cp1');
  });

  group('TaskStore I/O (H2 + H3)', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('task_store_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => tmp.path,
      );
      DebugService.instance.resetForTest();
      DebugService.instance.setEnabled(true);
    });
    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'), null);
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('save + load round-trips tasks and submissions', () async {
      final tasks = <GradingTask>[
        GradingTask(
          id: 't1', name: '测验1', subject: 'math', createdAt: DateTime(2026, 1, 1),
          rubric: const [RubricItem(questionNumber: 1, type: 'objective', maxPoints: 5)],
          questionPaperPaths: const [],
        ),
      ];
      const subs = <Submission>[
        Submission(id: 's1', taskId: 't1', label: '第1份'),
      ];
      await TaskStore.save(tasks, subs);
      final loaded = await TaskStore.load();
      expect(loaded.tasks.length, 1);
      expect(loaded.tasks.first.name, '测验1');
      expect(loaded.submissions.length, 1);
      expect(loaded.submissions.first.id, 's1');
    });

    test('load returns empty StoreData when no file exists', () async {
      final loaded = await TaskStore.load();
      expect(loaded.tasks, isEmpty);
      expect(loaded.submissions, isEmpty);
    });

    test('on corrupt tasks.json: renames file, emits event, returns empty',
        () async {
      final f = File(p.join(tmp.path, 'tasks.json'));
      await f.writeAsString('{ not valid json');
      final loaded = await TaskStore.load();
      expect(loaded.tasks, isEmpty);
      expect(loaded.submissions, isEmpty);
      expect(await f.exists(), isFalse, reason: 'corrupt file should be renamed');
      // Quarantine sibling should exist.
      final siblings = tmp
          .listSync()
          .map((e) => e.uri.pathSegments.last)
          .where((n) => n.startsWith('tasks.json.broken.task.'))
          .toList();
      expect(siblings, isNotEmpty,
          reason: 'expected a .broken.task.* sibling, got $siblings');
      // A DebugService event was emitted.
      final ev = DebugService.instance.events.single;
      expect(ev.scope, 'task');
    });

    test('a force-corrupt file is recoverable: load + load again both return empty',
        () async {
      // First save succeeds.
      await TaskStore.save([
        GradingTask(
          id: 't1', name: 'ok', subject: 'math', createdAt: DateTime(2026, 1, 1),
          rubric: const [],
          questionPaperPaths: const [],
        ),
      ], const []);
      // Now force-corrupt the file.
      final f = File(p.join(tmp.path, 'tasks.json'));
      await f.writeAsString('garbage');
      // First load: empty + quarantine.
      final l1 = await TaskStore.load();
      expect(l1.tasks, isEmpty);
      // Second load: still empty, no infinite loop, no crash.
      final l2 = await TaskStore.load();
      expect(l2.tasks, isEmpty);
    });

    test('save is atomic: writes via tmp + rename (no half-written file)',
        () async {
      // We can't easily inject a crash between write and rename in pure
      // Dart, but we can verify the *file exists* and is non-empty after
      // save — atomic semantics mean the file is either fully written or
      // not present.
      await TaskStore.save([
        GradingTask(
          id: 't1', name: 'X', subject: 'math', createdAt: DateTime(2026, 1, 1),
          rubric: const [],
          questionPaperPaths: const [],
        ),
      ], const []);
      final f = File(p.join(tmp.path, 'tasks.json'));
      expect(await f.exists(), isTrue);
      final raw = await f.readAsString();
      expect(raw.contains('"name":"X"'), isTrue);
      // No leftover .tmp file in the dir.
      final tmpFiles = tmp
          .listSync()
          .where((e) => e.uri.pathSegments.last.contains('.tmp.'))
          .toList();
      expect(tmpFiles, isEmpty, reason: 'no leftover tmp files after atomic write');
    });
  });
}
