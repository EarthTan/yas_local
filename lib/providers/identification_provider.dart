import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/identified_question.dart';
import '../services/error_formatter.dart';
import '../services/qwen_service.dart';
import 'settings_provider.dart';
import 'task_provider.dart';

class IdentificationState {
  final bool identifying;
  final List<IdentifiedQuestion> questions;
  final String? error;

  const IdentificationState({
    this.identifying = false,
    this.questions = const [],
    this.error,
  });

  bool get hasQuestions => questions.isNotEmpty;

  IdentificationState copyWith({
    bool? identifying,
    List<IdentifiedQuestion>? questions,
    Object? error = _keep,
  }) =>
      IdentificationState(
        identifying: identifying ?? this.identifying,
        questions: questions ?? this.questions,
        error: identical(error, _keep) ? this.error : error as String?,
      );

  static const _keep = Object();
}

class IdentificationNotifier extends StateNotifier<IdentificationState> {
  IdentificationNotifier(this.ref) : super(const IdentificationState());
  final Ref ref;

  Future<void> identify(String taskId) async {
    final settings = ref.read(settingsProvider);
    if (!settings.isConfigured) {
      state = state.copyWith(error: '未配置 API Key，请先到设置填写');
      return;
    }
    final notifier = ref.read(taskProvider.notifier);
    final task = notifier.taskById(taskId);
    final imagePaths = task?.questionPaperPaths ?? [];
    if (imagePaths.isEmpty) {
      state = state.copyWith(error: '没有题目照片，请先在创建任务时上传题目照片');
      return;
    }

    state = const IdentificationState(identifying: true);
    try {
      final qwen = QwenService(settings);
      final questions = await qwen.identifyQuestions(imagePaths);
      if (questions.isEmpty) {
        state = const IdentificationState(
            error: 'AI 未能识别出任何题目，请检查图片质量或手动输入');
        return;
      }
      state = IdentificationState(questions: questions);
    } catch (e) {
      state = IdentificationState(error: ErrorFormatter.format(e));
    }
  }
}

final identificationProvider =
    StateNotifierProvider.autoDispose<IdentificationNotifier, IdentificationState>(
        (ref) => IdentificationNotifier(ref));
