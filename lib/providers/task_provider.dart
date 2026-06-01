import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/task.dart';
import '../models/submission.dart';
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
  TaskNotifier() : super(const TaskState()) {
    _load();
  }

  Future<void> _load() async {
    final data = await TaskStore.load();
    state = TaskState(tasks: data.tasks, submissions: data.submissions, loaded: true);
  }

  Future<void> _persist() async =>
      TaskStore.save(state.tasks, state.submissions);

  Future<void> addTask(GradingTask task) async {
    state = state.copyWith(tasks: [...state.tasks, task]);
    await _persist();
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
  }

  Future<void> updateSubmission(Submission sub) async {
    state = state.copyWith(
      submissions: [
        for (final s in state.submissions) if (s.id == sub.id) sub else s,
      ],
    );
    await _persist();
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
  }
}

final taskProvider =
    StateNotifierProvider<TaskNotifier, TaskState>((ref) => TaskNotifier());
