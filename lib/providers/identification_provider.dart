import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/identified_question.dart';
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
    final subs = ref.read(taskProvider.notifier).submissionsFor(taskId);
    final imagePaths = subs
        .where((s) => s.imagePath != null)
        .map((s) => s.imagePath!)
        .toList();
    if (imagePaths.isEmpty) {
      state = state.copyWith(error: '没有可用的作业图片，请先上传作业');
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
      state = IdentificationState(error: _formatError(e));
    }
  }

  String _formatError(Object e) {
    if (e is DioException) {
      final status = e.response?.statusCode;
      final actualUrl = e.requestOptions.uri.toString();
      final body = e.response?.data?.toString() ?? '';
      final snippet = body.length > 200 ? '${body.substring(0, 200)}…' : body;
      final header = switch (status) {
        401 => '❌ API Key 无效（401）',
        403 => '❌ 权限不足（403）',
        404 => '❌ 接口不存在（404）',
        429 => '❌ 请求过频（429）',
        500 || 502 || 503 => '❌ 服务器错误（$status）',
        null => '❌ 网络错误：${e.message ?? e.type.name}',
        _ => '❌ HTTP $status',
      };
      return '$header\n$actualUrl${snippet.isNotEmpty ? '\n$snippet' : ''}';
    }
    final msg = e.toString();
    return msg.length > 300 ? '${msg.substring(0, 300)}…' : msg;
  }
}

final identificationProvider =
    StateNotifierProvider.autoDispose<IdentificationNotifier, IdentificationState>(
        (ref) => IdentificationNotifier(ref));
