import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/checkpoint.dart';
import '../models/reference_answer.dart';
import '../models/rubric.dart';
import '../models/strategy_message.dart';
import '../services/debug/debug_service.dart';
import '../services/error_formatter.dart';
import '../services/qwen_service.dart';
import '../services/reference_store.dart';
import 'settings_provider.dart';
import 'task_provider.dart';

class StrategyState {
  final String? error;
  final List<ReferenceAnswer> references;
  final bool refining;
  final int? refiningQuestion;

  const StrategyState({
    this.error,
    this.references = const [],
    this.refining = false,
    this.refiningQuestion,
  });

  bool get allConfirmed =>
      references.isNotEmpty && references.every((r) => r.confirmed);

  int get confirmedCount => references.where((r) => r.confirmed).length;

  StrategyState copyWith({
    Object? error = _keep,
    List<ReferenceAnswer>? references,
    bool? refining,
    Object? refiningQuestion = _keep,
  }) => StrategyState(
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
  StrategyNotifier(this.ref, {QwenService Function(Ref ref)? qwenFactory})
    // ignore: prefer_initializing_formals
    : _qwenFactory = qwenFactory,
      super(const StrategyState());
  final Ref ref;
  final QwenService Function(Ref ref)? _qwenFactory;

  /// Currently-loaded task id. Set by [load]. Used by [_scheduleSave] to know
  /// which `reference_<taskId>.json` to write to when a mutator fires.
  String? _saveTaskId;

  /// Pending debounced save. Cancelled and rescheduled on each mutation so a
  /// burst of edits only writes once, 500ms after the last one.
  Timer? _saveDebounce;

  /// Generation counter for in-flight async work. Bumped in [dispose] so any
  /// `await`ed work that resolves after dispose can detect it's stale and
  /// bail before writing to a dead notifier (see bbbbbiiiigBugs.md#S-9).
  int _token = 0;

  @override
  void dispose() {
    _token++;
    _saveDebounce?.cancel();
    super.dispose();
  }

  void _scheduleSave(String taskId) {
    _saveDebounce?.cancel();
    _saveTaskId = taskId;
    _saveDebounce = Timer(const Duration(milliseconds: 500), () {
      _saveDebounce = null;
      final id = _saveTaskId;
      if (id == null) return;
      _saveTaskId = null;
      // Fire-and-forget; notifier lives for the app's lifetime so this
      // cannot race with dispose.
      ReferenceStore.save(id, state.references);
    });
  }

  QwenService _newQwen() {
    final factory = _qwenFactory;
    return factory != null
        ? factory(ref)
        : QwenService(ref.read(settingsProvider));
  }

  /// Loads cached references from disk into state (no generation — bulk
  /// generation is owned by JobQueueNotifier.startStrategy).
  Future<void> load(String taskId) async {
    _saveTaskId = taskId;
    final cached = await ReferenceStore.load(taskId);
    state = state.copyWith(references: cached);
  }

  /// Retry generation for a single question — replaces the cached
  /// reference for that questionNumber with a fresh one from the VLM.
  Future<void> retryGenerate(String taskId, int questionNumber) async {
    final myToken = _token;
    final settings = ref.read(settingsProvider);
    if (!settings.isConfigured) {
      state = state.copyWith(error: '未配置 API Key，请先到设置填写');
      return;
    }
    final task = ref.read(taskProvider.notifier).taskById(taskId);
    if (task == null) return;
    final rubricItem = task.rubric.firstWhere(
      (r) => r.questionNumber == questionNumber,
      orElse: () => RubricItem(
        questionNumber: questionNumber,
        type: 'subjective',
        maxPoints: 0,
      ),
    );
    state = state.copyWith(refining: true, refiningQuestion: questionNumber);
    DebugService.instance.recordEvent(
      scope: 'task:$taskId / q:$questionNumber',
      message: 'retryGenerate 开始',
    );
    try {
      final updated = await _newQwen().generateStrategy(
        rubricItem: rubricItem,
        questionPaperPaths: task.questionPaperPaths,
        answerImagePaths: task.answerImagePaths,
        totalQuestions: task.rubric.length,
      );
      if (myToken != _token) return; // disposed mid-flight
      final newRefs = [
        for (final r in state.references)
          if (r.questionNumber == questionNumber) updated else r,
      ];
      // Clear a prior-phase error if every question now has at least one
      // checkpoint (i.e., no references are still in the "failed" state).
      // Otherwise the orange "部分题目生成失败…" banner would linger after
      // the user successfully retried the last failing question.
      final stillFailing = newRefs.any((r) => r.checkpoints.isEmpty);
      state = stillFailing
          ? state.copyWith(
              refining: false,
              refiningQuestion: null,
              references: newRefs,
            )
          : state.copyWith(
              refining: false,
              refiningQuestion: null,
              references: newRefs,
              error: null,
            );
      DebugService.instance.recordEvent(
        scope: 'task:$taskId / q:$questionNumber',
        message: 'retryGenerate 完成',
      );
    } catch (e) {
      if (myToken != _token) return; // disposed mid-flight
      state = state.copyWith(
        refining: false,
        refiningQuestion: null,
        error: ErrorFormatter.format(e),
      );
      DebugService.instance.recordEvent(
        scope: 'task:$taskId / q:$questionNumber',
        message: 'retryGenerate 失败',
        level: EventLevel.error,
        data: {'error': e.toString()},
      );
    }
  }

  /// Send a refinement message for a specific question.
  Future<void> sendMessage(
    String taskId,
    int questionNum,
    String message,
  ) async {
    final myToken = _token;
    final settings = ref.read(settingsProvider);
    if (!settings.isConfigured) return;

    final refIndex = state.references.indexWhere(
      (r) => r.questionNumber == questionNum,
    );
    if (refIndex == -1) return;
    final current = state.references[refIndex];

    final notifier = ref.read(taskProvider.notifier);
    final task = notifier.taskById(taskId);
    if (task == null) return;
    final rubricItem = task.rubric.firstWhere(
      (r) => r.questionNumber == questionNum,
      orElse: () => RubricItem(
        questionNumber: questionNum,
        type: 'subjective',
        maxPoints: 0,
      ),
    );

    state = state.copyWith(refining: true, refiningQuestion: questionNum);

    DebugService.instance.recordEvent(
      scope: 'task:$taskId / q:$questionNum',
      message: 'refine 开始',
    );

    final updatedHistory = [
      ...current.chatHistory,
      StrategyMessage(role: 'user', content: message),
    ];

    try {
      final qwen = _newQwen();
      final updated = await qwen.refineStrategy(
        rubric: rubricItem,
        current: current,
        chatHistory: current.chatHistory,
        userMessage: message,
      );

      if (myToken != _token) return; // disposed mid-flight

      final aiReply = updated.checkpoints
          .map((c) => '• ${c.description}（${c.points}分）')
          .join('\n');

      final finalHistory = [
        ...updatedHistory,
        StrategyMessage(role: 'assistant', content: '已更新批改策略：\n$aiReply'),
      ];

      final newRef = updated.copyWith(
        confirmed: false,
        chatHistory: finalHistory,
      );

      final newRefs = [...state.references];
      newRefs[refIndex] = newRef;
      state = state.copyWith(
        refining: false,
        refiningQuestion: null,
        references: newRefs,
      );
      DebugService.instance.recordEvent(
        scope: 'task:$taskId / q:$questionNum',
        message: 'refine 完成',
      );
    } catch (e) {
      if (myToken != _token) return; // disposed mid-flight
      // On error, still record the user message in history
      final newRef = current.copyWith(
        chatHistory: [
          ...updatedHistory,
          StrategyMessage(role: 'assistant', content: ErrorFormatter.format(e)),
        ],
      );
      final newRefs = [...state.references];
      newRefs[refIndex] = newRef;
      state = state.copyWith(
        refining: false,
        refiningQuestion: null,
        references: newRefs,
      );
      DebugService.instance.recordEvent(
        scope: 'task:$taskId / q:$questionNum',
        message: 'refine 失败',
        level: EventLevel.error,
        data: {'error': e.toString()},
      );
    }
    if (myToken != _token) return; // disposed mid-flight
    _scheduleSave(taskId);
  }

  void confirmQuestion(int questionNum) {
    _updateRef(questionNum, (r) => r.copyWith(confirmed: true));
    _scheduleSave(_saveTaskId ?? 'unknown');
  }

  void unconfirmQuestion(int questionNum) {
    _updateRef(questionNum, (r) => r.copyWith(confirmed: false));
    _scheduleSave(_saveTaskId ?? 'unknown');
  }

  void confirmAll() {
    state = state.copyWith(
      references: state.references
          .map((r) => r.copyWith(confirmed: true))
          .toList(),
    );
    _scheduleSave(_saveTaskId ?? 'unknown');
  }

  /// Saves all references (confirmed or not) to disk for Phase 2 to use.
  Future<void> saveAllConfirmed(String taskId) async {
    await ReferenceStore.save(taskId, state.references);
  }

  void _updateRef(
    int questionNum,
    ReferenceAnswer Function(ReferenceAnswer) update,
  ) {
    final newRefs = state.references.map((r) {
      if (r.questionNumber == questionNum) return update(r);
      return r;
    }).toList();
    state = state.copyWith(references: newRefs);
  }

  void editCheckpoint(
    int questionNumber,
    String checkpointId, {
    String? description,
    int? points,
  }) {
    state = state.copyWith(
      references: [
        for (final r in state.references)
          if (r.questionNumber == questionNumber)
            r.copyWith(
              checkpoints: [
                for (final c in r.checkpoints)
                  if (c.id == checkpointId)
                    c.copyWith(
                      description: description ?? c.description,
                      points: points ?? c.points,
                    )
                  else
                    c,
              ],
            )
          else
            r,
      ],
    );
    DebugService.instance.recordEvent(
      scope: 'strategy / q:$questionNumber',
      message: 'editCheckpoint $checkpointId',
    );
    _scheduleSave(_saveTaskId ?? 'unknown');
  }

  void addCheckpoint(
    int questionNumber, {
    required String description,
    required int points,
  }) {
    final newId = DateTime.now().microsecondsSinceEpoch.toString();
    state = state.copyWith(
      references: [
        for (final r in state.references)
          if (r.questionNumber == questionNumber)
            r.copyWith(
              checkpoints: [
                ...r.checkpoints,
                CheckpointDef(
                  id: newId,
                  description: description,
                  points: points,
                ),
              ],
            )
          else
            r,
      ],
    );
    DebugService.instance.recordEvent(
      scope: 'strategy / q:$questionNumber',
      message: 'addCheckpoint $newId',
    );
    _scheduleSave(_saveTaskId ?? 'unknown');
  }

  void removeCheckpoint(int questionNumber, String checkpointId) {
    state = state.copyWith(
      references: [
        for (final r in state.references)
          if (r.questionNumber == questionNumber)
            r.copyWith(
              checkpoints: r.checkpoints
                  .where((c) => c.id != checkpointId)
                  .toList(),
            )
          else
            r,
      ],
    );
    DebugService.instance.recordEvent(
      scope: 'strategy / q:$questionNumber',
      message: 'removeCheckpoint $checkpointId',
    );
    _scheduleSave(_saveTaskId ?? 'unknown');
  }
}

/// Test seam: override this provider in tests to inject a fake [QwenService].
/// Production code resolves to `null` and the notifier falls back to
/// constructing `QwenService(ref.read(settingsProvider))`.
final qwenFactoryProvider = Provider<QwenService Function(Ref ref)?>(
  (ref) => null,
);

final strategyProvider =
    StateNotifierProvider.autoDispose<StrategyNotifier, StrategyState>((ref) {
      return StrategyNotifier(ref, qwenFactory: ref.read(qwenFactoryProvider));
    });
