import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'package:yas_local/models/checkpoint.dart';
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
import 'package:yas_local/services/qwen_service.dart';
import 'package:yas_local/services/reference_store.dart';

GradingTask _gradingTask() => GradingTask(
  id: 't1',
  name: 'T1',
  subject: 'math',
  createdAt: DateTime(2026),
  rubric: const [
    RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 5),
  ],
  questionPaperPaths: const [],
);

class _FakeTaskNotifier extends TaskNotifier {
  _FakeTaskNotifier(super.ref, this._task, this._subs);
  final GradingTask _task;
  final List<Submission> _subs;
  final List<Submission> updated = [];

  @override
  GradingTask? taskById(String id) => _task.id == id ? _task : null;
  @override
  List<Submission> submissionsFor(String id) => _subs;
  @override
  Future<void> updateSubmission(Submission sub) async => updated.add(sub);
}

class _ConfiguredSettings extends SettingsNotifier {
  _ConfiguredSettings() {
    state = const AppSettings(apiKey: 'k');
  }
}

class _OkQwen extends QwenService {
  _OkQwen() : super(const AppSettings(apiKey: 'k'));
  int calls = 0;
  @override
  Future<List<QuestionGradeResult>> gradePaper({
    required String imagePath,
    required List<String> questionPaperPaths,
    required List<RubricItem> rubric,
    required List<ReferenceAnswer> refs,
    void Function(int attempt)? onAttempt,
  }) async {
    calls++;
    return const [
      QuestionGradeResult(
        questionNumber: 1,
        extractedAnswer: '42',
        checkpoints: [
          CheckpointResult(
            description: 'correct',
            passed: true,
            pointsAwarded: 5,
            reason: '',
          ),
        ],
        confidence: 0.9,
      ),
    ];
  }
}

class _ThrowQwen extends QwenService {
  _ThrowQwen() : super(const AppSettings(apiKey: 'k'));
  @override
  Future<List<QuestionGradeResult>> gradePaper({
    required String imagePath,
    required List<String> questionPaperPaths,
    required List<RubricItem> rubric,
    required List<ReferenceAnswer> refs,
    void Function(int attempt)? onAttempt,
  }) async => throw Exception('grade boom');
}

// Invokes [_onFirst] on the first gradePaper call (used to request cancel
// mid-run), then returns a trivial successful grade.
class _CancelOnFirstQwen extends QwenService {
  _CancelOnFirstQwen(this._onFirst) : super(const AppSettings(apiKey: 'k'));
  final void Function() _onFirst;
  int calls = 0;
  @override
  Future<List<QuestionGradeResult>> gradePaper({
    required String imagePath,
    required List<String> questionPaperPaths,
    required List<RubricItem> rubric,
    required List<ReferenceAnswer> refs,
    void Function(int attempt)? onAttempt,
  }) async {
    calls++;
    if (calls == 1) _onFirst();
    return const [
      QuestionGradeResult(
        questionNumber: 1,
        extractedAnswer: '42',
        checkpoints: [
          CheckpointResult(
            description: 'correct',
            passed: true,
            pointsAwarded: 5,
            reason: '',
          ),
        ],
        confidence: 0.9,
      ),
    ];
  }
}

class _StrategyOkQwen extends QwenService {
  _StrategyOkQwen() : super(const AppSettings(apiKey: 'k'));
  int calls = 0;
  @override
  Future<ReferenceAnswer> generateStrategy({
    required RubricItem rubricItem,
    required List<String> questionPaperPaths,
    required List<String> answerImagePaths,
    int totalQuestions = 0,
    void Function(int attempt)? onAttempt,
  }) async {
    calls++;
    return ReferenceAnswer(
      questionNumber: rubricItem.questionNumber,
      checkpoints: [
        CheckpointDef(
          id: 'q${rubricItem.questionNumber}-cp0',
          description: 'cp',
          points: 5,
        ),
      ],
    );
  }
}

GradingTask _twoQuestionTask() => GradingTask(
  id: 't1',
  name: 'T1',
  subject: 'math',
  createdAt: DateTime(2026),
  rubric: const [
    RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 5),
    RubricItem(questionNumber: 2, type: 'subjective', maxPoints: 5),
  ],
  questionPaperPaths: const [],
);

typedef _GradeSetup = ({ProviderContainer container, _FakeTaskNotifier fake});

