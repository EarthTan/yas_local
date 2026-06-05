import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/task.dart';
import '../models/submission.dart';
import 'atomic_io.dart';

class StoreData {
  final List<GradingTask> tasks;
  final List<Submission> submissions;
  const StoreData(this.tasks, this.submissions);
}

class TaskStore {
  static const _fileName = 'tasks.json';

  static String encode(List<GradingTask> tasks, List<Submission> subs) =>
      jsonEncode({
        'tasks': tasks.map((t) => t.toJson()).toList(),
        'submissions': subs.map((s) => s.toJson()).toList(),
      });

  static StoreData decode(Object? parsed) {
    if (parsed is! Map) return const StoreData([], []);
    return StoreData(
      (parsed['tasks'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(GradingTask.fromJson)
          .toList(),
      (parsed['submissions'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Submission.fromJson)
          .toList(),
    );
  }

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Read the persisted task + submission set. On parse failure the file
  /// is quarantined (renamed aside + DebugService event) and an empty
  /// `StoreData` is returned, so a corrupt file can never crash the app
  /// at startup.
  static Future<StoreData> load() async {
    final f = await _file();
    return readJsonOrQuarantine<StoreData>(
      f,
      decode,
      () => const StoreData([], []),
      scope: 'task',
    );
  }

  /// Atomically write [tasks] + [subs] to the on-disk store.
  ///
  /// Writes are NOT mutex-protected at the store level — see
  /// `TaskNotifier._persistChain` in `task_provider.dart:42-58`, which
  /// serializes every caller. Direct callers (other than the provider)
  /// can clobber each other; the atomic write ensures partial-state
  /// crashes don't truncate the file.
  static Future<void> save(List<GradingTask> tasks, List<Submission> subs) async {
    final f = await _file();
    await writeJsonAtomic(f, encode(tasks, subs));
  }
}
