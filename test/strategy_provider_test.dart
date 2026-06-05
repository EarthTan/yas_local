import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:yas_local/models/reference_answer.dart';
import 'package:yas_local/models/rubric.dart';
import 'package:yas_local/models/settings.dart';
import 'package:yas_local/models/strategy_message.dart';
import 'package:yas_local/models/task.dart';
import 'package:yas_local/providers/settings_provider.dart';
import 'package:yas_local/providers/strategy_provider.dart';
import 'package:yas_local/providers/task_provider.dart';
import 'package:yas_local/services/qwen_service.dart';

class _MemoryPathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _MemoryPathProvider(this.dir);
  final Directory dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir.path;
  @override
  Future<String?> getApplicationSupportPath() async => dir.path;
}

class _StubQwen extends QwenService {
  _StubQwen() : super(const AppSettings(apiKey: 'k'));
  @override
  Future<ReferenceAnswer> generateStrategy({
    required RubricItem rubricItem,
    required List<String> questionPaperPaths,
    required List<String> answerImagePaths,
    int totalQuestions = 0,
    void Function(int attempt)? onAttempt,
  }) async => ReferenceAnswer(questionNumber: rubricItem.questionNumber, checkpoints: const []);
  @override
  Future<ReferenceAnswer> refineStrategy({
    required RubricItem rubric,
    required ReferenceAnswer current,
    required List<StrategyMessage> chatHistory,
    required String userMessage,
  }) async => current;
}

ProviderContainer _container({required Directory tmp}) {
  late _StubQwen stub;
  final c = ProviderContainer(overrides: [
    settingsProvider.overrideWith((ref) {
      final n = SettingsNotifier();
      n.state = const AppSettings(apiKey: 'k');
      return n;
    }),
    taskProvider.overrideWith((ref) => TaskNotifier(ref)),
    qwenFactoryProvider.overrideWithValue((ref) {
      stub = _StubQwen();
      return stub;
    }),
  ]);
  c.read(taskProvider.notifier);
  addTearDown(c.dispose);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('strategy_');
    PathProviderPlatform.instance = _MemoryPathProvider(tmp);
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('editCheckpoint schedules a debounced save (500ms)', () async {
    final c = _container(tmp: tmp);
    // Keep the autoDispose strategyProvider alive for the duration of the
    // test. Without an active listener, `c.read(strategyProvider.notifier)`
    // would not pin the notifier and it would be disposed before our
    // awaited `n.load()` completes.
    final sub = c.listen(strategyProvider, (prev, next) {});
    addTearDown(sub.close);
    final n = c.read(strategyProvider.notifier);
    // Seed an in-memory reference so editCheckpoint has something to edit.
    final task = GradingTask(
      id: 't1', name: 'T1', subject: 'math', createdAt: DateTime(2026),
      rubric: const [RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 5)],
      questionPaperPaths: const [],
    );
    await c.read(taskProvider.notifier).addTask(task);
    // Seed by writing reference_t1.json directly so load() picks it up.
    final cacheFile = File('${tmp.path}/reference_t1.json');
    await cacheFile.writeAsString(jsonEncode([
      {
        'questionNumber': 1,
        'checkpoints': [
          {'id': 'cp1', 'description': 'd', 'points': 2}
        ],
        'equivalentForms': <String>[],
        'hasConsensus': true,
        'confirmed': false,
        'chatHistory': <Map<String, dynamic>>[],
      }
    ]));
    await n.load('t1');
    // Delete the seeded file so we can assert that editCheckpoint re-creates
    // it (after the debounce window) rather than just leaving it alone.
    await cacheFile.delete();
    n.editCheckpoint(1, 'cp1', description: 'updated');
    // Within 500ms, the save should NOT have happened.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final cacheFile2 = File('${tmp.path}/reference_t1.json');
    expect(await cacheFile2.exists(), isFalse, reason: 'debounce should delay save');
    // After 500ms+, the save should have happened.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(await cacheFile2.exists(), isTrue);
  });
}
