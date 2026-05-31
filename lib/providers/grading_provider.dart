import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/submission.dart';
import '../models/rubric.dart';
import '../services/qwen_service.dart';
import '../services/grading.dart';
import 'settings_provider.dart';
import 'task_provider.dart';

class GradingProgress {
  final int total;
  final int done;
  final bool running;
  final String? error;
  const GradingProgress({this.total = 0, this.done = 0, this.running = false, this.error});

  // Use a sentinel to allow clearing error back to null
  GradingProgress copyWith({
    int? total,
    int? done,
    bool? running,
    Object? error = _keep,
  }) =>
      GradingProgress(
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
    final rubricByNum = {for (final r in task.rubric) r.questionNumber: r};
    final qwen = QwenService(settings);

    // Clear any previous error and start fresh
    state = GradingProgress(total: subs.length, done: 0, running: true);

    for (final sub in subs) {
      try {
        await notifier.updateSubmission(sub.copyWith(status: SubmissionStatus.processing));
        final ocr = await qwen.ocrPaper(sub.imagePath!);
        final items = <GradedItem>[];
        for (final q in ocr) {
          final r = rubricByNum[q.number];
          if (r == null) continue;
          if (r.type == 'objective') {
            items.add(await _gradeObjective(qwen, r, q.studentAnswer));
          } else {
            items.add(await _gradeSubjective(qwen, r, q.studentAnswer));
          }
        }
        await notifier.updateSubmission(
            sub.copyWith(status: SubmissionStatus.done, items: items));
      } catch (e) {
        await notifier.updateSubmission(sub.copyWith(status: SubmissionStatus.failed));
      }
      state = state.copyWith(done: state.done + 1);
    }
    state = state.copyWith(running: false);
  }

  Future<GradedItem> _gradeObjective(QwenService qwen, RubricItem r, String ans) async {
    if (r.correctAnswer != null) {
      final res = gradeObjectiveByKey(student: ans, correct: r.correctAnswer!, maxPoints: r.maxPoints);
      return GradedItem(
        questionNumber: r.questionNumber, type: 'objective', extractedAnswer: ans,
        aiScore: res.score, confidence: res.confidence,
      );
    }
    final j = await qwen.judgeObjective(question: r.questionText, studentAnswer: ans, maxPoints: r.maxPoints);
    final correct = j['correct'] == true;
    return GradedItem(
      questionNumber: r.questionNumber, type: 'objective', extractedAnswer: ans,
      aiScore: correct ? r.maxPoints : 0,
      confidence: (j['confidence'] as num?)?.toDouble() ?? 0.5,
    );
  }

  Future<GradedItem> _gradeSubjective(QwenService qwen, RubricItem r, String ans) async {
    final d = await qwen.gradeSubjective(
        question: r.questionText, criteria: r.criteria, maxPoints: r.maxPoints, studentAnswer: ans);
    return GradedItem(
      questionNumber: r.questionNumber, type: 'subjective', extractedAnswer: ans,
      aiScore: (d['score'] as num?)?.toInt() ?? 0,
      aiComment: d['comment'] as String?,
      confidence: (d['confidence'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

final gradingProvider =
    StateNotifierProvider<GradingNotifier, GradingProgress>((ref) => GradingNotifier(ref));
