import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'debug/debug_service.dart';

/// Atomic file I/O helpers for the JSON stores.
///
/// `writeJsonAtomic` writes to a temp file in the same directory as the
/// target, fsyncs the contents, then renames over the target. The rename
/// is atomic on POSIX (macOS / Linux / iOS sandbox) and overwrites the
/// target. The temp file is cleaned up on any failure.
///
/// `readJsonOrQuarantine` reads a JSON file, decodes it, and on parse
/// failure renames the file aside (so it isn't lost forever) and emits a
/// DebugService event. The caller receives a "empty" value they supply
/// (e.g. `() => const AppSettings()`) and can keep going.
///
/// When the parsed JSON is a `List` and the caller-supplied [decode]
/// throws on the whole list, `readJsonOrQuarantine` re-tries [decode]
/// per element wrapped in a single-element list (`[item]`). Successful
/// per-item results are concatenated; failures are isolated. If any
/// item failed, the original file is quarantined to a per-item broken
/// name and the surviving raw JSON elements are atomically re-written
/// to the original path. This keeps one bad record from taking down the
/// entire file (the C-2 bug in `bbbbbiiiigBugs.md`).

int _quarantineCounter = 0;
int _pidSalt = 0;

/// Write [content] to [target] atomically.
///
/// On POSIX this is atomic w.r.t. concurrent readers: they see either the
/// old contents or the new, never a truncated mix. The temp file is
/// created in the same directory as [target] (same filesystem → atomic
/// rename). Throws on any error after cleaning up the temp file.
Future<void> writeJsonAtomic(File target, String content) async {
  // Use the parent dir for the tmp so rename stays on one filesystem.
  final parent = target.parent;
  // A small per-process counter disambiguates rapid back-to-back writes.
  final counter = (++_quarantineCounter) & 0xFFFF;
  final nanos = DateTime.now().microsecondsSinceEpoch;
  final tmp = File(
    '${parent.path}/.${target.uri.pathSegments.last}.tmp.$nanos.$counter',
  );
  try {
    // flush: true issues fsync(2) so the bytes are on disk before rename.
    await tmp.writeAsString(content, flush: true);
    await tmp.rename(target.path);
  } catch (_) {
    // Best-effort cleanup; the tmp file is in the same dir so a stale
    // entry is harmless (the next write generates a new name).
    try {
      if (await tmp.exists()) await tmp.delete();
    } catch (_) {}
    rethrow;
  }
}

/// Read [file], JSON-decode it, then pass the parsed value to [decode].
///
/// On any failure (read, JSON parse, or [decode] itself throwing on a
/// non-list parsed value) the file is quarantined (renamed aside +
/// DebugService event) and [empty] is returned.
///
/// **Per-item recovery**: when the parsed JSON is a `List` and [decode]
/// throws on the whole list, this helper re-tries [decode] per element
/// (wrapped as `[item]`) and concatenates the successful results.
/// Failures are isolated: the original file is quarantined to a
/// per-item broken name and the surviving raw JSON elements are
/// atomically re-written to the original path. The aggregated result is
/// returned to the caller. This keeps one bad record from taking down
/// the whole file.
///
/// On success returns `decode(parsed)`. If the file does not exist,
/// returns [empty] with no DebugService event (missing file is not an
/// error). The whole-file quarantine rename format is
/// `<original>.<scope>.broken.<pid>.<micros>.<counter>`; the per-item
/// quarantine format is `<original>.broken.<scope>.<micros>.<counter>`.
Future<T> readJsonOrQuarantine<T>(
  File file,
  T Function(Object? parsed) decode,
  T Function() empty, {
  required String scope,
}) async {
  if (!await file.exists()) return empty();
  final String raw;
  try {
    raw = await file.readAsString();
  } catch (e) {
    await _quarantineWhole(
      file,
      scope: scope,
      reason: 'read failed: ${_truncate(e.toString())}',
      phase: 'read',
    );
    return empty();
  }
  // An empty file is treated as "no data" — return empty() without an
  // event. A file with whitespace is the same.
  if (raw.trim().isEmpty) return empty();
  final Object? parsed;
  try {
    parsed = jsonDecode(raw);
  } catch (e) {
    await _quarantineWhole(
      file,
      scope: scope,
      reason: 'json parse failed: ${_truncate(e.toString())}',
      phase: 'decode',
    );
    return empty();
  }
  try {
    if (parsed is List) {
      return await _decodeListWithPerItemRecovery<T>(
        file,
        parsed,
        decode,
        scope: scope,
      );
    }
    return decode(parsed);
  } catch (e) {
    await _quarantineWhole(
      file,
      scope: scope,
      reason: 'decode failed: ${_truncate(e.toString())}',
      phase: 'decode',
    );
    return empty();
  }
}

