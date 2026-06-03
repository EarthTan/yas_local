import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/reference_answer.dart';
import '../models/rubric.dart';
import '../models/strategy_message.dart';
import '../models/task.dart';
import '../services/debug_service.dart';
import '../services/error_formatter.dart';
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
    await _generate(taskId, task.rubric, settings, task);
  }

  Future<void> _generate(
    String taskId,
    List<RubricItem> rubric,
    dynamic settings,
    GradingTask task,
  ) async {
    state = StrategyState(
      generating: true,
      genTotal: rubric.length,
      genDone: 0,
    );

    DebugService.instance.recordEvent(
      scope: 'task:$taskId',
      message: 'strategy generate 开始（${rubric.length} 题）',
    );

    final qwen = QwenService(settings);
    final references = <ReferenceAnswer>[];
    String? firstError;

    for (final item in rubric) {
      try {
        final ref = await qwen.generateStrategy(
          rubricItem: item,
          questionPaperPaths: task.questionPaperPaths,
          answerImagePaths: task.answerImagePaths,
          totalQuestions: rubric.length,
        );
        references.add(ref);
        DebugService.instance.recordEvent(
          scope: 'task:$taskId / q:${item.questionNumber}',
          message: '生成 checkpoints（${ref.checkpoints.length} 个）',
        );
      } catch (e) {
        firstError ??= ErrorFormatter.format(e);
        references.add(ReferenceAnswer(
          questionNumber: item.questionNumber,
          checkpoints: [],
          hasConsensus: false,
        ));
        DebugService.instance.recordEvent(
          scope: 'task:$taskId / q:${item.questionNumber}',
          message: '生成失败',
          level: EventLevel.error,
          data: {'error': e.toString()},
        );
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
    DebugService.instance.recordEvent(
      scope: 'task:$taskId',
      message: 'strategy generate 结束',
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
    await _generate(taskId, task.rubric, settings, task);
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
      DebugService.instance.recordEvent(
        scope: 'task:$taskId / q:$questionNum',
        message: 'refine 开始',
      );
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
      DebugService.instance.recordEvent(
        scope: 'task:$taskId / q:$questionNum',
        message: 'refine 完成',
      );
    } catch (e) {
      // On error, still record the user message in history
      final newRef = current.copyWith(chatHistory: [
        ...updatedHistory,
        StrategyMessage(role: 'assistant', content: ErrorFormatter.format(e)),
      ]);
      final newRefs = [...state.references];
      newRefs[refIndex] = newRef;
      state = state.copyWith(refining: false, refiningQuestion: null, references: newRefs);
      DebugService.instance.recordEvent(
        scope: 'task:$taskId / q:$questionNum',
        message: 'refine 失败',
        level: EventLevel.error,
        data: {'error': e.toString()},
      );
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

}

final strategyProvider =
    StateNotifierProvider.autoDispose<StrategyNotifier, StrategyState>(
        (ref) => StrategyNotifier(ref));
