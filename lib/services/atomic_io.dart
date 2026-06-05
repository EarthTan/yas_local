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
/// On any failure (read, JSON parse, or [decode] itself throwing) the
/// file is quarantined (renamed aside + DebugService event) and [empty]
/// is returned.
///
/// On success returns `decode(parsed)`. If the file does not exist,
/// returns [empty] with no DebugService event (missing file is not an
/// error). The quarantine rename format is
/// `<original>.<scope>.broken.<pid>.<micros>.<counter>`.
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
    await _quarantine(
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
    await _quarantine(
      file,
      scope: scope,
      reason: 'json parse failed: ${_truncate(e.toString())}',
      phase: 'decode',
    );
    return empty();
  }
  try {
    return decode(parsed);
  } catch (e) {
    await _quarantine(
      file,
      scope: scope,
      reason: 'decode failed: ${_truncate(e.toString())}',
      phase: 'decode',
    );
    return empty();
  }
}

Future<void> _quarantine(
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
