import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/submission.dart';
import '../models/checkpoint.dart';
import '../models/rubric.dart';
import '../models/reference_answer.dart';
import '../services/qwen_service.dart';
import '../services/reference_store.dart';
import 'settings_provider.dart';
import 'task_provider.dart';

enum GradingPhase { referenceGen, grading }

class GradingProgress {
  final GradingPhase phase;
  final int refTotal;
  final int refDone;
  final int total;
  final int done;
  final bool running;
  final String? error;

  const GradingProgress({
    this.phase = GradingPhase.referenceGen,
    this.refTotal = 0,
    this.refDone = 0,
    this.total = 0,
    this.done = 0,
    this.running = false,
    this.error,
  });

  GradingProgress copyWith({
    GradingPhase? phase,
    int? refTotal,
    int? refDone,
    int? total,
    int? done,
    bool? running,
    Object? error = _keep,
  }) =>
      GradingProgress(
        phase: phase ?? this.phase,
        refTotal: refTotal ?? this.refTotal,
        refDone: refDone ?? this.refDone,
        total: total ?? this.total,
        done: done ?? this.done,
        running: running ?? this.running,
        error: identical(error, _keep) ? this.error : error as String?,
      );

  static const _keep = Object();
}

class GradingNotifier extends StateNotifier<GradingProgress> {
  GradingNotifier(this.ref) : super(const GradingProgress());
  final Ref ref;

  Future<void> run(String taskId) async {
    final settings = ref.read(settingsProvider);
    if (!settings.isConfigured) {
      state = state.copyWith(error: '未配置 API Key，请先到设置填写');
      return;
    }
    final notifier = ref.read(taskProvider.notifier);
    final task = notifier.taskById(taskId);
    if (task == null) return;
    final subs = notifier.submissionsFor(taskId);
    final qwen = QwenService(settings);

    // ── Phase 1: Reference answer generation (cached per task) ──
    state = GradingProgress(
      phase: GradingPhase.referenceGen,
      refTotal: task.rubric.length,
      refDone: 0,
      running: true,
    );

    String? firstApiError;

    final cached = await ReferenceStore.load(taskId);
    final cachedByNum = {for (final r in cached) r.questionNumber: r};
    final references = <ReferenceAnswer>[];

    for (final rubricItem in task.rubric) {
      if (cachedByNum.containsKey(rubricItem.questionNumber)) {
        references.add(cachedByNum[rubricItem.questionNumber]!);
      } else {
        try {
          ReferenceAnswer refAnswer;
          if (rubricItem.correctAnswer != null) {
            refAnswer = await qwen.generateReferenceWithAnswer(rubricItem);
          } else {
            final images = _pickSampleImages(subs);
            if (images.isEmpty) {
              refAnswer = ReferenceAnswer(
                  questionNumber: rubricItem.questionNumber,
                  checkpoints: [],
                  hasConsensus: false);
            } else {
              refAnswer =
                  await qwen.generateReferenceFromImages(rubricItem, images);
            }
          }
          references.add(refAnswer);
        } catch (e) {
          firstApiError ??= _formatError(e);
          references.add(ReferenceAnswer(
              questionNumber: rubricItem.questionNumber,
              checkpoints: [],
              hasConsensus: false));
        }
      }
      state = state.copyWith(refDone: state.refDone + 1);
    }

    await ReferenceStore.save(taskId, references);

    if (firstApiError != null) {
      state = state.copyWith(running: false, error: firstApiError);
      return;
    }

    // ── Phase 2: Batch grading (rubric-first) ──
    final referenceByNum = {for (final r in references) r.questionNumber: r};

    state = state.copyWith(
      phase: GradingPhase.grading,
      total: subs.length,
      done: 0,
    );

    for (final sub in subs) {
      try {
        await notifier.updateSubmission(
            sub.copyWith(status: SubmissionStatus.processing));
        final ocr = await qwen.ocrPaper(sub.imagePath!);
        final ocrByNum = {for (final q in ocr) q.number: q.studentAnswer};

        final items = <GradedItem>[];
        for (final rubricItem in task.rubric) {
          final studentAnswer = ocrByNum[rubricItem.questionNumber] ?? '';
          final refAnswer = referenceByNum[rubricItem.questionNumber];

          if (studentAnswer.isEmpty) {
            items.add(_zeroItem(rubricItem, refAnswer));
            continue;
          }

          if (refAnswer == null || refAnswer.checkpoints.isEmpty) {
            items.add(GradedItem(
              questionNumber: rubricItem.questionNumber,
              type: rubricItem.type,
              extractedAnswer: studentAnswer,
              aiScore: 0,
              confidence: 0.5,
            ));
            continue;
          }

          final grade = await qwen.gradeAgainstReference(
            rubric: rubricItem,
            ref: refAnswer,
            studentAnswer: studentAnswer,
          );
          items.add(GradedItem(
            questionNumber: rubricItem.questionNumber,
            type: rubricItem.type,
            extractedAnswer: studentAnswer,
            checkpoints: grade.checkpoints,
            aiScore: grade.checkpoints
                .fold<int>(0, (sum, c) => sum + c.pointsAwarded),
            aiComment: grade.overallComment,
            confidence: grade.confidence,
          ));
        }

        await notifier.updateSubmission(
            sub.copyWith(status: SubmissionStatus.done, items: items));
      } catch (e) {
        await notifier.updateSubmission(
            sub.copyWith(status: SubmissionStatus.failed));
        firstApiError ??= _formatError(e);
      }
      state = state.copyWith(done: state.done + 1);
    }

    if (firstApiError != null) {
      state = state.copyWith(running: false, error: firstApiError);
    } else {
      state = state.copyWith(running: false);
    }
  }

