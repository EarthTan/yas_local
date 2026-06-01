import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/submission.dart';
import '../models/checkpoint.dart';
import '../services/qwen_service.dart';
import '../services/reference_store.dart';
import 'settings_provider.dart';
import 'task_provider.dart';

class GradingProgress {
  final int total;
  final int done;
  final bool running;
  final String? error;

  const GradingProgress({
    this.total = 0,
    this.done = 0,
    this.running = false,
    this.error,
  });

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

  Future<void> runPhase2Only(String taskId) async {
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

    final references = await ReferenceStore.load(taskId);
    final refByNum = {for (final r in references) r.questionNumber: r};

    state = GradingProgress(
      total: subs.length,
      done: 0,
      running: true,
    );

    String? firstApiError;

    for (final sub in subs) {
      try {
        await notifier.updateSubmission(
            sub.copyWith(status: SubmissionStatus.processing));

        final grades = await qwen.gradePaper(
          imagePath: sub.imagePath!,
          rubric: task.rubric,
          refs: references,
        );
        final gradeByNum = {for (final g in grades) g.questionNumber: g};

        final items = task.rubric.map((rubricItem) {
          final grade = gradeByNum[rubricItem.questionNumber];
          final ref = refByNum[rubricItem.questionNumber];

          if (grade == null || grade.extractedAnswer.isEmpty) {
            final checkpoints = ref?.checkpoints
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

          final aiScore = grade.checkpoints
              .fold<int>(0, (sum, c) => sum + c.pointsAwarded);
          return GradedItem(
            questionNumber: rubricItem.questionNumber,
            type: rubricItem.type,
            extractedAnswer: grade.extractedAnswer,
            checkpoints: grade.checkpoints,
            aiScore: aiScore,
            aiComment: grade.overallComment,
            confidence: grade.confidence,
          );
        }).toList();

        await notifier.updateSubmission(
            sub.copyWith(status: SubmissionStatus.done, items: items));
      } catch (e) {
        await notifier.updateSubmission(
            sub.copyWith(status: SubmissionStatus.failed));
        firstApiError ??= _formatError(e);
      }
      state = state.copyWith(done: state.done + 1);
    }

    state = state.copyWith(running: false, error: firstApiError);
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
