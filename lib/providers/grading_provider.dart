import 'package:dio/dio.dart';
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

    String? firstApiError;

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
        firstApiError ??= _formatError(e);
      }
      state = state.copyWith(done: state.done + 1);
    }

    // Expose the actual error so the UI can show it instead of silently failing.
    if (firstApiError != null) {
      state = state.copyWith(running: false, error: firstApiError);
    } else {
      state = state.copyWith(running: false);
    }
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

  String _formatError(Object e) {
    if (e is DioException) {
      final status = e.response?.statusCode;
      // ← Expose the ACTUAL URL Dio constructed — this is the key diagnostic info
      final actualUrl = e.requestOptions.uri.toString();
      final body = e.response?.data?.toString() ?? '';
      final snippet = body.length > 300 ? '${body.substring(0, 300)}…' : body;

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

final gradingProvider =
    StateNotifierProvider<GradingNotifier, GradingProgress>((ref) => GradingNotifier(ref));