  List<String> _pickSampleImages(List<Submission> subs) {
    final paths = subs
        .where((s) => s.imagePath != null)
        .map((s) => s.imagePath!)
        .toList();
    if (paths.length <= 5) return paths;
    final step = paths.length ~/ 5;
    return [for (int i = 0; i < 5; i++) paths[i * step]];
  }

  GradedItem _zeroItem(RubricItem rubricItem, ReferenceAnswer? refAnswer) {
    final checkpoints = refAnswer?.checkpoints
            .map((c) => CheckpointResult(
                  description: c.description,
                  passed: false,
                  pointsAwarded: 0,
                  reason: '未作答',
                ))
            .toList() ??
        [];
    return GradedItem(
      questionNumber: rubricItem.questionNumber,
      type: rubricItem.type,
      extractedAnswer: '',
      checkpoints: checkpoints,
      aiScore: 0,
      confidence: 1.0,
    );
  }

  String _formatError(Object e) {
    if (e is DioException) {
      final status = e.response?.statusCode;
      final actualUrl = e.requestOptions.uri.toString();
      final body = e.response?.data?.toString() ?? '';
      final snippet =
          body.length > 300 ? '${body.substring(0, 300)}…' : body;

      final header = switch (status) {
        401 => '❌ API Key 无效（401 Unauthorized）',
        403 => '❌ 权限不足（403 Forbidden）',
        404 => '❌ 接口不存在（404 Not Found）',
        422 => '❌ 请求格式有误（422 Unprocessable）',
        429 => '❌ 请求过频（429 Rate Limit）',
        500 || 502 || 503 => '❌ 服务器错误（$status）',
        null => '❌ 网络错误：${e.message ?? e.type.name}',
        _ => '❌ HTTP $status',
      };

      return [
        header,
        '实际请求 URL：\n$actualUrl',
        if (snippet.isNotEmpty) '服务器返回：\n$snippet',
      ].join('\n\n');
    }
    final msg = e.toString();
    return '批改出错：${msg.length > 400 ? '${msg.substring(0, 400)}…' : msg}';
  }
}

final gradingProvider = StateNotifierProvider<GradingNotifier, GradingProgress>(
    (ref) => GradingNotifier(ref));
