import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/task.dart';
import '../models/submission.dart';

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

  static StoreData decode(String raw) {
    if (raw.trim().isEmpty) return const StoreData([], []);
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return StoreData(
      (map['tasks'] as List? ?? [])
          .map((e) => GradingTask.fromJson(e as Map<String, dynamic>))
          .toList(),
      (map['submissions'] as List? ?? [])
          .map((e) => Submission.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<StoreData> load() async {
    final f = await _file();
    if (!await f.exists()) return const StoreData([], []);
    return decode(await f.readAsString());
  }

  static Future<void> save(List<GradingTask> tasks, List<Submission> subs) async {
    final f = await _file();
    await f.writeAsString(encode(tasks, subs));
  }
}
