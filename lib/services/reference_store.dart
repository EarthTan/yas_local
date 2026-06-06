import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/reference_answer.dart';
import 'async_lock.dart';
import 'atomic_io.dart';
import 'debug/debug_service.dart';

class ReferenceStore {
  static String encode(List<ReferenceAnswer> refs) =>
      jsonEncode(refs.map((r) => r.toJson()).toList());

  /// Synchronous decode for tests. Does NOT do per-item quarantine; if
  /// any record's `fromJson` throws, the whole call throws. Production
  /// code paths go through [load], which does per-item recovery.
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

  /// Read the cached references for [taskId].
  ///
  /// **Whole-file corruption** (read failure, JSON parse failure, top
  /// level is not a List) → file is renamed to
  /// `<name>.broken.reference.<…>` and a DebugService event is emitted;
  /// `[]` is returned.
  ///
  /// **Per-item corruption** (one record's `fromJson` throws while
  /// others succeed) → bad record is isolated. The original file is
  /// renamed to a per-item broken name and the surviving records are
  /// atomically re-written to the original path. The teacher keeps
  /// working with k-1 references instead of losing everything (the C-2
  /// bug in `bbbbbiiiigBugs.md`).
  static Future<List<ReferenceAnswer>> load(String taskId) async {
    final f = await _file(taskId);
    return _loadPerItem(f);
  }

  static Future<List<ReferenceAnswer>> _loadPerItem(File f) async {
    if (!await f.exists()) return const [];
    final String raw;
    try {
      raw = await f.readAsString();
    } catch (e) {
      await _quarantineWhole(f, reason: 'read failed: $e');
      return const [];
    }
    if (raw.trim().isEmpty) return const [];
    final Object? parsed;
    try {
      parsed = jsonDecode(raw);
    } catch (e) {
      await _quarantineWhole(f, reason: 'json parse failed: $e');
      return const [];
    }
    if (parsed is! List) {
      await _quarantineWhole(f, reason: 'top-level is not a List');
      return const [];
    }
    final rawItems =
        parsed.whereType<Map<String, dynamic>>().toList();
    final refs = <ReferenceAnswer>[];
    final badIdx = <int>[];
    for (var i = 0; i < rawItems.length; i++) {
      try {
        refs.add(ReferenceAnswer.fromJson(rawItems[i]));
      } catch (_) {
        badIdx.add(i);
      }
    }
    if (badIdx.isNotEmpty) {
      final stem = f.uri.pathSegments.last;
      final micros = DateTime.now().microsecondsSinceEpoch;
      final counter = (_perItemCounter = (_perItemCounter + 1) & 0xFFFF);
      final brokenPath =
          '${f.parent.path}/$stem.broken.reference.$micros.$counter';
      try {
        await f.rename(brokenPath);
      } catch (_) {
        await DebugService.instance.recordEvent(
          scope: 'reference',
          level: EventLevel.error,
          message: 'persist: per-item quarantine rename_failed',
          data: {'file': f.path, 'bad_indices': badIdx},
        );
        return refs;
      }
      final survivors = <Map<String, dynamic>>[
        for (var i = 0; i < rawItems.length; i++)
          if (!badIdx.contains(i)) rawItems[i],
      ];
      try {
        await writeJsonAtomic(f, jsonEncode(survivors));
      } catch (e) {
        await DebugService.instance.recordEvent(
          scope: 'reference',
          level: EventLevel.error,
          message: 'persist: per-item survivor rewrite failed',
          data: {'file': f.path, 'error': e.toString()},
        );
      }
      await DebugService.instance.recordEvent(
        scope: 'reference',
        level: EventLevel.error,
        message: 'persist: per-item quarantined',
        data: {
          'file': f.path,
          'bad_indices': badIdx,
          'quarantined_to': brokenPath,
        },
      );
    }
    return refs;
  }

  static Future<void> _quarantineWhole(File f,
      {required String reason}) async {
    final stem = f.uri.pathSegments.last;
    final micros = DateTime.now().microsecondsSinceEpoch;
    final counter = (_perItemCounter = (_perItemCounter + 1) & 0xFFFF);
    // Whole-file quarantine name: <stem>.broken.reference.<micros>.<counter>
    final brokenPath =
        '${f.parent.path}/$stem.broken.reference.$micros.$counter';
    try {
      await f.rename(brokenPath);
    } catch (e) {
      await DebugService.instance.recordEvent(
        scope: 'reference',
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
      scope: 'reference',
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

  /// Test-only: drop any pending writes and clear the lock. Use in setUp
  /// to ensure a clean slate between tests.
  static void resetForTest() {
    _lock.resetForTest();
  }
}