// Builds the container AND eagerly constructs the fake TaskNotifier with the
// container's REAL ref (so its _load() -> _refreshDebugSnapshot() ->
// ref.read(settingsProvider) works). Never pass a dummy ref to a real
// TaskNotifier subclass.
_GradeSetup _gradeSetup({
  required GradingTask task,
  required List<Submission> subs,
  required QwenService qwen,
  int? maxConcurrency,
}) {
  late _FakeTaskNotifier fake;
  final c = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith((ref) => _ConfiguredSettings()),
      taskProvider.overrideWith((ref) {
        fake = _FakeTaskNotifier(ref, task, subs);
        return fake;
      }),
      qwenFactoryProvider.overrideWithValue((ref) => qwen),
      if (maxConcurrency != null)
        jobQueueProvider.overrideWith(
          (ref) => JobQueueNotifier(
            ref,
            maxConcurrency: maxConcurrency,
            qwenFactory: ref.read(qwenFactoryProvider),
          ),
        ),
    ],
  );
  c.read(taskProvider.notifier); // force the override to build `fake`
  // Drain async _load() futures (TaskNotifier + SettingsNotifier fire one in
  // their constructors) BEFORE disposing, so they never write state on a
  // disposed notifier ("used after dispose"). Repo-standard idiom; this helper
  // owns disposal — tests must not addTearDown(dispose) again.
  addTearDown(() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    c.dispose();
  });
  return (container: c, fake: fake);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('JobState', () {
    test('defaults: phase=running, counters 0, no error', () {
      const j = JobState(taskId: 't1', kind: JobKind.grading);
      expect(j.phase, JobPhase.running);
      expect(j.total, 0);
      expect(j.done, 0);
      expect(j.failedCount, 0);
      expect(j.error, isNull);
      expect(j.cancelRequested, isFalse);
    });

    test('copyWith updates done but preserves cancelRequested', () {
      const j = JobState(
        taskId: 't1',
        kind: JobKind.grading,
        cancelRequested: true,
        total: 5,
      );
      final j2 = j.copyWith(done: 3);
      expect(j2.done, 3);
      expect(j2.total, 5);
      expect(
        j2.cancelRequested,
        isTrue,
        reason: 'unspecified fields preserved',
      );
    });

    test('copyWith can clear error back to null via sentinel', () {
      const j = JobState(taskId: 't1', kind: JobKind.strategy, error: 'boom');
      final j2 = j.copyWith(error: null);
      expect(j2.error, isNull);
    });

    test('copyWith without error arg preserves existing error', () {
      const j = JobState(taskId: 't1', kind: JobKind.strategy, error: 'boom');
      final j2 = j.copyWith(done: 1);
      expect(j2.error, 'boom');
    });
  });

  group('JobQueueNotifier.startGrading', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('jobq_');
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
      'grades only non-done submissions; progress + phase correct',
      () async {
        final subs = [
          const Submission(
            id: 's1',
            taskId: 't1',
            label: 'p1',
            imagePath: '/a.jpg',
          ),
          const Submission(
            id: 's2',
            taskId: 't1',
            label: 'p2',
            imagePath: '/b.jpg',
            status: SubmissionStatus.done,
          ),
        ];
        final qwen = _OkQwen();
        final s = _gradeSetup(task: _gradingTask(), subs: subs, qwen: qwen);

        await s.container.read(jobQueueProvider.notifier).startGrading('t1');

        expect(qwen.calls, 1, reason: 'only s1 (non-done) graded');
        final job = s.container.read(jobQueueProvider)['t1']!;
        expect(job.kind, JobKind.grading);
        expect(job.total, 1);
        expect(job.done, 1);
        expect(job.failedCount, 0);
        expect(job.phase, JobPhase.done);
      },
    );

    test(
      'failed unit -> submission failed, failedCount + error, phase failed',
      () async {
        final subs = [
          const Submission(
            id: 's1',
            taskId: 't1',
            label: 'p1',
            imagePath: '/a.jpg',
          ),
        ];
        final s = _gradeSetup(
          task: _gradingTask(),
          subs: subs,
          qwen: _ThrowQwen(),
        );

        await s.container.read(jobQueueProvider.notifier).startGrading('t1');

        expect(s.fake.updated.last.status, SubmissionStatus.failed);
        final job = s.container.read(jobQueueProvider)['t1']!;
        expect(job.failedCount, 1);
        expect(job.error, isNotNull);
        expect(job.phase, JobPhase.failed);
      },
    );

    test('idempotent: overlapping starts do not double-grade', () async {
      final subs = [
        const Submission(
          id: 's1',
          taskId: 't1',
          label: 'p1',
          imagePath: '/a.jpg',
        ),
        const Submission(
          id: 's2',
          taskId: 't1',
          label: 'p2',
          imagePath: '/b.jpg',
        ),
      ];
      final qwen = _OkQwen();
      final s = _gradeSetup(task: _gradingTask(), subs: subs, qwen: qwen);

      final n = s.container.read(jobQueueProvider.notifier);
      final f1 = n.startGrading('t1');
      final f2 = n.startGrading('t1'); // should no-op (job already running)
      await Future.wait([f1, f2]);

      expect(
        qwen.calls,
        2,
        reason: '2 submissions graded once each, not twice',
      );
    });

    test(
      'reference load failure -> terminal phase, never stuck running',
      () async {
        // Corrupt the reference cache. Pre-fix, ReferenceStore.load would
        // throw mid-start and the job had to reach a terminal phase to
        // avoid getting stuck running. Post-fix, ReferenceStore.load
        // quarantines the corrupt file and returns [] — so the job runs
        // to completion (done) with no references, which is a *more*
        // terminal-phase-correct outcome. The invariant we're protecting
        // is: any load-time failure must NOT leave the job running.
        await File(
          '${tmp.path}/reference_t1.json',
        ).writeAsString('{ this is not valid json');
        final subs = [
          const Submission(
            id: 's1',
            taskId: 't1',
            label: 'p1',
            imagePath: '/a.jpg',
          ),
        ];
        final s = _gradeSetup(
          task: _gradingTask(),
          subs: subs,
          qwen: _OkQwen(),
        );

        await s.container.read(jobQueueProvider.notifier).startGrading('t1');

        final job = s.container.read(jobQueueProvider)['t1']!;
        expect(
          job.phase,
          isNot(JobPhase.running),
          reason:
              'a load failure must reach a terminal phase, not stick running',
        );
      },
    );

    test('cancel mid-run skips remaining units', () async {
      final subs = [
        for (var i = 0; i < 3; i++)
          Submission(
            id: 's$i',
            taskId: 't1',
            label: 'p$i',
            imagePath: '/x.jpg',
          ),
      ];
      late ProviderContainer container;
      final qwen = _CancelOnFirstQwen(
        () => container.read(jobQueueProvider.notifier).cancel('t1'),
      );
      // maxConcurrency: 1 -> units run one at a time, so the cancel requested
      // during unit 0 is observed before units 1 and 2 can start.
      final s = _gradeSetup(
        task: _gradingTask(),
        subs: subs,
        qwen: qwen,
        maxConcurrency: 1,
      );
      container = s.container;

      await container.read(jobQueueProvider.notifier).startGrading('t1');

      expect(
        qwen.calls,
        1,
        reason: 'only the first unit grades; cancel skips the rest',
      );
      expect(container.read(jobQueueProvider)['t1']!.done, 1);
      // S-5 fix: cancelled job must end as `failed` with the cancel marker,
      // not `done` (the previous behavior made "已取消" jobs look like
      // successful completions on the home card).
      final job = container.read(jobQueueProvider)['t1']!;
      expect(job.phase, JobPhase.failed,
          reason: 'cancelled job phases to failed (S-5 fix)');
      expect(job.error, '用户已取消');
    });
  });

  group('JobQueueNotifier.startStrategy', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('jobq_strat_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => tmp.path,
          );
    });
    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('generates all rubric items and persists to ReferenceStore', () async {
      final qwen = _StrategyOkQwen();
      final s = _gradeSetup(
        task: _twoQuestionTask(),
        subs: const [],
        qwen: qwen,
      );

      await s.container.read(jobQueueProvider.notifier).startStrategy('t1');

      expect(qwen.calls, 2);
      final job = s.container.read(jobQueueProvider)['t1']!;
      expect(job.kind, JobKind.strategy);
      expect(job.done, 2);
      expect(job.phase, JobPhase.done);

      final saved = await ReferenceStore.load('t1');
      expect(saved.length, 2);
      expect(saved.every((r) => r.checkpoints.isNotEmpty), isTrue);
    });
  });
}
