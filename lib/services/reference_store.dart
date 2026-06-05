import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/reference_answer.dart';
import 'async_lock.dart';
import 'atomic_io.dart';

class ReferenceStore {
  static String encode(List<ReferenceAnswer> refs) =>
      jsonEncode(refs.map((r) => r.toJson()).toList());

  /// Public for testing; called by `readJsonOrQuarantine` with the parsed
  /// JSON value (a `List<dynamic>` for the reference cache shape).
  static List<ReferenceAnswer> decode(Object? parsed) {
    if (parsed is! List) return const [];
    return parsed
        .whereType<Map<String, dynamic>>()
        .map(ReferenceAnswer.fromJson)
        .toList();
  }

  static Future<File> _file(String taskId) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/reference_$taskId.json');
  }

  // Serializes all writes to per-task reference files. A single static
  // lock is correct because the lock is only held during disk I/O (a few
  // ms); serializing across taskIds is harmless and avoids the per-task
  // lifecycle management of N locks.
  static final AsyncLock _lock = AsyncLock();

  /// Atomically write [refs] to the cache file for [taskId]. Concurrent
  /// callers wait on an internal mutex; a failed write does not skip the
  /// next caller.
  static Future<void> save(String taskId, List<ReferenceAnswer> refs) {
    return _lock.synchronized(() async {
      final f = await _file(taskId);
      await writeJsonAtomic(f, encode(refs));
    });
  }

  /// Read the cached references for [taskId]. On parse failure the file
  /// is quarantined (renamed to `<name>.broken.reference.<pid>.<micros>.<counter>`
  /// and a DebugService event is emitted) and `[]` is returned.
  static Future<List<ReferenceAnswer>> load(String taskId) async {
    final f = await _file(taskId);
    return readJsonOrQuarantine<List<ReferenceAnswer>>(
      f,
      decode,
      () => <ReferenceAnswer>[],
      scope: 'reference',
    );
  }

  /// Test-only: drop any pending writes and clear the lock. Use in setUp
  /// to ensure a clean slate between tests.
  static void resetForTest() {
    _lock.resetForTest();
  }
}
