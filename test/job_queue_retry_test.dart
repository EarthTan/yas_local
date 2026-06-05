import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'package:yas_local/models/job_state.dart';
import 'package:yas_local/models/reference_answer.dart';
import 'package:yas_local/models/rubric.dart';
import 'package:yas_local/models/settings.dart';
import 'package:yas_local/models/submission.dart';
import 'package:yas_local/models/task.dart';
import 'package:yas_local/providers/job_queue_provider.dart';
import 'package:yas_local/providers/settings_provider.dart';
import 'package:yas_local/providers/strategy_provider.dart';
import 'package:yas_local/providers/task_provider.dart';
import 'package:yas_local/services/qwen_error.dart';
import 'package:yas_local/services/qwen_service.dart';

class _Always500Adapter implements HttpClientAdapter {
  _Always500Adapter(this._callCount);
  final List<int> _callCount;
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    _callCount.add(1);
    return ResponseBody.fromString(
      '{"error":"boom"}',
      500,
      headers: {'content-type': ['application/json']},
    );
  }
}

class _FakeTaskNotifier extends TaskNotifier {
  _FakeTaskNotifier(super.ref, this._task, this._subs);
  final GradingTask _task;
  final List<Submission> _subs;

  @override
  GradingTask? taskById(String id) => _task.id == id ? _task : null;
  @override
  List<Submission> submissionsFor(String id) => _subs;
  @override
  Future<void> updateSubmission(Submission sub) async {}
}

class _ConfiguredSettings extends SettingsNotifier {
  _ConfiguredSettings() {
    state = const AppSettings(apiKey: 'k');
  }
}

class _Http5xxQwen extends QwenService {
  _Http5xxQwen() : super(const AppSettings(apiKey: 'k'));
  @override
  Future<List<QuestionGradeResult>> gradePaper({
    required String imagePath,
    required List<String> questionPaperPaths,
    required List<RubricItem> rubric,
    required List<ReferenceAnswer> refs,
    void Function(int attempt)? onAttempt,
  }) async {
    throw QwenError(
      QwenErrorKind.http5xx,
      Exception('5xx simulated'),
    );
  }
}

class _Http4xxQwen extends QwenService {
  _Http4xxQwen() : super(const AppSettings(apiKey: 'k'));
  @override
  Future<List<QuestionGradeResult>> gradePaper({
    required String imagePath,
    required List<String> questionPaperPaths,
    required List<RubricItem> rubric,
    required List<ReferenceAnswer> refs,
    void Function(int attempt)? onAttempt,
  }) async {
    throw QwenError(QwenErrorKind.http4xx, Exception('401 simulated'));
  }
}

GradingTask _task() => GradingTask(
  id: 't1',
  name: 'T1',
  subject: 'math',
  createdAt: DateTime(2026),
  rubric: const [RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 5)],
  questionPaperPaths: const [],
);

ProviderContainer _container({required QwenService qwen}) {
  late _FakeTaskNotifier fake;
  final c = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith((ref) => _ConfiguredSettings()),
      taskProvider.overrideWith((ref) {
        fake = _FakeTaskNotifier(
          ref,
          _task(),
          [
            const Submission(
              id: 's1', taskId: 't1', label: 'p1', imagePath: '/a.jpg',
            ),
          ],
        );
        return fake;
      }),
      qwenFactoryProvider.overrideWithValue((ref) => qwen),
    ],
  );
  c.read(taskProvider.notifier);
  addTearDown(() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    c.dispose();
  });
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('jobq_retry_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('5xx: lastErrorKind set, phase reaches failed, no clobber', () async {
    final c = _container(qwen: _Http5xxQwen());

    await c.read(jobQueueProvider.notifier).startGrading('t1');

    final job = c.read(jobQueueProvider)['t1']!;
    expect(job.failedCount, 1);
    expect(job.phase, JobPhase.failed);
    // On a failed job, the snapshot is cleared by copyWith.
    expect(job.attempt, 0);
  });

  test('4xx: phase reaches failed', () async {
    final c = _container(qwen: _Http4xxQwen());

    await c.read(jobQueueProvider.notifier).startGrading('t1');

    final job = c.read(jobQueueProvider)['t1']!;
    expect(job.failedCount, 1);
    expect(job.phase, JobPhase.failed);
  });

  test(
    'inner attempt count is threaded to JobState.attempt during 3-attempt retry',
    () async {
      // Real QwenService + Dio mock that always returns 500. The inner
      // _retryingRequest should attempt 3 times before giving up; the test
      // captures the maximum value of JobState.attempt observed during the
      // run. With the bug, this max is always 1 (the outer _retryWithFeedback
      // hardcodes it). With the fix, the inner helper's 0-indexed attempt is
      // forwarded, so attempt reaches 3 at least once.
      final callCount = <int>[];
      final s = const AppSettings(
        apiKey: 'k',
        baseUrl: 'https://example.test/v1',
      );
      final qwen = QwenService(s);
      qwen.dio.httpClientAdapter = _Always500Adapter(callCount);

      final c = _container(qwen: qwen);

      // Subscribe to jobQueue state and record the max attempt value seen
      // while the job is running.
      var maxAttempt = 0;
      final sub = c.listen<Map<String, JobState>>(
        jobQueueProvider,
        (prev, next) {
          final job = next['t1'];
          if (job != null && job.attempt > maxAttempt) {
            maxAttempt = job.attempt;
          }
        },
        fireImmediately: true,
      );
      addTearDown(sub.close);

      await c.read(jobQueueProvider.notifier).startStrategy('t1');

      expect(callCount.length, 3,
          reason: 'inner helper should have done 3 attempts');
      expect(
        maxAttempt,
        greaterThanOrEqualTo(2),
        reason:
            'JobState.attempt should reflect inner helper progress (>=2 means '
            'attempt count was actually threaded, not hardcoded at 1)',
      );
    },
  );
}
