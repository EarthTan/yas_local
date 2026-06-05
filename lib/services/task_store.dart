import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/task.dart';
import '../models/submission.dart';
import 'atomic_io.dart';
import 'debug/debug_service.dart';

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

  /// Synchronous decode for tests. Does NOT do per-item quarantine; if
  /// any record's `fromJson` throws, the whole call throws. Production
  /// code paths go through [load], which does per-item recovery.
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

  /// Read the persisted task + submission set.
  ///
  /// **Whole-file corruption** (read failure, JSON parse failure, top
  /// level is not a Map) → the file is renamed aside with a `.broken.task.<…>`
  /// suffix, a DebugService event is emitted, and an empty `StoreData`
  /// is returned. A corrupt file can never crash the app at startup.
  ///
  /// **Per-item corruption** (one record's `fromJson` throws while
  /// others succeed) → the bad record is isolated. The original file is
  /// renamed to a per-item broken name and the surviving records are
  /// atomically re-written to the original path. The teacher keeps
  /// working with k-1 records instead of losing everything (the C-2
  /// bug in `bbbbbiiiigBugs.md`).
  static Future<StoreData> load() async {
    final f = await _file();
    return _loadPerItem(f);
  }

  static Future<StoreData> _loadPerItem(File f) async {
    if (!await f.exists()) return const StoreData([], []);
    final String raw;
    try {
      raw = await f.readAsString();
    } catch (e) {
      await _quarantineWhole(f, reason: 'read failed: $e');
      return const StoreData([], []);
    }
    if (raw.trim().isEmpty) return const StoreData([], []);
    final Object? parsed;
    try {
      parsed = jsonDecode(raw);
    } catch (e) {
      await _quarantineWhole(f, reason: 'json parse failed: $e');
      return const StoreData([], []);
    }
    if (parsed is! Map) {
      await _quarantineWhole(f, reason: 'top-level is not a Map');
      return const StoreData([], []);
    }
    final rawTasks = (parsed['tasks'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final rawSubs = (parsed['submissions'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final tasks = <GradingTask>[];
    final badTaskIdx = <int>[];
    for (var i = 0; i < rawTasks.length; i++) {
      try {
        tasks.add(GradingTask.fromJson(rawTasks[i]));
      } catch (_) {
        badTaskIdx.add(i);
      }
    }
    final subs = <Submission>[];
    final badSubIdx = <int>[];
    for (var i = 0; i < rawSubs.length; i++) {
      try {
        subs.add(Submission.fromJson(rawSubs[i]));
      } catch (_) {
        badSubIdx.add(i);
      }
    }
    if (badTaskIdx.isNotEmpty || badSubIdx.isNotEmpty) {
      // Re-write survivors back to the file atomically. Move the
      // original to a per-item broken name first so the bad records are
      // preserved for inspection.
      final stem = f.uri.pathSegments.last;
      final micros = DateTime.now().microsecondsSinceEpoch;
      final counter = (_perItemCounter = (_perItemCounter + 1) & 0xFFFF);
      final brokenPath =
          '${f.parent.path}/$stem.broken.task.$micros.$counter';
      try {
        await f.rename(brokenPath);
      } catch (_) {
        // If rename fails, just return survivors; don't overwrite original.
        await DebugService.instance.recordEvent(
          scope: 'task',
          level: EventLevel.error,
          message: 'persist: per-item quarantine rename_failed',
          data: {
            'file': f.path,
            'bad_task_indices': badTaskIdx,
            'bad_submission_indices': badSubIdx,
          },
        );
        return StoreData(tasks, subs);
      }
      final survivors = <String, dynamic>{
        'tasks': [
          for (var i = 0; i < rawTasks.length; i++)
            if (!badTaskIdx.contains(i)) rawTasks[i],
        ],
        'submissions': [
          for (var i = 0; i < rawSubs.length; i++)
            if (!badSubIdx.contains(i)) rawSubs[i],
        ],
      };
      try {
        await writeJsonAtomic(f, jsonEncode(survivors));
      } catch (e) {
        await DebugService.instance.recordEvent(
          scope: 'task',
          level: EventLevel.error,
          message: 'persist: per-item survivor rewrite failed',
          data: {
            'file': f.path,
            'error': e.toString(),
          },
        );
        // Survivors still returned to the caller; the file on disk is
        // now just the quarantined sibling. Next startup will see no
        // file → empty.
      }
      await DebugService.instance.recordEvent(
        scope: 'task',
        level: EventLevel.error,
        message: 'persist: per-item quarantined',
        data: {
          'file': f.path,
          'bad_task_indices': badTaskIdx,
          'bad_submission_indices': badSubIdx,
          'quarantined_to': brokenPath,
        },
      );
    }
    return StoreData(tasks, subs);
  }

  static Future<void> _quarantineWhole(File f, {required String reason}) async {
    final stem = f.uri.pathSegments.last;
    final micros = DateTime.now().microsecondsSinceEpoch;
    final counter = (_perItemCounter = (_perItemCounter + 1) & 0xFFFF);
    // Whole-file quarantine name: <stem>.broken.task.<micros>.<counter>
    // (matches the existing test expectations for `.broken.task.*`).
    final brokenPath = '${f.parent.path}/$stem.broken.task.$micros.$counter';
    try {
      await f.rename(brokenPath);
    } catch (e) {
      await DebugService.instance.recordEvent(
        scope: 'task',
        level: EventLevel.error,
        message: 'persist: corrupt file detected but rename_failed',
        data: {
          'file': f.path,
          'error': e.toString(),
          'reason': reason,
        },
      );
      return;
    }
    await DebugService.instance.recordEvent(
      scope: 'task',
      level: EventLevel.error,
      message: 'persist: corrupt file quarantined',
      data: {
        'file': f.path,
        'quarantined_to': brokenPath,
        'error': reason,
      },
    );
  }

  static int _perItemCounter = 0;

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