/// Decode a parsed JSON list with per-element recovery.
///
/// Calls [decode] once per element as `[elem]`; elements that throw are
/// treated as "bad records" and isolated. Elements that succeed are
/// retained. If any bad records were found, the original [file] is
/// quarantined under a per-item broken name and the surviving raw JSON
/// elements are atomically re-written to the original path. The final
/// return value is `decode(survivors)` so the caller's natural return
/// shape is preserved.
///
/// Throws if every element fails (caller falls back to whole-file
/// quarantine) or if [decode] throws on the survivor batch.
Future<T> _decodeListWithPerItemRecovery<T>(
  File file,
  List<dynamic> parsed,
  T Function(Object? parsed) decode, {
  required String scope,
}) async {
  final survivorElements = <dynamic>[];
  final badIndices = <int>[];
  for (var i = 0; i < parsed.length; i++) {
    final elem = parsed[i];
    try {
      decode([elem]);
      survivorElements.add(elem);
    } catch (_) {
      badIndices.add(i);
    }
  }
  if (badIndices.isEmpty) {
    // Fast path: every element decoded successfully. Re-invoke on the
    // full list so the caller's natural batch-level result is returned
    // (e.g. with any batch-level invariants the decoder enforces).
    return decode(parsed);
  }
  if (survivorElements.isEmpty) {
    // Every element failed. Throw to let the caller quarantine the
    // whole file (preserves the old "decode failed" path).
    throw const FormatException(
        'per-item decode failed for every element');
  }
  // Some elements survived. Quarantine the original file under a
  // per-item broken name and atomically re-write the survivors.
  final decoded = decode(survivorElements);
  final stem = file.uri.pathSegments.last;
  final micros = DateTime.now().microsecondsSinceEpoch;
  final counter = (++_quarantineCounter) & 0xFFFF;
  final brokenPath = '${file.parent.path}/$stem.broken.$scope.$micros.$counter';
  try {
    await file.rename(brokenPath);
  } catch (e) {
    await DebugService.instance.recordEvent(
      scope: scope,
      level: EventLevel.error,
      message: 'persist: per-item quarantine rename_failed',
      data: {
        'file': file.path,
        'bad_indices': badIndices,
        'error': _truncate(e.toString()),
      },
    );
    // Even if rename failed, the survivors are still useful in memory.
    return decoded;
  }
  try {
    await writeJsonAtomic(file, jsonEncode(survivorElements));
  } catch (e) {
    await DebugService.instance.recordEvent(
      scope: scope,
      level: EventLevel.error,
      message: 'persist: per-item survivor rewrite failed',
      data: {
        'file': file.path,
        'bad_indices': badIndices,
        'error': _truncate(e.toString()),
      },
    );
    // Survivors still returned to the caller; the file on disk is now
    // the quarantined sibling (original was renamed). Next startup will
    // see no file → empty.
  }
  await DebugService.instance.recordEvent(
    scope: scope,
    level: EventLevel.error,
    message: 'persist: per-item quarantined',
    data: {
      'file': file.path,
      'quarantined_to': brokenPath,
      'bad_indices': badIndices,
      'survivor_count': survivorElements.length,
    },
  );
  return decoded;
}

/// Quarantine [file] as a whole — rename aside, emit a DebugService
/// event. Used for genuine file corruption (read failure, JSON parse
/// failure) and as the fallback when per-item decode can't recover.
Future<void> _quarantineWhole(
  File file, {
  required String scope,
  required String reason,
  required String phase,
}) async {
  final dir = file.parent;
  final stem = file.uri.pathSegments.last;
  final pid = _pidString();
  final micros = DateTime.now().microsecondsSinceEpoch;
  final counter = (++_quarantineCounter) & 0xFFFF;
  // Pattern: <original-name>.broken.<scope>.<pid>.<micros>.<counter>
  // e.g. tasks.json → tasks.json.broken.task.<pid>.<micros>.<counter>
  final quarantineName = '$stem.broken.$scope.$pid.$micros.$counter';
  final target = File('${dir.path}/$quarantineName');
  try {
    await file.rename(target.path);
  } catch (e) {
    // Rename failed (file disappeared, perm denied). Still emit the event
    // so the user can see the failure in /debug; return without moving.
    await DebugService.instance.recordEvent(
      scope: scope,
      level: EventLevel.error,
      message: 'persist: corrupt file detected but rename_failed',
      data: {
        'file': file.path,
        'phase': 'rename_failed',
        'error': _truncate(e.toString()),
      },
    );
    return;
  }
  await DebugService.instance.recordEvent(
    scope: scope,
    level: EventLevel.error,
    message: 'persist: corrupt file quarantined',
    data: {
      'file': file.path,
      'quarantined_to': target.path,
      'phase': phase,
      'error': reason,
    },
  );
}

String _truncate(String s) =>
    s.length <= 500 ? s : '${s.substring(0, 500)}…';

String _pidString() {
  // No portable "process id" in pure Dart. Use a per-process salt seeded
  // lazily on first use; combined with the per-process microsecond clock
  // and the monotonic counter, two concurrent quarantine renames inside
  // the same isolate will not collide.
  if (_pidSalt == 0) {
    _pidSalt = Random().nextInt(1 << 30);
  }
  return _pidSalt.toRadixString(36);
}
