import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/task.dart';
import '../models/submission.dart';
import '../models/rubric.dart';
import '../providers/settings_provider.dart';
import '../services/debug_service.dart';
import '../services/task_store.dart';

class TaskState {
  final List<GradingTask> tasks;
  final List<Submission> submissions;
  final bool loaded;
  const TaskState({this.tasks = const [], this.submissions = const [], this.loaded = false});

  TaskState copyWith({List<GradingTask>? tasks, List<Submission>? submissions, bool? loaded}) =>
      TaskState(
        tasks: tasks ?? this.tasks,
        submissions: submissions ?? this.submissions,
        loaded: loaded ?? this.loaded,
      );
}

class TaskNotifier extends StateNotifier<TaskState> {
  TaskNotifier(this.ref) : super(const TaskState()) {
    _load();
  }

  final Ref ref;

  Future<void> _load() async {
    final data = await TaskStore.load();
    state = TaskState(tasks: data.tasks, submissions: data.submissions, loaded: true);
    _refreshDebugSnapshot();
  }

  Future<void> _persist() async =>
      TaskStore.save(state.tasks, state.submissions);

  Future<void> addTask(GradingTask task) async {
    state = state.copyWith(tasks: [...state.tasks, task]);
    await _persist();
    _refreshDebugSnapshot();
  }

  List<Submission> submissionsFor(String taskId) =>
      state.submissions.where((s) => s.taskId == taskId).toList();

  GradingTask? taskById(String id) {
    for (final t in state.tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  Future<void> setSubmissions(String taskId, List<Submission> subs) async {
    final others = state.submissions.where((s) => s.taskId != taskId).toList();
    state = state.copyWith(submissions: [...others, ...subs]);
    await _persist();
    _refreshDebugSnapshot();
  }

  Future<void> updateSubmission(Submission sub) async {
    state = state.copyWith(
      submissions: [
        for (final s in state.submissions) if (s.id == sub.id) sub else s,
      ],
    );
    await _persist();
    _refreshDebugSnapshot();
  }

  Future<void> resetGradingResults(String taskId) async {
    state = state.copyWith(
      submissions: [
        for (final s in state.submissions)
          if (s.taskId == taskId)
            s.copyWith(status: SubmissionStatus.pending, items: [])
          else
            s,
      ],
    );
    await _persist();
    _refreshDebugSnapshot();
  }

  Future<void> updateTaskRubric(String taskId, List<RubricItem> rubric) async {
    state = state.copyWith(
      tasks: [
        for (final t in state.tasks)
          if (t.id == taskId)
            GradingTask(
              id: t.id,
              name: t.name,
              subject: t.subject,
              createdAt: t.createdAt,
              rubric: rubric,
              questionPaperPaths: t.questionPaperPaths,
              answerImagePaths: t.answerImagePaths,
            )
          else
            t,
      ],
    );
    await _persist();
    _refreshDebugSnapshot();
  }

  void _refreshDebugSnapshot() {
    final s = ref.read(settingsProvider);
    DebugService.instance.refreshStateSnapshot(
      tasks: state.tasks,
      references: const [], // references are loaded per-task; debug screen joins with task.refs
      settings: s.copyWith(apiKey: '***'),
    );
  }
}

final taskProvider =
    StateNotifierProvider<TaskNotifier, TaskState>((ref) => TaskNotifier(ref));
