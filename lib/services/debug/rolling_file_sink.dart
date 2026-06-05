import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'debug_sink.dart';

/// Appends records to `{directory}/{baseName}_YYYY-MM-DD.log` files,
/// rolling to `.1.log`, `.2.log`, ... when [maxFileBytes] is exceeded.
/// One JSON object per line (NDJSON). Write errors are swallowed.
class RollingFileSink implements DebugSink {
  RollingFileSink({
    required this.directory,
    this.baseName = 'yas',
    this.maxFileBytes = 5 * 1024 * 1024,
  });

  final String directory;
  final String baseName;
  final int maxFileBytes;

  IOSink? _sink;
  String? _currentFilePath;
  final _writeLock = _Lock();

  String _formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  @override
  Future<void> write(DebugRecord record) async {
    await _writeLock.synchronized(() async {
      try {
        final dir = Directory(directory);
        if (!dir.existsSync()) dir.createSync(recursive: true);

        final today = _formatDate(record.timestamp);
        final expectedPath = p.join(directory, '${baseName}_$today.log');

        if (_currentFilePath != expectedPath) {
          await _rotate();
          _currentFilePath = expectedPath;
        }

        final json = jsonEncode(record.toJson());
        final bytes = utf8.encode('$json\n');

        // Flush any buffered bytes from the previous write so the on-disk
        // size we read below reflects what was actually persisted, not just
        // what's sitting in the IOSink's internal buffer.
        if (_sink != null) {
          try {
            await _sink!.flush();
          } catch (_) {}
        }
        final currentFile = File(_currentFilePath!);
        final currentSize =
            currentFile.existsSync() ? currentFile.lengthSync() : 0;
        if (currentSize + bytes.length > maxFileBytes) {
          await _rotate();
          _currentFilePath = expectedPath;
        }

        final file = File(_currentFilePath!);
        _sink = file.openWrite(mode: FileMode.append);
        _sink!.add(bytes);
      } catch (_) {
        try {
          await _sink?.close();
        } catch (_) {}
        _sink = null;
      }
    });
  }

  Future<void> _rotate() async {
    try {
      await _sink?.flush();
      await _sink?.close();
    } catch (_) {}
    _sink = null;

    final today = _formatDate(DateTime.now());
    final todayPath = p.join(directory, '${baseName}_$today.log');
    final f = File(todayPath);
    if (f.existsSync() && await f.length() >= maxFileBytes) {
      var i = 1;
      while (File(p.join(directory, '${baseName}_$today.$i.log')).existsSync()) {
        i++;
      }
      await f.rename(p.join(directory, '${baseName}_$today.$i.log'));
    }
  }

  @override
  Future<void> flush() async {
    await _writeLock.synchronized(() async {
      try {
        await _sink?.flush();
      } catch (_) {}
    });
  }

  @override
  Future<void> close() async {
    await _writeLock.synchronized(() async {
      try {
        await _sink?.flush();
        await _sink?.close();
      } catch (_) {}
      _sink = null;
    });
  }
}

class _Lock {
  Future<void> _last = Future.value();
  Future<T> synchronized<T>(Future<T> Function() body) {
    final completer = Completer<T>();
    final prev = _last;
    _last = completer.future.then((_) {}, onError: (_) {});
    prev.whenComplete(() async {
      try {
        completer.complete(await body());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }
}
