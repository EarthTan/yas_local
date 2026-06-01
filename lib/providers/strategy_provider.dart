import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/reference_answer.dart';
import '../models/rubric.dart';
import '../models/strategy_message.dart';
import '../models/submission.dart';
import '../services/qwen_service.dart';
import '../services/reference_store.dart';
import 'settings_provider.dart';
import 'task_provider.dart';

class StrategyState {
  final bool generating;
  final int genTotal;
  final int genDone;
  final String? error;
  final List<ReferenceAnswer> references;
  final bool refining;
  final int? refiningQuestion;

  const StrategyState({
    this.generating = false,
    this.genTotal = 0,
    this.genDone = 0,
    this.error,
    this.references = const [],
    this.refining = false,
    this.refiningQuestion,
  });

  bool get allConfirmed =>
      references.isNotEmpty && references.every((r) => r.confirmed);

  int get confirmedCount => references.where((r) => r.confirmed).length;

  StrategyState copyWith({
    bool? generating,
    int? genTotal,
    int? genDone,
    Object? error = _keep,
    List<ReferenceAnswer>? references,
    bool? refining,
    Object? refiningQuestion = _keep,
  }) =>
      StrategyState(
        generating: generating ?? this.generating,
        genTotal: genTotal ?? this.genTotal,
        genDone: genDone ?? this.genDone,
        error: identical(error, _keep) ? this.error : error as String?,
        references: references ?? this.references,
        refining: refining ?? this.refining,
        refiningQuestion: identical(refiningQuestion, _keep)
            ? this.refiningQuestion
            : refiningQuestion as int?,
      );

  static const _keep = Object();
}

class StrategyNotifier extends StateNotifier<StrategyState> {
  StrategyNotifier(this.ref) : super(const StrategyState());
  final Ref ref;

  /// Loads existing references from cache; if none, runs Phase 1 generation.
  Future<void> loadOrGenerate(String taskId) async {
    final settings = ref.read(settingsProvider);
    if (!settings.isConfigured) {
      state = state.copyWith(error: '未配置 API Key，请先到设置填写');
      return;
    }
    final notifier = ref.read(taskProvider.notifier);
    final task = notifier.taskById(taskId);
    if (task == null) return;

    // Try loading existing confirmed strategies from cache
    final cached = await ReferenceStore.load(taskId);
    if (cached.isNotEmpty) {
      state = state.copyWith(references: cached);
      return;
    }

    // No cache — generate Phase 1
    await _generate(taskId, task.rubric, notifier.submissionsFor(taskId), settings);
  }

  Future<void> _generate(
    String taskId,
    List<RubricItem> rubric,
    List<Submission> subs,
    dynamic settings,
  ) async {
    state = StrategyState(
      generating: true,
      genTotal: rubric.length,
      genDone: 0,
    );

    final qwen = QwenService(settings);
    final references = <ReferenceAnswer>[];
    String? firstError;

    for (final item in rubric) {
      try {
        ReferenceAnswer ref;
        if (item.correctAnswer != null) {
          ref = await qwen.generateReferenceWithAnswer(item, totalQuestions: rubric.length);
        } else {
          final images = _pickSampleImages(subs);
          if (images.isEmpty) {
            ref = ReferenceAnswer(
              questionNumber: item.questionNumber,
              checkpoints: [],
              hasConsensus: false,
            );
          } else {
            ref = await qwen.generateReferenceFromImages(item, images, totalQuestions: rubric.length);
          }
        }
        references.add(ref);
      } catch (e) {
        firstError ??= _formatError(e);
        references.add(ReferenceAnswer(
          questionNumber: item.questionNumber,
          checkpoints: [],
          hasConsensus: false,
        ));
      }
      state = state.copyWith(
        genDone: state.genDone + 1,
        references: List.unmodifiable(references),
      );
    }

    state = state.copyWith(
      generating: false,
      error: firstError,
      references: List.unmodifiable(references),
    );
  }

  /// Retry generation after an error.
  Future<void> regenerate(String taskId) async {
    final settings = ref.read(settingsProvider);
    if (!settings.isConfigured) {
      state = state.copyWith(error: '未配置 API Key，请先到设置填写');
      return;
    }
    final notifier = ref.read(taskProvider.notifier);
    final task = notifier.taskById(taskId);
    if (task == null) return;
    await _generate(taskId, task.rubric, notifier.submissionsFor(taskId), settings);
  }

  /// Send a refinement message for a specific question.
  Future<void> sendMessage(String taskId, int questionNum, String message) async {
    final settings = ref.read(settingsProvider);
    if (!settings.isConfigured) return;

    final refIndex = state.references.indexWhere((r) => r.questionNumber == questionNum);
    if (refIndex == -1) return;
    final current = state.references[refIndex];

    final notifier = ref.read(taskProvider.notifier);
    final task = notifier.taskById(taskId);
    if (task == null) return;
    final rubricItem = task.rubric.firstWhere(
      (r) => r.questionNumber == questionNum,
      orElse: () => RubricItem(questionNumber: questionNum, type: 'subjective', maxPoints: 0),
    );

    state = state.copyWith(refining: true, refiningQuestion: questionNum);

    final updatedHistory = [
      ...current.chatHistory,
      StrategyMessage(role: 'user', content: message),
    ];

    try {
      final qwen = QwenService(settings);
      final updated = await qwen.refineStrategy(
        rubric: rubricItem,
        current: current,
        chatHistory: current.chatHistory,
        userMessage: message,
      );

      final aiReply = updated.checkpoints
          .map((c) => '• ${c.description}（${c.points}分）')
          .join('\n');

      final finalHistory = [
        ...updatedHistory,
        StrategyMessage(
          role: 'assistant',
          content: '已更新批改策略：\n$aiReply',
        ),
      ];

      final newRef = updated.copyWith(
        confirmed: false,
        chatHistory: finalHistory,
      );

      final newRefs = [...state.references];
      newRefs[refIndex] = newRef;
      state = state.copyWith(refining: false, refiningQuestion: null, references: newRefs);
    } catch (e) {
      // On error, still record the user message in history
      final newRef = current.copyWith(chatHistory: [
        ...updatedHistory,
        StrategyMessage(role: 'assistant', content: '出错了：${_formatError(e)}'),
      ]);
      final newRefs = [...state.references];
      newRefs[refIndex] = newRef;
      state = state.copyWith(refining: false, refiningQuestion: null, references: newRefs);
    }
  }

  void confirmQuestion(int questionNum) {
    _updateRef(questionNum, (r) => r.copyWith(confirmed: true));
  }

  void unconfirmQuestion(int questionNum) {
    _updateRef(questionNum, (r) => r.copyWith(confirmed: false));
  }

  void confirmAll() {
    state = state.copyWith(
      references: state.references.map((r) => r.copyWith(confirmed: true)).toList(),
    );
  }

  /// Saves all references (confirmed or not) to disk for Phase 2 to use.
  Future<void> saveAllConfirmed(String taskId) async {
    await ReferenceStore.save(taskId, state.references);
  }

  void _updateRef(int questionNum, ReferenceAnswer Function(ReferenceAnswer) update) {
    final newRefs = state.references.map((r) {
      if (r.questionNumber == questionNum) return update(r);
      return r;
    }).toList();
    state = state.copyWith(references: newRefs);
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

final strategyProvider =
    StateNotifierProvider.autoDispose<StrategyNotifier, StrategyState>(
        (ref) => StrategyNotifier(ref));
